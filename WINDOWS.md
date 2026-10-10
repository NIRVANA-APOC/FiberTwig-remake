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
start.cmd test                    :: 快速 headless 自检（wintest / testsound / autotest=0
                                  ::   / closetest / piecetest / filltest=0）
start.cmd test all                :: headless 自动跑 0..17 关，检查 SCRIPT ERROR
start.cmd --headless -- --autotest=0 --complex
                                  :: 其余参数原样转交给 Godot
```

脚本会自动优先使用 `tools\` 下的 Godot，找不到时回退到 PATH 里的 `godot`；
检测到 `--headless` 时自动改用 `console.exe` 以保留命令行输出。

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
* `--closetest`：放置/锁定规则符合预期（闭合锁定环被拒绝）
* `--piecetest`：多格枝整块绘制、整块移除、辉光衰减全部通过
* `--filltest=0`：逐格填充后 `complete=true`，1 个连通分量，0 个开放关节
* `test all`：18 关全部无 `SCRIPT ERROR`（autotest 使用 `randi()`，
  每次运行的 cells/components 计数会不同，属正常）
* 窗口运行 15 秒：`OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility`，
  无错误输出
