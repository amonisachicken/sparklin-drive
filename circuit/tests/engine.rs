// SPDX-License-Identifier: GPL-3.0-or-later

//! 引擎级测试：**两个分支**各自的性质 + 开关切换。

use rustomp_dsp::{Circuit, Engine};
use rustomp_oracle::{harmonics_percent, thd_percent};
use sparklin_drive_circuit::{make_params, Branch};
use std::f64::consts::TAU;

const FS: f64 = 48_000.0;

fn run(amplitude: f64, symmetric: bool, seconds: f64) -> Vec<f64> {
    let mut e = Engine::<Branch>::new(FS);
    e.set_params(make_params(0.5, symmetric, 0.5));
    let n = (seconds * FS) as usize;
    let mut out = Vec::with_capacity(n);
    let mut ph = 0.0f64;
    for _ in 0..n {
        out.push(e.process(amplitude * ph.sin()));
        ph += TAU * 1_000.0 / FS;
    }
    out
}

#[test]
fn latency_is_reported() {
    assert_eq!(Engine::<Branch>::latency_samples(), 15);
}

/// 非对称分支：THD 与 ngspice 基线（27.57%）同量级。
#[test]
fn asymmetric_branch_clips() {
    let out = run(0.2, false, 3.0);
    let tail = &out[out.len() - (0.02 * FS) as usize..];
    let thd = thd_percent(tail, FS, 1_000.0, 9);
    println!("非对称分支 THD @0.2 V = {thd:.2} %");
    assert!(
        (thd - 27.6).abs() < 1.0,
        "非对称分支 THD {thd:.2}% 偏离基线"
    );
}

/// 对称分支：偶次谐波必须塌掉（这正是开关的作用）。
#[test]
fn symmetric_branch_kills_even_harmonics() {
    let asym = run(0.2, false, 3.0);
    let sym = run(0.2, true, 3.0);
    let h_asym = harmonics_percent(&rustomp_oracle::harmonics(
        &asym[asym.len() - (0.02 * FS) as usize..],
        FS,
        1_000.0,
        9,
    ));
    let h_sym = harmonics_percent(&rustomp_oracle::harmonics(
        &sym[sym.len() - (0.02 * FS) as usize..],
        FS,
        1_000.0,
        9,
    ));
    println!("非对称 h2 = {:.3} %  h3 = {:.2} %", h_asym[0], h_asym[1]);
    println!("对称   h2 = {:.3} %  h3 = {:.2} %", h_sym[0], h_sym[1]);
    assert!(h_asym[0] > 3.0, "非对称时 h2 应在 3.9% 附近");
    assert!(
        h_sym[0] < 0.2,
        "对称时 h2 应接近 0（实测 {:.3}%）",
        h_sym[0]
    );
}

/// 切换不能在波形上留下台阶。
///
/// 判据要小心：这个电路**本身**的削波边沿就很陡（相邻样本最大跳变 ≈0.10），
/// 所以不能用一个固定阈值。正确做法是拿"稳态信号自身的最大跳变"当基准：
/// 切换期间不能出现**明显超过**它的跳变（那才是咔哒）。
#[test]
fn switching_is_smooth() {
    let max_jump_steady = {
        let out = run(0.2, false, 0.2);
        let mut m = 0.0f64;
        for w in out.windows(2) {
            m = m.max((w[1] - w[0]).abs());
        }
        m
    };

    let mut e = Engine::<Branch>::new(FS);
    e.set_params(make_params(0.5, false, 0.5));
    let mut ph = 0.0f64;
    // 先跑 0.5 s 稳定
    for _ in 0..(0.5 * FS) as usize {
        e.process(0.2 * ph.sin());
        ph += TAU * 1_000.0 / FS;
    }
    // 切换到对称分支，观察相邻样本的最大跳变
    e.set_params(make_params(0.5, true, 0.5));
    let mut prev = e.process(0.2 * ph.sin());
    let mut max_jump = 0.0f64;
    for _ in 0..(0.05 * FS) as usize {
        ph += TAU * 1_000.0 / FS;
        let y = e.process(0.2 * ph.sin());
        max_jump = max_jump.max((y - prev).abs());
        prev = y;
    }
    println!(
        "切换期间最大跳变 {max_jump:.4} · 稳态信号自身 {max_jump_steady:.4} · 比值 {:.2}",
        max_jump / max_jump_steady
    );
    assert!(
        max_jump < max_jump_steady * 1.5,
        "切换出现台阶（{max_jump:.4} vs 稳态 {max_jump_steady:.4}），会听成咔哒"
    );
}

