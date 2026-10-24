#!/usr/bin/env zx
// One local execution supervisor. Python owns both kernel children and every
// original jobserver byte; this ESM client owns no CPU loans. Vendored verbatim
// into runtime/stdlib/scripts/command-supervisor.mjs at a fixed source commit.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const flagNames = ['CARGO_MAKEFLAGS', 'MAKEFLAGS', 'MFLAGS'];
function authentication(env) {
  for (const name of flagNames) {
    const found = [...(env[name] || '').matchAll(/(?:^|\s)--jobserver-(?:auth|fds)=([^\s]+)/g)];
    if (found.length) return {auth:found.at(-1)[1], flags:env[name]};
  }
  return {};
}
function requestJobs(env, jobs) {
  if (jobs === undefined) {
    const flags = authentication(env).flags || '';
    const found = [...flags.matchAll(/(?:^|\s)-j\s*(\d+)(?=\s|$)/g)];
    jobs = found.length ? Number(found.at(-1)[1]) : os.availableParallelism();
  }
  if (!Number.isSafeInteger(jobs) || jobs < 1 || jobs > 4096) throw new Error('SUPERVISOR_JOBS_RANGE');
  return jobs;
}
// Kept inside the ESM source, like the existing archive verifier's Python
// program. No generated script or runtime checkout of another repository.
const program = String.raw`
import os,sys,json,signal,ctypes,time,tempfile,errno,re
from pathlib import Path
config=json.loads(sys.argv[1])
control,status=3,4
os.set_blocking(control,False);os.set_blocking(status,False)
os.set_inheritable(control,False);os.set_inheritable(status,False)
signal.signal(signal.SIGPIPE,signal.SIG_IGN)
cancelled=None;reason=None;cancel_at=None;go=False;signal_pending=None
primary=None;primary_fd=None;child_rc=None;fork_attempted=False
exec_read=None;exec_write=None;exec_buffer=b'';exec_state='not-started'
control_open=True;pending=b'';status_pending=b'';status_open=True
borrowed=bytearray();returned=0;upstream_write=None;pool_fd=None;directory=None
expected=None;q=1;private_auth=None;report_once=set();quiescent=False
remaining=0;pool_drained=False;pool_closed=False;pool_unlinked=False;pool_done=False
error=None;diagnostic_rc=None;diagnostic_done=False;phase='api'

# These two functions only latch in-memory state. In particular signal handlers
# never stat a diagnostic file, send a signal, or throw into a ledger update.
def stop(sig=None,why=None):
    global cancelled,reason,cancel_at
    if reason is None:
        reason=why or 'cancelled';cancelled=sig if why is None or why=='cancelled' else None
        cancel_at=time.monotonic()

def latch_error(where,exc):
    global error
    if error is None:error='SUPERVISOR_'+where+': '+type(exc).__name__+': '+str(exc)
    stop(None,'supervisor-error')

def on_signal(sig,_):
    global signal_pending
    if signal_pending is None:signal_pending=sig
for number in (signal.SIGINT,signal.SIGTERM):signal.signal(number,on_signal)

def trace(event,**fields):
    target=os.environ.get('CANGJIE_JOBSERVER_LOG')
    if not target:return
    try:
        fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_APPEND,0o600)
        try:os.write(fd,(json.dumps(dict(event=event,pid=os.getpid(),time_ns=str(time.monotonic_ns()),**fields))+'\n').encode())
        finally:os.close(fd)
    except BaseException as exc:latch_error('TRACE',exc)

def flush_status():
    global status_pending,status_open
    if not status_open:return
    while status_pending:
        try:
            n=os.write(status,status_pending)
            if not n:raise OSError(errno.EIO,'zero status write')
            status_pending=status_pending[n:]
        except BlockingIOError:return
        except BaseException as exc:
            status_open=False;status_pending=b''
            latch_error('STATUS',exc)
            return

def emit(row):
    global status_pending
    try:
        row=dict(row,guardian=os.getpid(),directory=directory)
        if directory:
            try:
                p=Path(directory,'status.json');tmp=Path(directory,'status.tmp')
                tmp.write_text(json.dumps(row)+'\n');os.replace(tmp,p)
            except BaseException as exc:latch_error('STATUS_FILE',exc)
        data=(json.dumps(row)+'\n').encode()
        if len(status_pending)+len(data)<65536:status_pending+=data
        else:latch_error('STATUS',RuntimeError('status backlog'))
        flush_status()
    except BaseException as exc:latch_error('STATUS_ENCODE',exc)

def incomplete(message):
    if message in report_once:return
    report_once.add(message)
    emit(dict(type='incomplete',rc=1,error=message,reason=reason,reaped=quiescent,
              borrowed=len(borrowed),returned=returned,unreturnedHex=bytes(borrowed[returned:]).hex(),execState=exec_state))
    trace('supervisor-incomplete',error=message,borrowed=len(borrowed),returned=returned)

def responsibility_error(where,exc):
    latch_error(where,exc)
    incomplete(error)

def poll_control():
    global pending,go,control_open,signal_pending
    if signal_pending is not None:
        # Keep the signal pending if the diagnostic query returns an error.
        failure=directory and Path(directory,'failure').exists()
        sig=signal_pending;signal_pending=None
        stop(sig,None if not failure else 'command-failure')
    owner_fd=config.get('ownerFd')
    if owner_fd is not None:
        try:
            if not os.read(owner_fd,1):stop(None,'owner-eof')
        except BlockingIOError:pass
        except OSError:stop(None,'owner-eof')
    if not control_open:return
    while True:
        try:data=os.read(control,4096)
        except BlockingIOError:break
        except OSError:data=b''
        if not data:
            control_open=False;stop(None,'owner-eof');break
        pending+=data
        if len(pending)>65536:stop(None,'control-invalid');pending=b'';break
        while b'\n' in pending:
            line,pending=pending.split(b'\n',1)
            try:row=json.loads(line)
            except Exception:stop(None,'control-invalid');continue
            if row.get('go') is True:go=True
            elif row.get('cancel') in ('SIGINT','SIGTERM'):stop(getattr(signal,row['cancel']))
            else:stop(None,'control-invalid')

def pulse():
    try:poll_control();flush_status()
    except BaseException as exc:responsibility_error('CONTROL',exc)
    if error:incomplete(error)

def owned_children():
    return [int(value) for value in Path('/proc/self/task',str(os.getpid()),'children').read_text().split()]

def proc_preflight():
    owned_children();os.readlink('/proc/self/fd/'+str(control))
    [int(name) for name in os.listdir('/proc/self/fd')]
    for api in (os.fork,os.execvpe,os.waitstatus_to_exitcode,signal.pthread_sigmask):
        if not callable(api):raise RuntimeError('FORK_EXEC_API_UNAVAILABLE')
    mask=signal.pthread_sigmask(signal.SIG_BLOCK,set())
    signal.pthread_sigmask(signal.SIG_SETMASK,mask)
    r,w=os.pipe2(os.O_CLOEXEC|os.O_NONBLOCK)
    try:
        for fd,mode in ((r,os.O_RDONLY),(w,os.O_WRONLY)):
            reopened=os.open('/proc/self/fd/'+str(fd),mode|os.O_NONBLOCK);os.close(reopened)
    finally:os.close(r);os.close(w)

def auth_value():
    for name in ('CARGO_MAKEFLAGS','MAKEFLAGS','MFLAGS'):
        found=re.findall(r'(?:^|\s)--jobserver-(?:auth|fds)=([^\s]+)',os.environ.get(name,''))
        if found:return found[-1]
    return None

def borrow_pool():
    global upstream_write,pool_fd,expected,q,private_auth
    auth=auth_value();disabled=bool(auth and re.fullmatch(r'-?\d+,-?\d+',auth) and any(int(x)<0 for x in auth.split(',')))
    parent=auth is not None and not disabled
    if parent:
        if auth.startswith('fifo:'):
            source=auth[5:]
            if not __import__('stat').S_ISFIFO(os.stat(source).st_mode):raise RuntimeError('JOBSERVER_NOT_FIFO')
            read=os.open(source,os.O_RDONLY|os.O_NONBLOCK)
            try:upstream_write=os.open(source,os.O_WRONLY|os.O_NONBLOCK)
            except BaseException:os.close(read);raise
        elif re.fullmatch(r'\d+,\d+',auth):
            r,w=map(int,auth.split(','))
            if min(r,w)<5 or max(r,w)>1023:raise RuntimeError('JOBSERVER_INVALID_FD')
            for fd in (r,w):
                if not __import__('stat').S_ISFIFO(os.fstat(fd).st_mode):raise RuntimeError('JOBSERVER_NOT_PIPE')
            read=os.open('/proc/self/fd/'+str(r),os.O_RDONLY|os.O_NONBLOCK)
            try:upstream_write=os.open('/proc/self/fd/'+str(w),os.O_WRONLY|os.O_NONBLOCK)
            except BaseException:os.close(read);raise
            for fd in set((r,w)):os.close(fd)
        else:raise RuntimeError('JOBSERVER_INVALID_AUTH')
        try:
            for _ in range(config['jobs']-1):
                try:byte=os.read(read,1)
                except BlockingIOError:break
                if not byte:raise RuntimeError('JOBSERVER_EOF')
                borrowed.extend(byte)
        finally:os.close(read)
        q=1+len(borrowed)
    elif disabled:q=1
    else:q=config['jobs'] if config['mode']=='ninja' else 1
    if parent or disabled or config['mode']=='ninja':
        fifo=str(Path(directory,'fifo'));os.mkfifo(fifo,0o600)
        pool_fd=os.open(fifo,os.O_RDWR|os.O_NONBLOCK)
        expected=q if config['mode']=='ninja' else q-1
        if expected:os.write(pool_fd,b'+'*expected)
        private_auth=('fifo:'+fifo) if config['mode']=='ninja' else '3,4'
    trace('pool-start' if config['mode']=='ninja' else 'scope-budget',directory=directory,
          requested=config['jobs'],jobs=q,imported=parent,disabled=disabled,borrowed=len(borrowed),command=config['argv'])

def payload_environment():
    env=dict(os.environ)
    for key in ('CJCJ_COMMAND_LIFETIME_FD','CANGJIE_JOBSERVER_ROOT','CANGJIE_JOBSERVER_JOBS'):env.pop(key,None)
    env['CJCJ_SUPERVISOR_PARENT']=str(os.getpid())
    if private_auth:
        env['CJPM_JOBSERVER']='1'
        for key in ('CARGO_MAKEFLAGS','MAKEFLAGS','MFLAGS'):
            old=re.sub(r'(?:^|\s)--jobserver-(?:auth|fds)=[^\s]+','',env.get(key,''))
            old=re.sub(r'(?:^|\s)-j(?:\s*\d+)?(?=\s|$)','',old)
            env[key]=old.strip()+' --jobserver-auth='+private_auth+' -j'+str(q)
    if config['mode']=='ninja':env['CANGJIE_JOBSERVER_ROOT']=directory;env['CANGJIE_JOBSERVER_JOBS']=str(q)
    return env

class Primary:
    def __init__(self):self.pid=None;self.returncode=None
    def poll(self):
        if self.returncode is None:
            pid,value=os.waitpid(self.pid,os.WNOHANG)
            if pid:self.returncode=os.waitstatus_to_exitcode(value)
        return self.returncode

def setup_child():
    if pool_fd is not None:
        os.dup2(pool_fd,3);os.dup2(pool_fd,4)
        if pool_fd not in (3,4):os.close(pool_fd)

def spawn_primary():
    global primary,primary_fd,exec_read,exec_write,exec_state,fork_attempted
    env=payload_environment();child=Primary()
    exec_read,exec_write=os.pipe2(os.O_CLOEXEC|os.O_NONBLOCK)
    # G is single-threaded. Snapshot after creating all child FDs; no new FD is
    # created between here and fork. This also covers high inherited fd numbers.
    descriptors=[int(name) for name in os.listdir('/proc/self/fd')]
    previous_mask=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGINT,signal.SIGTERM})
    try:
        fork_attempted=True
        pid=os.fork()
        if pid==0:
            try:
                for name in ('SIGINT','SIGTERM','SIGPIPE','SIGXFZ','SIGXFSZ'):
                    if hasattr(signal,name):signal.signal(getattr(signal,name),signal.SIG_DFL)
                os.setsid();setup_child()
                keep={0,1,2,exec_write}|({3,4} if pool_fd is not None else set())
                for fd in descriptors:
                    if fd>=3 and fd not in keep:
                        try:os.close(fd)
                        except OSError as exc:
                            if exc.errno!=errno.EBADF:raise
                signal.pthread_sigmask(signal.SIG_SETMASK,previous_mask)
                os.execvpe(config['argv'][0],config['argv'],env)
            except BaseException as exc:
                # One small atomic error record; writer is CLOEXEC. No original
                # ledger is transferred to this child, even on pre-exec failure.
                try:os.write(exec_write,json.dumps({'errno':getattr(exc,'errno',None),'error':type(exc).__name__+': '+str(exc)}).encode()[:3000])
                except BaseException:pass
            finally:os._exit(127)
        child.pid=pid;primary=child;exec_state='pending'
    finally:signal.pthread_sigmask(signal.SIG_SETMASK,previous_mask)
    fd=exec_write;exec_write=None;os.close(fd)
    primary_fd=os.pidfd_open(primary.pid)

def poll_exec():
    global exec_read,exec_buffer,exec_state
    if exec_read is None:return
    while True:
        try:data=os.read(exec_read,4096)
        except BlockingIOError:return
        if data:
            exec_buffer+=data
            if len(exec_buffer)>4096:raise RuntimeError('exec error record too large')
        else:
            fd=exec_read;exec_read=None;os.close(fd)
            exec_state='error' if exec_buffer else 'closed'
            if exec_buffer:
                detail=json.loads(exec_buffer)
                latch_error('SPAWN',RuntimeError(detail['error']))
            trace('supervisor-exec-channel',state=exec_state,child=primary.pid)
            return

def await_primary():
    global primary_fd,child_rc
    while True:
        poll_exec()
        value=primary.poll()
        if value is not None:
            child_rc=value
            poll_exec()
            return
        if primary_fd is None:primary_fd=os.pidfd_open(primary.pid)
        pulse()
        if reason is not None:
            try:signal.pidfd_send_signal(primary_fd,signal.SIGKILL if time.monotonic()-cancel_at>=1.5 else (cancelled or signal.SIGTERM))
            except ProcessLookupError:pass
            if time.monotonic()-cancel_at>=5:incomplete('PRIMARY_NOT_REAPED')
        time.sleep(0.01)

def prepare():
    global phase,directory
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(36,1,0,0,0)!=0:raise OSError(ctypes.get_errno(),'PR_SET_CHILD_SUBREAPER')
    check=ctypes.c_int()
    if libc.prctl(37,ctypes.byref(check),0,0,0)!=0 or check.value!=1:raise RuntimeError('SUBREAPER_NOT_ACTIVE')
    probe=os.pidfd_open(os.getpid());signal.pidfd_send_signal(probe,0);os.close(probe)
    phase='proc';proc_preflight()
    phase='work';directory=tempfile.mkdtemp(prefix='.cangjie-supervisor-',dir=config['workRoot'])
    if config.get('ownerFd') is not None:os.set_blocking(config['ownerFd'],False);os.set_inheritable(config['ownerFd'],False)
    phase='borrow';borrow_pool()
    Path(directory,'group').write_text(str(os.getpid()))
    emit(dict(type='ready',jobs=q,borrowed=len(borrowed),mode=config['mode']))
    trace('supervisor-ready',directory=directory,mode=config['mode'],jobs=q,borrowed=len(borrowed),owner=os.getppid())
    while not go and reason is None:pulse();time.sleep(0.005)
    pulse()
    if reason is None:
        phase='spawn';spawn_primary()
        emit(dict(type='child',child=primary.pid,jobs=q,mode=config['mode']))
        trace('supervisor-child',child=primary.pid,directory=directory,mode=config['mode'])

def drain():
    global quiescent
    if not fork_attempted:
        quiescent=True
        return
    began=time.monotonic();sent=set()
    while True:
        owned_children()
        try:
            while True:
                pid,_=os.waitpid(-1,os.WNOHANG)
                if pid==0:break
        except ChildProcessError:
            quiescent=True
            return
        children=owned_children();elapsed=time.monotonic()-began
        if elapsed>5:incomplete('OWNED_CHILDREN_NOT_REAPED')
        for pid in children:
            try:fd=os.pidfd_open(pid)
            except ProcessLookupError:continue
            try:
                if pid not in sent or elapsed>=0.5:
                    signal.pidfd_send_signal(fd,signal.SIGKILL if elapsed>=0.5 else (cancelled or signal.SIGTERM));sent.add(pid)
            except ProcessLookupError:pass
            finally:os.close(fd)
        pulse();time.sleep(0.01)

def close_channel(name):
    fd=globals()[name]
    if fd is not None:
        globals()[name]=None
        os.close(fd) # Linux consumes the FD even when close reports EINTR/EIO.

def finish_pool():
    global remaining,pool_drained,pool_closed,pool_unlinked,pool_done
    if not quiescent:raise RuntimeError('POOL_BEFORE_QUIESCENT')
    if not pool_drained:
        if pool_fd is not None:
            while True:
                try:data=os.read(pool_fd,4096)
                except BlockingIOError:break
                if not data:break
                remaining+=len(data)
        pool_drained=True
    if not pool_closed:
        pool_closed=True;close_channel('pool_fd')
    if not pool_unlinked:
        if directory:
            try:os.unlink(str(Path(directory,'fifo')))
            except FileNotFoundError:pass
        pool_unlinked=True
    pool_done=True

def signal_name(number):
    # Linux real-time signals between SIGRTMIN and SIGRTMAX are valid but
    # need not have Python enum members. Their number is the stable identity.
    if number is None:return None
    try:return signal.Signals(number).name
    except ValueError:return None

def result_code():
    rc=(128+cancelled) if cancelled else (child_rc if child_rc is not None and child_rc>=0 else 128-child_rc if child_rc is not None else 1)
    if reason and not cancelled and rc==0:rc=1
    if diagnostic_rc is not None and not cancelled:rc=diagnostic_rc
    if error and not cancelled:rc=1
    return rc

def resolve_diagnostics():
    global diagnostic_rc,diagnostic_done,error
    failure=Path(directory,'failure') if directory else None
    if failure and failure.exists():
        first=json.loads(failure.read_text())
        value=first.get('rc') or 1
        if not isinstance(value,int) or value<0 or value>255:raise ValueError('invalid failure rc')
        diagnostic_rc=value
    if result_code()==0 and expected is not None and remaining!=expected:
        error='JOBSERVER_TOKEN_IMBALANCE expected='+str(expected)+' returned='+str(remaining)
    diagnostic_done=True

def give_back():
    global returned
    if not (quiescent and pool_done and diagnostic_done):raise RuntimeError('RETURN_BEFORE_SETTLED')
    since=time.monotonic()
    while returned<len(borrowed):
        try:
            n=os.write(upstream_write,borrowed[returned:])
            if n>0:returned+=n;continue
            raise OSError(errno.EIO,'zero return write')
        except OSError as exc:
            if exc.errno==errno.EINTR:continue
            if exc.errno not in (errno.EAGAIN,errno.EWOULDBLOCK):responsibility_error('RETURN',exc)
        if time.monotonic()-since>5:incomplete('JOBSERVER_RETURN_BLOCKED')
        pulse();time.sleep(0.05)
    close_channel('upstream_write')

# One exception boundary owns every phase from prepare/first read through final
# status. A failed stage keeps its cursor; no finally can jump to byte return.
try:prepare()
except BaseException as exc:latch_error(phase.upper(),exc)
phase='primary' if primary is not None else 'reap'
while phase!='done':
    try:
        if phase=='primary':
            await_primary()
            emit(dict(type='payload-exit',child=primary.pid,childRc=child_rc))
            trace('supervisor-payload-exit',child=primary.pid,childRc=child_rc,directory=directory)
            phase='reap'
        elif phase=='reap':
            drain();close_channel('primary_fd');close_channel('exec_read');close_channel('exec_write')
            phase='pool'
        elif phase=='pool':
            finish_pool();phase='diagnostics'
        elif phase=='diagnostics':
            resolve_diagnostics()
            trace('owned-reaped',child=primary.pid if primary else None,childRc=child_rc,reaped=True)
            if config['mode']=='ninja':trace('pool-end',directory=directory,jobs=q,returned=remaining,missing=(expected or 0)-remaining,rc=result_code())
            phase='return'
        elif phase=='return':
            give_back()
            if borrowed:trace('parent-return',count=returned,originalHex=bytes(borrowed).hex())
            phase='finish'
        elif phase=='finish':
            row=dict(type='finished',rc=result_code(),child=primary.pid if primary else None,childRc=child_rc,
                childSignal=signal_name(-child_rc) if child_rc is not None and child_rc<0 else None,
                childSignalNumber=-child_rc if child_rc is not None and child_rc<0 else None,
                cancelled=cancelled is not None,cancellationSignal=signal_name(cancelled),cancellationSignalNumber=cancelled,
                reason=reason,error=error,reaped=quiescent,ledgerReturned=returned==len(borrowed),borrowed=len(borrowed),returned=returned,jobs=q,execState=exec_state)
            trace('supervisor-finished',**{k:v for k,v in row.items() if k!='type'})
            row['rc']=result_code();row['error']=error
            emit(row)
            for _ in range(20):
                flush_status()
                if not status_pending:break
                time.sleep(0.005)
            phase='done'
    except BaseException as exc:
        responsibility_error(phase.upper(),exc)
        pulse();time.sleep(0.01)
sys.exit(result_code())
`;

