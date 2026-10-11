# Fiber Twig — 原始游戏交互逻辑（逆向分析）

本文只记录**从原始 `FiberTwig.exe` 恢复出来的交互逻辑**，不参考 remake 现有实现。
分析对象：`FiberTwig/FiberTwig.exe`
SHA-256 `f7a15e5ef1c7c142f93f5699898d61fea3bee0b023fa7ff2092aaefca8f22137`
工具：Ghidra 12.1.2（经 REA）。辅助证据：`demo.dat`（409 s 的真机录像）、
`options.cfg`、`FiberTwig.li`（`remake/assets/data/interface.json`）、
`assets/Game-*.png`。

---

## 0. 关键函数对照表

| 地址 | 角色 | 证据 |
|---|---|---|
| `FUN_004971b8` | 左/右键按下总处理（拾取、放置、旋转、工具点击） | 引用 `TakeFishka`/`RotateFishka`/`CanNotPutFishka`/`LHintMatchingJoints`/`ClosedLink`/`PutFishkaInOtboynik` |
| `FUN_0048f704` | 鼠标移动（FormMouseMove）：更新悬停、预览 | 写 `DAT_004bada0/a4`(鼠标)，调用 `FUN_00499668` |
| `FUN_0048b2d0` | 每帧游戏逻辑主循环（相机、自动生成、超时） | 调用 `FUN_0048c82c`(新枝)，写 `DAT_004badc8`(相机) |
| `FUN_00493c30` | 每帧渲染/界面刷新 | 调用 `FUN_0048bf78`(传送带) |
| `FUN_0048bf78` | 传送带移动 + 弃枝动画 + 悬停 | 引用 `<MoveSteck>`；写传送带 x |
| `FUN_0048c82c` | 生成新枝（`<NewFishkaInSteck>`） | 入口 x=799，上限 26 |
| `FUN_00490abc` | 传送带/弃枝区绘制（`lenta`） | 引用 `lenta` |
| `FUN_00499668` | 放置适配检查（格位/关节/透明枝） | 覆盖格列表、失败原因 |
| `FUN_0049f6f0` | 关节一致性检查（匹配/红灯绿灯） | 被 `FUN_00499668` 调用 |
| `FUN_00499e80` / `FUN_00499a28` | 屏幕坐标 → 棋盘格 | 用相机 `DAT_004badc8` |
| `FUN_00496f14` | 鼠标命中 Twig（状态 1/2/4） | 决定拾取 |
| `FUN_004a0538` | 计算“灯光格”（开放关节旁的空格）并返回参考格 | 写 `DAT_004bae38` |
| `FUN_004a0db8` / `FUN_004a0e4c` | PutAllow 检查（灯光格 / 匹配连接） | 被放置流程调用 |
| `FUN_004a24fc` | 禁放区域检查（`CanNotPutFishka`） | 引用字符串 |
| `FUN_004a1130` | **ClosedLink 判定**（是否有连通块被“锁死”） | 返回真 → 刷 `LHintClosedLink` |
| `FUN_004a1360` | “这一步能否直接过关”的判定（放行 ClosedLink） | 检查主连通块 1 与目标元素 |
| `FUN_0049fb7c` + `FUN_004a0484` | 连通块合并 / 分配新编号（最小未用正整数） | 放置流程 |
| `FUN_004a30c4` | 花瓶（Amphora/Clipper）点击：生成/剪断 | 引用 `ClipperFishkaNew` |
| `FUN_00498fb8`, `FUN_00499118`, `FUN_0049a030` | 移枝：传送带 / 场上 / 清空传送带 | 引用 `Error in TakeFishka`、`clearsteck` |
| `FUN_00484348` | 关卡开始（相机初值、进度条、WGame） | 写 `DAT_004badc8` |
| `FUN_0049a7e4` | 关卡解析/装载（`<Fishka>`、`<GhostFishka>`、`<Generator>`…） | 巨型函数 |
| `FUN_0049fd14` | 读取 `options.cfg` 的 `PutAllow`/`TakeAllow` | 字符串比较 |

Twig 记录（`DAT_004bae08`，每条 `0x38` 字节）：

