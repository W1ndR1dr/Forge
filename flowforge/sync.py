"""
FlowForge Sync Protocol

Handles synchronization between Pi cache and Mac source-of-truth.
Manages health checks, background sync, and conflict resolution.
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Optional, Callable, Any
from dataclasses import dataclass

from .cache import CacheManager, get_cache_manager, PendingOperation
from .remote import RemoteExecutor

logger = logging.getLogger(__name__)


@dataclass
class SyncResult:
    """Result of a sync operation."""
    success: bool
    message: str
    synced_projects: list[str]
    failed_operations: list[int]
    conflicts: list[dict]


@dataclass
class MacStatus:
    """Current status of Mac connectivity."""
    online: bool
    last_check: str
    last_successful_sync: Optional[str] = None
    pending_operations: int = 0


class SyncManager:
    """
    Manages synchronization between Pi and Mac.

    Responsibilities:
    - Periodic health checks to detect Mac availability
    - Background sync when Mac comes online
    - Queue management for offline operations
    - Conflict detection and resolution
    """

    def __init__(
        self,
        remote_executor: RemoteExecutor,
        cache_manager: Optional[CacheManager] = None,
        health_check_interval: int = 30,
        sync_interval: int = 60
    ):
        self.remote = remote_executor
        self.cache = cache_manager or get_cache_manager()
        self.health_check_interval = health_check_interval
        self.sync_interval = sync_interval

        # State
        self._mac_online = False
        self._last_check = None
        self._last_sync = None
        self._running = False
        self._health_task = None
        self._sync_task = None

        # Callbacks for status changes
        self._on_status_change: Optional[Callable[[bool], None]] = None

    @property
    def mac_online(self) -> bool:
        """Is Mac currently reachable?"""
        return self._mac_online

    def get_status(self) -> MacStatus:
        """Get current Mac status."""
        return MacStatus(
            online=self._mac_online,
            last_check=self._last_check.isoformat() if self._last_check else None,
            last_successful_sync=self._last_sync.isoformat() if self._last_sync else None,
            pending_operations=self.cache.get_pending_count()
        )

    async def check_mac_health(self) -> bool:
        """
        Quick health check to see if Mac is reachable.
        Uses a simple SSH echo command with short timeout.
        """
        try:
            # Quick SSH test - 5 second timeout
            result = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self.remote.run_command("echo ok")
                ),
                timeout=5.0
            )

            was_online = self._mac_online
            self._mac_online = result.strip() == "ok"
            self._last_check = datetime.utcnow()

            # Notify on status change
            if was_online != self._mac_online and self._on_status_change:
                self._on_status_change(self._mac_online)

            return self._mac_online

        except (asyncio.TimeoutError, Exception) as e:
            logger.debug(f"Mac health check failed: {e}")
            was_online = self._mac_online
            self._mac_online = False
            self._last_check = datetime.utcnow()

            if was_online and self._on_status_change:
                self._on_status_change(False)

            return False

    async def sync_project(self, project_name: str, project_path: str) -> SyncResult:
        """
        Sync a single project with Mac.

        1. Fetch current registry from Mac
        2. Check for remote changes
        3. Flush pending operations
        4. Update local cache
        """
        conflicts = []
        failed_ops = []

        try:
            # 1. Fetch current registry from Mac
            registry_path = f"{project_path}/.flowforge/registry.json"
            remote_registry_json = self.remote.read_file(registry_path)

            if not remote_registry_json:
                return SyncResult(
                    success=False,
                    message=f"Could not read registry for {project_name}",
                    synced_projects=[],
                    failed_operations=[],
                    conflicts=[]
                )

            remote_registry = json.loads(remote_registry_json)
            remote_hash = self.cache.compute_registry_hash(remote_registry)

            # 2. Check for remote changes (conflict detection)
            local_state = self.cache.get_sync_state(project_name)
            if local_state and local_state.last_mac_registry_hash:
                if local_state.last_mac_registry_hash != remote_hash:
                    # Mac changed while we had pending operations
                    conflicts = self._detect_conflicts(project_name, remote_registry)

            # 3. Flush pending operations
            pending = self.cache.get_pending_operations(project_name)
            for op in pending:
                try:
                    await self._execute_pending_operation(op, project_path)
                    self.cache.mark_operation_completed(op.id)
                except Exception as e:
                    logger.error(f"Failed to sync operation {op.id}: {e}")
                    self.cache.mark_operation_failed(op.id, str(e))
                    failed_ops.append(op.id)

            # 4. Re-fetch registry after applying pending ops
            # (it may have changed from our writes)
            updated_registry_json = self.remote.read_file(registry_path)
            if updated_registry_json:
                updated_registry = json.loads(updated_registry_json)
                updated_hash = self.cache.compute_registry_hash(updated_registry)

                # Update cache with fresh data
                config_path = f"{project_path}/.flowforge/config.json"
                config_json = self.remote.read_file(config_path)
                config = json.loads(config_json) if config_json else None

                self.cache.cache_project(
                    name=project_name,
                    path=project_path,
                    config=config,
                    registry=updated_registry
                )

                # Update sync state
                self.cache.update_sync_state(
                    project_name=project_name,
                    registry_hash=updated_hash,
                    sync_status="synced" if not conflicts else "conflict"
                )

            self._last_sync = datetime.utcnow()

            return SyncResult(
                success=len(failed_ops) == 0,
                message="Sync complete" if not failed_ops else f"{len(failed_ops)} operations failed",
                synced_projects=[project_name],
                failed_operations=failed_ops,
                conflicts=conflicts
            )

        except Exception as e:
            logger.error(f"Sync failed for {project_name}: {e}")
            return SyncResult(
                success=False,
                message=str(e),
                synced_projects=[],
                failed_operations=[],
                conflicts=[]
            )

    async def sync_all_projects(self) -> SyncResult:
        """Sync all cached projects."""
        if not self._mac_online:
            return SyncResult(
                success=False,
                message="Mac is offline",
                synced_projects=[],
                failed_operations=[],
                conflicts=[]
            )

        projects = self.cache.get_all_cached_projects()
        all_synced = []
        all_failed = []
        all_conflicts = []

        for project in projects:
            result = await self.sync_project(project["name"], project["path"])
            all_synced.extend(result.synced_projects)
            all_failed.extend(result.failed_operations)
            all_conflicts.extend(result.conflicts)

        return SyncResult(
            success=len(all_failed) == 0,
            message=f"Synced {len(all_synced)} projects",
            synced_projects=all_synced,
            failed_operations=all_failed,
            conflicts=all_conflicts
        )

    async def _execute_pending_operation(self, op: PendingOperation, project_path: str):
        """Execute a pending operation on the Mac."""
        self.cache.mark_operation_syncing(op.id)
        payload = json.loads(op.payload_json)

        if op.operation == "add_feature":
            await self._remote_add_feature(project_path, payload)
        elif op.operation == "update_feature":
            await self._remote_update_feature(project_path, payload)
        elif op.operation == "delete_feature":
            await self._remote_delete_feature(project_path, payload)
        else:
            raise ValueError(f"Unknown operation: {op.operation}")

    async def _remote_add_feature(self, project_path: str, payload: dict):
        """Add a feature on the Mac via CLI."""
        title = payload.get("title", "")
        description = payload.get("description", "")
        priority = payload.get("priority", 5)
        complexity = payload.get("complexity", "medium")
        tags = payload.get("tags", [])

        # Build forge add command
        cmd = f'cd "{project_path}" && forge add "{title}"'
        if description:
            cmd += f' --description "{description}"'
        cmd += f' --priority {priority}'
        cmd += f' --complexity {complexity}'
        if tags:
            cmd += f' --tags "{",".join(tags)}"'

        result = self.remote.run_command(cmd)
        if "error" in result.lower():
            raise Exception(result)

    async def _remote_update_feature(self, project_path: str, payload: dict):
        """Update a feature on the Mac."""
        feature_id = payload.get("feature_id")
        if not feature_id:
            raise ValueError("Missing feature_id")

        # Read registry, update feature, write back
        registry_path = f"{project_path}/.flowforge/registry.json"
        registry_json = self.remote.read_file(registry_path)
        registry = json.loads(registry_json)

        if feature_id in registry.get("features", {}):
            feature = registry["features"][feature_id]
            # Apply updates (only user-editable fields)
            for key in ["title", "description", "tags", "priority", "complexity"]:
                if key in payload:
                    feature[key] = payload[key]
            feature["updated_at"] = datetime.utcnow().isoformat()

            # Write back
            updated_json = json.dumps(registry, indent=2)
            # Use echo to write file remotely
            escaped_json = updated_json.replace('"', '\\"').replace('\n', '\\n')
            cmd = f'echo "{escaped_json}" > "{registry_path}"'
            self.remote.run_command(cmd)
        else:
            raise ValueError(f"Feature {feature_id} not found")

    async def _remote_delete_feature(self, project_path: str, payload: dict):
        """Delete a feature on the Mac."""
        feature_id = payload.get("feature_id")
        if not feature_id:
            raise ValueError("Missing feature_id")

        cmd = f'cd "{project_path}" && forge delete "{feature_id}" --force'
        result = self.remote.run_command(cmd)
        if "error" in result.lower():
            raise Exception(result)

    def _detect_conflicts(self, project_name: str, remote_registry: dict) -> list[dict]:
        """
        Detect conflicts between pending local changes and remote state.

        Conflict resolution strategy:
        - Remote wins for: status, branch, worktree_path (git state)
        - Local wins for: title, description, tags (user edits)
        - Both added: merge both
        """
        conflicts = []
        pending = self.cache.get_pending_operations(project_name)
        remote_features = remote_registry.get("features", {})

        for op in pending:
            payload = json.loads(op.payload_json)

            if op.operation == "update_feature":
                feature_id = payload.get("feature_id")
                if feature_id and feature_id in remote_features:
                    remote_feature = remote_features[feature_id]
                    # Check if we're updating fields that remote also changed
                    # For now, we use simple "local wins for user fields" strategy
                    # so no real conflicts for title/description/tags
                    pass

            elif op.operation == "add_feature":
                # Check if a feature with same title exists remotely
                title = payload.get("title", "").lower()
                for fid, feat in remote_features.items():
                    if feat.get("title", "").lower() == title:
                        conflicts.append({
                            "type": "duplicate_feature",
                            "local_title": payload.get("title"),
                            "remote_id": fid,
                            "remote_title": feat.get("title")
                        })
                        break

        return conflicts

    # ========== Background Tasks ==========

    async def start_background_tasks(self):
        """Start background health check and sync tasks."""
        if self._running:
            return

        self._running = True
        self._health_task = asyncio.create_task(self._health_check_loop())
        self._sync_task = asyncio.create_task(self._sync_loop())
        logger.info("Started background sync tasks")

    async def stop_background_tasks(self):
        """Stop background tasks."""
        self._running = False

        if self._health_task:
            self._health_task.cancel()
            try:
                await self._health_task
            except asyncio.CancelledError:
                pass

        if self._sync_task:
            self._sync_task.cancel()
            try:
                await self._sync_task
            except asyncio.CancelledError:
                pass

        logger.info("Stopped background sync tasks")

    async def _health_check_loop(self):
        """Periodic health check loop."""
        while self._running:
            try:
                await self.check_mac_health()
            except Exception as e:
                logger.error(f"Health check error: {e}")

            await asyncio.sleep(self.health_check_interval)

    async def _sync_loop(self):
        """Periodic sync loop (only when Mac is online)."""
        while self._running:
            try:
                if self._mac_online:
                    pending_count = self.cache.get_pending_count()
                    if pending_count > 0:
                        logger.info(f"Syncing {pending_count} pending operations...")
                        await self.sync_all_projects()
            except Exception as e:
                logger.error(f"Sync error: {e}")

            await asyncio.sleep(self.sync_interval)

    def on_status_change(self, callback: Callable[[bool], None]):
        """Register callback for Mac online/offline status changes."""
        self._on_status_change = callback


# Global sync manager (lazy initialization)
_sync_manager: Optional[SyncManager] = None


def get_sync_manager(remote_executor: Optional[RemoteExecutor] = None) -> SyncManager:
    """Get or create the global sync manager instance."""
    global _sync_manager
    if _sync_manager is None:
        if remote_executor is None:
            raise ValueError("RemoteExecutor required for first initialization")
        _sync_manager = SyncManager(remote_executor)
    return _sync_manager
