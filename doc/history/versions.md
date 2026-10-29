# 版本演进（v0.1.0 → v0.1.9）

> 归档：2026-10-29。开发留档。当前状态见 [`../current/architecture.md`](../current/architecture.md)
> 与 [`../current/releasing.md`](../current/releasing.md)。

早期 tag 密集，是因为**打包链路刚刚接通**：每个 tag 都在修"干净 checkout 里跑不起来"
的那一类问题。这一段的经验后来写进了框架与打包器的 doctor，现在不会再出现。

| tag | 主题 | 关键内容 |
|---|---|---|
| `v0.1.0` | 第一次发布 | 用 rustomp 做出来的参考插件，出 AU / VST3 / CLAP；`build.sh` 支持直接透传打包参数；面板设计文件换成用户的真实设计稿（含 3 个导入 SVG） |
| `v0.1.1` | 修打包器 | 钉 `rustomp-mac-plugin v0.1.1`：上一版 `pack.sh` 在干净 checkout 里会 `unbound variable` |
| `v0.1.2` | 修生成物 | 把 `url` 改成本仓却没重新生成 `identity.rs` → 重新生成；`test` 子命令也校验生成物 |
| `v0.1.3` | 修 CI 假绿 | 之前的"CI 通过"是假的：缺 `cargo-nih-plug` + `\| tee` 吞掉失败 + 上传空目录只警告。判据改为"产物数量 ≥1 且能下载" |
| `v0.1.4` | 新机体验 | 找不到框架时直接打印克隆命令（tag 自动取自 `Cargo.toml`），不让用户猜 |
| `v0.1.5` | 目录约定 | 依赖位置统一为"本仓同级目录"，去掉克隆到绝对目录的选项 |
| `v0.1.6` | 提示可执行 | 缺打包工具的提示拆成可逐行执行的命令；tag 取自 manifest |
| `v0.1.7` | 文档成形 | README 顶部加"依赖与获取方式"；新增 `MAKING-YOUR-OWN.md`（今在 `doc/current/`）；CI 钉 packer tag |
| `v0.1.8` | 版本配套 | 框架升 `rustomp v0.1.1`，打包器升 `v0.1.6` |
| `v0.1.9` | 三平台发布 | 加 `release.yml`：tag 触发 macOS / Windows / Linux 三平台构建 → GitHub Release（**未签名 prerelease**）。期间修了：Windows 的 MSVC `link.exe` 被 Git 的 GNU `link` 遮住、Linux 缺 `x11-xcb.pc` 与 OpenGL 头、Windows checkout 的 CRLF 导致生成物 `--check` 误报、`gh release` 需要 `-R` |

## tag 之后的改动（未发版）

| 改动 | 说明 |
|---|---|
| 文档重构 | README 改成产品向（面板 / 音色 / 安装 / 模板 / 许可），技术细节迁到 `doc/current/`，历史迁到 `doc/history/` |
| 框架升到 `v0.1.2` | 本工作区已指向 `v0.1.2`；mac 打包器 `v0.1.7`、win `v0.3.0`、linux `v0.1.0` 配套不变 |

## 为什么 tag 打这么密

回头看，`v0.1.1`–`v0.1.6` 这六个 tag 修的都是**同一类问题**：脚本在"作者的机器"上能跑，
在别人的干净 checkout 里跑不起来。现在的防线是：

1. `doctor` 子命令一次说清缺什么、装什么；
2. 缺依赖时打印**可直接复制执行**的命令，tag 从 manifest 读，不会过期；
3. CI 每次都在干净 runner 上从零 clone 三仓再构建；
4. `ARTIFACT:` 行是唯一产物来源，缺一个就失败。