| 偏移 | 含义 |
|---|---|
| `+0x00` | 形状编号（类型） |
| `+0x04` | x（屏幕/世界，见各状态） |
| `+0x08` | y |
| `+0x0C` | 连通块编号（-1 = 无） |
| `+0x10` | **状态**：1=场上, 2=传送带, 3=手持, 4=滑向弃枝区, 5=?, 6=透明目标(Ghost) |
| `+0x14` | 神秘枝（未揭示）=1 |
| `+0x15` | 幸运枝（带奖励）=1 |
| `+0x18` | 初始/不可操作标记 |
| `+0x28` | 锁定（顶部主干，不可砸/不可拿）=1 |
| `+0x20` | 动画/随机数 |

---

## 1. 交互逻辑总表（输入 → 条件 → 结果）

| # | 输入 | 前置条件 | 结果 | 证据 |
|---|---|---|---|---|
| 1 | 左键 | 光标为普通；鼠标在**玩法区** `Rect(0,0,600,500)`；手上有 Twig | 走**放置判定链**（§2），成功则落子 | `FUN_004971b8` |
| 2 | 左键 | 手上有 Twig；鼠标在**弃枝区** `Rect(600,400,800,500)` | Twig 进入弃枝传送带（§5） | `FUN_004971b8` + `PutFishkaInOtboynik` |
| 3 | 左键 | 手上有 Twig；点击其它位置 | 无效果（不会放回传送带） | `FUN_004971b8` |
| 4 | 左键 | 空手；点到状态 1/2/4 的 Twig（命中用其贴图格） | **拾起**该 Twig（§3） | `FUN_00496f14` + `FUN_004971b8` |
| 5 | 左键 | 空手；点击锤子图标（锤子数>0）/ 花瓶图标（花瓶数>0） | 选中工具，光标变为工具图标 | `FUN_004a2cd0` |
| 6 | 左键 | 工具已选中；点击 Twig | 锤子：砸掉；花瓶：生成/剪断（§6） | `FUN_004971b8`、`FUN_004a30c4` |
| 7 | 左键 | 点击 `BGenerateFishWGame`（箭头，768,506） | `RunMethod BGenerateFishWGameMouseUp` → **立即生成一根新枝** | `interface.json OnMouseUp` + demo |
| 8 | 右键 | 手上有 Twig | **旋转 90°**，并重新做适配预览 | `FUN_00499b84` / `FUN_00499cfc`，效果 `RotateFishka` |
| 9 | 右键 | 工具已选中 | 取消工具（恢复普通光标） | `FUN_004971b8` |
| 10 | 右键 | 其它 | 无效果 | — |
| 11 | 计时器 | 每 `Generator period` ms（关卡 `<Generator period>`；Easy×1.5） | 自动生成一根新枝（带上 <26 根时） | `FUN_0048b2d0` |
| 12 | 自动 | 任意放置成功 | 相机自动跟随（§7） | `FUN_004971b8` 写相机目标 |
| 13 | 自动 | 传送带塞满且僵持约 2 s | 弹出 `WGameOverDialog`（§4） | `FUN_0048b2d0` |
| 14 | 自动 | 全部连通 + 到达顶行 + 覆盖所有透明枝 | 过关动画 + `WFinishLevelDialog` | `FUN_004a1360`、`FUN_004a0538` 返回真 |

**没有**鼠标滚动/拖拽/滚轮/键盘移动视角 —— 相机完全自动（§7）。

---

## 2. 放置判定链（顺序即优先级）

对“手上的形状 + 鼠标对应格”依次检查，任一步失败即中止：

1. **形状适配** `FUN_00499668`
   - 形状覆盖的每个格子都必须在棋盘范围内（屏幕→格映射成功）。
   - 每个格必须为空（无场上枝）；若是**透明目标格**，该格的关节掩码必须与透明枝完全相同。
   - 与相邻已放置枝之间：**有关节指向对方时，对方的关节也必须指向自己**，否则失败（`FUN_0049f6f0`）。
   - 失败提示：透明枝不匹配 → `LHintTransparentTwig`；否则 `LHintMatchingJoints`。
2. **透明枝类型复核**：逐格复查同上。
3. **PutAllow 策略**（`options.cfg`，`FUN_004a0db8`/`FUN_004a0e4c`）
   - `paborderfish`(值 0)：放置必须覆盖至少一个“灯光格”（紧邻某个开放关节的空格，即必须接上图案）。
   - `paall`(1)：不检查。
   - `panearlight`(2)：覆盖灯光格，或与有匹配关节的邻居直接相连。
   - 出厂 `options.cfg` 写的是 `PutAllow=paBorder`，**与 exe 中比较的三个字符串都不相等**，因此实际取默认值 `0`（即必须接上图案）。
