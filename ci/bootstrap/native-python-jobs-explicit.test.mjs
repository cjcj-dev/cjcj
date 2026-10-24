import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import {windowsPythonJobs,windowsPythonBuildArgs} from './native-python-windows.mjs';
test('explicit jobs above available CPUs reach the PCbuild MSBuild argument',()=>{
 const available=os.availableParallelism(),jobs=available+1;
 console.log('PYTHON_EXPLICIT_JOBS_ASSERTION_REACHED '+JSON.stringify({available,jobs}));
 const selected=windowsPythonJobs(jobs);
 assert.equal(selected,jobs);
 assert.ok(windowsPythonBuildArgs(selected).includes('/m:'+jobs));
});
test('invalid jobs remain rejected independently of oversubscription',()=>{
 for(const jobs of [0,-1,1.5,'4',NaN,Infinity,Number.MAX_SAFE_INTEGER+1])
  assert.throws(()=>windowsPythonJobs(jobs),/WINDOWS_PYTHON_NATIVE_CAPACITY/);
});
