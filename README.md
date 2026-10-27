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

## 快速开始（macOS）

```bash
git clone git@github.com:amonisachicken/sparklin-drive.git
cd sparklin-drive
./scripts/build.sh
```

`build.sh` 会：体检 → 校验生成物没漂移 → 调打包工具 → 安装到 `~/Library/Audio/Plug-Ins/` → 打印 `ARTIFACT:` 列表。
装完在 Logic / 任何 AU·VST3·CLAP 宿主里就能看到 **Sparklin Drive Mono** 与 **Sparklin Drive Stereo**（两个独立身份）。

> 第一次跑之前需要两样东西（`./scripts/build.sh doctor` 会告诉你缺什么）：
> Rust + Xcode 命令行工具 + cmake，以及打包工具
> [rustomp-mac-plugin](https://github.com/amonisachicken/rustomp-mac-plugin)。
> 详细步骤与故障排查见 **[BUILDING.md](BUILDING.md)**。

```bash
./scripts/build.sh doctor     # 只体检
./scripts/build.sh test       # 只跑测试（不需要 ngspice）
./scripts/build.sh verify     # 需要 ngspice：整机对拍
```

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
scripts/build.sh         一键构建入口
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
