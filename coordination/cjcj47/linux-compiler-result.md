LANE=sym_cjcj_47_implement_r5749367643
# 获准真实Linux输入首次编译失败（不重跑取绿）
按113344Z答复复制b99430a618af-1ecb811801ca SDK到本棒私有real-linux/sdk（cp -aL），只在副本替换0189f2e0两SO。cjc SHA=b99430a618af85783974d8c0b7f598cca1f9bca882adfdfd99fc158b9a0e7917，当前runtime=c6d398ea09c329cf39271e6b42b619359e05ef92998f0b2dbbf49e5144a9994f，bounds=f18a1393f84d56a455c71c0c28bf1752c1778af06c0648c1b7cffa91c585c883。
--version rc=0。产品stdx.run→runBuildPy已执行，runtime split host=0,target=1通过。实际argv=[私有sdk/bin/cjc, 本棒real-linux/main.cj, -o, 本棒workspace/cangjie_stdx/real-consumer]，源码main() { return 47 }。compiler宿主loader严格指向指定48 host/runtime/lib/linux_x86_64_cjnative。
首次编译cjc rc=-11，strace仅见cjc execve=0，随后SIGSEGV si_code=SEGV_MAPERR,si_addr=0x10000000c；没有进入LLVM子进程或生成可运行ELF。保留kkk2:/root/sym_cjcj_47_implement_r5749367643/real-linux/{invocations.jsonl,run.log,run.rc,input.sha256,uptime-before.txt,uptime-after.txt,workspace/cangjie_stdx/compiler.stderr,workspace/cangjie_stdx/compiler-execve.log}。核域0-15已预约。首个脚本构造错误在setup-error.log中独立保留，该轮未启动compiler，不计编译样本。
#44也记录编译阶段SIG11，但其为另一CJC/负载，不能据同信号判同根因。本包按“不吸收#44编译资格”不改compiler算法、不重编碰绿。装置九刀green/restored=43/43，各刀局部转红继续收口。
请裁定真实Linux验收此项按“失败事实/增量归因未定/不计通过”保留并随C3闭合的处理，或指出当前调用缺少的现行配方条件。保持WIP等待，继续装置/报告工作。
