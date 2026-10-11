# Windows 本机运行说明

本目录是从 WSL (`\\wsl.localhost\Debian\home\nirvana\FiberTwig`) 拷贝到
`D:\Games\FiberTwig-remake` 的 Windows 工作副本，已在 Windows 上重建并验证。
最新一次同步：从 `gem:~/Documents/Games/FiberTwig/` 拉取（2026-10-10 晚间），
拉入 10 个更新文件 + 10 个新文件（2026-10-10 18:45 的玩法更新：相机逻辑、
传送带、多格枝整块绘制、ClosedLink 规则、`INTERACTION_LOGIC.md`、
`play.sh`、`assets/game*_belt.png` 等），本地的 Windows 专属文件全部保留。

## 已完成的 Windows 环境重建

| 项目 | 说明 |
|---|---|
| Godot | `tools\Godot_v4.7.2-stable_win64.exe`（编辑器/运行，180 MB）+ `..._console.exe`（CLI/headless 输出）。zip 安装包也保留在 `tools\` 下 |
| Python 虚拟环境 | `.venv\`（Windows 版，Python 3.14），已装 `Pillow 12.3.0`、`numpy 2.5.3` |
| 启动脚本 | 根目录 `start.cmd` |

`squares.zxc` 等原始资源、解密后的关卡、UI 数据都已随拷贝带上，无需重新解包。
Godot 首次运行会在 `remake\.godot\` 生成导入缓存（已加入 `.gitignore`）。

## 启动脚本用法

```bat
start.cmd                         :: 窗口模式运行游戏
start.cmd edit                    :: 用 Godot 编辑器打开项目
start.cmd level 6                 :: 直接运行第 6 关 (0..17)
start.cmd screen WLoad            :: 指定初始界面（WTitle/WLoad/WOptions/...）
start.cmd test                    :: 快速 headless 自检（wintest / testsound / langtest
                                  ::   / helptest / autotest=0 / closetest / piecetest / filltest=0）
start.cmd test all                :: headless 自动跑 0..17 关，检查 SCRIPT ERROR
start.cmd --headless -- --autotest=0 --complex
                                  :: 其余参数原样转交给 Godot
```

脚本会自动优先使用 `tools\` 下的 Godot，找不到时回退到 PATH 里的 `godot`；
检测到 `--headless` 时自动改用 `console.exe` 以保留命令行输出。

## 中文界面（简体中文）

游戏内置 6 种语言：英语、德语、法语、葡萄牙语、俄语，以及新增的
**简体中文**。切换方式：主菜单或游戏中 `Options`（选项）→ `Language`
（语言）→ 选择“简体中文”→ `OK`（确定），设置写入 `options.cfg`。
也可以在启动时指定语言（不修改 `options.cfg`）：

```bat
start.cmd -- --language=chs          :: 直接以简体中文启动
start.cmd screen WHelp -- --language=chs
```

全部界面文字、帮助页、关卡名称与提示均已汉化（`remake\assets\lng\chs_105.lng`，
UTF-8）。原版位图字体没有汉字，因此中文用随附的霞鹜文楷屏幕阅读版子集
（`remake\assets\fonts\LXGWWenKaiScreen-UI.ttf`，SIL OFL 1.1）绘制：楷体的笔锋
与原版手绘画面相配，14 px 下的字宽（汉字 14 px、拉丁 x 7 px、行框 17 px）与旧
字体完全一致，所以版面不变；中文按字符换行，并且不会把句号甩到下一行开头。
字体子集与翻译都可用 `tools\make_chs_lng.py` / `tools\make_chs_font.py` 重新生成
（改动任何文案后都要重跑字体脚本，否则新字会回退到系统字体）。

## Python 工具（可选）

原分析脚本 `tools\*.py` 需要 Pillow/numpy：

```bat
.venv\Scripts\python.exe tools\zxc.py --help
.venv\Scripts\python.exe -m pip install -r ...   :: 如需重装
```

与参考截图做像素对比（对应 SETUP.md §10 的流程）：

```bat
.venv\Scripts\python.exe -c "from PIL import Image; import numpy as np; a=np.array(Image.open('shot800.png').convert('RGB')).astype(int); b=np.array(Image.open('work/ref/Options.png').convert('RGB')).astype(int); d=np.abs(a-b); print('mean %.2f (%.2f%%), max %d' % (d.mean(), d.mean()/765*100, d.max()))"
```

## 验证结果（本机，Windows，同步自 gem 之后）

* `--wintest`：`WFinishLevelDialog`，1 个连通分量
* `--testsound`：16/16 WAV 加载成功
* `--langtest`：6 种语言全部加载，中文标题/换行/CJK 字体均通过（failures=0）
* `--helptest`：14 个帮助主题逐一切换页面全部通过（failures=0）
* `--closetest`：放置/锁定规则符合预期（闭合锁定环被拒绝）
* `--piecetest`：多格枝整块绘制、整块移除、辉光衰减全部通过
* `--filltest=0`：逐格填充后 `complete=true`，1 个连通分量，0 个开放关节
* `test all`：18 关全部无 `SCRIPT ERROR`（autotest 使用 `randi()`，
  每次运行的 cells/components 计数会不同，属正常）
* 窗口运行 15 秒：`OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility`，
  无错误输出

## 从 GitHub 克隆

仓库：`https://github.com/NIRVANA-APOC/FiberTwig`（私有），已推送分支 `main`。
`FiberTwig/fiber_twig` 是指向公共仓库 `NIRVANA-APOC/fiber_twig` 的 submodule（固定在 `master` 的 `039d5e5`）。

```bat
:: 本机用 SSH 别名 github:（~/.ssh/config）克隆
mkdir D:\Games && cd /d D:\Games
git clone --recursive github:NIRVANA-APOC/FiberTwig.git
:: 若 submodule 初始化失败（本机直连 github.com:443 受限制），用 SSH 重写 URL 重试：
cd FiberTwig && git -c url.github:NIRVANA-APOC/.insteadOf=https://github.com/NIRVANA-APOC/ submodule update --init
```
