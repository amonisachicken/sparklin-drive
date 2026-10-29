# 电路与实现

> 现状文档（随代码更新）。想知道"它为什么这么响"看这里；
> 想动手构建看 [`build.md`](build.md)，想改着做自己的看 [`making-your-own.md`](making-your-own.md)。

---

## 1. 电路

单电源 9V、OP07 运放、**反馈环内二极管钳位**的过载：

```text
IN ─C1─► IN+ ─ OP07 ─ OUT ─C3─► LEVEL ─► 出
          │      │
   R5+C2 ─┴      └─► GAIN（250k 电位器，可变电阻接法）
          │
         IN- ◄── 削波环：D1(1 只) ∥ (D2 + D3 反向串联)
```

| 部件 | 值 | 作用 |
|---|---|---|
| `XU1` | OP07A | 唯一的放大器件，反馈环里完成削波 |
| `P1` / `RP1A+RP1B` | 250k + 近端 4.7k（`RR5`） | GAIN，参数化时按抽头位置展开成两段电阻（拆成 500k 两半） |
| `D1 / D2 / D3` | 1N4148 | 削波环。**非对称档** 3 只全部参与；**对称档** 用 ≤0.01 Ω 的"导线"短接 D3，只剩 D1 ∥ D2 反串 |
| `P2` | 250k | LEVEL，两端电阻一段正接一段反接（`invert`），保证旋到底是真的 0 |
| `C1 / C2 / C3` | 4.7n / 47n / 1u | 输入耦合、增益级低通、输出耦合 |

### 两个分支 = 两份完整网表

`Clip Mode` 不是"运行时切换拓扑"，而是**两份独立的 SPICE 网表**：

| 文件 | 档位 | 谐波结构 |
|---|---|---|
| `circuit/netlist/sparklin_drive_asym.cir` | 上（默认，原机接法） | 奇次 + 偶次；2 次谐波 ≈ 3.9 %，暖、有肉 |
| `circuit/netlist/sparklin_drive_sym.cir` | 下 | 偶次被抑制到 < 0.2 %，只剩奇次；收紧、整齐 |

引擎里两套 `Circuit` 用 `Branch<Asym, Sym>` 组合，切换时**交叉淡化**（≈5 ms），
电路在后台持续运行 —— 所以换档不会有台阶或咔哒（`circuit/tests/engine.rs::switching_is_smooth` 守着这条）。

### 网表是唯一事实来源

`circuit/netlist/*.cir` 可以直接丢给 `ngspice` 跑。带 `@rustomp` 指令标注端口与电位器：

```spice
* @rustomp in=VS1 out=n_t27R newton=8
* @rustomp activity_i=50u
* @rustomp param RP1A gain pot max=500k
* @rustomp param RP2A level pot max=500k
* @rustomp param RP2B level pot max=500k invert
```

`rustomp-import --mna` 把它转成 `circuit/src/generated/{asym,sym}.rs`（入库 + `--check` 防漂移）。
网表改了却没重新生成，`./scripts/build.sh` 会直接 fail —— 这是故意的。

---

## 2. 器件模型

14 个型号的闭集，参数与 SPICE 对齐，逐型号与 ngspice 对拍
（精度规范见 rustomp 的 `docs/component-library.md`）：

| 类别 | 型号 |
|---|---|
| 二极管 ×4 | `1N4148` `1N34A` `1N4007` `1N5817` |
| LED ×3 | `LedRed` `LedGreen` `LedBLUE` |
| BJT ×4 | `BC549C` `BC559C` `AC127` `AC128` |
| JFET / MOSFET | `J201` / `2N7000` |
| 运放 | `OP07A`（含完整子电路：输入级、增益级、输出限幅） |

本插件实际用到的是 `1N4148` ×3 与 `OP07A`；其余型号在框架里，供你做别的单块时取用。

---

## 3. 实时路径

| 机制 | 参数 | 为什么 |
|---|---|---|
| MNA 装配 | 任意拓扑，牛顿求解 | 通用装配器，换电路不用改求解代码 |
| 过采样 | 默认 4×，可 2× | 48 kHz 下直接 1× 跑非线性电路会失效（高频折叠、波形畸变） |
| 自适应牛顿 | 上限 8 次、残差 1e-6 提前退出 | 削波陡沿处自动加密，稳态段落省算力 |
| 大跳变子步进 | 逐样本判据 + DC 恢复 | 防止拨弦瞬间求解失败或进次谐波极限环 |
| 延迟 | 全链路 **15 样本**（两种过采样率一致） | 宿主延迟补偿不会因档位/倍率跳变 |
| 旁通 | true-bypass + 5 ms 交叉淡化 | 干信号原样通过，切换不咔哒；电路继续运行，切回来没有"冷启动" |
| 熔断 | NaN / 发散检测 → 复位状态 | 一个坏样本不会污染整条轨道 |

