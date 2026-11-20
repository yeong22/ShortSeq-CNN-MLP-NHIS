"""Feature sets per observation window and preprocessing (Methods S1).

Continuous variables are z-scored with one scaler per column (each time point separately),
fitted on the training data only. Ordinal and binary variables are integer-encoded with one
encoder per column. Encoded values follow the sorted order of the training values.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


def window_spec(cfg: dict, window: str) -> dict:
    """Column layout for one observation window.

    static   : columns fed to the static encoder (and to the flat models)
    temporal : {variable: [column per time point, oldest first]} -> CNN channels
    flat     : static + all temporal columns, the input of LR / XGBoost / MLP
    """
    f = cfg["features"]
    chosen = set(f["windows"][window])
    times = [t for t in cfg["cohort"]["periods"] if t in chosen]
    temporal = {v: [f"{v}_{t}" for t in times] for v in f["temporal_continuous"] + f["temporal_ordinal"]}
    static = f["static_continuous"] + f["static_binary"]
    flat = static + [col for cols in temporal.values() for col in cols]
    return {"window": window, "times": times, "static": static, "temporal": temporal, "flat": flat}


class Preprocessor:
    def __init__(self, cfg: dict):
        f = cfg["features"]
        times = list(cfg["cohort"]["periods"])
        self.continuous = f["static_continuous"] + [f"{v}_{t}" for v in f["temporal_continuous"] for t in times]
        self.categorical = f["static_binary"] + [f"{v}_{t}" for v in f["temporal_ordinal"] for t in times]
        self.stats: dict[str, list[float]] = {}
        self.levels: dict[str, list[float]] = {}

    def fit(self, df: pd.DataFrame) -> "Preprocessor":
        for col in self.continuous:
            x = df[col].astype(float)
            std = float(x.std(ddof=0))
            self.stats[col] = [float(x.mean()), std if std > 0 else 1.0]
        for col in self.categorical:
            self.levels[col] = sorted(float(v) for v in pd.unique(df[col].astype(float)))
        return self

    def transform(self, df: pd.DataFrame) -> pd.DataFrame:
        out = pd.DataFrame(index=df.index)
        for col in self.continuous:
            mean, std = self.stats[col]
            out[col] = (df[col].astype(float) - mean) / std
        for col in self.categorical:
            mapping = {v: i for i, v in enumerate(self.levels[col])}
            codes = df[col].astype(float).map(mapping)
            if codes.isna().any():
                unseen = sorted(df.loc[codes.isna(), col].unique())[:5]
                raise ValueError(f"{col}: values not seen in the training data {unseen}")
            out[col] = codes.astype(int)
        return out

    def save(self, path: Path) -> None:
        Path(path).write_text(json.dumps({"stats": self.stats, "levels": self.levels}, indent=1))

    @classmethod
    def load(cls, cfg: dict, path: Path) -> "Preprocessor":
        obj = cls(cfg)
        saved = json.loads(Path(path).read_text())
        obj.stats, obj.levels = saved["stats"], saved["levels"]
        return obj


def to_arrays(X: pd.DataFrame, spec: dict) -> dict[str, np.ndarray]:
    """flat (n, F); static (n, S); temporal (n, C, T) with C variables and T time points."""
    return {
        "flat": X[spec["flat"]].to_numpy(np.float32),
        "static": X[spec["static"]].to_numpy(np.float32),
        "temporal": np.stack([X[cols].to_numpy(np.float32) for cols in spec["temporal"].values()], axis=1),
    }
