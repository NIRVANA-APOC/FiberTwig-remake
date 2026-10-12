#!/usr/bin/env bash
# Fiber Twig remake 启动脚本
#
# 用法:
#   ./play.sh                      正常窗口启动
#   ./play.sh --opengl3            使用 OpenGL3 渲染驱动（老显卡 / 驱动兼容模式）
#   ./play.sh --x11                强制 X11（Wayland 下走 XWayland）
#   ./play.sh --headless -- --autotest=0
#                                  透传引擎参数；`--` 之后是游戏参数
#   ./play.sh -- --screen=WGame --level=6
#
# 也可用环境变量指定引擎:  GODOT=/path/to/godot ./play.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/remake"

if [[ ! -f "$PROJECT/project.godot" ]]; then
    echo "play.sh: 找不到 Godot 项目: $PROJECT/project.godot" >&2
    exit 1
fi

find_engine() {
    if [[ -n "${GODOT:-}" ]]; then
        if [[ -x "$GODOT" ]]; then
            printf '%s\n' "$GODOT"
            return 0
        fi
        echo "play.sh: GODOT=$GODOT 不可执行" >&2
        return 1
    fi
    local c
    for c in \
        "$ROOT/tools/Godot_v4.7.2-stable_linux.x86_64" \
        "$(command -v godot4 2>/dev/null || true)" \
        "$(command -v godot 2>/dev/null || true)"; do
        if [[ -n "$c" && -x "$c" ]]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    return 1
}

ENGINE="$(find_engine)" || {
    echo "play.sh: 找不到 Godot 4 引擎。" >&2
    echo "  请放到 tools/，加入 PATH，或设置 GODOT=/path/to/godot。" >&2
    exit 1
}

ARGS=("--path" "$PROJECT")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --opengl3) ARGS+=("--rendering-driver" "opengl3"); shift ;;
        --x11)     ARGS+=("--display-driver" "x11");        shift ;;
        --)        shift; break ;;
        *)         break ;;
    esac
done

exec "$ENGINE" "${ARGS[@]}" "$@"
