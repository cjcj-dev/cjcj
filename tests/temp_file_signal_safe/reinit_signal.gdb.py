import gdb, json, os
records=[]
freed=[]
exits=[]
gdb.events.exited.connect(lambda e: exits.append(getattr(e,'exit_code',None)))
class Returned(gdb.FinishBreakpoint):
    def __init__(self,frame,p,s):
        self.p,self.s=p,s
        super().__init__(frame,internal=True)
    def stop(self):
        freed.append({'ptr':self.p,'path':self.s})
        return True
class Free(gdb.Breakpoint):
    def stop(self):
        frame=gdb.newest_frame()
        names=[]
        f=frame
        while f:
            names.append(f.name() or '')
            f=f.older()
        if len(names)>1 and 'TempFileManager4Init' in names[1]:
            p=int(gdb.parse_and_eval('$rsi'))
            try:
                s=gdb.Value(p).cast(gdb.lookup_type('char').pointer()).string(errors='replace')
            except Exception:
                return False
            if 'cangjie-tmp-' in s:
                Returned(frame,p,s) if os.environ.get('SIGNAL_TIMING', 'after') == 'after' else None
                if os.environ.get('SIGNAL_TIMING') == 'before':
                    freed.append({'ptr':p,'path':s,'not_yet_freed':True})
                    self.enabled=False
                    return True
                self.enabled=False
        return False
class Delete(gdb.Breakpoint):
    def stop(self):
        p=int(gdb.parse_and_eval('$rdi'))
        records.append({'api':self.location,'ptr':p,'released_argument':any(x['ptr']==p and not x.get('not_yet_freed',False) for x in freed)})
        return False
Free('_CNat4LibC4freeHk',internal=True)
Delete('unlink',internal=True)
Delete('rmdir',internal=True)
gdb.execute('set breakpoint pending on')
gdb.execute('handle SIGUSR1 SIGUSR2 SIGPWR nostop noprint pass')
gdb.execute('handle SIGINT nostop noprint pass')
gdb.execute('run')
if freed:
    try:
        gdb.execute('call (int)raise(2)')
        gdb.execute('call (unsigned int)sleep(2)')
    except gdb.error as e:
        print('INFERIOR_CALL_STATUS '+str(e))
result={'freed':freed,'calls':records,'exit_codes':exits}
with open(os.environ['OBS_RESULT'],'w') as f:json.dump(result,f,indent=2)
print('REINIT_SIGNAL_OBSERVATION '+json.dumps(result))
gdb.execute('quit')
