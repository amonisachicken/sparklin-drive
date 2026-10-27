# 构建说明

## 你需要什么

| 依赖 | 版本 | 检查 | 装法 |
|---|---|---|---|
| Rust | stable，≥ 1.80 | `cargo --version` | https://rustup.rs |
| rust target | `aarch64-apple-darwin` + `x86_64-apple-darwin` | `rustup target list --installed` | `rustup target add aarch64-apple-darwin x86_64-apple-darwin` |
| Xcode 命令行工具 | — | `xcode-select -p` | `xcode-select --install` |
| cmake | ≥ 3.20 | `cmake --version` | `brew install cmake` |
| python3 | ≥ 3.11（要 `tomllib`） | `python3 -V` | 系统自带或 `brew install python` |
| **cargo-nih-plug** | rev `de42101` | `cargo --list \| grep nih-plug` | `cargo install --git https://github.com/robbert-vdh/nih-plug.git --rev de42101 cargo-nih-plug --locked` |
| 网络 | 首次需要 | — | 拉 rustomp 的 tag、nih-plug、打包用第三方源码；受限网络先 `source ~/vpn.env` |

**三个仓的版本要配套**（都在各自仓库里显式声明了）：

| 组件 | 版本写在哪 |
|---|---|
| 框架 `rustomp` | 本仓 `Cargo.toml` 的 `tag = "v0.1.0"` |
| 打包工具 `rustomp-mac-plugin` | 本仓 `rustomp.toml` 的 `[requires] packer_tag = "v0.1.5"` |
| `cargo-nih-plug` | 打包工具的 `deps.lock`（rev `de42101`） |

**依赖约定：三个仓放在同一个目录（本仓的同级）。** 脚本会自动找到它们，不需要设任何环境变量。

```text
some-dir/
  rustomp/                 ← 框架（读清单 / 校验生成物）
  rustomp-mac-plugin/      ← 打包工具（AU/VST3/CLAP）
  sparklin-drive/          ← 本仓
```

```bash
cd some-dir
git clone --depth 1 --branch v0.1.0 https://github.com/amonisachicken/rustomp.git
git clone https://github.com/amonisachicken/rustomp-mac-plugin.git
./rustomp-mac-plugin/scripts/fetch-third-party.sh     # 只需一次（约 12 MB）
cd sparklin-drive && ./scripts/build.sh
```

> 缺哪个仓、该在哪执行什么命令，`./scripts/build.sh doctor` 会直接打印出来
> （克隆命令里的 tag 自动取自本仓 `Cargo.toml`）。

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
| AU | `<同级目录>/rustomp-mac-plugin/build/au-<variant>/Sparklin Drive <Variant>.component` |
| VST3 | `./target/bundled/Sparklin Drive <Variant>.vst3` |
| CLAP | `./target/bundled/Sparklin Drive <Variant>.clap` |
| 安装位置 | `~/Library/Audio/Plug-Ins/{Components,VST3,CLAP}/` |

---

## 开发期想改框架代码

`Cargo.toml` 里框架依赖钉在 tag（`v0.1.0`），保证任何人 clone 下来都能复现。
你要一边改 rustomp 一边改插件时，用本地覆盖，不要改 `Cargo.toml`：

```bash
cp .cargo/config.toml.example .cargo/config.toml     # 把 git 依赖 [patch] 到 ../rustomp
#   前提：框架已经在本仓的同级目录（见"依赖约定"）
#   想指到别处就改 .cargo/config.toml 里的 path
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
| `找不到 macOS 打包工具` | 它要和本仓**同级**：`cd .. && git clone https://github.com/amonisachicken/rustomp-mac-plugin.git` |
| `找不到 rustomp 框架` | 同上，同级：`cd .. && git clone --depth 1 --branch <tag> https://github.com/amonisachicken/rustomp.git rustomp`（`<tag>` 见本仓 `Cargo.toml`）；`doctor` 会直接把这条命令打印出来 |
| 确实不想装框架（不推荐） | `RUSTOMP_SKIP_DRIFT_CHECK=1 ./scripts/build.sh` —— 会跳过"生成物是否过期"的守卫 |
| `cannot specify features for packages outside of workspace` | 插件被放进了别的 Rust 项目的目录树里（`cargo-nih-plug` 会向上找最顶层 `Cargo.toml`）；把本仓放在独立目录 |
| `生成物与 rustomp.toml 不一致` | 改了网表/参数却没重新生成 → 按上面第 2、3 步重跑 |
| `error: failed to load manifest … rustomp-dsp` | 网络问题（首次要拉 rustomp 的 tag）；`source ~/vpn.env` 后重试 |
| `no such command: nih-plug` | 没装 `cargo-nih-plug`（`doctor` 会给安装命令；注意 `--rev de42101`） |
| `requires.packer = >=0.1（当前 …）` 报错 | 打包工具版本太旧 → `git -C ../rustomp-mac-plugin checkout <packer_tag>` |
| Logic 里看不到 / 显示旧名字 | `../rustomp-mac-plugin/scripts/reset-logic-cache.sh`（先退出 Logic） |
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

---

## 别人怎么验证过

| 方式 | 说明 |
|---|---|
| **CI**（`.github/workflows/build.yml`） | 干净 macOS runner：三仓 checkout 到同一目录 → `doctor` → `test` → `build --no-install` → 抓 `ARTIFACT:` → 上传产物。**不设任何环境变量** |
| **隔离验证** | 在 rustomp 仓：`./scripts/verify-isolation.sh`（全新目录、钉 tag、跑真实构建、检查依赖全来自 git） |
| 本地一键 | `./scripts/build.sh doctor` 体检；`./scripts/build.sh test` 跑测试（不需要 ngspice） |

CI 的产物与本机产物做过对拍：`au_smoke` 的 RMS 都是 **0.356170**（逐位一致）。
