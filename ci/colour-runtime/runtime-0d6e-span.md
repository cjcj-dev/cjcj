# Runtime selection span for #878

Coordinates: `9733dfc09d29eca27d19cc3937a149838b4e3322..0d6e0888216481c55d1e8b2a0fc2685672289b6a`.

This selection admits the complete span below, including merge commits. The gate result applies to the complete target, not an individual runtime repair. Original enumeration: #863 lane `sym_cjcj_863_implement_r6028976537`, `runtime-span.txt` (rc=0). Each line records the original commit mechanism.

```text
0d6e0888216481c55d1e8b2a0fc2685672289b6a fix(gc): qualify pinned same-source language toolchain (#1505)
f2283db793be1fcbe986f9a4ed5c217609dcf3ca fix(tests): keep director stall reports outside source cwd (#1502)
b895160473b86121497b7b96ed06214a4815976f gc_unit容量派生尺寸超过MSize32位边界：32GB输入使三项零尺寸清零下溢 (#1500)
e1fd6b453fdcea3524a0f62c04b02577557ac384 fix(tests): qualify real teardown exit states on ARM and x64 (#1495)
fe7c402adfdf08ea9c28ad0246af95c163ebda18 ci: qualify ARM root worker budgets with four bounded filters (#1494)
e794ef867a8618f07dad26ee054ec5ce1201802a fix(runtime): route concurrent VM operations and debug STS identity (ZGC vmThread.cpp:525, handshake.cpp:245) [skip ci]
1c00da0552ac4a4bb343ea08cf80d9a214a19bae fix(runtime): restore limited Linux return ABI (sharedRuntime.cpp:573-636) (#1461) [skip ci]
13100bd8968966cb6ff8c3e91454e9956f751978 ci: register reviewed PAC dispatch entry (#1488) [skip ci]
1a5e4c20fd3e8db9bd1d37b8b4bb07cb287aed75 fix(gc-test): observe actual promotion field consumers (#1477)
73722db3598748ca45807bb54f785ccf4fd1c31e fix(inspector): supply Heap declaration in real OHOS serializer (#1471)
2ebbe705f7669acec00c0e3bc59768d841a3f0a5 fix(runtime): complete owned carrier shutdown before runtime teardown (#1465)
3bd02fb82e73235d567d8fff501c8e4060b322c6 feat(runtime): dedicated VM thread executes ZGC VM operations (vmThread.cpp:325-430) (#1419)
b37f6c28881cb87c7894c4280c2327db7fe962da fix(gc): align remaining remap guards with ZGC (#1327) (#1440)
1d56071741c4ebef4448e15f4caa8dc7e9657563 test(gc): isolate partial commit supply (ZGC zPageAllocator.cpp:1906-1932) (#1464)
cd0188872527a76822a750c536468f7acec239ca test(gc): capture armed-root SIGSEGV stacks and map consumers (#1463)
fc2fe6e2dc0b295e09a540d8e6c55717fa147718 fix(gc): publish barrier owner into the init consumer chain (#1455)
31d670c3ec5e2ff6b3b385d8c568b80de9502e75 test: honor millisecond uncommit wait floor (ZGC zUncommitter.cpp:75) (#1450)
f86a05eda2a5b83acb4d1566a750a593c637ea1d test: distinguish explicit workers above ZGC CPU bound (zHeuristics.cpp:77) (#1451)
f791fb63b4dab7a76c693aee0e8e01b0531c3916 fix(runtime): publish main scheduler readiness after startup (#1429) (#1437)
a702cc1ae29f014a064de9fc742e2250f15ac215 fix(gc-gate): explicit qualified managed SDK admission (#1443)
848eb5dac7e9bc3c98538947447613e5fc8ab301 test: deterministic StringDedup cleanup and shrinking old-bucket assertions (#1446)
a92ceccbde0bf2beb407d8fb13d76a8084997b7a fix(gc): remove global GC enable chain (#1344) (#1445)
b5a9a6e600a33369744e8781ffc2e8b19ec27da8 fix(gc): align forwarding cursor and attached array with ZGC (#1441)
dacc7836b65997517e3e03853fdd9d0c0d44565f test: configure root fixture workers (ZGC zArguments.cpp:64) (#1438)
f91d1161ad171cb5d757456c5d1feeb17c778f3f fix(gc): align JNI critical initialization and count invariants with ZGC (#1442)
9dfc8ef5b34cdedaa9b304c21093b10615ee34be #1403 merge: t2 integration of #1310/#1312/#1313/#1315/#1334 onto main 7a09afc339 (#1439)
7a09afc33959587721cb11ad549777a0653a59c7 fix(gc-gate): preserve invocation-owned diagnostics (#1303) (#1420)
333414c2bb9ebaa4ab81aadf5f03a0f62882e106 fix(gc-unit): supply native aarch64 frame-root fixture (#1418)
7bae5c9431798e69bc740fd804cf4d75d0cfde3c fix(gc-unit): derive testable hook contract from current product sources (#1407)
b41b10d2f75c4a87e531116b8659ef27dd8ff673 fix(gc-unit): restore registration omitted by #1338 (zRelocationSet.cpp:126) (#1428)
54ab903ecb713f7fd8a3e85a77b8014a6a3954e9 Merge pull request #1417 from cjcj-dev/sym/1294-implement-r5907308431
9ac998ac2c45e51d943c7a3ea27d4743e4d9117d Merge pull request #1416 from cjcj-dev/sym/1298-implement-r5907297386
5a69cf844663f98ac599bf4df3164c8b06d76725 Merge pull request #1415 from cjcj-dev/sym/1397-implement-r5906319245
df45bcf6d63642624947a3a9ee89c982198476f0 fix(gc): align branch detach with ZGC zRelocate.cpp:1026 (#1423)
cd0f3384f696aedd1ed013a8052e11c9ac9e07b2 Merge remote-tracking branch 'cjcjdev/main' into sym/1294-implement-r5907308431
2611dfe8869b344b8b4058b21bfc788f240fa3f7 Merge remote-tracking branch 'cjcjdev/main' into sym/1298-implement-r5907297386
0f59d359568f0469c286da9991397fa67aee1543 ci: select ARM test ELF from registration (zAddress_aarch64.inline.hpp:29)
a39cdaa7cc5087ae8e92bfd6490ebfdd08cedd6c Merge pull request #1408 from cjcj-dev/sym/1355-implement-r5905806307
746982d5d8a6fa073a0c01b99a1af723487b404f ci: pass exact unit selections to ARM runner (zAddress_aarch64.inline.hpp:29)
c2e38e56942157de720dfdc35f14ab9b7282b2c3 test(gc): make BSD errno diagnostics causally checked ZGC zPhysicalMemoryBacking_bsd.cpp:110-159
75d4ef9c7b69c6059332f62fec4623e57ccf128a fix(gc): include BSD trace declarations ZGC os_bsd.cpp:1815-1820
b3822a7e012be4ac1534a165343fbb0ae3a13912 ci: add authorized ARM ELF/product ref unit runner (zAddress_aarch64.inline.hpp:29)
2af4e5e4e624eb056893abb5b5c4d7ae5963c8f8 test(gc): verify Darwin product alignment assertions ZGC zPhysicalMemoryBacking_bsd.cpp:99-148
3a0c6e889b9171872d205fd0bda8be49c93d5b61 test(gc): preserve native product archive routing ZGC zPhysicalMemoryBacking_bsd.cpp:99
527a32402520272e035623796acfe8b6bbc502aa test(gc): exercise Darwin product reserve and commit ZGC zPhysicalMemoryBacking_bsd.cpp:75-161
7f93bee308cd47bdf5fc0473c7f91e2452144e23 fix(gc): normalize BSD reserve failures at OS helper ZGC os_bsd.cpp:1798-1822
9f77f8b0b903ae07d965818fd32b75dafb1655d9 fix(gc): align BSD commit diagnostics with ZGC zPhysicalMemoryBacking_bsd.cpp:99-161
54d6d54e297666594f736abd12d148e69b2468b9 test(gc): encode minor remap input per zAddress_aarch64.inline.hpp:29
7fd0e9b7d935a8f64afa501b13ff07f277b20d76 test(scheduler): cover UI entry and inlined queue snapshot (Go proc.go:7293)
a9ed63f1c5a5655cae824678abf729a2c5f90721 Merge remote-tracking branch 'cjcjdev/main' into sym/1397-implement-r5906319245
9d61e370c2a92c085ee7cf7af8c335615dbde9f0 test(scheduler): verify count snapshots and queue state at product exits (Go proc.go:7293)
6e47ee367b6c56208695b357d36d8fa16ddd4f1f Merge remote-tracking branch 'cjcjdev/main' into sym/1355-implement-r5905806307
6f66fbd3fcbdb2ff999417dc1862c59e0f5aaabc Merge pull request #1406 from cjcj-dev/sym/1404-implement-r5905787271
346372a390a2f13208f049078ba391290302153a Merge remote-tracking branch 'cjcjdev/main' into sym/1355-implement-r5905806307
1d9009de56429a9b8bafb3643c258a5e4605e845 test(scheduler): observe product queue count lock ownership (Go proc.go:7293)
91919f81917f6722bca7562f9cae8f92767a2b9b test: remove unused ZTestRegionHeap fixture (#1353) (#1405)
088001f5bee28f287ea7d3caeca3e2c26d0f03eb fix(scheduler): serialize global queue count reads (Go proc.go:7249,7293)
19afcbcc7e614b66874e36cd172e25279149807f fix(test): sample exited workers correctly (workerThread.cpp:218)
8b70c53b9f554be9b6c7f0d462e80370557df657 test: share GCLOG schema versions with young-STW fixtures (gclog_schema.py:211)
17c23de8c6d462e501bacc18120dd5dd4476175d fix(gc): align verification and root task closures with ZGC (#1342)
9d1c0e97facf51c6c7c659158175dcbaac834bcf fix(runtime): preserve armed polls across logical-owner binding (#1401)
8545147ea963543954757d02da8b6dfb610b5776 fix(scheduler): wake idle processors after syscall exit enqueue (#1400)
f29281826cf80d1b5eee923ad0050289532a817d Merge pull request #1364 from cjcj-dev/sym/1329-implement-r5895635641
ba3df1388231f9c28b5b15df60976cf0cc157310 test(gc): attach follow threads per ZGC zMark.cpp:637
01560d12c9ae8d0e42b7427c5e049afb91e7e10f fix(gc): own follow context per ZGC zMark.cpp:635-668
7ac12d3a6d35dd46869f8ac77bc8ec1087d543c4 Merge remote-tracking branch 'cjcjdev/main' into sym/1329-implement-r5895635641
6508228717bc550631f160fbcb20f58cfc1fc457 test(gc): read atomic wake state per ZGC zMarkTerminate.inline.hpp:107-123
9c7866ce02609ad016992ee0cf5697868b51665f Merge pull request #1390 from cjcj-dev/sym/1389-implement-r5902130102
6d35925289eb608cba75892616a822fc0986b300 fix(gc): merge mark consumers and retain alignment per ZGC zMark.cpp:417-425
13b0db80fef2846df8be37ebde18020759769400 fix(runtime): restore GC totals through serviceability cycle managers (#1366)
a052b4afb7731aa8c833b67cf7a5c1063db9b5db fix(gc): scope invisible roots to the array initialization window (ZGC zThreadLocalData.hpp:101) (#1386)
d0ed34e5b8ae5758dacdc6255ffd7599ef45f9a5 refactor(gc): remove parallel forwarding lifetime interfaces (#1338)
1b1e02152705ba775f0dfd5e1c542def6fa0d1ec fix(gc): align mark consumption and array continuations with ZGC (#1363)
dc6cd95371761d9a0e82113e63578a6e4b8f5789 fix(gc): remove unconsumed tracer stubs (#1376)
c77be07bc3ed809156ddf2f9b48227c0a15a45e3 test(gc): separate worker join positive control (ZGC zMark.cpp:621)
9e7e339b02874a159f16f91e91416002dc868cfc Merge remote-tracking branch 'cjcjdev/main' into sym/1389-implement-r5902130102
5bdb2832170061fd055e9e8947f10492bb01e7e2 test(gc): observe proactive handshake STS membership (ZGC zMark.cpp:621)
09a992bc67955394308bf2b7c4433270ea36bc28 Merge pull request #1382 from cjcj-dev/sym/1380-implement-r5899973197
821ced73084bb248ff19eadddd0004f428fb8aeb fix(gc): leave STS for proactive flush (ZGC zMark.cpp:621)
29da17b32c406f3eb611aa518a07b104a273638e test: migrate uncommitter fixture API (ZGC zUncommitter.cpp:206)
583370740011dc5d3f465872549f6dacb0617af7 Merge pull request #1374 from cjcj-dev/sym/1373-implement-r5899269880
b4dd9a5a7484f2773c1c4a80ae2d6c2f6145ce56 fix(gc): align remset task flush and relocated field ownership with ZGC (#1340)
ce466e3b594198d52b0a9c1ae8760fb042f7241c fix(runtime): restore ZGC collection lifecycle records and readers (#1370)
ba1e06f1cf0adb0dd4d75bab5b49054805a676c4 fix(gc): align mark flush and director tick with ZGC (#1339)
42e277b9342a0dc7ecb5cbedb2a7b07a1d123c42 fix(gc): reset canceled uncommit cache history and align cycle state (#1320)
a8545708069155f291eaab472477ced6cce05310 Merge pull request #1367 from cjcj-dev/sym/1318-implement-r5896375677
da0abf38f36df440920c785b0fd28ff71cb39a1b Merge remote-tracking branch 'cjcjdev/main' into sym/1373-implement-r5899269880
f249ed9064053b4af44ce4879953a7261d82f4e5 Merge pull request #1365 from cjcj-dev/sym/1321-implement-r5896287532
481df97b56dccdeacd02ca4f4f0dec1c65899ca6 test(gc): migrate alloc_page fixtures (ZGC zHeap.hpp:111)
333ead0c735573cec16a5855ded52d3f0a432b4f Merge pull request #1368 from cjcj-dev/sym/1317-implement-r5896380676
244461cf64f74b2d5e5945784da5048b55de66fc Merge pull request #1362 from cjcj-dev/sym/1331-implement-r5895529148
9dce56c966f99f051dbe3fcb4ce1ff4db24832d5 test(gc): migrate remembered publication to ZGC zHeap.cpp:253 allocation
3de79e3a65bd9586ccbcbe924da5ce75e93219ea Merge remote-tracking branch 'cjcjdev/main' into sym/1317-implement-r5896380676
bfb22f6951562bcf81d479bea901acfa56913db9 test(gc): compare page pointers for ZGC zHeap.cpp:253 allocation contract
17fc74abafbbd65e87efadcd92addd9d5e138ade chore(gc): merge main for arraycopy validation (refArrayKlass.cpp:272)
0ca1d90c4a6721e04f3441d1c59c2f2b9ccccf97 test(gc): complete worker origin matrix and harvested-set checks
9bf3b1e3bb7a0634390c968d9293d13fc9f93991 test(gc): observe live TLAB accounting and release stalled fixture
2873a9fe2546ef503e534073fe00eb470c362177 Merge remote-tracking branch 'cjcjdev/main' into sym/1318-implement-r5896375677
6f75e652e7025a50235670e9f9e00a8e2c6f10ed fix(gc): report weak-root deaths to storage owners (#1335) (#1357)
f969b653c1b6cca81d5469fc40944bd838a09ddf Merge remote-tracking branch 'cjcjdev/main' into sym/1331-implement-r5895529148
f39c6df0858962a021352c3eae607bcf3f5d67b2 chore(gc): retain main root closures alongside ZGC zPageAllocator.cpp:1467 alignment
ce18db329c6a1bd5ef7eb116d4f18620ff3d6970 Merge pull request #1359 from cjcj-dev/sym/1333-implement-r5895295864
b78b76b95124b4264ee35d2d199d9815508c6ed7 test(gc): exercise allocator failure and worker origins at ZGC zPageAllocator.cpp:1494
2219cf24e3e2f9d3dbb543bbda316e42a4d25281 refactor(gc): preserve ZGC allocator decision steps (ZGC zObjArrayAllocator.cpp:41-77)
454db840ae4de03dfb44e6577c98d8ba045f7582 test(gc): retire managed product hook consumers (ZGC zObjArrayAllocator.cpp:140-187)
bf8be27ac49a674cc04f55f5462499e5f343455d fix(gc): align allocation transactions and worker flags with ZGC zPageAllocator.cpp:1467
01f6ae12785768057b54bc960297bcd59ae2e279 test(gc): drive segmented clearing from external GC thread (ZGC zObjArrayAllocator.cpp:138-183)
0489ef541fcf5883c809d8e486255d564513885e fix(gc): route array initialization through allocator (ZGC zObjArrayAllocator.cpp:46-105)
b472767fd9fb37e936b3a122f972c4befd49e2f1 test(gc): cover empty destination and headerless array copies (refArrayKlass.cpp:272)
0673590a4696202101acaa730c09aa03adc3ea95 chore(coordination): record 1331 final verification harness and entry cut
94d3817b5edf7541965525f197a3b64b754c9731 fix(gc): retain headerless value payload adaptation (zBarrierSet.inline.hpp:477)
4dab8fc812643ffd3d5a6b156fe59b6fa0d05115 fix(gc): establish arraycopy length at entry (refArrayKlass.cpp:272)
6955edada9a8babe8b7eb8dcf8557654542385d7 fix(gc): place page table iterators at ZGC zPageTable.inline.hpp:36-90
184794066ce865e3af466c8628b8586499cd9174 wip(auto): preserve sym_cangjie_runtime_1331_implement_r5895529148 before recovery redispatch
54644ce16b1e45f51ae04887e0b817a820c42b61 test(gc): use configured driver budgets per ZGC zDriver.cpp:183,399-400
c086eebbc6f9e48064339c7482765a24ce9cace8 fix(gc): migrate cache consumers and match ZGC zMarkTerminate.hpp:33-36 counter layout
ea2d4c78c0e6cb1bad5d89176657245722604cf1 fix(gc): split mark end and flush task generations per ZGC zMark.cpp:417-425,895-991
d5d7123e14af4408875412e268192c6b9a91a5cb fix(gc): route page iteration through ZGC zPageTable.inline.hpp:57-90
356eb4725fab0e1e037291c4053eb7fcef774e63 fix(gc): select worker maximum by generation per ZGC zWorkers.cpp:41-79
5bb63fdd22259d33a7e1479630dc73ff991cb803 fix(gc): align termination atomics and cache size with ZGC zMarkTerminate.inline.hpp:43-123 zGlobals.hpp:79
b3b47f46108c39ec664905990cef90a7305c7843 fix(gc): align value counts and page table extent with ZGC zValue.inline.hpp:45 and zPageTable.cpp:32
5200da2af40ecf5e04c5e823fee27bd5e5f39433 Merge remote-tracking branch 'cjcjdev/main' into sym/1333-implement-r5895295864
d1f697a053fec85a657286ce5d1c4aeb8fba09b7 fix(gc): align heap iterator termination and bitmaps with ZGC (#1325)
d3a4a1591b4ecb40fe455c104ac853f4a770714a test(gc): exercise root closure through GC (ZGC zStackWatermark.cpp:163)
7f48515004f5b36fcfb7e0eac5b61e554dc6de40 fix(gc): port uncolored root closures (ZGC zUncoloredRoot.hpp:87)
e79d5f985719808c04c68d3e63e9358cbc391ee4 Merge pull request #1323 from cjcj-dev/sym/1306-implement-r5892792442
37ffd0b7e4c192553acb00229bb35616b9ce9f0c fix(gc-unit): link the product internal Copy object on aarch64 (#1296)
d9d530281a2edbcb0aef1f6cf6ea48ab058fd45a test(gc): observe shared-page undo through real allocation (zObjectAllocator.cpp:66-110)
4c500746d6cc1b28a6047b0d5ec29dcc2069af27 refactor(gc): account pages after table publication (zHeap.cpp:255-262)
2fbd5b92b78ef8df812a193577ac5a295c1dbfd4 refactor(gc): own TLAB history in ZTLABUsage (zTLABUsage.cpp:41-67)
```