export async function supervisedCommand(argv, {cwd, env=process.env, mode='ordinary', jobs, signal, onEvent, workRoot}={}) {
  if (process.platform !== 'linux') throw new Error('SUPERVISOR_LINUX_REQUIRED');
  if (!Array.isArray(argv) || !argv.length || argv.some(x=>typeof x!=='string')) throw new Error('SUPERVISOR_ARGV');
  jobs=requestJobs(env,jobs);
  const environment={...env};delete environment.CJCJ_COMMAND_LIFETIME_FD;
  workRoot=path.resolve(workRoot||environment.CJCJ_SUPERVISOR_WORK||fs.mkdtempSync(path.join(os.tmpdir(),'cangjie-supervisor-work-')));
  fs.mkdirSync(workRoot,{recursive:true});
  environment.CJCJ_SUPERVISOR_WORK=workRoot;
  const stdio=['inherit','inherit','inherit','pipe','pipe'];
  const {auth}=authentication(environment);
  if (auth && /^\d+,\d+$/.test(auth)) {
    const originals=auth.split(',').map(Number);
    for (const fd of originals) if (!Number.isSafeInteger(fd)||fd<3||fd>1023||!fs.fstatSync(fd).isFIFO()) throw new Error('JOBSERVER_INVALID_FD');
    stdio.push(...originals);
    // Rewrite ONLY the selected authentication; all flags are normalized by G
    // before payload launch. The original open-file descriptions are untouched.
    for (const name of flagNames) environment[name]=(environment[name]||'').replace(/(--jobserver-(?:auth|fds)=)\d+,\d+/g,(_,prefix)=>prefix+'5,6');
  }
  let ownerFd;
  const ownerEndpoint=environment.CJCJ_SUPERVISOR_OWNER_FD;
  delete environment.CJCJ_SUPERVISOR_OWNER_FD;
  if(ownerEndpoint!==undefined){
    const fd=Number(ownerEndpoint);
    if(!/^\d+$/.test(ownerEndpoint)||fd<3||fd>1023||!fs.fstatSync(fd).isFIFO())throw new Error('SUPERVISOR_OWNER_FD');
    ownerFd=stdio.length;stdio.push(fd);
  }
  let child, cancelled, final, incomplete, protocolError, ready, closed=false;
  const send=row=>{if(child?.stdio[3]&&!child.stdio[3].destroyed)child.stdio[3].write(JSON.stringify(row)+'\n',()=>{});};
  const cancel=name=>{cancelled||=name;if(ready)send({cancel:cancelled});};
  const handlers=new Map(['SIGINT','SIGTERM'].map(name=>[name,()=>cancel(name)]));
  const abort=()=>cancel(signal?.reason?.cancellationSignal||'SIGTERM');
  for(const [name,fn]of handlers)process.on(name,fn);
  signal?.addEventListener('abort',abort,{once:true});
  try {
    if(signal?.aborted)abort();
    const result=await new Promise((resolve,reject)=>{
      child=spawn('python3',['-I','-c',program,JSON.stringify({argv,mode,jobs,ownerFd,workRoot})],{cwd,env:environment,stdio,detached:true});
      child.stdio[3]?.on('error',()=>{});
      const statusClosed=()=>{if(!final&&!incomplete){protocolError='SUPERVISOR_STATUS_CLOSED';child.stdio[3]?.end();}};
      child.stdio[4]?.on('error',statusClosed);
      child.stdio[4]?.on('end',statusClosed);
      child.stdio[4]?.on('close',statusClosed);
      let buffer='';
      child.stdio[4]?.on('data',chunk=>{
        buffer+=chunk;
        while(buffer.includes('\n')) {
          const end=buffer.indexOf('\n'),line=buffer.slice(0,end);buffer=buffer.slice(end+1);
          let row;try{row=JSON.parse(line);}catch{protocolError='SUPERVISOR_STATUS_INVALID';child.stdio[3].end();continue;}
          onEvent?.(row);
          if(row.guardian!==child.pid){protocolError='SUPERVISOR_IDENTITY';child.stdio[3].end();continue;}
          if(row.type==='ready'){ready=row;send(cancelled?{cancel:cancelled}:{go:true});}
          if(row.type==='finished')final=row;
          if(row.type==='incomplete'){
            incomplete=row;child.stdio[3].end();child.stdio[3].unref?.();child.stdio[4].unref?.();child.unref();resolve(row);
          }
        }
      });
      child.once('error',error=>reject(Object.assign(new Error('SUPERVISOR_DEPENDENCY python3: '+error.message),{rc:1})));
      child.once('close',(rc,termination)=>{
        closed=true;
        if(incomplete)return;
        if(!final||protocolError)resolve({type:'incomplete',rc:1,error:termination?'SUPERVISOR_LOST':protocolError||'SUPERVISOR_LOST',guardian:child.pid,directory:ready?.directory,supervisorRc:rc,supervisorSignal:termination,reaped:false,ledgerReturned:false});
        else if(rc!==final.rc)resolve({...final,rc:1,error:final.error||'SUPERVISOR_EXIT_MISMATCH',supervisorRc:rc,supervisorSignal:termination});
        else resolve(final);
      });
    });
    if(cancelled)return {...result,rc:cancelled==='SIGINT'?130:143,cancelled:true,cancellationSignal:cancelled};
    return result;
  } finally {
    signal?.removeEventListener('abort',abort);
    for(const [name,fn]of handlers)process.removeListener(name,fn);
    if(!closed&&!incomplete)child?.stdio[3]?.end();
  }
}

// Node normally resolves the module URL through symlinks, but keeps the CLI
// spelling in argv. Resolve both sides, also for --preserve-symlinks-main.
function isCommandEntry() {
  if (!process.argv[1]) return false;
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch (error) {
    if (['ENOENT', 'ENOTDIR'].includes(error.code)) return false;
    throw error;
  }
}
if(isCommandEntry()) {
  try {
    const separator=process.argv.indexOf('--');
    if(separator<0)throw new Error('SUPERVISOR_USAGE [--ninja JOBS] -- COMMAND');
    const options=process.argv.slice(2,separator);
    if(options.length&&!(options.length===2&&options[0]==='--ninja'))throw new Error('SUPERVISOR_OPTIONS');
    const result=await supervisedCommand(process.argv.slice(separator+1),{mode:options.length?'ninja':'ordinary',jobs:options.length?Number(options[1]):undefined});
    if(result.error)console.error(result.error);
    process.exitCode=result.rc;
  } catch(error){console.error(error.stack);process.exitCode=error.rc||1;}
}
