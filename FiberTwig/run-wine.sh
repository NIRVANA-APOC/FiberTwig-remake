#!/usr/bin/env bash
# 用 Wine 运行 Fiber Twig（需在游戏目录下运行，游戏会读写这里的 temp/、saves/、options.cfg）
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec wine FiberTwig.exe "$@"
