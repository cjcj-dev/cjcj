These files are byte-for-byte copies of upstream cangjie_compiler
`unittests/Utils/CangjieFiles/{testpkg01.cj,pkg01.cj,emptyfile.cj}` at
`367d9ca8845ba8ef5fd9c17ea983c9692e303f62`.

`testpkg01.cj` starts with the UTF8 BOM EF BB BF; `pkg01.cj` has no BOM;
`emptyfile.cj` has zero bytes. Preserve their bytes (including line endings).
FileUtilTest reads these tracked, read-only inputs from the private checkout
root, using PROJECT_SOURCE_DIR when supplied and the workspace cwd otherwise.
They live for the checkout lifetime; tests do not create or remove them.
