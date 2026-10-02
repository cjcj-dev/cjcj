"""Synthetic SB API controls; these never certify a native API execution."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, MagicMock, patch

lldb = types.ModuleType('lldb')
for i, name in enumerate(('eStateStopped', 'eStateExited', 'eStateRunning', 'eStopReasonNone',
                          'eStopReasonInvalid', 'eStopReasonBreakpoint', 'eStopReasonSignal',
                          'eStopReasonException', 'eStopReasonTrace')):
    setattr(lldb, name, i)
lldb.SBDebugger = types.SimpleNamespace(StateAsCString=lambda state: str(state))
sys.modules['lldb'] = lldb
spec = importlib.util.spec_from_file_location('observer', Path(__file__).with_name('observer.py'))
o = importlib.util.module_from_spec(spec)
spec.loader.exec_module(o)


def snapshot(reason=lldb.eStopReasonBreakpoint, data=None):
    return {'state': lldb.eStateStopped, 'stop_id': 7, 'threads': [
        {'tid': 19, 'reason': reason, 'data': [1, 1] if data is None else data}],
        'breakpoints': [{'id': i, 'locations': [{'id': 1, 'resolved': True}]} for i in (1, 2, 3)]}


def calibration():
    old = {'ss_sp': 0, 'ss_size': 0, 'ss_flags': 4}
    valid = {'ss_sp': 4096, 'ss_size': 262144, 'ss_flags': 0}
    events = [{'thread_id': 19, 'kind': 'query', 'rc': 0, 'in': None, 'old': old},
              {'thread_id': 19, 'kind': 'install', 'rc': 0, 'in': valid, 'old': None},
              {'thread_id': 19, 'kind': 'install', 'rc': -1, 'errno': 12,
               'in': dict(valid, ss_size=0), 'old': None},
              {'thread_id': 19, 'kind': 'install', 'rc': 0, 'in': old, 'old': None}]
    receipts = [dict(copy.deepcopy(event), kind=kind, errno=event.get('errno', 0))
                for event, kind in zip(events, ('query', 'valid', 'invalid', 'restore'))]
    return events, receipts


class ObserverTests(unittest.TestCase):
    def test_ordinary_return_lifecycle(self):
        target = Mock()
        bp = target.BreakpointCreateByAddress.return_value
        bp.IsValid.return_value = bp.IsEnabled.return_value = True
        bp.GetID.return_value = 3
        bp.GetNumLocations.return_value = 1
        loc = bp.GetLocationAtIndex.return_value
        loc.IsResolved.return_value = loc.IsEnabled.return_value = True
        loc.GetID.return_value = 1
        loc.GetAddress.return_value.GetLoadAddress.return_value = 4096
        _, call = o.create_return(target, 4096, 19)
        bp.SetOneShot.assert_called_once_with(False)
        bp.SetThreadID.assert_called_once_with(19)
        o.validate_return(call, 19, 3, 1, 4096, 19)
        target.BreakpointDelete.return_value = True
        target.FindBreakpointByID.return_value.IsValid.return_value = False
        self.assertEqual(o.delete_return(target, 3), {'breakpoint_id':3, 'deleted':True, 'absent':True})
        for args, reason in [((19, 4, 1, 4096, 19), 'RETURN_IDENTITY_MISMATCH'),
                             ((19, 3, 2, 4096, 19), 'RETURN_IDENTITY_MISMATCH'),
                             ((20, 3, 1, 4096, 19), 'return native thread mismatch'),
                             ((19, 3, 1, 4097, 19), 'RETURN_PC_MISMATCH')]:
            with self.assertRaisesRegex(RuntimeError, '^'+reason+'$'):
                o.validate_return(call, *args)

    def test_delete_failure(self):
        for deleted, live in [(False, False), (True, True)]:
            target = Mock()
            target.BreakpointDelete.return_value = deleted
            target.FindBreakpointByID.return_value.IsValid.return_value = live
            with self.assertRaisesRegex(RuntimeError, '^RETURN_BREAKPOINT_DELETE_FAILED$'):
                o.delete_return(target, 3)

    def reject(self, value, code):
        with self.assertRaisesRegex(RuntimeError, '^' + code + '$'):
            o.classify_stop(value)

    def test_entry(self):
        self.assertEqual(o.classify_stop(snapshot()), [(19, 1, 1)])

    def test_query_return(self):
        self.assertEqual(o.classify_stop(snapshot(data=[2, 1])), [(19, 2, 1)])
        self.assertEqual(o.classify_stop(snapshot(data=[3, 1])), [(19, 3, 1)])

    def test_no_threads(self):
        value = snapshot(); value['threads'] = []
        self.reject(value, 'STOP_WITHOUT_THREAD')

    def test_no_reason(self):
        value = snapshot(lldb.eStopReasonNone)
        value['threads'].append({'tid': 20, 'reason': lldb.eStopReasonInvalid, 'data': []})
        self.reject(value, 'STOP_WITHOUT_REASON')

    def test_empty_breakpoint(self):
        self.reject(snapshot(data=[]), 'BREAKPOINT_STOP_WITHOUT_ID')

    def test_odd_breakpoint(self):
        self.reject(snapshot(data=[1]), 'MALFORMED_BREAKPOINT_DATA')

    def test_signal(self):
        self.reject(snapshot(lldb.eStopReasonSignal, [10]), 'UNEXPECTED_SIGNAL')

    def test_exception(self):
        self.reject(snapshot(lldb.eStopReasonException, [42]), 'UNEXPECTED_EXCEPTION')

    def test_unknown_reason(self):
        self.reject(snapshot(lldb.eStopReasonTrace, []), 'UNEXPECTED_STOP_REASON')

    def test_unknown_id(self):
        self.reject(snapshot(data=[99, 1]), 'UNKNOWN_BREAKPOINT')

    def test_unknown_location(self):
        self.reject(snapshot(data=[1, 99]), 'UNKNOWN_BREAKPOINT_LOCATION')

    def transition(self, success=True, after=(lldb.eStateStopped, 8), asynchronous=False):
        process = Mock()
        process.GetState.side_effect = [lldb.eStateStopped, after[0]]
        process.GetStopID.side_effect = [7, after[1]]
        error = Mock()
        error.Success.return_value = success
        error.GetError.return_value = 0 if success else 5
        error.GetType.return_value = 1
        process.Continue.return_value = error
        debugger = Mock(); debugger.GetAsync.return_value = asynchronous
        record = {}
        with tempfile.TemporaryDirectory(dir=os.environ.get('OBSERVER_TEST_ROOT')) as directory:
            path = str(Path(directory) / 'record.json')
            def resumed():
                # The pre-action position must already be durable at the API call.
                saved = json.loads(Path(path).read_text())
                self.assertEqual(saved['continues'][0]['before']['stop_id'], 7)
                self.assertEqual(saved['stop_snapshots'][0]['stop_id'], 7)
                return error
            process.Continue.side_effect = resumed
            try:
                o.continue_sync(debugger, process, record, path, lambda: snapshot())
            finally:
                if not asynchronous:
                    saved = json.loads(Path(path).read_text())
                    self.assertEqual(saved['continues'][0]['error']['success'], success)
                    self.assertEqual(saved['continues'][0]['after']['stop_id'], after[1])
                    self.assertEqual(len(saved['stop_snapshots']), 2)
                self.assertEqual(process.Continue.call_count, 0 if asynchronous else 1)

    def test_continue_progress(self): self.transition()
    def test_continue_exit(self): self.transition(after=(lldb.eStateExited, 7))
    def test_continue_failure(self):
        with self.assertRaisesRegex(RuntimeError, '^CONTINUE_REJECTED$'): self.transition(success=False)
    def test_continue_no_progress(self):
        with self.assertRaisesRegex(RuntimeError, '^CONTINUE_NO_PROGRESS$'): self.transition(after=(lldb.eStateStopped, 7))
    def test_async_not_instant_stopped(self):
        with self.assertRaisesRegex(RuntimeError, '^ASYNC_MODE_UNQUALIFIED$'): self.transition(asynchronous=True)
    def test_continue_running(self):
        with self.assertRaisesRegex(RuntimeError, '^CONTINUE_UNEXPECTED_STATE$'): self.transition(after=(lldb.eStateRunning, 7))

    def qualify(self, events, receipts):
        o.qualify_calibration(events, receipts, 19, {'SS_ONSTACK': 1, 'SIGSTKSZ': 131072}, 0)

    def test_complete_receipts(self): self.qualify(*calibration())
    def test_wrong_thread(self):
        events, receipts = calibration(); events[2]['thread_id'] = 20
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_THREAD_MISMATCH$'): self.qualify(events, receipts)
    def test_missing_receipt(self):
        events, receipts = calibration()
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_RECEIPT_COUNT$'): self.qualify(events, receipts[:3])
    def test_wrong_receipt(self):
        events, receipts = calibration(); receipts[1]['in']['ss_size'] = 1
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_RECEIPT_MISMATCH:in$'): self.qualify(events, receipts)
    def test_errno(self):
        events, receipts = calibration(); receipts[2]['errno'] = 22
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_ERRNO_MISMATCH$'): self.qualify(events, receipts)
    def test_api_success_invalid(self):
        events, receipts = calibration(); events[2]['rc'] = receipts[2]['rc'] = 0
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_API_RESULTS$'): self.qualify(events, receipts)
    def test_call_order(self):
        events, receipts = calibration(); receipts[1]['kind'] = 'invalid'
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_CALL_ORDER$'): self.qualify(events, receipts)
    def test_invalid_size(self):
        events, receipts = calibration(); events[2]['in']['ss_size'] = receipts[2]['in']['ss_size'] = 1
        with self.assertRaisesRegex(RuntimeError, '^CALIBRATION_API_PARAMETERS$'): self.qualify(events, receipts)

    def test_pre_kill_snapshot(self):
        debugger, target, process = Mock(), Mock(), MagicMock()
        debugger.GetAsync.return_value = False
        debugger.CreateTarget.return_value = target
        target.IsValid.return_value = True; target.GetTriple.return_value = 'arm64-apple-macosx15.0.0'
        target.GetByteOrder.return_value = 99
        module = Mock(); target.GetModuleAtIndex.return_value = module
        module.GetNumSymbols.return_value = 1
        symbol = module.GetSymbolAtIndex.return_value
        symbol.GetName.return_value = 'calibration_begin'; symbol.GetType.return_value = 98
        symbol.GetStartAddress.return_value.GetFileAddress.return_value = 4096
        for bp, number in ((target.BreakpointCreateBySBAddress.return_value, 1),
                           (target.BreakpointCreateByName.return_value, 2)):
            bp.IsValid.return_value = True; bp.GetID.return_value = number
            bp.IsEnabled.return_value = True; bp.GetThreadID.return_value = 19
            bp.GetNumLocations.return_value = 0
        target.FindBreakpointByID.side_effect = lambda number: {1: target.BreakpointCreateBySBAddress.return_value, 2: target.BreakpointCreateByName.return_value}[number]
        target.Launch.return_value = process
        process.IsValid.return_value = True; process.GetProcessID.return_value = 123
        process.GetState.return_value = lldb.eStateStopped
        process.GetStopID.return_value = 7; process.GetNumThreads.return_value = 0
        process.GetSelectedThread.return_value.IsValid.return_value = False
        process.__iter__.return_value = iter([])
        error = Mock(); error.Success.return_value = True
        with tempfile.TemporaryDirectory(dir=os.environ.get('OBSERVER_TEST_ROOT')) as directory:
            path = Path(directory) / 'record.json'
            config = Path(directory) / 'config.json'
            config.write_text(json.dumps({'output': str(path), 'binary': '/synthetic-calibrator',
                                          'mode': 'calibrate', 'argv': [], 'environment': {},
                                          'cwd': directory, 'stdout': directory+'/stdout',
                                          'stderr': directory+'/stderr'}))
            def kill():
                saved = json.loads(path.read_text())
                self.assertEqual(saved['error'], 'STOP_WITHOUT_THREAD')
                self.assertEqual(saved['stop_snapshots'][0]['stop_id'], 7)
                self.assertEqual(saved['stop_snapshots'][0]['threads'], [])
                return error
            process.Kill.side_effect = kill
            classifier = o.classify_stop
            def classified(snapshot):
                saved = json.loads(path.read_text())
                self.assertEqual(saved['stop_snapshots'][0], snapshot)
                return classifier(snapshot)
            with patch.object(o, 'classify_stop', side_effect=classified), patch.dict(os.environ, SIGNAL_OBSERVER_CONFIG=str(config)), \
                 patch.object(lldb, 'eByteOrderLittle', 99, create=True), \
                 patch.object(lldb, 'eSymbolTypeCode', 98, create=True), \
                 patch.object(lldb, 'SBLaunchInfo', Mock(), create=True), \
                 patch.object(lldb, 'SBError', Mock(return_value=error), create=True), \
                 patch.object(lldb.SBDebugger, 'GetVersionString', lambda: 'synthetic', create=True):
                o.observe(debugger, '', None, {})
            saved = json.loads(path.read_text())
            self.assertEqual(saved['status'], 'OBSERVER_UNQUALIFIED')
            self.assertEqual(process.Kill.call_count, 1)
            process.Continue.assert_not_called()

    def test_snapshot_detached(self):
        frame = Mock(); frame.GetPC.return_value = 4096
        frame.GetFunctionName.return_value = 'calibration_begin'
        frame.GetModule.return_value.GetFileSpec.return_value.fullpath = '/calibrator'
        frame.GetModule.return_value.GetUUIDString.return_value = 'uuid'
        thread = Mock(); thread.GetThreadID.return_value = 19
        thread.IsValid.return_value = True
        thread.GetStopReason.return_value = lldb.eStopReasonBreakpoint
        thread.GetStopDescription.return_value = 'breakpoint 1.1'
        thread.GetStopReasonDataCount.return_value = 2
        thread.GetStopReasonDataAtIndex.side_effect = [1, 1]
        thread.GetNumFrames.return_value = 2; thread.GetFrameAtIndex.return_value = frame
        process = Mock(); process.GetState.return_value = lldb.eStateStopped
        process.GetStopID.return_value = 7; process.GetSelectedThread.return_value = thread
        process.GetNumThreads.return_value = 1
        process.__iter__ = Mock(return_value=iter([thread]))
        location = Mock(); location.GetID.return_value = 1
        location.IsResolved.return_value = True; location.IsEnabled.return_value = True
        location.GetAddress.return_value.GetLoadAddress.return_value = 4096
        bp = Mock(); bp.IsValid.return_value = True; bp.GetID.return_value = 1
        bp.IsEnabled.return_value = True; bp.GetThreadID.return_value = 19
        bp.GetNumLocations.return_value = 1; bp.GetLocationAtIndex.return_value = location
        pending = {3: {'thread_id': 19}}
        value = o.stop_snapshot(process, Mock(), 19, pending, [bp])
        pending[3]['thread_id'] = 20
        self.assertEqual(value['pending']['3']['thread_id'], 19)
        self.assertEqual(value['threads'][0]['data'], [1, 1])
        self.assertEqual(len(value['threads'][0]['frames']), 2)
        self.assertEqual(value['breakpoints'][0]['locations'][0]['address'], 4096)
        self.assertEqual(value['active_thread'], 19)

if __name__ == '__main__': unittest.main(verbosity=2)
