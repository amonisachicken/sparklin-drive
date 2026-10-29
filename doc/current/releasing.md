# 发布

> 现状文档。日常开发只需要 [`build.md`](build.md)；本文讲"包是怎么打出来、怎么发出去的"。

---

## 1. 版本与配套

当前配套（写死在代码里，改版本时三处一起改）：

| 组件 | 版本 | 写在哪 |
|---|---|---|
| 本插件 | `v0.1.9` | `Cargo.toml` 的 `workspace.package.version` |
| 框架 `rustomp` | `v0.1.2` | `Cargo.toml` 的 `workspace.dependencies`（`tag = "v0.1.2"`） |
| macOS 打包器 | `v0.1.7` | `rustomp.toml` 的 `[requires] packer_tag` |
| Windows 打包器 | `v0.3.0` | `.github/workflows/release.yml` 的环境变量 |
| Linux 打包器 | `v0.1.0` | 同上 |
| `cargo-nih-plug` | rev `de42101` | 打包器的 `deps.lock` |

`rustomp-gen` 与打包器启动时各校验一次 `[requires]`，版本不配套会直接报错。

---

## 2. 产物清单

`publish` job 会把三个平台的产物统一改名成下面这些，挂到 Release 上：

| 平台 | 文件 | 来源 |
|---|---|---|
| macOS（universal） | `Sparklin-Drive-<ver>-macOS.dmg` | 打包器 `--format dmg` |
| | `Sparklin-Drive-<ver>-macOS-plugins.zip` | AU `.component` + `.vst3` + `.clap` 打包 |
| Windows x64 | `Sparklin-Drive-<ver>-Windows-x64-Setup-system.msi` | 系统级 MSI（需管理员） |
| | `Sparklin-Drive-<ver>-Windows-x64-Setup-per-user.msi` | 用户级 MSI（免 UAC） |
| | `Sparklin-Drive-<ver>-Windows-x64-plugins.zip` | `.vst3` + `.clap` 打包 |
| Linux x64 | `Sparklin-Drive-<ver>-Linux-x64.tar.gz` | 含 `install.sh`（`--system` 可选） |
| 全部 | `SHA256SUMS.txt` | 上面所有文件的校验和 |

每个平台都是 mono + stereo **两个身份**一起出（`Sparklin Drive Mono` / `Sparklin Drive Stereo`）。

---

## 3. 流程

`.github/workflows/release.yml`，两个触发方式：

| 触发 | 行为 |
|---|---|
| push tag `v*` | 三平台构建 → 汇总 → 创建**新的** GitHub Release（prerelease） |
| `workflow_dispatch` + `publish_tag` | 构建并对已有 tag **补发/覆盖**产物（`gh release upload --clobber`） |
| `workflow_dispatch`（不填 tag） | 只构建、上传 Actions artifact，不碰 Release（验证 runner 用） |

三个 job 各自独立：

| job | runner | 关键步骤 |
|---|---|---|
| `macos` | `macos-14`（arm64） | 装两个 rust target → `brew install cmake` → `fetch-third-party.sh` → `test` → `build.sh --format au/vst3/clap/dmg` → 抓 `ARTIFACT:` → 打 zip |
| `windows` | `windows-2022` | MSVC 优先级修正（Git 的 GNU `link` 会遮住 `link.exe`）→ `doctor` → `test` → `build.sh --format vst3/clap/msi` |
| `linux` | `ubuntu-22.04` | 装 GUI / X11 开发库 → `RUSTOMP_REQUIRE_VERIFY=1` → `build.sh --format targz` |

几点刻意的选择：

- **Linux 用 22.04 而不是 24.04**：产物与构建机 glibc 绑定，22.04 是 glibc 2.35，能覆盖更老的发行版。
- **`ARTIFACT:` 是唯一的产物来源**：CI 不猜路径，只读 `build.sh` stdout 的 `ARTIFACT:` 行，
  缺一个就 `exit 1`（防止"上传空目录只警告"的假绿）。
- **`.gitattributes` 强制 LF**：Windows checkout 若转成 CRLF，生成物的 `--check` 会误报漂移。
- **`RUSTOMP_REQUIRE_VERIFY=1`**：Linux 上确实跑通了 `clap-probe` / `pluginval` 才允许出包，
  不会出现"参数就绪但没验证"的假通过。

---

## 4. 签名现状

| 平台 | 现在 | 对外正式分发需要 |
|---|---|---|
| macOS | **ad-hoc 签名**（`codesign -s -`），未公证 | Apple Developer ID + `notarytool` 公证 + 装订（staple） |
| Windows | 未签名 | Authenticode 代码签名证书 |
| Linux | 不涉及 | 分发包校验和（已有 `SHA256SUMS.txt`） |

后果：macOS 首次运行会被 Gatekeeper 拦（README 里有放行图文步骤），Windows 会弹 SmartScreen。
因此 Release 一律标记 **prerelease / 技术预览**，不宣称可用于生产。

---

## 5. 发版检查清单

- [ ] `./scripts/build.sh test` 全绿；`verify` 与 ngspice 偏差在可接受范围
- [ ] `Cargo.toml` 版本号、`rustomp.toml` 的 `[requires]`、workflow 里的三处 tag 都对得上
- [ ] 干净 clone + 三仓同级仍能 `./scripts/build.sh`（CI 每次都在验证这件事）
- [ ] AU 四字符码 / VST3 class id / bundle id **没有变**（发布后改 = 换了一个插件）
- [ ] `README.md` 的下载表、Gatekeeper 步骤与实际产物一致
- [ ] `SHA256SUMS.txt` 里每个文件都在
- [ ] 打 tag 并推到 `master`，确认 Release 页面的产物数量与预期一致
