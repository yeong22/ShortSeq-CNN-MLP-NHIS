"""Step 5: SHAP explanations for the fusion model (Fig. 3).

DeepExplainer runs on a random sample of the test set; the first rows of that sample also serve
as the background, as in the original analysis. SHAP values of the static and temporal inputs are
joined into one matrix so that every column is one predictor at one time point (e.g. total_chol_t3).

shap's DeepExplainer has no rule for SiLU, the activation of the published fusion model, and
falls back to a plain gradient (the original analysis ran that way). With explain.silu_rule:
rescale (default) SiLU gets the DeepLIFT rescale rule used for other elementwise activations,
so the values add up to the model output; "gradient" reproduces the original behaviour.

In:  <output_dir>/models/fusion__<main window>.pt, preprocessor.json, <processed_dir>/test.csv
Out: <output_dir>/figures/shap_{beeswarm,bar,temporal}.png
     <output_dir>/results/shap_importance.csv, shap_temporal.csv (mean |SHAP|, no row-level values)
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import torch

from .features import Preprocessor, to_arrays
from .split import read_cohort
from .train import build_net
from .utils import ensure_dirs, log, paths


def _as_matrix(values, n: int) -> np.ndarray:
    """Normalise SHAP output (list per input, optional trailing output axis) to (n, features)."""
    if isinstance(values, list) and len(values) == 1 and isinstance(values[0], list):
        values = values[0]
    arrays = values if isinstance(values, list) else [values]
    flat = []
    for a in arrays:
        a = np.asarray(a)
        if a.shape[-1] == 1 and a.ndim > 2:
            a = a[..., 0]
        flat.append(a.reshape(n, -1))
    return np.concatenate(flat, axis=1)


def _register_rules(silu_rule: str) -> None:
    from shap.explainers._deep import deep_pytorch as dp

    dp.op_handler.setdefault("Identity", dp.passthrough)
    if silu_rule == "rescale":
        dp.op_handler["SiLU"] = dp.nonlinear_1d
    elif silu_rule == "gradient":
        dp.op_handler.pop("SiLU", None)
    else:
        raise ValueError(f"explain.silu_rule must be 'rescale' or 'gradient', got {silu_rule!r}")


def run_explain(cfg: dict, device: torch.device) -> pd.DataFrame | None:
    import matplotlib.pyplot as plt
    import shap

    p = paths(cfg)
    ensure_dirs(p["results"], p["figures"])
    e = cfg["explain"]
    window = cfg["features"]["main_window"]
    ckpt_path = p["models"] / f"{e['model']}__{window}.pt"
    if not ckpt_path.exists():
        log.warning("explain skipped: %s not found (train the fusion model on window %s first)", ckpt_path, window)
        return None
    ckpt = torch.load(ckpt_path, map_location=device, weights_only=False)
    if ckpt["model"] != "fusion":
        raise ValueError("explain step expects the fusion model")
    spec = ckpt["spec"]
    model = build_net("fusion", ckpt["net_params"], spec).to(device)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()

    pre = Preprocessor.load(cfg, p["models"] / "preprocessor.json")
    test = read_cohort(p["processed"] / "test.csv")
    sample = test.sample(frac=e["sample_ratio"], random_state=cfg["seed"])
    arrays = to_arrays(pre.transform(sample), spec)
    static = torch.tensor(arrays["static"], device=device)
    temporal = torch.tensor(arrays["temporal"], device=device)
    nb = e["n_background"]
    background = [static[:nb], temporal[:nb]]
    data = [static, temporal]
    n = len(static)
    log.info("SHAP on %d test rows (background: the first %d of them)", n, nb)

    _register_rules(e["silu_rule"])
    explainer = shap.DeepExplainer(model, background)
    values = explainer.shap_values(data, check_additivity=False)
    shap_matrix = _as_matrix(values, n)

    with torch.no_grad():
        output = model(*data).float().cpu().numpy().ravel()
    expected = float(np.ravel(explainer.expected_value)[0])
    gap = np.abs(output - (expected + shap_matrix.sum(axis=1)))
    log.info("additivity: mean |f(x) - (E[f] + sum SHAP)| = %.2e (max %.2e) on the logit scale",
             gap.mean(), gap.max())

    # column order: static, then temporal variable by variable, each oldest -> newest
    temporal_names = [col for cols in spec["temporal"].values() for col in cols]
    names = spec["static"] + temporal_names
    feature_matrix = np.concatenate([arrays["static"], arrays["temporal"].reshape(n, -1)], axis=1)

    importance = pd.DataFrame({"feature": names, "mean_abs_shap": np.abs(shap_matrix).mean(axis=0)})
    importance = importance.sort_values("mean_abs_shap", ascending=False)
    importance.to_csv(p["results"] / "shap_importance.csv", index=False)

    for kind, fname in [("dot", "shap_beeswarm.png"), ("bar", "shap_bar.png")]:
        shap.summary_plot(shap_matrix, feature_matrix, feature_names=names, plot_type=kind,
                          max_display=e["max_display"], show=False)
        plt.tight_layout()
        plt.savefig(p["figures"] / fname, dpi=200, bbox_inches="tight")
        plt.close()

    times = spec["times"]
    temporal_shap = (importance.set_index("feature").loc[temporal_names, "mean_abs_shap"]
                     .to_numpy().reshape(len(spec["temporal"]), len(times)))
    temporal_df = pd.DataFrame(temporal_shap, index=list(spec["temporal"]), columns=times)
    temporal_df.to_csv(p["results"] / "shap_temporal.csv")
    fig, ax = plt.subplots(figsize=(1.2 * len(times) + 3, 4))
    im = ax.imshow(temporal_shap, cmap="YlOrRd", aspect="auto")
    ax.set_xticks(range(len(times)), times)
    ax.set_yticks(range(len(temporal_df)), temporal_df.index)
    fig.colorbar(im, ax=ax, label="mean |SHAP|")
    ax.set_title("Temporal predictors by time point")
    fig.tight_layout()
    fig.savefig(p["figures"] / "shap_temporal.png", dpi=200)
    plt.close(fig)
    print(importance.head(e["max_display"]).to_markdown(index=False, floatfmt=".4f"))
    return importance