4. **禁放区域** `FUN_004a24fc`：落点不得与关卡中的禁放/事件矩形（`<Bomb>`/`<BonusElement>`/`<MakeGhostRect>` 一类）重叠 → 否则播放 `CanNotPutFishka` 并拒绝。
5. **ClosedLink 锁死判定** `FUN_004a1130`：
   - 放置并合并连通块之后，若**新连通块没有任何开放关节**（= 再也无法与其它枝连接），
     且场上还存在不属于主连通块（编号 1）的枝 → **拒绝**：提示 `LHintClosedLink`、回滚连通块编号、播放 `ClosedLink`。
   - 例外：`FUN_004a1360` 判定“放下这一步即可过关”时，放行。
   - 注意：**与成环无关**。原版允许各种形状的环、也允许贴着关卡自带的环继续建；
     只有“产生一个封闭死块”才报 ClosedLink。
6. 成功结算：
   - 合并连通块（`FUN_0049fb7c`，新编号取最小未用正整数 `FUN_004a0484`），连接主连通块时播 `ConnectLink`；
   - 每覆盖一格加该形状的 `FishkaScore`，刷新 `LScoreCountWGame`；
   - 覆盖到的透明枝（状态 6）被移除；
   - 幸运枝 → 按关卡概率取一个奖励（`FUN_004aa9e4`），播放 `PutBonusFishka`/`PutbonusFishka`；
   - 组合图案检测（`FishCombinations.dat`/`CombSequence`，`FUN_00498cc4`）；
   - 播放 `PutFishka`；相机目标更新（§7）。

---

## 3. 拾取（拿枝）规则

| Twig 状态 | 可否拾取 | 说明 |
|---|---|---|
| 2 传送带 | 是 | 从传送带列表移除，进入手持 |
| 4 滑向弃枝区 | 是 | 同时取消弃枝动画定时 |
| 1 场上 | **仅当 `TakeAllow=taborderfish`** | 且不能是初始/锁定枝（顶部主干 `+0x28`）。出厂 `TakeAllow=taDenied` → 场上枝拿不起来 |
| 6 透明目标 / 0 空 / 5 | 否 | 命中测试直接跳过 |

- 命中判定 `FUN_00496f14`：按形状覆盖格组成的矩形并集（神秘枝用其图标矩形）。
- 拾起后播放 `TakeFishka`；神秘枝额外播 `TakeQuestFishka` 并**揭示真实形状**（`+0x14` 清 0），首次给提示 `LHintFirstTakeQuestFishka`。
- 手持枝跟随鼠标，鼠标移动时持续做适配预览（`FUN_0048f704`）。
- 手上有枝时再点传送带不会换枝；也不会把枝放回传送带。

---

## 4. 传送带（Steck）

- **生成**（`FUN_0048c82c`）：
  - 自动：每 `_DAT_004bae48` ms（`<Generator period="...">`；Easy ×1.5）一根；
  - 箭头按钮：立即一根，并把下一次自动生成推迟一个周期（`demo.dat` 每次点击后约 100 ms 出现 `<NewFishkaInSteck>`）；
  - 上限：带上的枝数 `< 26`；
  - 新枝：x = **799**；y = `585 − 贴图高度`（底边对齐）；形状按关卡 `FishTypeSequence`/`FishkaProb` 分布随机；
    神秘枝概率 `_DAT_004bae84`、幸运枝概率 `_DAT_004bae8c`（关卡 XML）。
- **移动**（`FUN_0048bf78`）：
  - 每帧向左移 1 个 `delta` 单位；最左的枝到 `x ≤ 5` 停下；
  - 与前一枝间距 ≥ `前一枝宽 + 2 px` 才继续前移（落后多时该帧以 2 倍速“追赶”），因此队列左端紧密堆积、右侧稀疏；“宽”指上一条实际绘制表面的宽度，盲盒枝即图标宽度；
  - 全场约 25 px/s（`demo.dat`：10259 px / 409 s）。
