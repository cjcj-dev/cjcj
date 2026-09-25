"""Observe native path ownership without replacing or modifying product calls.

Run in batch gdb on the fixture; set ALLOCATION_RESULT and EXPECT_LIVE.
EXPECT_LIVE=0 for normal/reinit; EXPECT_LIVE=2 for the direct positive control.
The x86-64 ABI supplies CString return values in rax and free's pointer in rdi.
"""
import gdb,json,os
exit_codes=[]
gdb.events.exited.connect(lambda event: exit_codes.append(getattr(event, 'exit_code', None)))
allocations=[]
live={}
errors=[]
class AllocationReturn(gdb.FinishBreakpoint):
    def __init__(self, frame):
        self.caller = frame.older().name() if frame.older() else None
        super().__init__(frame, internal=True)
    def stop(self):
        try:
            p=int(gdb.parse_and_eval('$rax'))
            s=gdb.Value(p).cast(gdb.lookup_type('char').pointer()).string()
            if 'cangjie-tmp-' in s:
                record={'ptr':hex(p),'path':s,'freed':False,'caller':self.caller}
                allocations.append(record);live[p]=record
        except Exception as e:errors.append(str(e))
        return False
class Allocate(gdb.Breakpoint):
    def stop(self):
        AllocationReturn(gdb.newest_frame())
        return False
class Free(gdb.Breakpoint):
    def stop(self):
        p=int(gdb.parse_and_eval('$rdi'))
        if p in live:
            live.pop(p)['freed']=True
        return False
Allocate('_CNat4LibC13mallocCStringHRNat6StringE',internal=True)
Free('__libc_free',internal=True)
gdb.execute('run')
result={'allocations':allocations,'live':list(live.values()),'errors':errors,'exit_codes':exit_codes}
with open(os.environ['ALLOCATION_RESULT'],'w') as f:json.dump(result,f,indent=2)
print('ALLOCATION_RESULT '+json.dumps(result))
expected = int(os.environ['EXPECT_LIVE'])
passed = exit_codes == [0] and bool(allocations) and not errors and len(live) == expected
print('OWNERSHIP_ASSERT expected_live=%d actual_live=%d pass=%s' % (expected,len(live),passed))
gdb.execute('quit '+('0' if passed else '1'))
