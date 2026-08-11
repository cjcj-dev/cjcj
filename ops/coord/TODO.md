
## ⭐⭐⭐⭐⭐ 0811 18:2x 心跳 —— ⭐ 看起来像全通道故障，⭐⭐ 实为**四条同时交付退出**

- [x] ⭐ ① 在飞 = **0 条**（⛔ 20 分钟前 8 条）⇒ ⭐ 先按"全通道故障"诊断 ⇒ ⭐⭐ **诊断结果是它们全交付了**
- [x] ⭐ ② `longrun_check 20` 无长跑 · ⭐ ④ advisor 积压 **0**（⭐ 正确方向）· ⭐ `/tmp/audit/tasks` 231 份存活
- [x] ⭐ `abiassert` **6 笔早已在 master**（⭐ 我的 `e7309871` 全带进去了）
- [x] ⭐ `designaudit` / `garbregion` = `DELIVERY_REF=none` ⇒ ⭐ 报告类，⛔ 无可合

### ⭐⭐⭐⭐⭐ `sigb` 13 分钟答完 —— ⭐⭐ **签名 B 不是着色缺陷，⭐ 是编译器缺陷**
```
⭐⭐⭐ `WHATISIT` = **(b) 整个 64 位都是垃圾**（⭐ 未初始化栈槽被当对象头读）
   ⛔ 不是 (a) 合法堆地址+垃圾高位 · ⛔ 不是 (c) 浮点/ASCII 语义值 ⇒ ⭐ 四枚 + 跨 run 全同形
⭐⭐ `MAPS` = ⭐ 低 48 位 **NOT_IN_ANY_MAPPING**（⭐ 四枚 × multi-run）⇒ ⭐⭐ 这就排除了 (a)
⭐⭐⭐ `WHOWROTE` = **没有"往指针高位写"的写入者**
   ⇒ ⭐⭐ 写入面 = **PEA 栈提升后的假对象【从未初始化】**
   ⇒ ⭐ `String.runes` 0x15 桩返回栈 VA → `escapeControlCharacters` 读 `*(rbx)` = 随机 64 位
⭐⭐ `PEA` = **成立**（⭐ 四枚产物**直接**证据，⛔ 非间接推断）
⭐⭐⭐ `POSCTRL`（⭐ 三条，⭐ 同一命令形状）：
   ⭐ stageB `String5runesHv size=0x00ad` vs ⭐⭐ **四枚坏样 `size=0x15`**
   ⭐⭐ **pin cjc × 着色 RT `--version` RC=0** ⇐ ⭐⭐⭐ **plain 编译器【能】在着色 RT 上跑**
⭐⭐ `COLOUR` = ⭐ 它自算与主控第二节**一致**：⭐ 色位最高 57、⭐ rdi 跨 run 稳定 bit≥58 ⇒ 非着色
⭐ `SICODE` = ⭐ 主形态 `si_code=128 / si_addr=(nil)`；⭐ 偶发 `si_code=1`（⭐ 高位碰巧规范时走页故障）
   ⇒ ⭐⭐ **正是主控 0810 那条"两分支"的活体实证**
```
⇒ ⭐⭐⭐⭐⭐ **归属改判：⭐ 挡住整条发版链（Q5/Q11/Q14/Q15 + final-std）的是【编译器 PEA】，⛔ 不是 GC/着色**
⇒ ⚠ ⭐⭐ `hostpair` 的 A 类表述要修：⭐ 「plain 编译器 + 着色 rt 自相矛盾」**至少对 `--version` 不成立**（RC=0）

- [ ] ⭐⭐⭐ **修法（`sigb` 给的方向，⛔ 它未测）**：⭐ `tzinit` 的 **skip `UncolorIfGCPtr` on EXIT**
      ⇒ ⭐ 重编 std 使 `runes`/`lines`/iterator 的 `size ≠ 0x15` ⇒ ⭐⭐ **判据现成：`size=0xad` vs `0x15`**

### ⛔⛔ `tools/unharvested.sh` 有**两个独立缺口**（⭐ 本轮各暴露一次）
```
⭐ ① `garbregion` 首行不是 `PROGRESS=DONE` ⇒ ⭐⭐ **首行匹配器结构性看不见它**
   ⇒ ⭐ 同族：`three-tools-copied-one-format-assumption-producers-break`
⭐ ② `abiassert`/`designaudit` **只因我在台账里提过就被当成已收割**
   ⇒ ⭐⭐⭐ **登记 ≠ 收割** —— ⭐ 我提的是【派发】，⛔ 不是【裁决】
   ⇒ ⭐ 同族：`registering-an-item-can-silence-its-alarm`
⇒ ⭐⭐ 两者都让它**少报**（⛔ 不是多报）⇒ ⭐ 而少报是静默的
```

### ⚠ 主控本轮两次自查生效
```
⭐ ① 「在飞=0」时**先带阳性对照复核**（`pgrep -fc opencode`）⇒ ⭐ 避免报假警"全通道故障"
⭐ ② 查 abiassert 是否已合，⭐ 第一次用**猜的标识**（`colourAbi`）⇒ 全 0
   ⇒ ⭐⭐ 第二次从**提交自己的 diff** 取（`countSdkLoadBadMask`）⇒ ⭐⭐⭐ 才发现它早在 master
   ⇒ ⭐ 这条规则（⭐ 标识必须取自该提交）本战役已第二次救我
```