- **绘制**（`FUN_00490abc`）：
  - 神秘枝（`+0x14`）改用 `HidenFishkaPicture` 图标表面绘制（否则用形状表面）；生成时 y = 585 − **所绘制表面**高度，所以盲盒枝按图标高度站立在传送带上；
  - 幸运枝（`+0x15`）以 **加法式黄色叠加**绘制，强度 = `Sin(GetTickCount/300 + 每枝随机相位) * 64 + 150`（周期 ≈1.9 s，范围 86…214），即传送带上的金色闪光；
  - 鼠标悬停的枝以白色、强度 200 高亮；
  - 传送带贴图从 x<0 平铺到屏幕右缘（整个 800 px 宽）。
- **失败判定**（`FUN_0048b2d0`）：
  带数 >5、第一根在 x=5、最后一根与前一根重叠（完全塞满）、本帧无任何枝移动、且 Time Control 无效；
  此状态持续约 **2 秒**（期间画 `ProgressOTT` 进度条）→ `WGameOverDialog`。

---

## 5. 弃枝区 DROP SECTION（反向传送带）

- 区域：面板 `Rect(600,400,800,500)`（在工具下方、传送带上方；`LDropSectionWGame` 标签在 607,430）。
- 手上有枝时点击该区域且当前没有正在滑落的枝、冷却已过：
  - 枝变为状态 4，坐标 x=615、y=`480 − 贴图高`；
  - 播放 `PutFishkaInOtboynik`；随后以 **2 倍传送带速度向右**移动，x ≥ 795 后删除；
  - 期间再点它可拿回（取消滑落）。
- 冷却由 **Drop Section Accelerator** 技能/奖励决定（`_DAT_004baeb4`）；
  加速器生效时（`DAT_004baebc` 未到期的倒计时）冷却缩短，并在 (606,388) 画 `DropAxelIcon.png`，HUD `LDropAccelCounWGame` 显示剩余秒数。

---

## 6. 工具

| 工具 | 选中 | 使用 | 限制 |
|---|---|---|---|
| 锤子 | 点图标（锤子数>0），或 `F3` | 点 Twig：移除 + `HammerFishka`+`HammerFishkaSound`，数量−1 | 初始枝、顶部主干锁定枝（`+0x18`/`+0x28`）、透明枝 → `UnableHammer`；可砸传送带上的枝 |
| 花瓶 | 点图标（花瓶数>0），或 `F4` | 点空格：按相邻开放关节生成所需形状（`FUN_00499aec`）+ `ClipperFishkaNew`，数量−1；点已有枝：剪掉，数量−1 | 同样受锁定/初始限制；生成也要过 ClosedLink（失败 → `LHintClosedLink` 并回滚） |
| 取消 | 右键（或再点图标） | 光标恢复普通 | — |

---

## 7. 相机

- **没有任何鼠标/键盘自由滚动**。相机只随建造自动移动。
- 视口高 500（`_DAT_004badc4` = 500，`_DAT_004badc0` = 0）。
- 范围：`cam ∈ [最上方初始枝的 y, 最下方初始枝的 y + 40 − 500]`
  （`DAT_004bae6c`、`DAT_004bae70` 由初始 `<Fishka>` 计算）。
- 关卡开始（`FUN_00484348`）：`cam = (最下方初始枝 y + 40) − 1000`，然后向目标平滑移动。
- **放置后的目标**：`target = 最低的“开放关节相邻格”的 y − 80`，夹在范围内；
  相机按梯形速度（加速到半程后减速）移动到 `target` 并停在原地。
  （效果：图案向上建时，视图在最低开放关节升过屏幕下方 80 px 后才跟着上移 → “自下而上跟随”。）
- 过关动画：`DAT_004baf64=1` 时相机以 ±2 速度在范围内往返，配合完成对话。

---

## 8. 进度 / 难度 / 奖励（与交互相关的部分）

