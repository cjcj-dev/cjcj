"""Read-only LLDB observer. Only the private calibrator changes its own stack."""
import hashlib
import json
import os
import time
import traceback
import lldb


def sha(path):
    with open(path, 'rb') as f:
        h = hashlib.sha256()
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
        return h.hexdigest()


def persist(path, record):
    # Atomic replacement preserves the last complete record under the watchdog.
    temporary = path + '.writing'
    with open(temporary, 'w') as f:
        json.dump(record, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)


def process_position(process):
    state = process.GetState()
    return {'state': state, 'state_name': lldb.SBDebugger.StateAsCString(state),
            'stop_id': process.GetStopID(True)}


def stop_snapshot(process, target, active, pending, breakpoints):
    snapshot = dict(process_position(process), timestamp=time.time(),
                    active_thread=active, pending=pending, threads=[], breakpoints=[])
    selected = process.GetSelectedThread()
    snapshot['selected_thread'] = selected.GetThreadID() if selected.IsValid() else None
    snapshot['thread_count'] = process.GetNumThreads()
    for thread in process:
        reason = thread.GetStopReason()
        item = {'tid': thread.GetThreadID(), 'reason': reason,
                'reason_name': next((name for name in dir(lldb) if name.startswith('eStopReason')
                                     and getattr(lldb, name) == reason), str(reason)),
                'description': thread.GetStopDescription(4096),
                'data': [thread.GetStopReasonDataAtIndex(i)
                         for i in range(thread.GetStopReasonDataCount())], 'frames': []}
        for i in range(min(2, thread.GetNumFrames())):
            frame = thread.GetFrameAtIndex(i)
            module = frame.GetModule()
            item['frames'].append({'pc': frame.GetPC(), 'function': frame.GetFunctionName(),
                                   'module': str(module.GetFileSpec().fullpath),
                                   'uuid': module.GetUUIDString(), 'frame': str(frame)})
        snapshot['threads'].append(item)
    for bp in breakpoints:
        if bp is None or not bp.IsValid():
            continue
        snapshot['breakpoints'].append({'id': bp.GetID(), 'enabled': bp.IsEnabled(),
            'thread_id': bp.GetThreadID(), 'locations': [
                {'id': bp.GetLocationAtIndex(i).GetID(),
                 'resolved': bp.GetLocationAtIndex(i).IsResolved(),
                 'enabled': bp.GetLocationAtIndex(i).IsEnabled(),
                 'address': bp.GetLocationAtIndex(i).GetAddress().GetLoadAddress(target)}
                for i in range(bp.GetNumLocations())]})
    # No SB handles or references to mutable pending calls survive the capture.
    return json.loads(json.dumps(snapshot))


def classify_stop(snapshot):
    if not snapshot['threads']:
        raise RuntimeError('STOP_WITHOUT_THREAD')
    known = {bp['id']: {loc['id'] for loc in bp['locations'] if loc['resolved'] and loc.get('enabled', True)}
             for bp in snapshot['breakpoints'] if bp.get('enabled', True)}
    hits = []
    for thread in snapshot['threads']:
        reason, data = thread['reason'], thread['data']
        if reason in (lldb.eStopReasonNone, lldb.eStopReasonInvalid):
            continue  # Other threads may have no stop reason; never resume an all-empty stop.
        if reason == lldb.eStopReasonSignal:
            raise RuntimeError('UNEXPECTED_SIGNAL')
        if reason == lldb.eStopReasonException:
            raise RuntimeError('UNEXPECTED_EXCEPTION')
        if reason != lldb.eStopReasonBreakpoint:
            raise RuntimeError('UNEXPECTED_STOP_REASON')
        if not data:
            raise RuntimeError('BREAKPOINT_STOP_WITHOUT_ID')
        if len(data) % 2:
            raise RuntimeError('MALFORMED_BREAKPOINT_DATA')
        for bp_id, location in zip(data[::2], data[1::2]):
            if bp_id not in known:
                raise RuntimeError('UNKNOWN_BREAKPOINT')
            if location not in known[bp_id]:
                raise RuntimeError('UNKNOWN_BREAKPOINT_LOCATION')
            hits.append((thread['tid'], bp_id, location))
    if not hits:
        raise RuntimeError('STOP_WITHOUT_REASON')
    return hits



