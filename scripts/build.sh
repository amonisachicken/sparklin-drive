#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Sparklin Drive 的**一键构建入口**。
#
#   ./scripts/build.sh            # 体检 → 校验生成物 → 打包（mono+stereo）→ 安装 → 打印 ARTIFACT
#   ./scripts/build.sh doctor     # 只体检
#   ./scripts/build.sh test       # 只跑测试（不需要 ngspice）
#   ./scripts/build.sh verify     # 需要 ngspice：整机对拍
#   ./scripts/build.sh --format au --variant stereo   # 透传给打包工具
#
# 依赖（缺什么 doctor 会告诉你）：
#   - Rust（含 aarch64/x86_64-apple-darwin 两个 target）
#   - Xcode 命令行工具 + cmake
#   - rustomp-mac-plugin（打包工具，https://github.com/amonisachicken/rustomp-mac-plugin）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKER="${RUSTOMP_MAC_PLUGIN:-$HOME/develop/rustomp-mac-plugin}"
FRAMEWORK="${RUSTOMP_ROOT:-$ROOT/../rustomp}"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

locate_framework() {
    if [ -f "${FRAMEWORK}/tools/meta/plugin_meta.py" ]; then return 0; fi
    for cand in "$HOME/develop/rustomp" "$ROOT/../rustomp"; do
        if [ -f "${cand}/tools/meta/plugin_meta.py" ]; then FRAMEWORK="$(cd "$cand" && pwd)"; return 0; fi
    done
    return 1
}

doctor() {
    say "依赖体检"
    if [ -x "${PACKER}/pack.sh" ]; then
        PLUGIN_DIR="$ROOT" "${PACKER}/pack.sh" --help >/dev/null 2>&1 || true
        "${PACKER}/scripts/doctor.sh" || die "打包工具体检未通过"
    else
        cat >&2 <<EOT
  ✗ 找不到打包工具（${PACKER}/pack.sh）

  打包在独立仓库里，装一次即可：
    git clone git@github.com:amonisachicken/rustomp-mac-plugin.git ~/develop/rustomp-mac-plugin
    export RUSTOMP_MAC_PLUGIN=~/develop/rustomp-mac-plugin

  首次还要拉打包用的第三方源码：
    ~/develop/rustomp-mac-plugin/scripts/fetch-third-party.sh
EOT
        return 1
    fi
    if locate_framework; then
        printf '  ✓ 框架：%s\n' "$FRAMEWORK"
    else
        warn "没找到 rustomp 框架（只影响生成物漂移校验，不影响打包）"
    fi
}

# 生成物漂移：仓库里存着 generated/*.rs，改过网表就必须重新生成
check_generated() {
    if ! locate_framework; then
        warn "跳过生成物校验（没有框架；设 RUSTOMP_ROOT 后启用）"
        return 0
    fi
    say "校验生成物（rustomp-gen --check）"
    cargo run -q --release --manifest-path "${FRAMEWORK}/crates/rustomp-gen/Cargo.toml" -- "$ROOT" --check \
        || die "生成物与 rustomp.toml / 网表不一致：重新生成后再提交
       cargo run --manifest-path ${FRAMEWORK}/crates/rustomp-gen/Cargo.toml -- $ROOT
       （电路侧）${FRAMEWORK}/scripts/make-netlist.sh $ROOT/circuit/netlist"
}

# 无子命令（或以 - 开头）时按 build 处理，参数透传给打包工具
if [ $# -eq 0 ]; then set -- build; fi
case "$1" in
    -*) set -- build "$@" ;;
esac

case "${1:-build}" in
    doctor) doctor ;;
    test)
        # 测试也要先校验生成物：本地改完 toml/网表忘了重新生成，测试是绿的但发布出去是旧的
        check_generated
        say "测试（不需要 ngspice）"
        cargo test --release
        ;;
    verify)
        if ! locate_framework; then die "verify 需要 rustomp 框架（RUSTOMP_ROOT=…）"; fi
        say "整机对拍（需要 ngspice）"
        cargo test --release -- --nocapture
        "${FRAMEWORK}/scripts/verify.sh" --only oracle || die "对拍未通过"
        ;;
    build|"")
        shift || true
        doctor
        check_generated
        say "打包"
        export PLUGIN_DIR="$ROOT"
        export RUSTOMP_ROOT="$(cd "$FRAMEWORK" 2>/dev/null && pwd || echo "$FRAMEWORK")"
        exec "${PACKER}/pack.sh" "$ROOT" "$@"
        ;;
    *) die "未知子命令：$1（doctor | test | verify | build）" ;;
esac
