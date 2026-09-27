"""Case admission for private copies of the pinned upstream harnesses."""
import json
import os
from pathlib import Path
import time


def wait_for_load(case):
    # Called before upstream starts a case's timeout clock. Already running
    # cases drain normally; all idle workers stop admitting work above 160.
    paused = False
    while True:
        load = os.getloadavg()[0]
        if load <= 160:
            if paused:
                record('resume', case, load)
            return
        if not paused:
            record('pause', case, load)
            paused = True
        time.sleep(1)


def record(event, case, load):
    row = json.dumps(dict(event=event, case=str(case), load1=load,
                          pid=os.getpid(), time=time.time())) + '\n'
    fd = os.open(os.environ['CANGJIE_TEST_ADMISSION_LOG'],
                 os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        os.write(fd, row.encode())
    finally:
        os.close(fd)


def cleanup_executable(test, cfg):
    # Keep failure artifacts. Upstream Maple already removes passing work dirs.
    # Conformance keeps its binaries indefinitely unless we remove each result.
    if test.result != 'PASSED':
        return
    relative = Path(test.test_path).parent.relative_to(cfg.tests_root_path)
    binary = Path(cfg.binary_output_path) / relative / test.name
    if binary.is_file():
        binary.unlink()
