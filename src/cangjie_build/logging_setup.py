from __future__ import annotations

import logging
import sys
import time
from collections.abc import Generator
from contextlib import contextmanager

from rich.console import Console
from rich.logging import RichHandler

_CONSOLE = Console(stderr=True, highlight=False, soft_wrap=True)


def _make_handler(level: str) -> logging.Handler:
    """RichHandler on a TTY, plain StreamHandler elsewhere.

    In CI logs Rich cannot detect terminal width and falls back to 80 columns,
    after which its time/message Table layout wraps every line. A plain
    formatter avoids that and keeps each log record on one row.
    """
    handler: logging.Handler
    if sys.stderr.isatty():
        handler = RichHandler(
            console=_CONSOLE,
            show_path=False,
            show_time=True,
            omit_repeated_times=False,
            markup=False,
            rich_tracebacks=True,
        )
    else:
        handler = logging.StreamHandler()
        handler.setFormatter(
            logging.Formatter(
                fmt="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
        )
    handler.setLevel(level)
    return handler


def configure_logging(level: str = "INFO") -> None:
    """Install a single log handler at the desired level. Idempotent."""
    root = logging.getLogger()
    for h in list(root.handlers):
        root.removeHandler(h)
    root.addHandler(_make_handler(level))
    root.setLevel(level)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


@contextmanager
def stage(name: str) -> Generator[None]:
    """Wrap a build stage with a banner + duration log line."""
    log = get_logger("cangjie_build.stage")
    log.info("==> %s: starting", name)
    started = time.monotonic()
    try:
        yield
    except BaseException:
        elapsed = time.monotonic() - started
        log.error("==> %s: FAILED after %.1fs", name, elapsed)
        raise
    else:
        elapsed = time.monotonic() - started
        log.info("==> %s: done in %.1fs", name, elapsed)
