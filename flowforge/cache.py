"""
FlowForge Offline Cache Manager

SQLite-based caching for offline-first operation on Raspberry Pi.
Caches project data locally so iOS can function when Mac is offline.
"""

import json
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, Any
from dataclasses import dataclass, asdict


@dataclass
class CachedProject:
    """Cached project with config and registry snapshot."""
    name: str
    path: str
    cached_at: str
    config_json: Optional[str] = None
    registry_json: Optional[str] = None


@dataclass
class PendingOperation:
    """Operation queued while Mac was offline."""
    id: int
    project_name: str
    operation: str  # 'add_feature', 'update_feature', 'delete_feature'
    payload_json: str
    created_at: str
    status: str  # 'pending', 'syncing', 'completed', 'failed'
    error_message: Optional[str] = None


@dataclass
class SyncState:
    """Sync state for a project."""
    project_name: str
    last_sync: Optional[str]
    last_mac_registry_hash: Optional[str]
    sync_status: str  # 'synced', 'pending', 'conflict'


class CacheManager:
    """
    SQLite cache manager for offline-first operation.

    Stores project data locally on Pi so iOS app can:
    - View features when Mac is offline
    - Queue changes for later sync
    - Track sync state per project
    """

    def __init__(self, cache_dir: Optional[Path] = None):
        """Initialize cache manager with database path."""
        if cache_dir is None:
            cache_dir = Path.home() / ".flowforge-cache"
        cache_dir.mkdir(parents=True, exist_ok=True)

        self.db_path = cache_dir / "flowforge.db"
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        """Get database connection with row factory."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        """Initialize database schema."""
        conn = self._get_connection()
        try:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS projects (
                    name TEXT PRIMARY KEY,
                    path TEXT NOT NULL,
                    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    config_json TEXT,
                    registry_json TEXT
                );

                CREATE TABLE IF NOT EXISTS features (
                    id TEXT NOT NULL,
                    project_name TEXT NOT NULL,
                    data_json TEXT NOT NULL,
                    cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id, project_name),
                    FOREIGN KEY (project_name) REFERENCES projects(name)
                );

                CREATE TABLE IF NOT EXISTS pending_operations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    project_name TEXT NOT NULL,
                    operation TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    status TEXT DEFAULT 'pending',
                    error_message TEXT
                );

                CREATE TABLE IF NOT EXISTS sync_state (
                    project_name TEXT PRIMARY KEY,
                    last_sync TIMESTAMP,
                    last_mac_registry_hash TEXT,
                    sync_status TEXT DEFAULT 'pending'
                );

                CREATE INDEX IF NOT EXISTS idx_pending_status
                ON pending_operations(status);

                CREATE INDEX IF NOT EXISTS idx_pending_project
                ON pending_operations(project_name);

                CREATE INDEX IF NOT EXISTS idx_features_project
                ON features(project_name);
            """)
            conn.commit()
        finally:
            conn.close()

    # ========== Project Cache ==========

    def cache_project(
        self,
        name: str,
        path: str,
        config: Optional[dict] = None,
        registry: Optional[dict] = None
    ):
        """Cache a project's config and registry."""
        conn = self._get_connection()
        try:
            config_json = json.dumps(config) if config else None
            registry_json = json.dumps(registry) if registry else None

            conn.execute("""
                INSERT OR REPLACE INTO projects
                (name, path, cached_at, config_json, registry_json)
                VALUES (?, ?, ?, ?, ?)
            """, (name, path, datetime.utcnow().isoformat(), config_json, registry_json))

            # Also cache individual features for fast lookup
            if registry and "features" in registry:
                self._cache_features_from_registry(conn, name, registry["features"])

            conn.commit()
        finally:
            conn.close()

    def _cache_features_from_registry(self, conn: sqlite3.Connection, project_name: str, features: dict):
        """Cache individual features from registry."""
        # Clear existing features for this project
        conn.execute("DELETE FROM features WHERE project_name = ?", (project_name,))

        # Insert all features
        for feature_id, feature_data in features.items():
            conn.execute("""
                INSERT INTO features (id, project_name, data_json, cached_at)
                VALUES (?, ?, ?, ?)
            """, (feature_id, project_name, json.dumps(feature_data), datetime.utcnow().isoformat()))

    def get_cached_project(self, name: str) -> Optional[CachedProject]:
        """Get cached project by name."""
        conn = self._get_connection()
        try:
            row = conn.execute(
                "SELECT * FROM projects WHERE name = ?", (name,)
            ).fetchone()

            if row:
                return CachedProject(
                    name=row["name"],
                    path=row["path"],
                    cached_at=row["cached_at"],
                    config_json=row["config_json"],
                    registry_json=row["registry_json"]
                )
            return None
        finally:
            conn.close()

    def get_all_cached_projects(self) -> list[dict]:
        """Get list of all cached projects (name + path only)."""
        conn = self._get_connection()
        try:
            rows = conn.execute(
                "SELECT name, path FROM projects ORDER BY name"
            ).fetchall()
            return [{"name": row["name"], "path": row["path"]} for row in rows]
        finally:
            conn.close()

    def get_cached_features(self, project_name: str) -> list[dict]:
        """Get all cached features for a project."""
        conn = self._get_connection()
        try:
            rows = conn.execute(
                "SELECT data_json FROM features WHERE project_name = ? ORDER BY id",
                (project_name,)
            ).fetchall()
            return [json.loads(row["data_json"]) for row in rows]
        finally:
            conn.close()

    def get_cached_registry(self, project_name: str) -> Optional[dict]:
        """Get full cached registry for a project."""
        project = self.get_cached_project(project_name)
        if project and project.registry_json:
            return json.loads(project.registry_json)
        return None

    # ========== Pending Operations Queue ==========

    def queue_operation(
        self,
        project_name: str,
        operation: str,
        payload: dict
    ) -> int:
        """Queue an operation for later sync."""
        conn = self._get_connection()
        try:
            cursor = conn.execute("""
                INSERT INTO pending_operations
                (project_name, operation, payload_json, created_at, status)
                VALUES (?, ?, ?, ?, 'pending')
            """, (project_name, operation, json.dumps(payload), datetime.utcnow().isoformat()))
            conn.commit()
            return cursor.lastrowid
        finally:
            conn.close()

    def get_pending_operations(self, project_name: Optional[str] = None) -> list[PendingOperation]:
        """Get pending operations, optionally filtered by project."""
        conn = self._get_connection()
        try:
            if project_name:
                rows = conn.execute("""
                    SELECT * FROM pending_operations
                    WHERE project_name = ? AND status = 'pending'
                    ORDER BY created_at
                """, (project_name,)).fetchall()
            else:
                rows = conn.execute("""
                    SELECT * FROM pending_operations
                    WHERE status = 'pending'
                    ORDER BY created_at
                """).fetchall()

            return [PendingOperation(
                id=row["id"],
                project_name=row["project_name"],
                operation=row["operation"],
                payload_json=row["payload_json"],
                created_at=row["created_at"],
                status=row["status"],
                error_message=row["error_message"]
            ) for row in rows]
        finally:
            conn.close()

    def get_pending_count(self, project_name: Optional[str] = None) -> int:
        """Get count of pending operations."""
        conn = self._get_connection()
        try:
            if project_name:
                row = conn.execute("""
                    SELECT COUNT(*) as count FROM pending_operations
                    WHERE project_name = ? AND status = 'pending'
                """, (project_name,)).fetchone()
            else:
                row = conn.execute("""
                    SELECT COUNT(*) as count FROM pending_operations
                    WHERE status = 'pending'
                """).fetchone()
            return row["count"]
        finally:
            conn.close()

    def mark_operation_syncing(self, operation_id: int):
        """Mark operation as currently syncing."""
        conn = self._get_connection()
        try:
            conn.execute(
                "UPDATE pending_operations SET status = 'syncing' WHERE id = ?",
                (operation_id,)
            )
            conn.commit()
        finally:
            conn.close()

    def mark_operation_completed(self, operation_id: int):
        """Mark operation as successfully completed."""
        conn = self._get_connection()
        try:
            conn.execute(
                "UPDATE pending_operations SET status = 'completed' WHERE id = ?",
                (operation_id,)
            )
            conn.commit()
        finally:
            conn.close()

    def mark_operation_failed(self, operation_id: int, error: str):
        """Mark operation as failed with error message."""
        conn = self._get_connection()
        try:
            conn.execute(
                "UPDATE pending_operations SET status = 'failed', error_message = ? WHERE id = ?",
                (error, operation_id)
            )
            conn.commit()
        finally:
            conn.close()

    def clear_completed_operations(self):
        """Remove completed operations from queue."""
        conn = self._get_connection()
        try:
            conn.execute("DELETE FROM pending_operations WHERE status = 'completed'")
            conn.commit()
        finally:
            conn.close()

    # ========== Sync State ==========

    def get_sync_state(self, project_name: str) -> Optional[SyncState]:
        """Get sync state for a project."""
        conn = self._get_connection()
        try:
            row = conn.execute(
                "SELECT * FROM sync_state WHERE project_name = ?", (project_name,)
            ).fetchone()

            if row:
                return SyncState(
                    project_name=row["project_name"],
                    last_sync=row["last_sync"],
                    last_mac_registry_hash=row["last_mac_registry_hash"],
                    sync_status=row["sync_status"]
                )
            return None
        finally:
            conn.close()

    def update_sync_state(
        self,
        project_name: str,
        registry_hash: Optional[str] = None,
        sync_status: str = "synced"
    ):
        """Update sync state after successful sync."""
        conn = self._get_connection()
        try:
            conn.execute("""
                INSERT OR REPLACE INTO sync_state
                (project_name, last_sync, last_mac_registry_hash, sync_status)
                VALUES (?, ?, ?, ?)
            """, (project_name, datetime.utcnow().isoformat(), registry_hash, sync_status))
            conn.commit()
        finally:
            conn.close()

    def set_sync_pending(self, project_name: str):
        """Mark project as having pending changes to sync."""
        conn = self._get_connection()
        try:
            conn.execute("""
                UPDATE sync_state SET sync_status = 'pending'
                WHERE project_name = ?
            """, (project_name,))
            conn.commit()
        finally:
            conn.close()

    # ========== Utilities ==========

    @staticmethod
    def compute_registry_hash(registry: dict) -> str:
        """Compute hash of registry for change detection."""
        # Normalize by sorting keys
        normalized = json.dumps(registry, sort_keys=True)
        return hashlib.sha256(normalized.encode()).hexdigest()[:16]

    def get_cache_stats(self) -> dict:
        """Get cache statistics."""
        conn = self._get_connection()
        try:
            projects = conn.execute("SELECT COUNT(*) as count FROM projects").fetchone()["count"]
            features = conn.execute("SELECT COUNT(*) as count FROM features").fetchone()["count"]
            pending = conn.execute(
                "SELECT COUNT(*) as count FROM pending_operations WHERE status = 'pending'"
            ).fetchone()["count"]

            return {
                "projects_cached": projects,
                "features_cached": features,
                "pending_operations": pending,
                "db_path": str(self.db_path),
                "db_size_kb": self.db_path.stat().st_size // 1024 if self.db_path.exists() else 0
            }
        finally:
            conn.close()

    def clear_all(self):
        """Clear all cached data (for testing)."""
        conn = self._get_connection()
        try:
            conn.executescript("""
                DELETE FROM pending_operations;
                DELETE FROM sync_state;
                DELETE FROM features;
                DELETE FROM projects;
            """)
            conn.commit()
        finally:
            conn.close()


# Global cache instance (lazy initialization)
_cache_manager: Optional[CacheManager] = None


def get_cache_manager() -> CacheManager:
    """Get or create the global cache manager instance."""
    global _cache_manager
    if _cache_manager is None:
        _cache_manager = CacheManager()
    return _cache_manager