/// **削波活动量**要能驱动 GUI 的 LED（问题：之前 `Ckt::activity()` 走 trait 默认值 0 → 灯永远不亮）。
#[test]
fn activity_rises_when_clipping() {
    let mut e = Engine::<Branch>::new(FS);
    e.set_params(make_params(0.5, false, 0.5));
    // 静音：活动量应接近 0
    for _ in 0..(0.3 * FS) as usize {
        e.process(0.0);
    }
    let idle = e.activity_indicator();
    // 大信号：二极管明显导通 → 活动量应接近 1
    let mut ph = 0.0f64;
    for _ in 0..(0.5 * FS) as usize {
        e.process(0.2 * ph.sin());
        ph += TAU * 1_000.0 / FS;
    }
    let loud = e.activity_indicator();
    println!("活动量：静音 {idle:.3} · 削波 {loud:.3}");
    assert!(idle < 0.05, "静音时活动量应≈0（实测 {idle:.3}）");
    assert!(loud > 0.5, "削波时活动量应→1（实测 {loud:.3}）");
}

/// **true-bypass**（踩钉）：淡出后输出应等于"延迟 15 样本的干信号"，且切回来还有湿声。
#[test]
fn bypass_passes_dry_signal() {
    const DRY_LEN: usize = 15;
    let mut e = Engine::<Branch>::new(FS);
    e.set_params(make_params(0.5, false, 0.5));

    // 先把 wet 通道跑热
    let mut ph = 0.0f64;
    for _ in 0..(0.2 * FS) as usize {
        e.process(0.2 * ph.sin());
        ph += TAU * 1_000.0 / FS;
    }

    e.set_bypass(true);
    let mut hist = [0.0f64; DRY_LEN];
    let mut pos = 0usize;
    let mut worst = 0.0f64;
    // 5 ms 的指数淡化要 ~60 ms 才衰减到 1e-5，所以前 80 ms 不看
    for i in 0..(0.12 * FS) as usize {
        let x = 0.2 * ph.sin();
        ph += TAU * 1_000.0 / FS;
        let y = e.process(x);
        let dry = hist[pos];
        hist[pos] = x;
        pos = (pos + 1) % DRY_LEN;
        if i > (0.08 * FS) as usize {
            worst = worst.max((y - dry).abs());
        }
    }
    println!(
        "bypass 期间与干路最大偏差 {:.2e}（is_bypassed={}）",
        worst,
        e.is_bypassed()
    );
    assert!(e.is_bypassed(), "应当处于 bypass");
    assert!(worst < 1e-4, "bypass 后输出应等于干路（偏差 {worst:.2e}）");

    // GUI 的灯：bypass 期间活动量必须归零（用户报"踩下去灯还亮着"，DEVLOG E66）
    let lit = e.activity_indicator();
    println!("bypass 后活动量 {lit:.3}");
    assert!(lit < 0.01, "bypass 时灯应当熄灭（实测 {lit:.3}）");

    // 切回来：应当重新有湿声（削波后的波形不等于干路）
    e.set_bypass(false);
    let mut diff = 0.0f64;
    for i in 0..(0.05 * FS) as usize {
        let x = 0.2 * ph.sin();
        ph += TAU * 1_000.0 / FS;
        let y = e.process(x);
        if i > (0.01 * FS) as usize {
            diff = diff.max((y - x).abs());
        }
    }
    assert!(!e.is_bypassed(), "应当已回到湿路");
    assert!(diff > 0.01, "切回后应听到湿声（与输入差 {diff:.4}）");
}
