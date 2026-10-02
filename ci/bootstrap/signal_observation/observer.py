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


def observe(debugger, command, result, internal_dict):
    cfg = json.load(open(os.environ['SIGNAL_OBSERVER_CONFIG']))
    record = {'status': 'OBSERVER_UNQUALIFIED', 'events': [], 'config': cfg,
              'readonly_expressions': [], 'modules': []}
    path = cfg['output']
    process = None
    try:
        debugger.SetAsync(False)
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

        while process.GetState() == lldb.eStateStopped:
            if time.monotonic() > deadline:
                raise RuntimeError('observer deadline exceeded')
            handled = False
            for thread in process:
                if thread.GetStopReason() != lldb.eStopReasonBreakpoint:
                    if thread.GetStopReason() not in (lldb.eStopReasonNone, lldb.eStopReasonInvalid):
                        raise RuntimeError('unexpected stop: ' + thread.GetStopDescription(512))
                    continue
                ids = [thread.GetStopReasonDataAtIndex(i) for i in range(0, thread.GetStopReasonDataCount(), 2)]
                frame = thread.GetFrameAtIndex(0)
                tid = thread.GetThreadID()
                for bp_id in ids:
                    handled = True
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
                            exit_bp = target.BreakpointCreateByAddress(record['caller_return_pc'])
                            exit_bp.SetThreadID(tid)
                            exit_bp.SetOneShot(True)
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
                        call = pending.pop(bp_id)
                        if tid != call['thread_id']:
                            raise RuntimeError('return native thread mismatch')
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
                        record['events'].append(call)
                        target.BreakpointDelete(bp_id)
                    elif exit_bp is not None and bp_id == exit_bp.GetID():
                        if tid != active or pending:
                            raise RuntimeError('Create exit without closed same-thread calls')
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
                        bp = target.BreakpointCreateByAddress(ret)
                        bp.SetThreadID(tid)
                        bp.SetOneShot(True)
                        pending[bp.GetID()] = {'thread_id': tid, 'call_pc': frame.GetPC(), 'return_pc': ret,
                            'kind': 'query' if new_ptr == 0 else 'install', 'new_pointer': new_ptr,
                            'old_pointer': old_ptr, 'in': stack(new_ptr), 'caller': str(thread.GetFrameAtIndex(1))}
                    else:
                        raise RuntimeError('unknown breakpoint ' + str(bp_id))
            if not handled:
                raise RuntimeError('unclassified stopped process')
            # Preserve partial evidence even if the outer 120-second watchdog kills LLDB.
            with open(path, 'w') as f:
                json.dump(record, f, indent=2)
            process.Continue()
        record['process_state'] = str(process.GetState())
        if process.GetState() != lldb.eStateExited:
            raise RuntimeError('product did not exit normally')
        record['process_rc'] = process.GetExitStatus()
        if active is None or pending or not exited_entry:
            raise RuntimeError('entry/return evidence incomplete')
        if cfg['mode'] == 'calibrate':
            receipts = [json.loads(line[len('RECEIPT '):]) for line in open(cfg['stdout']) if line.startswith('RECEIPT ')]
            events = record['events']
            if len(receipts) != 4 or len(events) != 4:
                raise RuntimeError('calibration requires exactly query/valid/invalid/restore')
            for event, receipt in zip(events, receipts):
                for key in ('rc', 'in', 'old'):
                    if event[key] != receipt[key]:
                        raise RuntimeError('LLDB/native mismatch: ' + key)
                if event['rc'] != 0 and event.get('errno') != receipt['errno']:
                    raise RuntimeError('LLDB/native errno mismatch')
            if not (events[0]['rc'] == events[1]['rc'] == events[3]['rc'] == 0 and events[2]['rc'] != 0 and record['process_rc'] == 0):
                raise RuntimeError('positive failure or successful install/restore not qualified')
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
            process.Kill()
    finally:
        with open(path, 'w') as f:
            json.dump(record, f, indent=2)
        print('SIGNAL_OBSERVATION ' + record['status'])


def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f observer.observe signal-observe')
