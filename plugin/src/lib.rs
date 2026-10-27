// SPDX-License-Identifier: GPL-3.0-or-later

//! Sparklin Drive —— 插件外壳（**手写文件**）。
//!
//! 这个文件刻意保持很短：身份、参数表、`Plugin` 实现全部由
//! `cargo run -q -p rustomp-gen -- <本项目>` 从 `rustomp.toml` 生成到
//! `src/generated/`（入库、可 review、有漂移守卫）。
//!
//! 手写的东西放这里或新建模块；**不要改 `src/generated/`**。

mod generated;

/// 手写的界面层（`plugin_impl.rs` 里的 `gui` feature 钩子会调用 `editor::make`）
#[cfg(feature = "gui")]
mod editor;

pub use generated::plugin_impl::*;
