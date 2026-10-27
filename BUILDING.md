# 构建说明

## 你需要什么

| 依赖 | 版本 | 检查 | 装法 |
|---|---|---|---|
| Rust | ≥ 1.80（含两个 target） | `cargo --version` | https://rustup.rs |
| rust target | `aarch64-apple-darwin` + `x86_64-apple-darwin` | `rustup target list --installed` | `rustup target add aarch64-apple-darwin x86_64-apple-darwin` |
| Xcode 命令行工具 | — | `xcode-select -p` | `xcode-select --install` |
| cmake | ≥ 3.20 | `cmake --version` | `brew install cmake` |
| python3 | ≥ 3.11 | `python3 -V` | 系统自带或 `brew install python` |
| 网络 | 首次需要 | — | 拉 rustomp / nih-plug / 打包用第三方源码 |

打包工具（**独立仓库**）：[rustomp-mac-plugin](https://github.com/amonisachicken/rustomp-mac-plugin)

```bash
git clone git@github.com:amonisachicken/rustomp-mac-plugin.git ~/develop/rustomp-mac-plugin
export RUSTOMP_MAC_PLUGIN=~/develop/rustomp-mac-plugin       # 建议写进 shell profile
~/develop/rustomp-mac-plugin/scripts/fetch-third-party.sh    # 只需一次（clap-wrapper / CLAP / AudioUnitSDK）
```

一条命令体检：

```bash
./scripts/build.sh doctor
```

---

## 构建

```bash
./scripts/build.sh                       # 默认：mono + stereo，AU/VST3/CLAP，并安装
./scripts/build.sh --variant stereo --format au        # 只出 stereo 的 AU
./scripts/build.sh --no-install          # 只要产物，不安装
```

它会依次做：

1. `doctor`（缺什么直接告诉你装什么）
2. **生成物漂移校验**（`rustomp-gen --check`）—— 改了网表/参数却没重新生成，这里就 fail
3. 调 `rustomp-mac-plugin/pack.sh`，结尾打印 `ARTIFACT:` 列表

产物位置：

| 格式 | 路径 |
|---|---|
| AU | `~/develop/rustomp-mac-plugin/build/au-<variant>/Sparklin Drive <Variant>.component` |
| VST3 | `./target/bundled/Sparklin Drive <Variant>.vst3` |
| CLAP | `./target/bundled/Sparklin Drive <Variant>.clap` |
| 安装位置 | `~/Library/Audio/Plug-Ins/{Components,VST3,CLAP}/` |

---

## 开发期想改框架代码

`Cargo.toml` 里框架依赖钉在 tag（`v0.1.0`），保证任何人 clone 下来都能复现。
你要一边改 rustomp 一边改插件时，用本地覆盖，不要改 `Cargo.toml`：

```bash
cp .cargo/config.toml.example .cargo/config.toml     # 把 git 依赖 [patch] 到 ../rustomp
```

`.cargo/config.toml` 已被 gitignore，不会误提交。

---

## 改了电路 / 参数表怎么办

```bash
# 1) 改网表或 rustomp.toml
# 2) 重新生成装配代码
cargo run --release --manifest-path ../rustomp/crates/rustomp-import/Cargo.toml -- \
    circuit/netlist/sparklin_drive_asym.cir --mna circuit/src/generated/asym.rs
# 3) 重新生成插件侧代码
cargo run --release --manifest-path ../rustomp/crates/rustomp-gen/Cargo.toml -- .
# 4) 校验 + 构建
./scripts/build.sh
```

> `--check` 只比对不写入；CI 用它防"忘了重新生成"。

---

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `找不到 macOS 打包工具` | 设 `RUSTOMP_MAC_PLUGIN`（见上）；或把 rustomp-mac-plugin clone 到 `~/develop/` |
| `cannot specify features for packages outside of workspace` | 插件被放进了别的 Rust 项目的目录树里（`cargo-nih-plug` 会向上找最顶层 `Cargo.toml`）；把本仓放在独立目录 |
| `生成物与 rustomp.toml 不一致` | 改了网表/参数却没重新生成 → 按上面第 2、3 步重跑 |
| `error: failed to load manifest … rustomp-dsp` | 网络问题（首次要拉 rustomp 的 tag）；`source ~/vpn.env` 后重试 |
| Logic 里看不到 / 显示旧名字 | `~/develop/rustomp-mac-plugin/scripts/reset-logic-cache.sh`（先退出 Logic） |
| 插件能扫到但没声音 | 确认用的是 **Mono** 或 **Stereo** 版本对应通道条；`check-au.sh` 会自检渲染 |
| 构建很慢 | 首次要编 nih-plug + egui（~3-5 分钟）；之后增量 |

---

## 平台支持

| 平台 | 状态 |
|---|---|
| macOS（AU/VST3/CLAP） | ✅ 本仓脚本支持 |
| Windows / Linux（VST3/CLAP） | 需要 `rustomp-win-plugin` / `rustomp-linux-plugin`（未开工，同一套契约） |
| standalone | 未支持（打包工具 v0.2 计划） |
| AAX | 不做（需要 Avid 授权） |
