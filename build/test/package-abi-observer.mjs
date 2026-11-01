// Finite observation of the public package ABI gate. No SDK input or ABI
// implementation is replaced. Stop before path parity/consumers/SDK writes;
// exit 78 is an observation boundary, never package success.
export async function load(url, context, nextLoad) {
  const loaded = await nextLoad(url, context);
  if (url !== new URL('../../ci/srcbuild/lib/package-install.mjs', import.meta.url).href) return loaded;
  const source = String(loaded.source);
  const anchor = 'assertSdkCompilerRuntimeAbi({sdk,target});';
  if (source.split(anchor).length !== 2) throw new Error('package ABI observation anchor changed');
  return {...loaded, source: source.replace(anchor, anchor + `
 console.log('PACKAGE_ABI_READONLY_BOUNDARY_REACHED');
 process.exit(78);
`)};
}
