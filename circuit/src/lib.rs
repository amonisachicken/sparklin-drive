// SPDX-License-Identifier: GPL-3.0-or-later

//! **Sparklin Drive 的电路实现（v2，MNA 生成路径）** —— 两个完整分支 + 开关切换。
//!
//! 按决策 D-005：开关**不在电路层**用元件模拟，而是每个状态一份**完整电路**，
//! 由框架的 [`rustomp_dsp::Branch`] 选择 + 10 ms 交叉淡化。
//!
//! | 分支 | 网表 | 削波环 |
//! |---|---|---|
//! | `asym` | `sparklin_drive_asym.cir` | 1 只 ∥ 2 只串联（原机、非对称） |
//! | `sym` | `sparklin_drive_sym.cir` | 短接 D3 → 1 只 ∥ 1 只（对称） |
//!
//! 生成物不手改；重新生成：
//! ```bash
//! cargo run -q -p rustomp-import -- \
//!   plugins/sparklin-drive/circuit/netlist/sparklin_drive_asym.cir \
//!   --mna plugins/sparklin-drive/circuit/src/generated/asym.rs
//! cargo run -q -p rustomp-import -- \
//!   plugins/sparklin-drive/circuit/netlist/sparklin_drive_sym.cir \
//!   --mna plugins/sparklin-drive/circuit/src/generated/sym.rs
//! ```

pub mod asym {
    include!("generated/asym.rs");
}

pub mod sym {
    include!("generated/sym.rs");
}

/// 开关两态的分支组合。
pub type Branch = rustomp_dsp::Branch<asym::Ckt, sym::Ckt>;

/// 分支参数（两路各自的 gain/level + 选择位）。
pub type Params = rustomp_dsp::BranchParams<asym::Params, sym::Params>;

/// 由插件参数装配电路参数。
///
/// 参数顺序必须与 `rustomp.toml` 里 `[[params]]` 的**声明顺序**一致
/// （`gain, symmetric, level`）—— `rustomp-gen` 的 `params_builder` 就按那个顺序生成调用。
pub fn make_params(gain: f64, symmetric: bool, level: f64) -> Params {
    Params {
        a: asym::Params { gain, level },
        b: sym::Params { gain, level },
        select_b: symmetric,
    }
}
