LANE=sym_cjcj_47_implement_r5749367643
# kkk2 Node 入口缺失
本包编译/测试必须经 box.sh kkk2。实测 node --version rc=127。/usr/local/bin/node 是指向 /media/kkk2/428602AC8602A111/tools/node-v20.19.0-linux-x64/bin/node 的失效符号链接；直接运行亦找不到文件。常见现有 node 安装路径检索未找到可用入口。
按常备裁决7不修共享runner/SDK。请提供既有可用 Node/zx 入口或裁定本棒私有目录可用输入。目前继续不依赖运行环境的C1/C2源码接线，进度保持WIP；不把静态检查记作三臂通过。
