"""Step 4: test-set performance, model comparison and risk stratification.

Paper: Methods > Statistical analysis; Fig. 2; Table S7.

- AUROC, AUPRC, sensitivity, specificity with 95% CIs. The paper does not state how its CIs were
  computed; this release uses a percentile bootstrap (evaluate.n_bootstrap resamples).
- cutoff by the Youden index, chosen on the validation predictions (evaluate.cutoff_from)
- DeLong test for AUROC differences against the reference model (fusion)
- KNKPC rule: flagged if HBV, HCV or cirrhosis (2022 KLCA-NCC surveillance targets)
- risk quintiles of the reference model: cases, crude incidence per 100,000 (as in Fig. 2B),
  Kaplan-Meier 5-year cumulative incidence and Cox hazard ratios vs Q1
- calibration (not reported in the paper): Brier score; Platt and isotonic recalibration fitted
  on validation predictions and scored on the test set

The DeLong, bootstrap and survival code was written for this release; the original notebooks
did not include it.

In:  <output_dir>/predictions/*.csv, <processed_dir>/test.csv
Out: <output_dir>/results/{performance,delong,risk_groups,calibration}.csv, <output_dir>/figures/*.png
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from scipy.stats import norm, rankdata
from sklearn.isotonic import IsotonicRegression
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score, roc_curve

from .split import read_cohort
from .utils import ensure_dirs, log, paths

LABELS = {"lr": "LR", "xgb": "XGBoost", "mlp": "MLP", "fusion": "Fusion", "knkpc": "KNKPC"}


# ----------------------------------------------------------------------------- metrics
def youden_cutoff(y: np.ndarray, p: np.ndarray) -> float:
    fpr, tpr, thr = roc_curve(y, p)
    return float(thr[np.argmax(tpr - fpr)])


def point_metrics(y: np.ndarray, p: np.ndarray, cutoff: float) -> dict[str, float]:
    pred = p >= cutoff
    tp = np.sum(pred & (y == 1))
    tn = np.sum(~pred & (y == 0))
    return {
        "auroc": roc_auc_score(y, p),
        "auprc": average_precision_score(y, p),
        "sensitivity": tp / max(np.sum(y == 1), 1),
        "specificity": tn / max(np.sum(y == 0), 1),
    }


def bootstrap_ci(y, p, cutoff, n_boot, seed, alpha=0.05) -> dict[str, tuple[float, float]]:
    rng = np.random.default_rng(seed)
    draws = []
    for _ in range(n_boot):
        idx = rng.integers(0, len(y), len(y))
        if 0 < y[idx].sum() < len(idx):
            draws.append(point_metrics(y[idx], p[idx], cutoff))
    df = pd.DataFrame(draws)
    return {k: (df[k].quantile(alpha / 2), df[k].quantile(1 - alpha / 2)) for k in df.columns}


def delong_test(y: np.ndarray, p1: np.ndarray, p2: np.ndarray) -> tuple[float, float, float, float]:
    """Paired DeLong test (fast version of Sun & Xu, 2014). Returns auc1, auc2, z, p."""
    if np.isnan(p1).any() or np.isnan(p2).any():
        raise ValueError("DeLong test got missing predictions")
    pos, neg = y == 1, y == 0
    m, n = pos.sum(), neg.sum()
    preds = np.vstack([p1, p2])
    X, Y = preds[:, pos], preds[:, neg]
    tx = np.vstack([rankdata(r) for r in X])
    ty = np.vstack([rankdata(r) for r in Y])
    tz = np.vstack([rankdata(r) for r in np.hstack([X, Y])])
    aucs = tz[:, :m].sum(axis=1) / (m * n) - (m + 1) / (2 * n)
    v01 = (tz[:, :m] - tx) / n
    v10 = 1 - (tz[:, m:] - ty) / m
    cov = np.cov(v01) / m + np.cov(v10) / n
    contrast = np.array([1.0, -1.0])
    var = contrast @ cov @ contrast
    if not var > 0:  # identical predictions
        return float(aucs[0]), float(aucs[1]), float("nan"), float("nan")
    z = (aucs[0] - aucs[1]) / np.sqrt(var)
    return float(aucs[0]), float(aucs[1]), float(z), float(2 * norm.sf(abs(z)))


# ----------------------------------------------------------------------------- loading
def load_predictions(cfg: dict, test: pd.DataFrame) -> dict[tuple[str, str], pd.DataFrame]:
    out = {}
    test_ids = set(test["id"])
    for f in sorted(paths(cfg)["predictions"].glob("*__*.csv")):
        model, window = f.stem.split("__", 1)
        df = pd.read_csv(f, dtype={"id": str})
        if set(df.loc[df["split"] == "test", "id"]) != test_ids:
            raise ValueError(f"{f.name} was made for a different test set; re-run --step train after --step split")
        out[(model, window)] = df
    if not out:
        raise FileNotFoundError("No predictions found; run --step train first.")
    return out


def knkpc_score(cfg: dict, test: pd.DataFrame) -> np.ndarray | None:
    """1 if any KNKPC marker (HBV, HCV, cirrhosis) is present; None when the markers are not configured."""
    markers = cfg["evaluate"].get("knkpc_markers") or []
    if not markers or not set(markers) <= set(test.columns):
        return None
    return test[markers].eq(1).any(axis=1).astype(float).to_numpy()


def _cutoff_reference(cfg: dict) -> str:
    source = cfg["evaluate"]["cutoff_from"]
    if source not in ("valid", "test"):
        raise ValueError(f"evaluate.cutoff_from must be 'valid' or 'test', got {source!r}")
    return source


# ----------------------------------------------------------------------------- analyses
def performance_table(cfg, preds, test) -> pd.DataFrame:
    e = cfg["evaluate"]
    source = _cutoff_reference(cfg)
    rows = []
    k = knkpc_score(cfg, test)
    if k is not None:
        y_test = test[cfg["label_column"]].to_numpy()
        m, ci = point_metrics(y_test, k, 1.0), bootstrap_ci(y_test, k, 1.0, e["n_bootstrap"], cfg["seed"])
        rows.append({"window": "-", "model": "knkpc", "cutoff": 1.0, **m, **{f"{a}_ci": b for a, b in ci.items()}})
    for (model, window), df in preds.items():
        ref = df[df["split"] == source]
        te = df[df["split"] == "test"]
        cutoff = youden_cutoff(ref["y"].to_numpy(), ref["prob"].to_numpy())
        y, p = te["y"].to_numpy(), te["prob"].to_numpy()
        m, ci = point_metrics(y, p, cutoff), bootstrap_ci(y, p, cutoff, e["n_bootstrap"], cfg["seed"])
        rows.append({"window": window, "model": model, "cutoff": cutoff, **m, **{f"{a}_ci": b for a, b in ci.items()}})
    table = pd.DataFrame(rows)
    for metric in ["auroc", "auprc", "sensitivity", "specificity"]:
        table[f"{metric}_lo"] = table[f"{metric}_ci"].map(lambda t: t[0])
        table[f"{metric}_hi"] = table[f"{metric}_ci"].map(lambda t: t[1])
        table = table.drop(columns=f"{metric}_ci")
    return table


def delong_table(cfg, preds, test) -> pd.DataFrame:
    e = cfg["evaluate"]
    rows = []
    k = knkpc_score(cfg, test)
    for window in sorted({w for _, w in preds}):
        ref_key = (e["reference_model"], window)
        if ref_key not in preds:
            continue
        ref = preds[ref_key].query("split == 'test'").set_index("id")
        others = {m: preds[(m, window)].query("split == 'test'").set_index("id")["prob"]
                  for m, w in preds if w == window and m != e["reference_model"]}
        if k is not None:
            others["knkpc"] = pd.Series(k, index=test["id"])
        for model, prob in others.items():
            prob = prob.reindex(ref.index)
            a_ref, a_other, z, pval = delong_test(ref["y"].to_numpy(), ref["prob"].to_numpy(), prob.to_numpy())
            rows.append({"window": window, "reference": e["reference_model"], "model": model,
                         "auroc_reference": a_ref, "auroc_model": a_other, "z": z, "p": pval})
    return pd.DataFrame(rows)


def risk_groups(cfg, preds, test):
    """Equal-size quintiles of predicted risk (reference model, main window).

    Reports cases, crude incidence per 100,000 (cases / n, the measure in Fig. 2B), the
    Kaplan-Meier cumulative incidence at the end of follow-up, and Cox hazard ratios vs Q1.
    """
    from lifelines import CoxPHFitter, KaplanMeierFitter

    e = cfg["evaluate"]
    key = (e["reference_model"], cfg["features"]["main_window"])
    if key not in preds:
        log.warning("risk groups skipped: no predictions for %s", key)
        return None, None
    if "fu_years" not in test.columns:
        log.warning("risk groups skipped: no fu_years column in the cohort table")
        return None, None
    te = preds[key].query("split == 'test'").merge(test[["id", "fu_years"]], on="id", validate="one_to_one")
    q = e["n_risk_groups"]
    te["group"] = pd.qcut(te["prob"].rank(method="first"), q, labels=[f"Q{i + 1}" for i in range(q)])
    horizon = float(cfg["cohort"]["label_years"][1] - cfg["cohort"]["index_year"] + 1)

    rows, curves = [], {}
    for g, d in te.groupby("group", observed=True):
        km = KaplanMeierFitter().fit(d["fu_years"], d["y"])
        curves[g] = 1 - km.survival_function_.iloc[:, 0]
        rows.append({"group": g, "n": len(d), "cases": int(d["y"].sum()),
                     "crude_per_100k": d["y"].mean() * 1e5,
                     "km_cum_incidence_per_100k": float(1 - km.predict(horizon - 1e-9)) * 1e5})
    dummies = pd.get_dummies(te["group"], drop_first=True, dtype=float)
    cox = CoxPHFitter().fit(pd.concat([te[["fu_years", "y"]], dummies], axis=1), "fu_years", "y")
    hr = np.exp(cox.confidence_intervals_).join(np.exp(cox.params_).rename("hr"))
    hr.columns = ["hr_lo", "hr_hi", "hr"]
    table = pd.DataFrame(rows).merge(hr, left_on="group", right_index=True, how="left")
    table.loc[table["group"] == "Q1", ["hr", "hr_lo", "hr_hi"]] = 1.0
    return table, curves


def calibration_table(cfg, preds) -> pd.DataFrame:
    rows = []
    for (model, window), df in preds.items():
        va, te = df[df["split"] == "valid"], df[df["split"] == "test"]
        platt = LogisticRegression().fit(va[["prob"]], va["y"])
        iso = IsotonicRegression(out_of_bounds="clip").fit(va["prob"], va["y"])
        for method, p in {"raw": te["prob"].to_numpy(),
                          "platt": platt.predict_proba(te[["prob"]])[:, 1],
                          "isotonic": iso.predict(te["prob"])}.items():
            rows.append({"window": window, "model": model, "method": method,
                         "brier": brier_score_loss(te["y"], p), "auroc": roc_auc_score(te["y"], p)})
    return pd.DataFrame(rows)


# ----------------------------------------------------------------------------- figures
def plot_roc(cfg, preds, test, perf, path):
    import matplotlib.pyplot as plt

    window = cfg["features"]["main_window"]
    fig, ax = plt.subplots(figsize=(5, 5))
    k = knkpc_score(cfg, test)
    if k is not None:
        fpr, tpr, _ = roc_curve(test[cfg["label_column"]].to_numpy(), k)
        r = perf.query("model == 'knkpc'").iloc[0]
        ax.plot(fpr, tpr, label=f"KNKPC ({r.auroc:.3f} [{r.auroc_lo:.3f}-{r.auroc_hi:.3f}])")
    for model in cfg["evaluate"]["models"]:
        if (model, window) not in preds:
            continue
        te = preds[(model, window)].query("split == 'test'")
        fpr, tpr, _ = roc_curve(te["y"], te["prob"])
        r = perf.query("model == @model and window == @window").iloc[0]
        ax.plot(fpr, tpr, label=f"{LABELS.get(model, model)} ({r.auroc:.3f} [{r.auroc_lo:.3f}-{r.auroc_hi:.3f}])")
    ax.plot([0, 1], [0, 1], "--", color="grey")
    ax.set(xlabel="1 - Specificity", ylabel="Sensitivity", title=f"ROC, window {window}")
    ax.legend(loc="lower right", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def plot_risk(curves, table, path):
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(6, 4))
    for g, curve in curves.items():
        r = table.query("group == @g").iloc[0]
        ax.step(curve.index, curve.values * 100, where="post",
                label=f"{g}: {r.cases} cases, HR {r.hr:.2f}")
    ax.set(xlabel="Time (years)", ylabel="Cumulative risk (%)", title="Cumulative incidence by predicted-risk quintile")
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def run_evaluate(cfg: dict) -> pd.DataFrame:
    p = paths(cfg)
    ensure_dirs(p["results"], p["figures"])
    test = read_cohort(p["processed"] / "test.csv")
    preds = load_predictions(cfg, test)

    perf = performance_table(cfg, preds, test)
    perf.to_csv(p["results"] / "performance.csv", index=False)
    delong_table(cfg, preds, test).to_csv(p["results"] / "delong.csv", index=False)
    calibration_table(cfg, preds).to_csv(p["results"] / "calibration.csv", index=False)
    plot_roc(cfg, preds, test, perf, p["figures"] / "roc.png")
    table, curves = risk_groups(cfg, preds, test)
    if table is not None:
        table.to_csv(p["results"] / "risk_groups.csv", index=False)
        plot_risk(curves, table, p["figures"] / "cumulative_risk.png")

    show = perf.assign(model=perf["model"].map(lambda m: LABELS.get(m, m)))
    for metric in ["auroc", "auprc", "sensitivity", "specificity"]:
        show[metric] = [f"{a:.3f} ({lo:.3f}-{hi:.3f})" for a, lo, hi in
                        zip(show[metric], show[f"{metric}_lo"], show[f"{metric}_hi"])]
    print(show[["window", "model", "cutoff", "auroc", "auprc", "sensitivity", "specificity"]]
          .to_markdown(index=False, floatfmt=".3f"))
    return perf
