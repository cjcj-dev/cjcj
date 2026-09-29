"""GDB reader for the official x86_64 host runtime's existing USER request state.

No inferior calls or writes. GCRequest layout: upstream runtime/src/Heap/
Collector/GcRequest.h:39-49. RequestGC stores prevRequestTime at +32; verify
that store in the tested host runtime before using this x86_64 apparatus.
"""

import json
import os
from pathlib import Path

import gdb


result = {'events': [], 'inferior_rc': None}
output = Path(os.environ['PHASE_GC_OUTPUT'])
sites = ('ToCHIRPackage', 'DestroyASTResources',
         'PerformGenericInstantiation', 'PerformCHIRCompilation')


def exited(event):
    result['inferior_rc'] = getattr(event, 'exit_code', None)


class RequestState(gdb.Breakpoint):
    def __init__(self, address):
        self.address = address
        self.previous = self.read_state()['timestamp']
        super().__init__(f'*(unsigned long long*){address + 32}',
                         type=gdb.BP_WATCHPOINT, wp_class=gdb.WP_WRITE,
                         internal=True)

    def read_state(self):
        data = bytes(gdb.selected_inferior().read_memory(self.address, 40))
        return {'reason': int.from_bytes(data[:4], 'little'),
                'is_sync': bool(data[16]), 'is_concurrent': bool(data[17]),
                'timestamp': int.from_bytes(data[32:40], 'little')}

    def stop(self):
        state = self.read_state()
        stack = []
        frame = gdb.newest_frame()
        while frame is not None:
            stack.append(frame.name() or '<unknown>')
            frame = frame.older()
        # Choose the nearest caller: ToCHIRPackage is itself reached from
        # PerformCHIRCompilation, and must not be attributed to its ancestor.
        site = next((site for function in stack for site in sites if site in function), None)
        result['events'].append(dict(state, previous=self.previous, site=site,
                                     stack=stack, thread=gdb.selected_thread().global_num))
        self.previous = state['timestamp']
        return False


try:
    gdb.execute('set pagination off')
    gdb.execute('set confirm off')
    gdb.execute('set print thread-events off')
    gdb.execute('handle SIGSEGV SIGUSR1 SIGUSR2 SIGPIPE nostop noprint pass')
    gdb.events.exited.connect(exited)
    gdb.execute('starti', to_string=True)
    # Stop after shared libraries load without inserting a software breakpoint
    # into the compiler's instructions.
    gdb.Breakpoint('main', type=gdb.BP_HARDWARE_BREAKPOINT,
                   temporary=True, internal=True)
    gdb.execute('continue', to_string=True)
    address = int(gdb.parse_and_eval("(char *)&'_ZN12MapleRuntime12g_gcRequestsE'"))
    result['request_address'] = address
    watcher = RequestState(address)
    result['initial'] = watcher.read_state()
    gdb.execute('continue')
except Exception as error:
    result['observer_error'] = str(error)
finally:
    output.write_text(json.dumps(result, indent=2) + '\n')