def create_return(target, address, tid):
    bp = target.BreakpointCreateByAddress(address)
    bp.SetThreadID(tid)
    bp.SetOneShot(False)
    if not bp.IsValid() or not bp.IsEnabled() or bp.GetNumLocations() != 1:
        raise RuntimeError('RETURN_BREAKPOINT_NOT_UNIQUE')
    loc = bp.GetLocationAtIndex(0)
    if not loc.IsResolved() or not loc.IsEnabled() or loc.GetAddress().GetLoadAddress(target) != address:
        raise RuntimeError('RETURN_BREAKPOINT_LOCATION_INVALID')
    return bp, {'breakpoint_id': bp.GetID(), 'location_id': loc.GetID(),
                'return_pc': address, 'thread_id': tid}


def validate_return(call, tid, bp_id, location, pc, active):
    if (bp_id, location) != (call['breakpoint_id'], call['location_id']):
        raise RuntimeError('RETURN_IDENTITY_MISMATCH')
    if tid != call['thread_id'] or tid != active:
        raise RuntimeError('return native thread mismatch')
    if pc != call['return_pc']:
        raise RuntimeError('RETURN_PC_MISMATCH')


def delete_return(target, bp_id):
    deleted = target.BreakpointDelete(bp_id)
    absent = not target.FindBreakpointByID(bp_id).IsValid()
    if not deleted or not absent:
        raise RuntimeError('RETURN_BREAKPOINT_DELETE_FAILED')
    return {'breakpoint_id': bp_id, 'deleted': deleted, 'absent': absent}


def continue_sync(debugger, process, record, path, capture):
    # SBProcess::Continue dispatches ResumeSynchronous when GetAsync() is false.
    # Never apply the stopped/no-progress predicate to an asynchronous transition.
    if debugger.GetAsync():
        raise RuntimeError('ASYNC_MODE_UNQUALIFIED')
    transition = {'before': process_position(process), 'async': False}
    record.setdefault('continues', []).append(transition)
    record.setdefault('stop_snapshots', []).append(capture())
    persist(path, record)
    error = process.Continue()
    transition['error'] = {'success': error.Success(), 'text': str(error),
                           'code': error.GetError(), 'type': error.GetType()}
    transition['after'] = process_position(process)
    record.setdefault('stop_snapshots', []).append(capture())
    persist(path, record)
    if not transition['error']['success']:
        raise RuntimeError('CONTINUE_REJECTED')
    if (transition['after']['state'] == lldb.eStateStopped and
            transition['after']['stop_id'] == transition['before']['stop_id']):
        raise RuntimeError('CONTINUE_NO_PROGRESS')
    if transition['after']['state'] not in (lldb.eStateStopped, lldb.eStateExited):
        raise RuntimeError('CONTINUE_UNEXPECTED_STATE')


def qualify_calibration(events, receipts, active, layout, process_rc):
    if len(receipts) != 4 or len(events) != 4:
        raise RuntimeError('CALIBRATION_RECEIPT_COUNT')
    for event, receipt, kind in zip(events, receipts, ('query', 'valid', 'invalid', 'restore')):
        if event['thread_id'] != active:
            raise RuntimeError('CALIBRATION_THREAD_MISMATCH')
        if receipt['kind'] != kind or event['kind'] != ('query' if kind == 'query' else 'install'):
            raise RuntimeError('CALIBRATION_CALL_ORDER')
        for key in ('rc', 'in', 'old'):
            if event[key] != receipt[key]:
                raise RuntimeError('CALIBRATION_RECEIPT_MISMATCH:' + key)
        if event['rc'] != 0 and event.get('errno') != receipt['errno']:
            raise RuntimeError('CALIBRATION_ERRNO_MISMATCH')
    query, valid, invalid, restore = events
    if not (query['rc'] == valid['rc'] == restore['rc'] == process_rc == 0
            and invalid['rc'] == -1 and invalid.get('errno', 0) != 0):
        raise RuntimeError('CALIBRATION_API_RESULTS')
    if (query['in'] is not None or query['old'] is None or
            query['old']['ss_flags'] & layout['SS_ONSTACK'] or
            valid['in'] is None or not valid['in']['ss_sp'] or
            valid['in']['ss_size'] != layout['SIGSTKSZ'] * 2 or valid['in']['ss_flags'] != 0 or
            invalid['in'] != dict(valid['in'], ss_size=0) or
            restore['in'] != query['old'] or
            any(event['old'] is not None for event in (valid, invalid, restore))):
        raise RuntimeError('CALIBRATION_API_PARAMETERS')


