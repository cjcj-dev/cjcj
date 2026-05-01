from __future__ import annotations


class BuildError(RuntimeError):
    """Raised when a build stage or sub-process fails."""

    def __init__(self, stage: str, message: str, *, returncode: int | None = None) -> None:
        self.stage = stage
        self.returncode = returncode
        suffix = f" (exit={returncode})" if returncode is not None else ""
        super().__init__(f"[{stage}] {message}{suffix}")


class ConfigError(ValueError):
    """Raised for invalid configuration / unsupported targets."""
