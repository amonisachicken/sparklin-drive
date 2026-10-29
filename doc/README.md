# 文档索引

README 只讲「这是什么、怎么装、怎么用」。所有细节在这里，分两类：

- **[`current/`](current/)** —— **现状**：现在还能照着做的，自行构建、二次开发、发布流程。
- **[`history/`](history/)** —— **历史**：开发留档，只保留证据，不再更新。

维护规则：属于"现在的事实"写进 `current/`；一旦过时，移到 `history/`，
在 `current/` 里留一行指针。历史文档只允许修正链接，不用新结论改写旧记录。

---

## 现状（可执行）

| 文档 | 内容 | 什么时候读 |
|---|---|---|
| [`current/build.md`](current/build.md) | 依赖清单、三平台分步安装、构建命令、产物路径、故障排查 | 想自己编译 / 装不上 / 构建报错 |
| [`current/making-your-own.md`](current/making-your-own.md) | 拿本仓当模板：改身份 / 电路 / 面板 / 参数表 + 发布检查清单 + 易踩的坑 | 想做自己的单块 |
| [`current/architecture.md`](current/architecture.md) | 电路拓扑、器件模型、实时机制、验证数字、仓库结构、面板契约 | 想改 DSP / 理解它为什么这么响 |
| [`current/releasing.md`](current/releasing.md) | 三平台产物清单、release workflow、签名现状与后续项 | 要发版 / 想知道包是怎么来的 |

## 历史（留档，不再更新）

| 文档 | 内容 |
|---|---|
| [`history/README.md`](history/README.md) | 归档索引与归档流程 |
| [`history/versions.md`](history/versions.md) | 版本演进 v0.1.0 → v0.1.9（每个 tag 解决了什么） |
| [`history/legacy-ab.md`](history/legacy-ab.md) | 与手推 WDF 实现（legacy）的 AB 测试：方法、结论、THD 差 0.08 pp |

外部参考（不在本仓，只读）：

| 文档 | 位置 |
|---|---|
| 生态与仓库边界、三个跨仓契约 | [`rustomp/docs/ecosystem.md`](https://github.com/amonisachicken/rustomp/blob/master/docs/ecosystem.md) |
| 电路导入与网表指令 | [`rustomp/docs/circuit-import.md`](https://github.com/amonisachicken/rustomp/blob/master/docs/circuit-import.md) |
| 器件库与精度档位 | [`rustomp/docs/component-library.md`](https://github.com/amonisachicken/rustomp/blob/master/docs/component-library.md) |
| 面板契约（`[ui]` 每个字段） | `rustomp-box-designer/docs/01-contract-panel-toml.md` |
| 面板导出 → 装进插件的 6 步 | `rustomp-box-designer/docs/06-export-runbook.md` |
