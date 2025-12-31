"""
Path translation for Forge Pi→Mac architecture.

When Forge runs on a Raspberry Pi but git repos live on Mac,
paths need to be translated between the two environments.

Pi stores: /home/brian/AirFit (or relative: AirFit)
Mac needs: /Users/Brian/Projects/Active/AirFit

This module handles the translation transparently.
"""

from pathlib import Path
from typing import Optional
import os


class PathTranslator:
    """
    Translates paths between Pi and Mac environments.

    Usage:
        translator = PathTranslator(
            pi_base="/home/brian",
            mac_base="/Users/Brian/Projects/Active"
        )

        # For SSH commands to Mac
        mac_path = translator.pi_to_mac("/home/brian/AirFit")
        # -> "/Users/Brian/Projects/Active/AirFit"

        # For storing in registry
        relative = translator.to_relative("/Users/Brian/Projects/Active/AirFit")
        # -> "AirFit"

    Passthrough mode:
        If pi_base == mac_base or either is None, translations are no-ops.
        This supports running Forge directly on Mac (local development).
    """

    def __init__(self, pi_base: Optional[str], mac_base: Optional[str]):
        """
        Initialize path translator.

        Args:
            pi_base: Base path on Pi (e.g., "/home/brian")
            mac_base: Base path on Mac (e.g., "/Users/Brian/Projects/Active")
        """
        self.pi_base = pi_base.rstrip("/") if pi_base else None
        self.mac_base = mac_base.rstrip("/") if mac_base else None

        # Passthrough if both are None, same, or either is missing
        self.is_passthrough = (
            (self.pi_base == self.mac_base)
            or not self.pi_base
            or not self.mac_base
        )

    def pi_to_mac(self, pi_path: str) -> str:
        """
        Convert Pi path to Mac path for SSH commands.

        Args:
            pi_path: Path on Pi (e.g., "/home/brian/AirFit")

        Returns:
            Mac path (e.g., "/Users/Brian/Projects/Active/AirFit")
        """
        if self.is_passthrough:
            return pi_path

        if pi_path.startswith(self.pi_base):
            return pi_path.replace(self.pi_base, self.mac_base, 1)
        return pi_path

    def mac_to_pi(self, mac_path: str) -> str:
        """
        Convert Mac path to Pi path for local operations.

        Args:
            mac_path: Path on Mac (e.g., "/Users/Brian/Projects/Active/AirFit")

        Returns:
            Pi path (e.g., "/home/brian/AirFit")
        """
        if self.is_passthrough:
            return mac_path

        if mac_path.startswith(self.mac_base):
            return mac_path.replace(self.mac_base, self.pi_base, 1)
        return mac_path

    def to_relative(self, full_path: str) -> str:
        """
        Extract project-relative path for registry storage.

        Strips either Pi or Mac base to get a portable relative path.

        Args:
            full_path: Full path from either environment

        Returns:
            Relative path (e.g., "AirFit/.forge-worktrees/dark-mode")
        """
        if self.pi_base and full_path.startswith(self.pi_base):
            return full_path[len(self.pi_base):].lstrip("/")
        if self.mac_base and full_path.startswith(self.mac_base):
            return full_path[len(self.mac_base):].lstrip("/")
        # Already relative or unrecognized base
        return full_path

    def resolve_for_pi(self, path: str) -> str:
        """
        Resolve a path for use on Pi.

        If relative, prepends Pi base. If absolute Mac path, converts.

        Args:
            path: Relative or absolute path

        Returns:
            Absolute Pi path
        """
        if self.is_passthrough:
            # In passthrough mode, use mac_base or pi_base (whichever exists)
            base = self.mac_base or self.pi_base or ""
            if not os.path.isabs(path):
                return os.path.join(base, path)
            return path

        if not os.path.isabs(path):
            # Relative path - prepend Pi base
            return os.path.join(self.pi_base, path)
        if path.startswith(self.mac_base):
            # Mac absolute path - convert to Pi
            return self.mac_to_pi(path)
        return path

    def resolve_for_mac(self, path: str) -> str:
        """
        Resolve a path for use on Mac (SSH commands).

        If relative, prepends Mac base. If absolute Pi path, converts.

        Args:
            path: Relative or absolute path

        Returns:
            Absolute Mac path
        """
        if self.is_passthrough:
            base = self.mac_base or self.pi_base or ""
            if not os.path.isabs(path):
                return os.path.join(base, path)
            return path

        if not os.path.isabs(path):
            # Relative path - prepend Mac base
            return os.path.join(self.mac_base, path)
        if path.startswith(self.pi_base):
            # Pi absolute path - convert to Mac
            return self.pi_to_mac(path)
        return path


def create_path_translator() -> PathTranslator:
    """
    Create PathTranslator from environment variables.

    Reads:
        FORGE_PROJECTS_PATH - Pi-native base path
        FORGE_MAC_PROJECTS_PATH - Mac base path (for SSH)

    Returns:
        Configured PathTranslator
    """
    pi_base = os.environ.get("FORGE_PROJECTS_PATH")
    mac_base = os.environ.get("FORGE_MAC_PROJECTS_PATH")

    return PathTranslator(pi_base, mac_base)
