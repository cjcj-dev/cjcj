# TASK21:03 M1与ir2后继合同

## 固定与写权
旧C438bf/install-t2 ELF7abf/std-438bf-1031全部冻结。新私有树source-m1-1031，分支fix/compiler-m1-master-1031；接合master7288为af75d52f672450be94dc68d498e80091b9018530。唯一内容冲突ParserTest_test.cj已保三个真实case：master合法interfaceDecl、原438bf完整distinct-parent断言、selfInheritanceRecovery全部原438bf精确位置/消息/数量断言。不是主线合并授权，未push。
初次--no-checkout新worktree尚无index就merge被拒，原stdout保；此时没有产品修改。仅在新空树正常read-tree -mu HEAD物化再merge；原source未reset/stash/清理。

## M1产品合同
Linux正常宏生产仍以公共逻辑compiler入口计算target runtime DT_RPATH，--disable-new-dtags；它是SDK绑定产物，不承诺随意跨SDK复用。修复消费漏边：所有已发布/缓存/显式--macro-lib/宏server的OpenMacroLibrary入口，在dlmopen/LoadCJLibrary及image initializer前检查实际SO现有DT_RPATH。使用现成LLVM ELFObjectFile公开reader，不新建ELF解析器/manifest或sidecar调度，不恢复helper。
首RPATH经真实路径（含合法ORIGIN）解析必须等于本次选中runtime目录；RUNPATH/missing/malformed/stale绑定拒绝并明确要求用当前SDK正常重编或重链接，不继续加载。旧SDK仍存在也须拒，不能只依赖old-path ENOENT。位于当前SDK runtime目录内libcangjie-std-*由正常成对std安装提供，按既有SDK来源边界消费，不把私有用户macro冒标准库。
该门是SDK选择/失效契约，不校验所有潜在ABI，不证明任意依赖自带RPATH闭包或安全对抗文件替换。原ir2/CJO配对义务保持。其他平台不冒Linux门。
写集：ToolChain生产注释；InvokeUtil共同加载入口；现有静态LLVM shim新增窄只读验证函数（compiler内部C ABI，不增公共R/N ABI），CI注册有限native门。新compiler必须编当前shim，禁止直接拿N575既成旧shim覆盖；N575库/headers只读依赖不改。

## sdk_target_delivery_1031配套真实门（NOT_RUN）
1. 固定新C及完整合格target std/runtime，在SDK-A公共bin/cjc正常产生Identity/链macro SO+CJO，记录原真实macro body/ordinary控制。固定SO字节不重产。
2. 当前正常SDK-B：A仍可见时，通过默认import、显式--macro-lib、正常CJPM缓存命中路径消费同SO，须在macro body/目标runtime initializer前给明确stale-binding非零；不得以新work重产或loader自然找不到库算门。
3. 安全隐藏无引用SDK-A（finally恢复），同旧SO明确拒绝；不修改SO/CJO/mtime。完整既有runtime namespace初始化可能发生，判据是旧macro SO不得被打开初始化。
4. 用SDK-B原正常producer重新编/链接macro，CJO及所有受影响宏缓存正常更新，真实body→普通CJ传递依赖/std.time→目标run成功。新SO须readelf真实RPATH指B，host仍H893/423，target f6d/aee892/N575。缺配套std不启动。
5. 同包搬迁若宏通过正常ORIGIN接线且runtime同步搬迁，可沿实际字节正常加载；本C默认绝对RPATH产物采取显式失效重产，不能声称旧绝对SO自动可搬迁。
stdx owner需核其两个宏producer与发布/install路径：保正常宏重链接/缓存失效，不只复制原SO；其现M1 e079发布接线是否消费此新拒绝需按实际树核，本C不跨写。CI仅需按此接口补旧SO门，不改变当前被冻结SDK。

## ir2完整成对门（全部NOT_RUN）
固定C后继 + 同C正常重产完整std aee892（真实helper CJO/BC/DSO）+ R f6d029及N575。现std438bf完整失败，不能用build-tree core拼完整安装。R owner需提供helper声明/原producer、同步flag修复与Finalizer桥当前固定身份；H执行闭包为H893/host423，不能拿target当host。
真实helper声明reportResetFailureV1(value:Any,typeName:CPointer<UInt8>,context:CPointer<Unit>,notify:CPointer<Unit>):Int32。通知Int32(context,UInt32 kind,typePtr,UIntNative typeLen,msgPtr,UIntNative msgLen)，长度不含终NUL/允许嵌NUL；notify同步复制完成才ACK0，回调不throw，借出字节在回调返回前有效，helper同R finally释放。
原生公开macro正常producer通过真实CJO隐式登记发版本化ir2 reset，旧签名不得fallback。每臂新工作域、每臂一个实际CLI：
- 成功初始化/reset：kind0→ACK0→同R GetTaskRet0（result允许null）→Release一次→外部H控制线程owned Fini一次0→H主任务自然退出，宏/目标marker都到。
- 原Exception与原Error：在真实目标global reset初始化入口分别抛具体类型/原detailMessage（不得override格式化），kind1/2同步精确UTF8复制，异常CLI自身非零，所有已提交future DONE后释放/Fini，保原类型/消息，不被清理异常遮盖。
- helper准备/导出失败：仅原R私域精确刀使helper返回其声明-1..-5之一；C必须kind3/4保可知helper状态与“原细节不可用”，H失败谓词到达，不当正常kind0，不永等。独立正常控制及源码恢复；不能用直接H decoder测试冒实际reset入口。
- ACK非0/通知无法记录：沿真实回调失败出口非零终态，不能吞错成功；仍保owner/arg/future至DONE，Get失败不得Release活future/Fini。监督有界超时仅记受控失败，不冒合法完成。
- borrowed H控制：实际借用H不Fini H；owned R在Init成功立即记责任、后续符号/预载失败仍走已有Main finally→CloseRuntime，保首次异常及责任。失败Fini不再调用取0，不dlclose活映像。
动态取证按实际需要交原Grok，仅已有函数/自然执行点或正常既有日志，记录ACK/Get/Release/Fini/最后H退出顺序；不自造监控框架、不在callback锁内等待自己。每臂监督总≤180秒/首fault保，不循环至绿；具体目标布局/资源在完整pair成熟后实核裁定。旧sig/scope/内存耗用永久保。
这些是执行合同不是PASS。SOURCE增量交原Sol；真实公开旧SO/ir2门与默认pin配套未完成前PAIR_HOLD保持。

## R1/R2 successor controls
Linux_CJNATIVE emits the SDK macro RPATH before user link options, preserving private paths after it. Ordinary shared/executable ordering is unchanged. Admission remains first-path based: an old SDK first and current SDK only at the tail is rejected. The selected runtime directory is retained independently of the native handle, only exposed while initialization succeeded and close has not started; borrowed H still uses the same admission, never initializes/finalizes another H merely to obtain a handle.

The registered tests/macro_binding_paths/Main.cj consumer calls the real Linux_CJNATIVE.GenerateLinkingTool and RuntimeInit/OpenMacroLibrary. Its native SO only validates image admission/loading and borrowed-host close/task behavior, not CJ macro expansion or owned-R ir2. ci/test-macro-binding-paths.mjs records the original two assertion failures, ordinary control, stale-first rejection and repaired paths. The public paired SDK gate must additionally produce a CJ macro with explicit private RPATH, retain the old SO for both default/explicit/cache consumers, and perform normal relink recovery.
