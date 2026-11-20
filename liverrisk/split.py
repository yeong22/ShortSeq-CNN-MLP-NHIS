"""Step 2: patient-level train/test split, stratified by outcome, age decade and sex.

Paper: Methods > Study population and design (80% training, 20% test).

In:  <processed_dir>/cohort.csv
Out: <processed_dir>/train.csv, <processed_dir>/test.csv, <output_dir>/results/split_summary.csv
"""
from __future__ import annotations

import pandas as pd
from sklearn.model_selection import train_test_split

from .utils import ensure_dirs, log, paths


def read_cohort(path) -> pd.DataFrame:
    return pd.read_csv(path, dtype={"id": str})


def split_cohort(cfg: dict) -> tuple[pd.DataFrame, pd.DataFrame]:
    p = paths(cfg)
    s = cfg["split"]
    df = read_cohort(p["processed"] / "cohort.csv")
    df["age_decade"] = (df["age"] // 10).astype(int)
    strata = df[s["stratify_on"]].astype(str).agg("_".join, axis=1)
    train, test = train_test_split(df, test_size=s["test_size"], stratify=strata, random_state=s["seed"])

    ensure_dirs(p["processed"], p["results"])
    train.to_csv(p["processed"] / "train.csv", index=False)
    test.to_csv(p["processed"] / "test.csv", index=False)
    summary = (
        pd.concat([train.assign(split="train"), test.assign(split="test")])
        .groupby(["split", "liver_label"])
        .size()
        .rename("n")
        .reset_index()
    )
    summary.to_csv(p["results"] / "split_summary.csv", index=False)
    log.info("train %d (%d cases) | test %d (%d cases)",
             len(train), int(train["liver_label"].sum()), len(test), int(test["liver_label"].sum()))
    return train, test
