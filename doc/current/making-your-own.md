# 用它做你自己的单块

> 现状文档。本文是**动手清单**，尽量按顺序做；环境出问题看 [`build.md`](build.md)。

本仓**就是模板**：它是"用 rustomp 做一个插件"的完整样本 —— 电路网表、生成代码、面板产物、
构建脚本、CI 都在。换掉电路和面板，就是另一台机器。

下面按"动手顺序"给出清单。全程只有 4 个地方要改：**身份 / 电路 / 面板 / 参数表**。

> 下面的 tag 只是示例，以本仓当前声明为准：框架 tag 看 `Cargo.toml` 的 `tag = "…"`，
> 打包器 tag 看 `rustomp.toml` 的 `[requires] packer_tag`。

---

## 0. 先跑通再改（强烈建议）

```bash
# 框架 + 本平台打包工具 + 本仓放同一个目录
mkdir -p ~/projects && cd ~/projects
git clone --depth 1 --branch v0.1.2 https://github.com/amonisachicken/rustomp.git
git clone -b v0.1.7 https://github.com/amonisachicken/rustomp-mac-plugin.git   # macOS
./rustomp-mac-plugin/scripts/fetch-third-party.sh      # 首次：clap-wrapper / CLAP / AudioUnitSDK（约 12 MB）
git clone https://github.com/amonisachicken/sparklin-drive.git my-drive
cd my-drive

./scripts/build.sh doctor             # 体检：缺什么、怎么装，一次说清
./scripts/build.sh                    # 确认原样能出插件（约 3–5 分钟，首次要编 nih-plug + egui）
```

> 缺依赖时 `build.sh` 会直接告诉你"在哪个目录、敲什么命令"（克隆命令里的 tag 自动取自本仓
> `Cargo.toml` / `rustomp.toml`，不会过期）。

能跑通说明工具链、打包工具、框架都对。**先别改任何东西** —— 出问题时你才知道是"环境"还是"我的改动"。

---

## 1. 改身份（`rustomp.toml`）

```toml
[plugin]
package = "my-drive"                     # cargo 包名：小写短横线
name = "My Drive"                        # 宿主里显示的名字
vendor = "YOUR VENDOR"
url = "https://github.com/you/my-drive"
clap_id = "com.yourvendor.my_drive"      # 变体会追加 .mono / .stereo
vst3_class_id = "MyDriveXXXXXXXXV01"     # 恰好 16 字节
vst3_class_id_mono = "MyDriveXXXXXM01"
vst3_class_id_stereo = "MyDriveXXXXXS01"

[au]
manufacturer_code = "YrVd"               # AU 四字符制造商码（自己定一个）
manufacturer_name = "YOUR VENDOR"
bundle_id = "com.yourvendor.my_drive"
subtype_dual = "Md01"                    # 三个 subtype 必须互不相同
subtype_mono = "Md02"
subtype_stereo = "Md03"
```

> ⚠️ **这些码发布后不可改**。宿主按 `(manufacturer, subtype)` 认插件；改了等于换了一个插件
> —— 用户的自动化会话、Logic 的插入记录全部失效。**在第一次发布前就定好**。

还有 `[requires]`（跨仓版本约束，`build.sh` / `pack.sh` 启动时校验）：

```toml
[requires]
framework  = ">=0.1,<0.2"     # 你 fork 时用的框架版本范围
packer     = ">=0.1"
packer_tag = "v0.1.7"         # 本版用过的打包工具 tag（"缺依赖"提示里会引用它）
designer   = ">=0.1"
```

同时改 cargo 包名（两处）：

```bash
# plugin/Cargo.toml： name / [lib] name
# circuit/Cargo.toml：name（plugin/Cargo.toml 里的路径依赖也要跟着改）
```

---

## 2. 换电路

### 2.1 写网表

`circuit/netlist/*.cir` 是**唯一事实来源**（SPICE 网表，ngspice 可以直接跑）。
要求（见 rustomp 的 `docs/circuit-import.md` §10）：

| 要求 | 说明 |
|---|---|
| 端口显式标注 | `* @rustomp in=<node> out=<node>`，绝不猜"哪个是输出" |
| 可调元件显式声明 | `* @rustomp param=P1 pos=<node>`，不从 `250k+250k` 反推电位器 |
| 型号落在闭集表 | `1N4148 1N34A 1N4007 1N5817 LedRed LedGreen LedBLUE BC549C BC559C AC127 AC128 J201 2N7000 OP07A` |
| 迭代次数够 | `* @rustomp newton=8`（少了会进次谐波极限环，方波才看得出来） |

**开关 = 两份完整网表**（不是"切换拓扑"）：本仓的 `Clip Mode` 就是 `asym` / `sym` 两份。

### 2.2 生成 + 验收

