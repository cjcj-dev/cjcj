import os from 'node:os';

// A caller may lower concurrency for memory or time constraints. Do not let
// upstream build.py defaults silently replace that explicit selection.
export function crossBuildJobs(env = process.env, component = 'runtime') {
  const requested = (component === 'std' ? env.STD_BUILD_JOBS : undefined)
    ?? env.CANGJIE_BUILD_JOBS ?? (env.CMAKE_BUILD_PARALLEL_LEVEL || undefined);
  const available = os.availableParallelism();
  const jobs = requested === undefined ? available : Number(requested);
  if (!Number.isSafeInteger(jobs) || jobs < 1)
    throw new Error('CROSS_BUILD_JOBS: expected a positive safe integer');
  return jobs;
}
