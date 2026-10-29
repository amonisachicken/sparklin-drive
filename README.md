# Sparklin Drive

一款**电路级建模**的电吉他过载效果器插件（AU / VST3 / CLAP），用
[rustomp](https://github.com/amonisachicken/rustomp) 框架从**真实的模拟电路**算出来的音色。

> 这是"用 rustomp 做插件"的**参考实现**：电路网表、生成代码、面板产物、构建脚本全在仓库里。
> **它同时是模板** —— 想做一个自己的插件，看 **[MAKING-YOUR-OWN.md](MAKING-YOUR-OWN.md)**
> （改身份 / 电路 / 面板 / 参数表，四步 + 发布清单 + 6 条易踩的坑）。

```text
     电路（SPICE 网表）                面板（设计器导出）              插件
  ─────────────────────      ────────────────────────      ──────────────
  sparklin_drive_asym.cir  →  ui.toml + panel.png      →   AU / VST3 / CLAP
  sparklin_drive_sym.cir      （rustomp-box-designer）      宿主里能弹
        │
        └─ rustomp-import → MNA 装配器 → 4× 过采样 → 自适应牛顿迭代
```

---

## 依赖与获取方式（先读这段）

### 目录布局：框架 + 本平台打包工具 + 本仓

```text
some-dir/
  rustomp/                    ← 框架（读 rustomp.toml / 校验生成物）
  rustomp-mac-plugin/         ← macOS：AU/VST3/CLAP + DMG
  rustomp-win-plugin/         ← Windows：VST3/CLAP + MSI
  rustomp-linux-plugin/       ← Linux：VST3/CLAP + tar.gz
  sparklin-drive/             ← 本仓（你在这里）
```

按平台放一个打包工具即可（都放也行）；`scripts/build.sh` 会按 `uname` 自动选。
脚本按这个位置找依赖，**不需要设任何环境变量**。

### 一次装齐

```bash
mkdir -p ~/projects && cd ~/projects

# 框架（tag 见本仓 Cargo.toml 里 rustomp-dsp 的 tag = "..."）
git clone --depth 1 --branch v0.1.2 https://github.com/amonisachicken/rustomp.git

# 打包工具（按平台取一个；tag 见各仓 Releases）
git clone -b v0.1.7 https://github.com/amonisachicken/rustomp-mac-plugin.git     # macOS
git clone -b v0.3.0 https://github.com/amonisachicken/rustomp-win-plugin.git     # Windows
git clone -b v0.1.0 https://github.com/amonisachicken/rustomp-linux-plugin.git   # Linux

# 本仓
git clone https://github.com/amonisachicken/sparklin-drive.git
```

首次还要拉打包工具的第三方依赖：

```bash
./rustomp-mac-plugin/scripts/fetch-third-party.sh          # macOS
./rustomp-win-plugin/scripts/fetch-third-party.sh --all    # Windows
./rustomp-linux-plugin/scripts/fetch-third-party.sh --all  # Linux
```

### 系统依赖

**macOS**

| 依赖 | 为什么需要 | 检查 | 装法 |
|---|---|---|---|
| Rust（stable） | 编译插件 | `cargo --version` | https://rustup.rs |
| 两个 rust target | universal 二进制（Intel + Apple Silicon） | `rustup target list --installed` | `rustup target add aarch64-apple-darwin x86_64-apple-darwin` |
| Xcode 命令行工具 | 链接系统框架、`codesign`、`plutil` | `xcode-select -p` | `xcode-select --install` |
| cmake ≥ 3.20 | 把 CLAP 包成 AUv2（clap-wrapper） | `cmake --version` | `brew install cmake` |
| python3 ≥ 3.11 | 读 `rustomp.toml`（`tomllib`） | `python3 -V` | 系统自带，或 `brew install python` |

**Windows / Linux**：见各自打包工具的 README（Windows 需要 MSVC 工具链 + Python ≥3.11；
Linux 需要 g++、Python ≥3.11、X11 开发库）。两个平台都不需要 cmake。

**三平台都要**：`cargo-nih-plug`（`cargo install --git https://github.com/robbert-vdh/nih-plug.git
--rev de42101 cargo-nih-plug --locked`；rev 必须与打包工具的 `deps.lock` 一致）。

> 网络受限时先 `source ~/vpn.env`；打包工具也支持 `RUSTOMP_GIT_SSH=1` 把 https 重写成 SSH。

### 预编译包（技术预览）

不想自己编译可以直接下 **[Releases](https://github.com/amonisachicken/sparklin-drive/releases)**：

| 平台 | 资产 | 说明 |
|---|---|---|
| macOS | `.dmg` / `-macOS-plugins.zip` | universal；DMG 里双击 `安装.command` |
| Windows x64 | MSI（system / per-user）/ zip | 用户级免 UAC；系统级需管理员；**只装一种** |
| Linux x64 | `.tar.gz` | `install.sh`（用户级）或 `sudo ./install.sh --system` |

> **未签名**：macOS 可能被 Gatekeeper 拦、Windows 可能弹 SmartScreen；仅供测试。
> 正式分发需要 Developer ID/公证与 Authenticode。

### 自查

```bash
./scripts/build.sh doctor      # 缺什么、怎么装，一次说清（含克隆命令与正确的 tag）
```

---

## 快速开始（三平台）

依赖齐了之后，一条命令（`build.sh` 自动选本平台的打包工具）：

```bash
cd ~/projects/sparklin-drive
./scripts/build.sh
```

`build.sh` 会：体检 → 校验生成物没漂移 → 调打包工具 → 安装到用户插件目录 → 打印 `ARTIFACT:` 列表。

| 平台 | 装到哪 | 额外产物 |
|---|---|---|
| macOS | `~/Library/Audio/Plug-Ins/` | `--format dmg` → `<Name> Installer.dmg` |
| Windows | `%LOCALAPPDATA%\Programs\Common\` | `--format msi` → 系统级 / 用户级两个 MSI |
| Linux | `~/.vst3` / `~/.clap` | `--format targz` → 可复现 tar.gz |

装完在宿主里能看到 **Sparklin Drive Mono** 与 **Sparklin Drive Stereo**（两个独立身份）。

```bash
./scripts/build.sh doctor     # 只体检
./scripts/build.sh test       # 只跑测试（不需要 ngspice）
./scripts/build.sh verify     # 需要 ngspice：整机对拍
./scripts/build.sh --no-install --format targz   # Linux：只出分发包
```

> 缺依赖时它不会让你猜 —— 直接打印"在哪个目录、敲什么命令"。
> 详细步骤、产物路径与故障排查见 **[BUILDING.md](BUILDING.md)**。

---

## 这不是"贴模拟味的建模"，是算电路

| 层 | 内容 |
|---|---|
| **器件模型** | 14 个型号闭集（`1N4148` `1N34A` `1N4007` `1N5817` 红/绿/蓝 LED、`BC549C` `BC559C` `AC127` `AC128` `J201` `2N7000` `OP07`），参数与 SPICE 对齐，逐点与 ngspice 对拍 |
| **电路** | 双运放 clipper：输入缓冲 → 非反相增益级（P1 250k + R5 4.7k）→ 二极管环形钳位 → 音量 |
| **开关** | `Clip Mode` 不是"切换拓扑"，而是**两份完整网表**（非对称 / 对称），切换时交叉淡化 |
| **实时** | MNA 装配 + 4× 过采样 + 自适应牛顿迭代（上限 8、残差 1e-6 提前退出） |
| **验收** | THD @0.2 V：ngspice **27.5682%** / 本实现 **27.579%** |

电路源码就在仓库里，`ngspice` 可以直接跑（见 `circuit/netlist/`）。

---

## 仓库结构

```text
rustomp.toml             插件清单：身份 / AU 码 / 参数表 / 素材 / 面板（[assets]+[ui] 由设计器生成）
Cargo.toml               自己的 workspace（framework 依赖钉在 rustomp 的 tag 上）
circuit/
  netlist/*.cir          电路"源码"（ngspice 可直接跑）
  src/generated/*.rs     由网表生成的装配代码（入库 + --check 防漂移）
  tests/engine.rs        电路行为测试（THD / 偶次 / 旁通 / 活动量）
plugin/
  src/editor.rs          手写界面层（~90 行：创建 egui 编辑器）
  src/generated/*.rs     身份 / 参数表 / Plugin 实现 / 面板声明 / 参数桥 / 素材字节
assets/                  面板底图 + 控件贴图（设计器导出，12 px/mm）
design/panel.box.json    设计器源文件（可回设计器继续改）
scripts/build.sh         一键构建入口（doctor / build / test / verify）
BUILDING.md              依赖清单、分步安装、产物位置、故障排查
MAKING-YOUR-OWN.md       拿它当模板：改身份/电路/面板的四步清单
```

---

## 面板从哪来

面板由 [rustomp-box-designer](https://github.com/amonisachicken/rustomp-box-designer) 画，
导出 `ui.toml` 的标记块 + 素材 PNG；本仓的 `assets/` 与 `rustomp.toml` 的 `[assets]/[ui]` 就是它的产物。
想改面板：打开 `design/panel.box.json` → 改 → 导出素材包 → 覆盖 `assets/`、替换 `[ui]` 段 → `./scripts/build.sh`。

---

## 用它做你自己的插件

```bash
git clone git@github.com:amonisachicken/sparklin-drive.git my-drive
cd my-drive && ./scripts/build.sh          # 先确认原样能跑通
```

然后按 **[MAKING-YOUR-OWN.md](MAKING-YOUR-OWN.md)** 改：身份（`rustomp.toml`）→ 电路（网表）→
面板（设计器导出）→ 参数表。里面有发布前检查清单，以及"AU 码发布后不可改"这类容易吃亏的地方。

---

## 与 `sparklin-drive-legacy` 的关系

| | 本仓（v2） | legacy |
|---|---|---|
| 引擎 | rustomp MNA（通用装配器） | 手推 WDF（一次性实现） |
| 电路来源 | 网表 → 代码生成 | 手写 Rust |
| 状态 | **活跃** | 冻结归档（保留作 AB 基线） |

两者音色做过 AB，主观"A/B 无可感差别"；客观 THD 差 **0.08 pp**（27.579% vs 27.650%）。

---

## 许可证

- 代码：**GPL-3.0-or-later**
- 面板美术（手写 logo / 字标）：同 GPL-3.0-or-later（如需单独授权请联系）
- 依赖：rustomp（GPL-3.0）、nih-plug（ISC）、egui（MIT/Apache-2.0）
