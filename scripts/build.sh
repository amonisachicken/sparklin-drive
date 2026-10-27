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

# 依赖约定：三个仓放在**同一个目录**下（本仓的同级）
#
#   some-dir/
#     rustomp/                ← 框架
#     rustomp-mac-plugin/     ← 打包工具
#     sparklin-drive/         ← 本仓（你在跑的 build.sh 在这）
#
# 不假设任何绝对路径（每台机器不同）；两个环境变量只作显式覆盖用。
PACKER="${RUSTOMP_MAC_PLUGIN:-$ROOT/../rustomp-mac-plugin}"
FRAMEWORK="${RUSTOMP_ROOT:-$ROOT/../rustomp}"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# 插件钉的框架 tag（提示里用，随 Cargo.toml 自动变）
framework_tag() {
    grep -oE 'tag = "v[0-9]+\.[0-9]+\.[0-9]+"' "$ROOT/Cargo.toml" 2>/dev/null \
        | head -1 | sed 's/tag = "//; s/"$//'
}

framework_hint() {
    _tag="$(framework_tag)"
    _tag="${_tag:-v0.1.0}"
    _parent="$(dirname "$ROOT")"
    _me="$(basename "$ROOT")"
    cat >&2 <<EOT
  ✗ 找不到 rustomp 框架 —— 读 rustomp.toml、校验生成物都要用它

  约定：三个仓放在**同一个目录**下（本仓的同级）

    ${_parent}/
      rustomp/                 ← 缺这个
      rustomp-mac-plugin/
      ${_me}/    ← 你在这里

  在这个目录里执行（tag 与本仓 Cargo.toml 一致）：

    cd "${_parent}"
    git clone --depth 1 --branch ${_tag} https://github.com/amonisachicken/rustomp.git rustomp

  克隆完直接重跑 ./scripts/build.sh 即可，**不需要设任何环境变量**。

  仓库：https://github.com/amonisachicken/rustomp
EOT
}

locate_framework() {
    if [ -f "${FRAMEWORK}/tools/meta/plugin_meta.py" ]; then
        FRAMEWORK="$(cd "$FRAMEWORK" && pwd)"; return 0
    fi
    # 约定位置：本仓的同级目录
    if [ -f "$ROOT/../rustomp/tools/meta/plugin_meta.py" ]; then
        FRAMEWORK="$(cd "$ROOT/../rustomp" && pwd)"; return 0
    fi
    return 1
}

doctor() {
    say "依赖体检"
    # 先查框架：它是打包工具读清单的前提，缺了后面的报错会很晦涩
    if ! locate_framework; then
        framework_hint
        return 1
    fi
    printf '  ✓ 框架：%s\n' "$FRAMEWORK"
    if [ -x "${PACKER}/pack.sh" ]; then
        PLUGIN_DIR="$ROOT" "${PACKER}/pack.sh" --help >/dev/null 2>&1 || true
        "${PACKER}/scripts/doctor.sh" || die "打包工具体检未通过"
    else
        _parent="$(dirname "$ROOT")"
    _ptag="$(grep -oE 'packer_tag = "v[0-9.]+"' rustomp.toml 2>/dev/null | head -1 | sed 's/.*"v/v/; s/"$//')"
    cat >&2 <<EOT
  ✗ 找不到打包工具（${PACKER}/pack.sh）

  按约定，它和框架一起放在**本仓的同级目录**。依次执行：

    cd "${_parent}"
    git clone https://github.com/amonisachicken/rustomp-mac-plugin.git
    ${_ptag:+git -C rustomp-mac-plugin checkout ${_ptag}      # 钉到本版用过的 tag}
    ./rustomp-mac-plugin/scripts/fetch-third-party.sh        # 首次：拉 clap-wrapper 等（约 12 MB）

  然后重跑 ./scripts/build.sh，不需要设任何环境变量。

  仓库：https://github.com/amonisachicken/rustomp-mac-plugin
EOT
        return 1
    fi
}

# 生成物漂移：仓库里存着 generated/*.rs，改过网表就必须重新生成
check_generated() {
    # 显式跳过（不推荐）：没有框架时也能只打包，但生成物可能是旧的
    if [ "${RUSTOMP_SKIP_DRIFT_CHECK:-0}" = "1" ]; then
        warn "RUSTOMP_SKIP_DRIFT_CHECK=1：跳过生成物漂移校验（生成物可能已过期）"
        return 0
    fi
    if ! locate_framework; then
        framework_hint
        die "没有框架就无法校验生成物（这是防\"改了网表忘记重新生成\"的守卫）
      确实只想打包、不要守卫（不推荐）：RUSTOMP_SKIP_DRIFT_CHECK=1 ./scripts/build.sh"
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