活动量（LED）由电路内部的 `activity_i = 50 µA` 观测量驱动，阈值 + 150 ms 释放，
不是从输出电平猜的。

---

## 4. 验证

| 项 | 数字 | 出处 |
|---|---|---|
| THD @ 0.2 V（非对称档） | ngspice **27.5682 %** / 本实现 **27.579 %** | `circuit/tests/engine.rs` |
| h2（非对称 / 对称） | ≈3.9 % / < 0.2 % | 同上，`symmetric_branch_kills_even_harmonics` |
| 报告延迟 | 15 样本 | 同上，`latency_is_reported` |
| 静态工作点 | 与 ngspice 差 0.06 mV 级 | 框架侧 MNA 对拍 |
| CI 与本机产物一致性 | `au_smoke` RMS 都是 **0.356170**（逐位一致） | `.github/workflows/build.yml` |
| 打包产物技术校验 | `clap-probe`（声道/端口）+ `pluginval` strictness 5 | 三平台 release workflow |

运行方式：

```bash
./scripts/build.sh test       # 电路测试，不需要 ngspice
./scripts/build.sh verify     # 与 ngspice 整机对拍，需要 ngspice
```

`circuit/tests/engine.rs` 里的基线数字是**回归基线**，不是装饰：换电路时要按新电路重设。

### 已知的精度缺口

| 缺口 | 影响 |
|---|---|
| 二极管 `Cjo / tt`、MOSFET `Cgs / Cgd` 未进实时路径 | 高频段（>10 kHz）与 ngspice 的偏离略大 |
| 电位器只有线性 B 型 taper | 没有 A / C 型对数曲线（本机用的就是 B 型，所以无所谓） |
| 未在真实 DAW 中做人工听感验收 | 只有 `pluginval` 与自动化冒烟；主观听感以实际演奏为准 |

---

## 5. 仓库结构

```text
rustomp.toml             插件清单：身份 / AU 码 / 参数表 / 素材 / 面板（[assets]+[ui] 由设计器生成）
Cargo.toml               自己的 workspace（framework 依赖钉在 rustomp 的 tag 上）
circuit/
  netlist/*.cir          电路"源码"（ngspice 可直接跑）
  src/generated/*.rs     由网表生成的装配代码（入库 + --check 防漂移）
  tests/engine.rs        电路行为测试（THD / 偶次 / 旁通 / 活动量 / 换档平滑）
plugin/
  src/editor.rs          手写界面层（~90 行：创建 egui 编辑器）
  src/generated/*.rs     身份 / 参数表 / Plugin 实现 / 面板声明 / 参数桥 / 素材字节
assets/                  面板底图 + 控件贴图（设计器导出，12 px/mm）
design/panel.box.json    设计器源文件（可回设计器继续改）
scripts/build.sh         一键构建入口（doctor / build / test / verify）
doc/                     现状文档 + 历史留档
pictures/                README 用的截图与 Gatekeeper 示意图
.github/workflows/       build.yml（macOS CI）/ release.yml（三平台发布）
```

**生成物入库**是刻意的：`--check` 能拦住"改了网表忘了重新生成"，也让 diff 里能看出
电路改动带来的代码变化。

---

## 6. 参数与面板

`rustomp.toml` 的 `[[params]]`：

| 参数 | 类型 | 范围 | 面板控件 |
|---|---|---|---|
| `gain` | float | 0–100 % | 旋钮 `k2` |
| `level` | float | 0–100 % | 旋钮 `k1` |
| `symmetric` | bool | — | 拨杆（上 = false = 非对称） |
| `bypass` | bool | — | 3PDT 脚踏 |
| `clip_indicator` | indicator | — | LED（虚拟参数，读引擎活动量） |

面板契约（与 [rustomp-box-designer](https://github.com/amonisachicken/rustomp-box-designer) 一致）：

| 约定 | 值 |
|---|---|
| 面板尺寸 | 60 × 112 mm，导出 **12 px/mm** |
| 坐标系 | 毫米浮点，原点左上 |
| 窗口 | 360 × 672 px |
| 旋钮行程 | 270°（指针朝上 ⇔ 0.5），拖拽 260 px 走完全程 |
| 素材缺失 | **编译期**报错（`rustomp-gen` 校验） |

---

## 7. 两个插件身份

Mono 与 Stereo 是**两个独立的插件**，不是同一个插件里的两个模式：

| 变体 | 名字 | AU subtype | CLAP id 后缀 |
|---|---|---|---|
| mono | Sparklin Drive Mono | `Sp02` | `.mono` |
| stereo | Sparklin Drive Stereo | `Sp03` | `.stereo` |

原因（ADR-008）：宿主对"同一插件按通道数自适应"的支持不可靠，识别错通道比多一个条目更糟。
AU 四字符码（`HpEf` / `Sp01..Sp03`）与 VST3 class id **发布后不可改** —— 宿主按这个认插件。
