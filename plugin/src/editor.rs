// SPDX-License-Identifier: GPL-3.0-or-later

//! **手写的界面层**：把 `rustomp-gui` 的声明式面板接到 nih-plug 的参数上。
//!
//! 分工：
//! - **生成的**：`generated/panel.rs`（面板布局，来自 `rustomp.toml` 的 `[ui]`）、
//!   `generated/params.rs`（参数表 + `to_dsp()`）、`generated/plugin_impl.rs`（插件实现）；
//! - **生成的**（另有）：`generated/bridge.rs`（参数桥）、`generated/assets.rs`（素材字节）；
//! - **手写的**（本文件）：只有"创建 egui 编辑器"这几十行。
//!
//! 这个文件之所以这么短，是因为能生成的全生成了：
//! 参数桥漏一个分支不会编译失败（`bypass` 就这么"点了没反应"，DEVLOG E66），
//! 素材名写死则设计器一改名就要改代码。

use nih_plug::prelude::*;
use nih_plug_egui::{create_egui_editor, egui};
use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc,
};

use crate::generated::panel::PANEL;
use crate::generated::params::PluginParams;

// ---------------------------------------------------------------- 素材
//
// 素材住在插件项目里（框架不持有素材）。分辨率约定见 rustomp-box-designer/docs/03-assets.md：
// 面板 12 px/mm、旋钮/拨杆同密度。

// 素材字节由 `generated/assets.rs` 提供（从 rustomp.toml 的 `[assets]` 生成），
// 所以这里**不再写死素材名**：设计器改名/加图后重新生成即可，不用改这个文件。
use crate::generated::assets::{IMAGES, PANEL_PNG};

/// 参数桥也由生成器提供（`[[params]]` → `ParamAccess`）。
/// 以前是手写的 match，**漏一个参数不会编译失败**，只会"点了没反应"
/// —— `bypass` 就是这么漏掉的（DEVLOG E66）。
use crate::generated::bridge::ParamBridge;

static ASSETS: rustomp_gui::Assets = rustomp_gui::Assets {
    panel: PANEL_PNG,
    images: IMAGES,
};

// ---------------------------------------------------------------- 编辑器

/// 由生成的 `plugin_impl.rs` 在 `gui` feature 打开时调用。
pub fn make(params: Arc<PluginParams>, activity: Arc<AtomicU32>) -> Option<Box<dyn Editor>> {
    create_egui_editor(
        params.editor_state.clone(),
        rustomp_gui::UiState::default(),
        |ctx, state| {
            ctx.set_visuals(egui::Visuals::light());
            // 新建 egui Context 后旧纹理句柄全部失效，必须清空重建
            rustomp_gui::reset_textures(state);
        },
        move |ctx, setter, state| {
            let level = f32::from_bits(activity.load(Ordering::Relaxed));
            let access = ParamBridge {
                params: &params,
                setter,
                activity: level,
            };
            egui::CentralPanel::default()
                .frame(egui::Frame::NONE)
                .show(ctx, |ui| {
                    rustomp_gui::draw(ui, &PANEL, &ASSETS, state, &access, level);
                });
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 面板声明必须自洽：旋钮角度对称（指针朝上 = 50%）、贴图名都存在、尺寸合法。
    #[test]
    fn generated_panel_is_valid() {
        let errs = rustomp_gui::validate_panel(&PANEL, &ASSETS);
        assert!(errs.is_empty(), "面板校验失败：{errs:#?}");
        assert_eq!(PANEL.knobs.len(), 2, "两个旋钮（LEVEL / GAIN）");
        assert_eq!(PANEL.toggles.len(), 1, "一个拨杆（Clip Mode）");
        assert_eq!(PANEL.leds.len(), 1, "一个指示灯");
        // 素材坐标 = 毫米：60 x 112 mm 的面板
        assert!((PANEL.svg_w - 60.0).abs() < 0.01);
        assert!((PANEL.svg_h - 112.0).abs() < 0.01);
    }
}
