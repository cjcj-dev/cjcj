"""Drive the real observe entry with synthetic SB handles, never native receipts."""
from test_observer import o, lldb, Mock, MagicMock, patch, unittest, tempfile, os, Path, json


class LifecycleEntryTests(unittest.TestCase):
    def run_entry(self, fault=None):
        debugger, target, process = Mock(), Mock(), MagicMock()
        debugger.GetAsync.return_value = False
        debugger.CreateTarget.return_value = target
        target.IsValid.return_value = True
        target.GetTriple.return_value = 'arm64-apple-macosx15'
        target.GetByteOrder.return_value = 99
        target.GetAddressByteSize.return_value = 8
        symbol = target.GetModuleAtIndex.return_value.GetSymbolAtIndex.return_value
        target.GetModuleAtIndex.return_value.GetNumSymbols.return_value = 1
        product = fault in ('exit', 'exit-pending', 'collision')
        symbol.GetName.return_value = 'CreateAltSignalStack' if product else 'calibration_begin'
        symbol.GetType.return_value = 98
        symbol.GetStartAddress.return_value.GetFileAddress.return_value = 4096
        live, created = {}, []
        invalid = Mock(); invalid.IsValid.return_value = False
        def make_bp(number, address):
            bp = Mock()
            bp.IsValid.side_effect = lambda: number in live
            bp.GetID.return_value = number
            bp.IsEnabled.return_value = True
            bp.GetThreadID.return_value = 19
            bp.GetNumLocations.return_value = 1
            loc = bp.GetLocationAtIndex.return_value
            loc.GetID.return_value = 1
            loc.IsResolved.return_value = loc.IsEnabled.return_value = True
            loc.GetAddress.return_value.GetLoadAddress.return_value = address
            loc.GetAddress.return_value.GetModule.return_value.GetFileSpec.return_value.fullpath = '/libsystem'
            live[number] = bp
            return bp
        target.BreakpointCreateBySBAddress.return_value = make_bp(1, 4096)
        target.BreakpointCreateByName.return_value = make_bp(2, 8192)
        def create(address):
            bp = make_bp(3 + len(created), address); created.append(bp); return bp
        target.BreakpointCreateByAddress.side_effect = create
        target.FindBreakpointByID.side_effect = lambda number: live.get(number, invalid)
        def delete(number):
            if fault == 'delete': return False
            if fault != 'still-live': live.pop(number)
            return True
        target.BreakpointDelete.side_effect = delete
        target.modules = []
        target.ReadInstructions.return_value = ''
        target.Launch.return_value = process
        process.IsValid.return_value = True
        process.GetProcessID.return_value = 123
        sequence = [(1, 4096), (2, 8192), (3, 12288), (2, 8192), (4, 12288)]
        if product: sequence = [(1,4096), (2,8192), (4,12288), (3,16384)]
        if fault == 'exit-pending': sequence[2] = (3,16384)
        if fault == 'nested': sequence[2] = (2, 8192)
        if fault == 'stale': sequence[4] = (3, 12288)
        cursor = [0]
        frame = Mock()
        frame.GetPC.side_effect = lambda: sequence[min(cursor[0], len(sequence)-1)][1] + (4 if fault == 'pc' and cursor[0] == 2 else 0)
        frame.GetFunctionName.return_value = 'CreateAltSignalStack'
        frame.GetModule.return_value.GetFileSpec.return_value.fullpath = '/synthetic'
        frame.GetModule.return_value.GetUUIDString.return_value = 'uuid'
        def register(name):
            value = Mock(); value.IsValid.return_value = True
            value.GetValueAsUnsigned.return_value = {'x30':(16384 if product and (cursor[0] == 0 or fault == 'collision') else 12288), 'x0':0, 'x1':0, 'w0':0}[name]
            return value
        frame.FindRegister.side_effect = register
        thread = MagicMock()
        thread.GetThreadID.side_effect = lambda: 20 if fault == 'tid' and cursor[0] == 2 else 19
        thread.IsValid.return_value = True
        thread.GetStopReason.return_value = lldb.eStopReasonBreakpoint
        thread.GetStopDescription.return_value = 'synthetic one-shot breakpoint 3'
        def data():
            number = sequence[min(cursor[0], len(sequence)-1)][0]
            if cursor[0] == 2:
                if fault == 'empty' or created[0].SetOneShot.call_args.args[0]: return []
                if fault == 'id': return [99, 1]
                if fault == 'location': return [number, 99]
                if fault == 'duplicate': return [number, 1, number, 1]
            return [number, 1]
        thread.GetStopReasonDataCount.side_effect = lambda: len(data())
        thread.GetStopReasonDataAtIndex.side_effect = lambda i: data()[i]
        thread.GetNumFrames.return_value = 1
        thread.GetFrameAtIndex.return_value = frame
        thread.__iter__.side_effect = lambda: iter([frame])
        process.__iter__.side_effect = lambda: iter([thread])
        process.GetThreadByID.return_value = thread
        process.GetSelectedThread.return_value = thread
        process.GetNumThreads.return_value = 1
        process.GetState.side_effect = lambda: lldb.eStateExited if cursor[0] == len(sequence) else lldb.eStateStopped
        process.GetStopID.side_effect = lambda *_: cursor[0] + 10
        process.GetExitStatus.return_value = 0
        error = Mock(); error.Success.return_value = True
        error.GetError.return_value = error.GetType.return_value = 0
        def resume():
            cursor[0] += 1
            if cursor[0] == 2 and created[0].SetOneShot.call_args.args[0]: live.pop(3)
            return error
        process.Continue.side_effect = resume
        process.Kill.return_value = error
        with tempfile.TemporaryDirectory(dir=os.environ.get('OBSERVER_TEST_ROOT')) as directory:
            root = Path(directory); output = root/'record.json'; stdout = root/'stdout'
            stdout.write_text('LAYOUT ' + json.dumps({'pointer_size':8}) + '\n')
            config = root/'config.json'
            config.write_text(json.dumps({'output':str(output), 'binary':'/synthetic',
                'mode':('product' if product else 'calibrate'), 'layout':{'pointer_size':8}, 'argv':[], 'environment':{}, 'cwd':directory,
                'stdout':str(stdout), 'stderr':str(root/'stderr')}))
            with patch.dict(os.environ, SIGNAL_OBSERVER_CONFIG=str(config)), \
                 patch.object(lldb, 'eByteOrderLittle', 99, create=True), \
                 patch.object(lldb, 'eSymbolTypeCode', 98, create=True), \
                 patch.object(lldb, 'SBLaunchInfo', Mock(), create=True), \
                 patch.object(lldb, 'SBError', Mock(return_value=error), create=True), \
                 patch.object(lldb.SBDebugger, 'GetVersionString', lambda:'synthetic', create=True), \
                 patch.object(o, 'qualify_calibration'):
                o.observe(debugger, '', None, {})
            return json.loads(output.read_text()), created

    def test_entry_ordinary_lifecycle(self):
        record, created = self.run_entry()
        self.assertEqual(record['status'], 'CALIBRATED', record.get('error'))
        self.assertEqual([event['breakpoint_id'] for event in record['events']], [3, 4])
        for event, bp in zip(record['events'], created):
            bp.SetOneShot.assert_called_once_with(False)
            bp.SetThreadID.assert_called_once_with(19)
            self.assertTrue(event['deletion']['absent'])
        self.assertEqual(record['events'][0]['return_pc'], record['events'][1]['return_pc'])

    def test_exit_lifecycle(self):
        record, created = self.run_entry('exit')
        self.assertEqual(record['exit_thread_id'], 19)
        self.assertEqual(record['exit_pc'], 16384)
        self.assertTrue(record['exit_deletion']['absent'])
        created[0].SetOneShot.assert_called_once_with(False)
        record, _ = self.run_entry('exit-pending')
        self.assertEqual(record['error'], 'Create exit without closed same-thread calls')
        self.assertNotIn('exit_deletion', record)
        record, _ = self.run_entry('collision')
        self.assertEqual(record['error'], 'AMBIGUOUS_RETURN')

    def test_entry_rejections(self):
        for fault, expected in [('empty','BREAKPOINT_STOP_WITHOUT_ID'),
                ('id','UNKNOWN_BREAKPOINT'), ('location','UNKNOWN_BREAKPOINT_LOCATION'),
                ('tid','return native thread mismatch'), ('pc','RETURN_PC_MISMATCH'),
                ('duplicate','AMBIGUOUS_RETURN'), ('delete','RETURN_BREAKPOINT_DELETE_FAILED'),
                ('still-live','RETURN_BREAKPOINT_DELETE_FAILED'), ('nested','nested sigaltstack call'),
                ('stale','UNKNOWN_BREAKPOINT')]:
            with self.subTest(fault=fault):
                record, _ = self.run_entry(fault)
                self.assertEqual(record['error'], expected)
                self.assertTrue(record['stop_snapshots'][-1]['pending'])


if __name__ == '__main__': unittest.main()