```bash
# 网表 → 装配代码
cargo run --release --manifest-path ../rustomp/crates/rustomp-import/Cargo.toml -- \
    circuit/netlist/my_circuit.cir --mna circuit/src/generated/my_circuit.rs

# 插件侧代码（身份 / 参数表 / 面板 / 参数桥 / 素材字节）
cargo run --release --manifest-path ../rustomp/crates/rustomp-gen/Cargo.toml -- .

./scripts/build.sh test        # 电路测试（不需要 ngspice）
./scripts/build.sh verify      # 与 ngspice 对拍（需要 ngspice）
```

`circuit/tests/engine.rs` 里的基线数字（THD / 偶次 / 旁通）要按你的电路重设 ——
**它们是回归基线，不是装饰**。

---

## 3. 换面板

1. 打开 [rustomp-box-designer](https://github.com/amonisachicken/rustomp-box-designer)，载入
   `design/panel.box.json`（或新建）
2. 画好 → 导出**素材包（zip）**
3. 把 PNG 覆盖到 `assets/`，把 `ui.toml` 的标记块替换掉 `rustomp.toml` 的 `[assets]`+`[ui]`
4. 新的 `panel.box.json` 放回 `design/`（保留可追溯）

```bash
./scripts/build.sh
```

约定（设计器已内置）：坐标是**毫米浮点**、素材 **12 px/mm**、旋钮行程 270°（指针朝上 ⇔ 0.5）。

---

## 4. 改参数表

`rustomp.toml` 的 `[[params]]` 决定插件在宿主里的参数。类型必须与控件匹配：

| 控件 | 允许的参数类型 |
|---|---|
| 旋钮 | `float` |
| 拨杆 / 脚踏 | `bool` |
| LED | `indicator`（虚拟，读引擎活动量） |

改完**一定要重新生成**（`build.sh` 会用 `--check` 拦住忘记的情况）。

---

## 5. 发布前检查清单

- [ ] `./scripts/build.sh` 全新 clone 能跑通（CI 已经是这么做的）
- [ ] `./scripts/build.sh test` 全绿；`verify` 与 ngspice 在可接受偏差内
- [ ] 插件名 / AU 码 / VST3 id / bundle id **已定稿**（发布后不可改）
- [ ] `LICENSE` 明确（本仓是 GPL-3.0；链接 rustomp 决定）
- [ ] 美术素材的授权写清（自有作品建议显式注明许可）
- [ ] `README.md` 里"这是什么 / 怎么装 / 已知限制"能看懂
- [ ] 打 tag（`v0.1.0`）并把 CI 产物挂到 Release
- [ ] **CI 改指向你自己的仓库**：`.github/workflows/build.yml` 里三处 `repository:` /
      `path:` 是 amonisachicken 的仓；fork 后要么改成你的 fork，要么保留指向上游
      （框架与打包工具本身不需要 fork，直接依赖上游 tag 即可）
- [ ] `rustomp.toml` 的 `[requires]` 三个字段与实际用的 tag 对得上
- [ ] 签名：目前打包工具只做 **ad-hoc 签名**；对外分发需要 Apple Developer ID + 公证

---

## 6. 易踩的坑

| 坑 | 说明 |
|---|---|
| 插件项目放进别的 Rust 项目目录里 | `cargo-nih-plug` 会向上找**最顶层** `Cargo.toml` 当 workspace 根 → `packages outside of workspace`。放在独立目录 |
| 改了网表没重新生成 | `build.sh` 的 `--check` 会 fail（这是故意的） |
| mono / stereo 想要"一个插件同时支持" | 别这么做：宿主识别不可靠。本仓按 ADR-008 出**两个独立身份** |
| 发布后才想改 AU subtype | 等于换插件：老工程全部失效 |
| Logic 里看不到 / 显示旧名字 | `rustomp-mac-plugin/scripts/reset-logic-cache.sh`（先退出 Logic） |
| 想要 standalone | 未支持（三平台的打包器都明确不做） |
| 想发 Windows / Linux 版 | 用 `rustomp-win-plugin` / `rustomp-linux-plugin`（已落地，同一套 `ARTIFACT:` 契约；`build.sh` 会自动分派） |
| 三个仓版本不配套 | 框架 tag 在 `Cargo.toml`、打包工具 tag 在 `[requires] packer_tag`、`cargo-nih-plug` rev 在打包工具 `deps.lock` —— 三处要能对上 |
| 忘了 `fetch-third-party.sh` | 首次构建前必须跑（约 12 MB）；否则 AUv2 的 CMake 会找不到 clap-wrapper |

---

## 7. 还需要读什么

| 文档 | 位置 |
|---|---|
| 生态与仓库边界、三个跨仓契约 | `rustomp/docs/ecosystem.md` |
| 电路导入与网表指令 | `rustomp/docs/circuit-import.md` |
| 器件库与精度档位 | `rustomp/docs/component-library.md` |
| 面板契约（`[ui]` 每个字段） | `rustomp-box-designer/docs/01-contract-panel-toml.md` |
| 导出→装进插件的 6 步 | `rustomp-box-designer/docs/06-export-runbook.md` |
| 构建故障排查 | 本仓 [`build.md`](build.md) |