def observe(debugger, command, result, internal_dict):
    cfg = json.load(open(os.environ['SIGNAL_OBSERVER_CONFIG']))
    record = {'status': 'OBSERVER_UNQUALIFIED', 'events': [], 'config': cfg,
              'readonly_expressions': [], 'modules': [], 'stop_snapshots': [], 'continues': []}
    path = cfg['output']
    process = None
    capture = None
    try:
        debugger.SetAsync(False)
        record['lldb'] = {'version': lldb.SBDebugger.GetVersionString(), 'async': debugger.GetAsync()}
        target = debugger.CreateTarget(cfg['binary'])
        if not target.IsValid() or not target.GetTriple().startswith('arm64'):
            raise RuntimeError('expected live arm64 Mach-O target: ' + target.GetTriple())
        record['triple'] = target.GetTriple()
        if cfg.get('layout') and target.GetAddressByteSize() != cfg['layout']['pointer_size']:
            raise RuntimeError('SDK/target pointer size mismatch')
        if target.GetByteOrder() != lldb.eByteOrderLittle:
            raise RuntimeError('unqualified target byte order')
        # Take the symbol start, not a debugger-selected post-prologue location:
        # x30 must still be the caller return PC at this entry.
        module = target.GetModuleAtIndex(0)
        needle = 'calibration_begin' if cfg['mode'] == 'calibrate' else 'CreateAltSignalStack'
        symbols = []
        for i in range(module.GetNumSymbols()):
            sym = module.GetSymbolAtIndex(i)
            name = sym.GetName() or ''
            if needle in name and sym.GetType() == lldb.eSymbolTypeCode:
                symbols.append(sym)
        unique = {s.GetStartAddress().GetFileAddress(): s for s in symbols}
        if len(unique) != 1:
            raise RuntimeError('entry symbol not unique: ' + str([(s.GetName(), s.GetStartAddress().GetFileAddress()) for s in symbols]))
        sym = next(iter(unique.values()))
        record['entry_symbol'] = sym.GetName()
        entry = target.BreakpointCreateBySBAddress(sym.GetStartAddress())
        syscall = target.BreakpointCreateByName('sigaltstack')
        launch = lldb.SBLaunchInfo(cfg['argv'])
        launch.SetEnvironmentEntries([k + '=' + v for k, v in cfg['environment'].items()], False)
        launch.SetWorkingDirectory(cfg['cwd'])
        launch.AddOpenFileAction(1, cfg['stdout'], False, True)
        launch.AddOpenFileAction(2, cfg['stderr'], False, True)
        error = lldb.SBError()
        process = target.Launch(launch, error)
        if not error.Success() or not process.IsValid():
            raise RuntimeError('debugger launch rejected: ' + str(error))
        record['pid'] = process.GetProcessID()
        active = None
        pending = {}
        exit_bp = None
        exited_entry = cfg['mode'] == 'calibrate'
        deadline = time.monotonic() + 110

        def reg(frame, name):
            value = frame.FindRegister(name)
            if not value.IsValid():
                raise RuntimeError('register unavailable: ' + name)
            return value.GetValueAsUnsigned()

        def stack(pointer):
            if not pointer:
                return None
            err = lldb.SBError()
            data = process.ReadMemory(pointer, cfg['layout']['stack_size'], err)
            if not err.Success() or len(data) != cfg['layout']['stack_size']:
                raise RuntimeError('stack_t memory read failed: ' + str(err))
            fields = {}
            for field in ('ss_sp', 'ss_size', 'ss_flags'):
                offset, size = cfg['layout'][field]
                fields[field] = int.from_bytes(data[offset:offset + size], 'little', signed=field == 'ss_flags')
            return fields

        def images():
            record['modules'] = []
            for mod in target.modules:
                name = str(mod.GetFileSpec().fullpath)
                item = {'path': name, 'uuid': mod.GetUUIDString()}
                if os.path.isfile(name):
                    item['sha256'] = sha(name)
                record['modules'].append(item)

        exit_identity = None

        def capture():
            bps = [target.FindBreakpointByID(bp.GetID()) for bp in (entry, syscall, exit_bp)
                   if bp is not None] + [target.FindBreakpointByID(i) for i in pending]
            return stop_snapshot(process, target, active, pending, bps)

        # Capture even a launch rejection before the exception handler can Kill.
        while process.GetState() == lldb.eStateStopped:
            snapshot = capture()
            record['stop_snapshots'].append(snapshot)
            persist(path, record)
            if time.monotonic() > deadline:
                raise RuntimeError('observer deadline exceeded')
            hits = classify_stop(snapshot)
            if len(hits) != 1:
                raise RuntimeError('AMBIGUOUS_RETURN')
            for tid, bp_id, location_id in hits:
                thread = process.GetThreadByID(tid)
                frame = thread.GetFrameAtIndex(0)
                if bp_id == entry.GetID():
                    if active is not None:
                        raise RuntimeError('entry repeated')
                    active = tid
                    if cfg['mode'] == 'calibrate':
                        layouts = [json.loads(line[len('LAYOUT '):]) for line in open(cfg['stdout']) if line.startswith('LAYOUT ')]
                        if len(layouts) != 1:
                            raise RuntimeError('SDK layout receipt missing')
                        cfg['layout'] = layouts[0]
                        if target.GetAddressByteSize() != cfg['layout']['pointer_size']:
                            raise RuntimeError('SDK layout pointer mismatch')
                    record['entry_thread_id'] = tid
                    record['entry_pc'] = frame.GetPC()
                    record['caller_return_pc'] = reg(frame, 'x30')
                    record['entry_backtrace'] = [str(f) for f in thread]
                    record['entry_instructions'] = str(target.ReadInstructions(frame.GetPCAddress(), 100))
                    if cfg['mode'] != 'calibrate':
                        exit_bp, exit_identity = create_return(target, record['caller_return_pc'], tid)
                        record['exit_breakpoint'] = exit_identity
                    if syscall.GetNumLocations() != 1:
                        raise RuntimeError('real sigaltstack location not unique: ' + str(syscall.GetNumLocations()))
                    location = syscall.GetLocationAtIndex(0).GetAddress()
                    record['sigaltstack_module'] = str(location.GetModule().GetFileSpec().fullpath)
                    if 'libsystem' not in record['sigaltstack_module']:
                        raise RuntimeError('sigaltstack is not libsystem')
                    record['sigaltstack_instructions'] = str(target.ReadInstructions(location, 24))
                    images()
                    entry.SetEnabled(False)
                elif bp_id in pending:
                    call = dict(pending[bp_id])
                    validate_return(call, tid, bp_id, location_id, frame.GetPC(), active)
                    unsigned = reg(frame, 'w0') & 0xffffffff
                    call['rc'] = unsigned if unsigned < 0x80000000 else unsigned - 0x100000000
                    call['old'] = stack(call['old_pointer'])
                    if call['rc'] != 0:
                        getters = target.FindSymbols('__error', lldb.eSymbolTypeCode)
                        addresses = {getters.GetContextAtIndex(i).GetSymbol().GetStartAddress().GetLoadAddress(target) for i in range(getters.GetSize())}
                        addresses.discard(lldb.LLDB_INVALID_ADDRESS)
                        if len(addresses) != 1:
                            raise RuntimeError('errno getter symbol not unique')
                        getter = next(iter(addresses))
                        expr = '*(int *)((int * (*)())0x%x)()' % getter
                        record['readonly_expressions'].append({'thread_id': tid, 'expression': expr})
                        opts = lldb.SBExpressionOptions()
                        opts.SetIgnoreBreakpoints(True)
                        opts.SetUnwindOnError(True)
                        opts.SetTimeoutInMicroSeconds(2000000)
                        val = frame.EvaluateExpression(expr, opts)
                        if not val.GetError().Success():
                            raise RuntimeError('same-thread errno getter failed: ' + str(val.GetError()))
                        call['errno'] = val.GetValueAsSigned()
                    call['deletion'] = delete_return(target, bp_id)
                    pending.pop(bp_id)
                    record['events'].append(call)
                    persist(path, record)
                elif exit_bp is not None and bp_id == exit_bp.GetID():
                    if tid != active or pending:
                        raise RuntimeError('Create exit without closed same-thread calls')
                    validate_return(exit_identity, tid, bp_id, location_id, frame.GetPC(), active)
                    record['exit_deletion'] = delete_return(target, bp_id)
                    record['exit_thread_id'] = tid
                    record['exit_pc'] = frame.GetPC()
                    exited_entry = True
                    syscall.SetEnabled(False)
                elif bp_id == syscall.GetID():
                    if active is None or tid != active or (cfg['mode'] != 'calibrate' and exited_entry):
                        continue
                    if pending:
                        raise RuntimeError('nested sigaltstack call')
                    if cfg['mode'] != 'calibrate' and not any(needle in (f.GetFunctionName() or '') for f in thread):
                        raise RuntimeError('sigaltstack caller not CreateAltSignalStack')
                    new_ptr, old_ptr = reg(frame, 'x0'), reg(frame, 'x1')
                    ret = reg(frame, 'x30')
                    if exit_identity is not None and ret == exit_identity['return_pc']:
                        raise RuntimeError('AMBIGUOUS_RETURN')
                    bp, identity = create_return(target, ret, tid)
                    pending[bp.GetID()] = dict(identity, **{'call_pc': frame.GetPC(),
                        'kind': 'query' if new_ptr == 0 else 'install', 'new_pointer': new_ptr,
                        'old_pointer': old_ptr, 'in': stack(new_ptr), 'caller': str(thread.GetFrameAtIndex(1))})
                else:
                    raise RuntimeError('unknown breakpoint ' + str(bp_id))
            continue_sync(debugger, process, record, path, capture)
        record['process_state'] = str(process.GetState())
        if process.GetState() != lldb.eStateExited:
            raise RuntimeError('product did not exit normally')
        record['process_rc'] = process.GetExitStatus()
        if active is None or pending or not exited_entry:
            raise RuntimeError('entry/return evidence incomplete')
        if cfg['mode'] == 'calibrate':
            receipts = [json.loads(line[len('RECEIPT '):]) for line in open(cfg['stdout']) if line.startswith('RECEIPT ')]
            events = record['events']
            qualify_calibration(events, receipts, active, cfg['layout'], record['process_rc'])
            record['status'] = 'CALIBRATED'
        else:
            events = record['events']
            if not events or events[0]['kind'] != 'query':
                raise RuntimeError('product query not observed')
            q = events[0]
            old = q['old']
            conditions = {'query_failed': q['rc'] != 0,
                'onstack': bool(old['ss_flags'] & cfg['layout']['SS_ONSTACK']),
                'existing_large_enough': old['ss_sp'] != 0 and old['ss_size'] >= cfg['selected_size']}
            record['skip_conditions'] = conditions
            if any(conditions.values()):
                if len(events) != 1:
                    raise RuntimeError('calls conflict with skip decision')
                record['status'] = 'QUERY_FAILED' if conditions['query_failed'] else 'LEGAL_SKIP'
            else:
                if len(events) != 2 or events[1]['kind'] != 'install':
                    raise RuntimeError('install branch incomplete')
                install = events[1]
                if install['in']['ss_size'] != cfg['selected_size'] or not install['in']['ss_sp'] or install['in']['ss_flags'] != 0:
                    raise RuntimeError('actual install parameter identity mismatch')
                record['status'] = 'INSTALLED' if install['rc'] == 0 else 'INSTALL_FAILED'
            expected = cfg['expected_libraries']
            for name, digest in expected.items():
                found = [m for m in record['modules'] if os.path.basename(m['path']) == name]
                if len(found) != 1 or found[0].get('sha256') != digest:
                    raise RuntimeError('loaded library identity mismatch: ' + name)
    except Exception as exc:
        record['status'] = 'OBSERVER_UNQUALIFIED'
        record['error'] = str(exc)
        record['traceback'] = traceback.format_exc()
        if process and process.IsValid() and process.GetState() != lldb.eStateExited:
            if capture:
                record['stop_snapshots'].append(capture())
            else:
                record['stop_snapshots'].append(stop_snapshot(process, target, None, {}, [entry, syscall]))
            persist(path, record)
            killed = process.Kill()
            record['kill'] = {'success': killed.Success(), 'error': str(killed),
                              'after': process_position(process)}
    finally:
        persist(path, record)
        print('SIGNAL_OBSERVATION ' + record['status'])


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f observer.observe signal-observe')