- **Time Control**（`DAT_004baeb8` 截止时刻）：生效期间不判负，HUD `LLiveCountWGame` 显示剩余秒。
- **Drop Section Accelerator**（`DAT_004baebc` 截止时刻 + `_DAT_004baeb4` 间隔）：弃枝冷却缩短。
- **Good Luck**：提高幸运枝概率（生成时的概率乘 (1+luck/100)，见关卡数据）。
- **难度**：生成周期 Easy ×1.5；`DAT_004bafc1/c2` 为作弊/难度开关。
- **过关条件**（原版 `FUN_004a0538` 返回真）：所有枝同属一个连通块 **且不存在任何开放关节**
  （指向空格或未覆盖透明枝的关节都算开放）；**没有“到达顶行”这一独立条件** —— 图案顶部同样要闭合。
  最后一块封住网络时（同时满足连通+无开放关节）→ `WFinishLevelDialog`。
- **计分**：每覆盖格加 `FishkaScore[形状]`；组合另计。

---

## 9. 与原版的配置映射

| options.cfg | 取值 | 含义 |
|---|---|---|
| `PutAllow` | `paborderfish` (0) / `paall` (1) / `panearlight` (2) | 放置策略（见 §2.3） |
| `TakeAllow` | `tadenied` (0) / `taborderfish` (1) | 是否允许拿起场上枝 |

出厂 `options.cfg` 的 `paBorder` 与 exe 字符串不匹配，实际按 0（必须接上图案）运行。

---

## 10. 尚未完全解析 / 待验证

1. **花瓶生成形状的选择**（`FUN_00499aec` 的输入集合）——只确认“与相邻开放关节匹配”，具体取直/弯/三通的选择逻辑未完全展开。
2. **禁放区域的具体来源**（`FUN_004a24fc` 遍历的 `DAT_004bae34` 记录）——初步判断是关卡 XML 的 `<Bomb>`/`<BonusElement>`/`<MakeGhostRect>`。
3. **相机目标格排除集 `DAT_004bae7c`** 的具体含义（可能是被覆盖的透明枝）。
4. **`FUN_00499b84`/`FUN_00499cfc` 两个旋转变体的差异**（`DAT_004bade4` 的取值来源），行为上都是 90° 旋转。
5. 未分析区间 `0x49543b..0x496e00`（Ghidra 未建函数，含弃枝动画/生成按钮的实现），行为已由 `demo.dat` 与 `FUN_004971b8`/`FUN_0048bf78` 交叉确认。

---

## 11. remake 实现对照（2024-10 更新）

`remake/src/Main.gd` 已按本表重写，位置如下：

| 原始规则 | remake 实现 |
|---|---|
| 放置链（§2） | `can_place_shape` + `_joints_consistent` + `_put_allowed`/`_light_cells` + `_closes_link` |
| ClosedLink（原版图论规则） | `_closes_link`（连通块无开放关节且存在其它连通块 ⇒ 拒绝；`_level_complete` 放行） |
| 计分/透明枝/幸运枝/组合 | `_place`、`_check_combos`、`_give_bonus` |
| 拾取（§3） | `_pickup`（神秘枝拿取即揭示；TakeAllow=taDenied ⇒ 场上枝不可拿） |
| 传送带参数（§4） | `BELT_ENTRY=799`、`BELT_CAPACITY=26`、`BELT_GAP=2`、`_update_belt`/`_update_generator`；速度默认 2×（可通过 `--beltspeed=` 设回原版 25 px/s） |
| 堵塞判负 + 进度条 | `_update_overfull`（2 s）+ `_draw_belt` 中的 `ProgressOTT` |
| 弃枝区（§5） | `DROP_RECT`、`_drop_held`、`_update_drop_belt`（2×带速，x≥795 删除） |
| 工具（§6） | `_tool_icon_at`、`_use_hammer`、`_use_amphora`（初始/锁定枝不可操作） |
| 相机（§7） | `_camera_follow`/`_set_cam_target`/`_update_camera`（梯形跟随，无手动滚动；按原版 1 px/tick² 固定 180 tick/s 步进，起点视野 ~930 px 约 0.33 s 走完） |
| 鼠标指针 | `_sync_cursor`：原版 `MouseCursor.png` / `hammer1.png` / `cap1.png`，热区 (0,0)（原版把贴图左上角画在鼠标位置） |
| 过关/结束动画 | `_check_state`（`_level_complete`）+ `_process` 中的相机往返 |
| PutAllow/TakeAllow（§9） | `opt_put_allow`（从 `options.cfg` 读取） |
| 音效 | `_play_effect` 严格按 `EffectsType.dat` 的 `[PlaySound]`：`CombinationSound`→ClosedLink.wav、`PutFishkaInOtboynik`→GetFishka.wav、`UnableHammer`→GameOver.wav、幸运枝→`PutBonusFishka`(Link.wav)；`ConnectLink`/`ClosedLink`/`HammerFishka` 等无声；`BurnFishka.wav`、`Combination.wav` 未被任何效果引用 |
| BGM | `MENU_MUSIC`=`In the lost forest2.mo3`（WTitle / WBetweenLevelMenu）、`FINISH_MUSIC`=`Be happy!.mo3`（`WFinishLevelDialog`），关卡内播 `<PlayMusic>` |
| 多格枝 | 放置后按“一条枝记录”处理：`world.pieces` 保留整块美术、`_remove_fishka` 整块移除（`--piecetest`） |

