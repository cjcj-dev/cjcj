# Pending native plugin integration checks

The metadata unit tests exercise the same validator called by the production
loader. They do not establish a native plugin ABI or loader integration PASS.
Use only a fixture whose getter return ABI has been independently accepted for
this implementation's `MetaTransformPluginInfo`; do not substitute an unrelated
C++ SDK header. These checks have not been executed.

For a small valid source `main() {}`, invoke the candidate compiler with
`--plugin <absolute-library-path>`. Each library must omit `executeCHIRPlugins`
so the production C++ fallback is selected. Retain the no-plugin compilation
as a positive control.

- Null version, present callback: normal invalid-plugin diagnostic and nonzero
  exit, with no signal/ICE. The callback must not run.
- Wrong version, present callback: the same normal invalid-plugin rejection.
- Matching version, null callback: the same normal invalid-plugin rejection.
- Matching version, present callback: explicit unsupported-native-plugin
  diagnostic and nonzero exit; no silently successful compilation. This is a
  capability rejection, not evidence that C++ plugin execution works.

Run the valid Cangjie-plugin route as a separate positive control using the
existing approved runtime/fixture; the native rejection must not affect it.
A controlled rollback of the frontend rejection should make the fourth case
fail its diagnostic/exit assertions. A rollback of the metadata null guard
requires the authorized isolated core=0 gate and signal/rc evidence; a crash is
not a successful invalid-plugin rejection. Restore and rebuild before recovery.
