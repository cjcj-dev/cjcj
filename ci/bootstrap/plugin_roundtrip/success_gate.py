import gdb, json, os, re, hashlib
state = {'restore_enter': 0, 'restore_return': 0, 'gate_return': []}
class Finish(gdb.FinishBreakpoint):
    def __init__(self, key):
        super().__init__(gdb.newest_frame(), internal=True)
        self.key = key
    def stop(self):
        if self.key == 'gate_return':
            state[self.key].append(int(gdb.parse_and_eval('$rax')) & 255)
        else:
            state[self.key] += 1
        return False
class Start(gdb.Breakpoint):
    def __init__(self, symbol, key):
        super().__init__("*'" + symbol + "'", internal=True)
        self.key = key
    def stop(self):
        if 'mapped_files' not in state:
            mappings = gdb.execute('info proc mappings', to_string=True)
            with open(os.environ['GATE_JSON'] + '.maps', 'w') as f:
                f.write(mappings)
            paths = {line.split()[-1] for line in mappings.splitlines() if '/' in line}
            state['mapped_files'] = {}
            for path in sorted(paths):
                if os.path.isfile(path):
                    with open(path, 'rb') as f:
                        state['mapped_files'][path] = hashlib.sha256(f.read()).hexdigest()
        if self.key == 'restore_return':
            state['restore_enter'] += 1
        Finish(self.key)
        return False
for term, key in [('StringToCHIRPtr', 'restore_return'), ('ExecuteCjPlugins', 'gate_return')]:
    output = gdb.execute('info functions ' + term, to_string=True)
    symbols = re.findall(r'0x[0-9a-f]+\s+([^\s;]+)', output)
    matches = [s for s in symbols if term in s]
    assert len(matches) == 1, output
    Start(matches[0], key)
gdb.execute('run')
mode = os.environ['GATE_MODE']
expected = {'pass': (1, 1, [1]), 'reject': (0, 0, [0]), 'missing': (1, 1, [0])}[mode]
actual = (state['restore_enter'], state['restore_return'], state['gate_return'])
state['expected'] = expected
state['pass'] = actual == expected
with open(os.environ['GATE_JSON'], 'w') as f:
    json.dump(state, f, indent=2)
print('ASSERT product-success-gate ' + json.dumps(state))
gdb.execute('quit ' + ('0' if state['pass'] else '1'))