验证：`--closetest`（用户截图的 Tutorial 会话 + 锁定环）、`--filltest=0`（逐格填满 Tutorial，
最终 `WFinishLevelDialog`）、`--piecetest`（多格枝整块保留 / 整块移除）、`--autotest` 烟雾测试、`--wintest`、`--testsound` 全部通过。

---

## 12. 修复补遗（2025-10，与原版逐条对照）

以下结论来自 Ghidra 12.1.4 对 `FiberTwig.exe` 的二次反编译（函数体见 `work/tools/decomp/`），
以及针对每个问题的回归测试。

| 问题 | 原版依据 | remake 实现 |
|---|---|---|
| 取回刚放置的枝 | `FUN_004971b8`：`DAT_004bae78` 保存最近放置的 twig 下标；空手点击它时即使 `TakeAllow=taDenied` 也能拿回（state 1→3），其它场上枝仍需 `DAT_004baded`；幸运枝在发放奖励前先清 `+0x15` 标志；`FUN_004aa5ac` 只重算连通块，不回退组合进度/已发奖励 | `last_placed` 快照 + `_take_back_last()`：恢复 cell/ghost/pieces/score 并把该枝放回手中（命中检测用屏幕坐标 + `cam_y`）；发放幸运奖励时把快照的 bonus 标志清 0，组合进度不回退，因此反复放置/回滚无法反复触发奖励；锤子/水壶/新放置会清除该状态 |
| 破碎特效（ClearSteck / 锤子） | `FUN_004aa9e4`：对带上每根枝先调 `HammerFishka` 特效再移除，最后一声 `HammerFishkaSound`；该特效是 `EffectsType.dat` 的 SparkCloneEffect（`star.png` 15 颗，重力 150，255→0 淡出约 1 s，4 帧每 100 ms） | `_spawn_hammer_sparks()`/`_update_sparks()`/`_draw_sparks()`；锤子与 `_give_bonus(1)` 均调用（ClearSteck 实现为逐枝生成火花再清带） |
| 获得锤子 / 双耳壶 / 分数的提示 | `FUN_004aa9e4` 在各奖励分支调用 `GiveHammer`/`GiveClipper`/`GiveScore`；EffectsType.dat：1 颗对应道具图（hammer1/cap1/ScoreStar.png）在鼠标位置（SparkSX/SY=%MouseCursor），重力 -30 上漂，255→0 淡出 2 s，SparkClipper 5 5 605 490，音效 GetFishka.wav | `_spawn_icon_spark()` 在 `_give_bonus` 0/2/3 分支生成单个 80×80 图标火花（位置=mouse_pos，grav=-30，life=2s，裁切到游戏区），音效走 `_play_effect` 的现有 GetFishka.wav 映射 |
| Next Level 技能提示 | 提示只在鼠标悬停对应增益时显示 | `_skill_hover()` 跟踪当前行：换行立即刷新提示、离开关闭；行区域改为各技能实际控件范围 (40,72/172/272/372/472,130×80) |
| 水壶虚影 | `FUN_004a30c4` 在鼠标格生成形状 | `_amphora_shape_at()` 供 `_use_amphora` 与 `_update_hover` 共用，工具选中时显示同款虚影预览 |
| DROP SECTION 冷却 + 反向传送带 | `FUN_00490abc`：第二条 `lenta` 画在 (610,482)，源区 `(0x3f-scroll, 0xf7-scroll)`（反向）；`FUN_0048bf78`/`FUN_0048b2d0`：`DAT_004b9790` 暂停、`DAT_004baf74` 为恢复期限 | 枝销毁（x≥795）后 `drop_cd=DROP_COOLDOWN`（加速器生效时为 0），期间 `drop_belt_offset` 冻结；`_draw_belt` 画反向条带 |
| ClosedLink 误报 | `FUN_004a1130` 只在“合并后的连通块无开放关节且存在其它连通块”时拒绝；`FUN_004971b8` 当**第一格是透明枝**或 `FUN_004a1360` 判定可完成时放行 | `_closes_link` 改为模拟放置 + `_connected_components()`/`_level_complete()`，并加入“首格为 ghost”例外；全部为 ghost 的放置跳过 PutAllow（原版 `local_29`）；提示按原版区分 `LHintMatchingJoints` / `LHintTransparentTwig` / `LHintClosedLink` |
| 枝接口/位置错误 | 原版从精灵边缘推导接口 | `LAYOUTS` 修正镜像的 `*_1a`（123_134→134_123、124_234→234_124）与 `Skoba1/2`（23_34 / 34_14）；新增 `--shapetest` 用像素连通度校验全部 14 个布局（0 failures） |
| 场景交互 | `FUN_0049a7e4` 解析 `<Point>`（state 5 隐形枝 + `border`）、`<Bomb>`；`FUN_004a1678` 在点接入主连通块后触发 `FUN_004a1f54/FUN_004a1e5c`（换图）、`FUN_004a22a0`（沿连接摧毁 r 层枝，ghost=true 转透明枝）、`FUN_004a2094`（picturebomb 按 r 移除砖块并画 `bombimage`）与 `StartEffect` 音效 | `BoardWorld.setup` 生成隐形 point 枝并参与连通；`_check_bonus_elements()`/`_activate_bonus()`/`_destroy_twigs_around()`/`world.bomb_bricks()` 实现全部效果 |
| 组合误判定 | `FUN_004aa128`：只检查 `DAT_004bae98` 指向的当前组合，且必须以刚放置的 twig 为锚点逐格比对 state-1 枝 | `combo_step` + `_matches_combo(c, placement)`：锚点必须是被放置格，point 隐形枝不参与；组合严格按 `CombSequence` 顺序完成 |
| New Game 从第 1 关开始 | `BNewWTitleMouseUp` 是唯一进入难度框的路径 | `new_game_pending` + `_reset_campaign()`；`_next_level()` 直接开始下一关，不再弹难度框；**载入存档也直接恢复（`start_level(..., false)`），不弹难度/初始增益框** |
| 传送带 / 弃枝区图层 | `FUN_00490abc` 将 twig 与 lenta 条带裁剪在 `0x31a`（794px）以内；游戏场景（传送带、弃枝枝）绘制在面板控件之后 | `BELT_CLIP`/`_draw_twig_clipped()` 裁剪 twig 与闪光；主 lenta 同原版画在 `(5,587)` 宽 789；`_draw_belt`/`_draw_sparks` 移到 `ui.draw_form("WGame")` 之后，弃枝区的 twig 现在盖住“丢弃区”字样 |
| 难度框只弹一次 | WTitle 的 `ShowModal WStartDialog` | 同上一行：只在 New Game 且确认后应用 |
| Demo 按钮 | `BDemoWLoad`：`RunMethod BDemoWTitleMouseUp` + `ChangeModal WGame` | `_start_demo()` 解析 `demo.dat`；`demo_mode` 下 `_update_game` 只走 `_demo_step`（回放事件），结束后 `_end_demo()` 回标题；修复了逐字符拼串导致的 O(n²) 卡死 |
| 主界面 realArcade 水印 | 非 Puzzle Lab 原版素材，为盗版发行商后加水印 | 用 OpenCV NS 修复去掉 `Title1.jpg` 右下角水印（其余游戏内图片经模板匹配确认无该标志） |

新增自测：`--fixtest`（回滚、弃枝冷却与传送带冻结/恢复、组合顺序、bonus 触发与换图、水壶预览）、
`--shapetest`（多格枝掩码与贴图边缘一致）、`--demo`（回放 `demo.dat`）。

性能：放置判定所需的连通块/开放关节/“下一格”数据由 `_rebuild_board_cache`
在棋盘变化时一次性重建，鼠标移动时的检查为 O(被触碰连通块的开放关节)，
不再每次全盘扫描。
