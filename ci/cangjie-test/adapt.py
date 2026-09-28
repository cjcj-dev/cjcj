"""Apply recorded scheduling-only edits to private pinned harness copies."""
import hashlib
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise ValueError('upstream scheduling anchor mismatch: ' + str(path))
    path.write_text(text.replace(before, after))


def prepare(inputs, output):
    destination = output / 'execution-inputs'
    shutil.copytree(inputs, destination)
    test = destination / 'cangjie_test'
    framework = destination / 'cangjie_test_framework'
    harness = test / 'Conformance/Compiler/harness'
    for root in (framework, harness):
        shutil.copyfile(HERE / 'admission.py', root / 'admission.py')
    maple = framework / 'maple_test/run.py'
    replace_once(maple, '    remain_time = timeout\n',
                 '    from admission import wait_for_load\n'
                 '    wait_for_load(case_path)\n    remain_time = timeout\n')
    driver = harness / 'core/driver_manager.py'
    for phase in ('compile', 'execute'):
        anchor = f"    '''Choose {'compilation' if phase == 'compile' else 'execution'} driver for tests'''\n"
        replace_once(driver, anchor, anchor + '    from admission import wait_for_load\n'
                     '    wait_for_load(test.test_path)\n')
    manager = harness / 'core/task_manager.py'
    replace_once(manager, '        self.reporter.write_test_result(test)\n',
                 '        self.reporter.write_test_result(test)\n'
                 '        from admission import cleanup_executable\n'
                 '        cleanup_executable(test, self.cfg)\n')
    changed = [maple, driver, manager, framework / 'admission.py', harness / 'admission.py']
    hashes = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in changed}
    return test, framework, hashes
