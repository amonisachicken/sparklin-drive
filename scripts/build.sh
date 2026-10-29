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
# 支持 macOS / Windows（MSYS）/ Linux；打包交给**对应平台**的打包工具。
#
# 依赖（缺什么 doctor 会告诉你）：
#   - Rust + 平台工具链（macOS: Xcode CLT + cmake；Windows: MSVC；Linux: g++ + X11 开发库）
#   - rustomp-mac-plugin / rustomp-win-plugin / rustomp-linux-plugin（同级目录，按平台取用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 依赖约定：框架 + **本平台**的打包工具 + 本仓放在同一个目录下
#
#   some-dir/
#     rustomp/                    ← 框架
#     rustomp-<平台>-plugin/       ← 打包工具（mac / win / linux 三选一）
#     sparklin-drive/             ← 本仓（你在跑的 build.sh 在这）
#
# 不假设任何绝对路径；环境变量只作显式覆盖用。
_pick_packer() {
    case "$(uname -s)" in
        Darwin)                _platform=mac;   _repo=rustomp-mac-plugin;
                               _extra="./rustomp-mac-plugin/scripts/fetch-third-party.sh" ;;
        MINGW*|MSYS*|CYGWIN*)  _platform=win;   _repo=rustomp-win-plugin;
                               _extra="./rustomp-win-plugin/scripts/doctor.sh" ;;
        Linux)                 _platform=linux; _repo=rustomp-linux-plugin;
                               _extra="./rustomp-linux-plugin/scripts/fetch-third-party.sh --all" ;;
        *) printf '✗ 不支持的平台：%s（macOS / Windows / Linux）\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    _default_packer="$ROOT/../$_repo"
    if [ -n "${RUSTOMP_PACKER:-}" ]; then
        PACKER="$RUSTOMP_PACKER"
    else
        case "$_platform" in
            mac)   PACKER="${RUSTOMP_MAC_PLUGIN:-$_default_packer}" ;;
            win)   PACKER="${RUSTOMP_WIN_PLUGIN:-$_default_packer}" ;;
            linux) PACKER="${RUSTOMP_LINUX_PLUGIN:-$_default_packer}" ;;
        esac
    fi
}
_pick_packer
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
      rustomp/                  ← 缺这个
      rustomp-<平台>-plugin/     ← 本平台的打包工具（mac / win / linux）
      ${_me}/    ← 你在这里

  在这个目录里执行（tag 与本仓 Cargo.toml 一致）：

    cd "${_parent}"
    git clone --depth 1 --branch ${_tag} https://github.com/amonisachicken/rustomp.git rustomp

  克隆完直接重跑 ./scripts/build.sh 即可，**不需要设任何环境变量**。

  仓库：https://github.com/amonisachicken/rustomp
EOT
}

packer_tag_hint() {
    # 只有 macOS 的提示用 manifest 里的 packer_tag；win/linux 建议 checkout 各自最新 release tag
    if [ "$_platform" = "mac" ]; then
        _ptag="$(grep -oE 'packer_tag = "v[0-9.]+"' "$ROOT/rustomp.toml" 2>/dev/null             | head -1 | sed 's/.*"v/v/; s/"$//')"
        [ -n "$_ptag" ] && printf '    git -C %s checkout %s      # 本仓 rustomp.toml 的 packer_tag\n' "$_repo" "$_ptag"
    fi
}

packer_hint() {
    cat >&2 <<EOT
  ✗ 找不到 ${_platform} 打包工具（${PACKER}/pack.sh）

  按约定，它和框架一起放在**本仓的同级目录**。依次执行：

    cd "$(dirname "$ROOT")"
    git clone https://github.com/amonisachicken/${_repo}.git
$(packer_tag_hint)
    ${_extra}

  然后重跑 ./scripts/build.sh，不需要设任何环境变量。

  仓库：https://github.com/amonisachicken/${_repo}
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
    printf '  ✓ 平台：%s（打包工具：%s）\n' "$_platform" "$PACKER"
    if [ -x "${PACKER}/pack.sh" ]; then
        PLUGIN_DIR="$ROOT" "${PACKER}/pack.sh" --help >/dev/null 2>&1 || true
        "${PACKER}/scripts/doctor.sh" || die "打包工具体检未通过"
    else
        packer_hint
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
    _gen_manifest="${FRAMEWORK}/crates/rustomp-gen/Cargo.toml"
    # Windows 上 cargo 是原生程序：把 MSYS 路径转成 Windows 路径，避免 --manifest-path 解析失败
    [ "$_platform" = "win" ] && _gen_manifest="$(cygpath -w "$_gen_manifest")"
    cargo run -q --release --manifest-path "$_gen_manifest" -- "$ROOT" --check \
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
