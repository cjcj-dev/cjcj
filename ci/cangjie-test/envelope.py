"""Synchronous, inherited CPU envelope; never rewrite compiler arguments."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


def group():
    line = next(line for line in Path('/proc/self/cgroup').read_text().splitlines()
                if line.startswith('0::'))
    return Path('/sys/fs/cgroup') / line[3:].lstrip('/')


def terminate_children(signum, frame):
    # Only the dedicated scope created below; no name-based process matching.
    path = group()
    if path.name.startswith('cangjie-test-'):
        for pid in (path / 'cgroup.procs').read_text().split():
            if int(pid) != os.getpid():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
    raise SystemExit(128 + signum)


def enter():
    """Return envelope identity in child; return the child's rc in parent."""
    marker = os.environ.get('CANGJIE_TEST_SCOPE')
    if marker and group().name == marker + '.scope':
        # A closed caller session must not leave its tests running.
        parent = os.getppid()
        signal.signal(signal.SIGTERM, terminate_children)
        signal.signal(signal.SIGHUP, terminate_children)
        signal.signal(signal.SIGINT, terminate_children)
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'PR_SET_PDEATHSIG')
        if os.getppid() != parent:
            terminate_children(signal.SIGTERM, None)
        quota, period = (group() / 'cpu.max').read_text().split()
        affinity = sorted(os.sched_getaffinity(0))
        if quota == 'max' or int(quota) > 96 * int(period) or len(affinity) != 96:
            raise RuntimeError('CPU_ENVELOPE: expected 96 CPUs and quota <=96 CPUs')
        return dict(cgroup=str(group()), cpu_max=f'{quota} {period}', affinity=affinity)
    available = sorted(os.sched_getaffinity(0))
    if len(available) < 96:
        raise RuntimeError('CPU_ENVELOPE: requires 96 available CPUs')
    cpus = ','.join(map(str, available[-96:]))
    unit = 'cangjie-test-' + str(os.getpid()) + '-' + hashlib.sha256(os.getcwd().encode()).hexdigest()[:8]
    env = dict(os.environ, CANGJIE_TEST_SCOPE=unit)
    command = ['systemd-run', '--scope', '--quiet', '--unit=' + unit,
               '-p', 'AllowedCPUs=' + cpus, '-p', 'CPUQuota=9600%',
               sys.executable, *sys.argv]
    def stop(signum, frame):
        subprocess.run(['systemctl', 'stop', unit + '.scope'], check=False)
        raise SystemExit(128 + signum)
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, stop)
    parent = os.getppid()
    if ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0):
        raise RuntimeError('cannot bind CPU scope to caller lifetime')
    if os.getppid() != parent:
        stop(signal.SIGTERM, None)
    try:
        return subprocess.call(command, env=env)
    finally:
        subprocess.run(['systemctl', 'stop', unit + '.scope'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False)
