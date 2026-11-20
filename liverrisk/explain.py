"""Step 5: SHAP explanations for the fusion model (Fig. 3).

DeepExplainer runs on a random sample of the test set with a small background set. SHAP values
of the static and temporal inputs are joined into one matrix so that every column is one
predictor at one time point (e.g. total_chol_t3).

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


def run_explain(cfg: dict, device: torch.device) -> pd.DataFrame:
    import matplotlib.pyplot as plt
    import shap

    p = paths(cfg)
    ensure_dirs(p["results"], p["figures"])
    e = cfg["explain"]
    window = cfg["features"]["main_window"]
    ckpt = torch.load(p["models"] / f"{e['model']}__{window}.pt", map_location=device, weights_only=False)
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
    data = [static[nb:], temporal[nb:]]
    n = len(data[0])
    log.info("SHAP on %d test rows (background %d)", n, nb)

    try:
        values = shap.DeepExplainer(model, background).shap_values(data, check_additivity=False)
    except Exception as err:  # some layer types are not supported by DeepExplainer
        log.warning("DeepExplainer failed (%s); using GradientExplainer", err)
        values = shap.GradientExplainer(model, background).shap_values(data)

    # column order: static, then temporal variable by variable, each oldest -> newest
    temporal_names = [col for cols in spec["temporal"].values() for col in cols]
    names = spec["static"] + temporal_names
    shap_matrix = _as_matrix(values, n)
    feature_matrix = np.concatenate(
        [arrays["static"][nb:], arrays["temporal"][nb:].reshape(n, -1)], axis=1)

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
    temporal = (importance.set_index("feature").loc[temporal_names, "mean_abs_shap"]
                .to_numpy().reshape(len(spec["temporal"]), len(times)))
    temporal_df = pd.DataFrame(temporal, index=list(spec["temporal"]), columns=times)
    temporal_df.to_csv(p["results"] / "shap_temporal.csv")
    fig, ax = plt.subplots(figsize=(1.2 * len(times) + 3, 4))
    im = ax.imshow(temporal, cmap="YlOrRd", aspect="auto")
    ax.set_xticks(range(len(times)), times)
    ax.set_yticks(range(len(temporal_df)), temporal_df.index)
    fig.colorbar(im, ax=ax, label="mean |SHAP|")
    ax.set_title("Temporal predictors by screening period")
    fig.tight_layout()
    fig.savefig(p["figures"] / "shap_temporal.png", dpi=200)
    plt.close(fig)
    print(importance.head(e["max_display"]).to_markdown(index=False, floatfmt=".4f"))
    return importance
