"""Step 1: build the analytic cohort from the NHIS tables.

Paper: Methods > Study population and design, Predictor and outcome definitions; Fig. S1.

In:  the tables listed under `raw_files` in the config (column lists in data/README.md).
Out: <processed_dir>/cohort.csv  one row per person (stays on the analysis server)
     <output_dir>/results/cohort_flow.csv  counts only, for the flowchart
"""
from __future__ import annotations

import re
from pathlib import Path

import numpy as np
import pandas as pd

from .utils import ensure_dirs, log, paths


def _years(span: list[int]) -> list[int]:
    return list(range(span[0], span[1] + 1))


def read_table(path: Path, id_col: str) -> pd.DataFrame:
    df = pd.read_csv(path, dtype={id_col: str}, low_memory=False)
    df.columns = [c.replace(" ", "") for c in df.columns]  # e.g. "CTRB_ 2010" -> "CTRB_2010"
    return df.set_index(id_col)


def first_of_period(df: pd.DataFrame, prefix: str, years: list[int]) -> pd.Series:
    """Value from the first exam of a period, filled with the next year's value if missing."""
    cols = [f"{prefix}_{y}" for y in years if f"{prefix}_{y}" in df.columns]
    if not cols:
        raise KeyError(f"No columns {prefix}_<year> for years {years}")
    out = pd.to_numeric(df[cols[0]], errors="coerce")
    for col in cols[1:]:
        out = out.fillna(pd.to_numeric(df[col], errors="coerce"))
    return out


def numeric(df: pd.DataFrame, col: str) -> pd.Series:
    """Column as numbers; all-missing if the column does not exist (e.g. a question not asked that year)."""
    if col in df.columns:
        return pd.to_numeric(df[col], errors="coerce")
    return pd.Series(np.nan, index=df.index)


def any_flag(df: pd.DataFrame, prefix: str, years: list[int]) -> pd.Series:
    cols = [f"{prefix}_{y}" for y in years if f"{prefix}_{y}" in df.columns]
    if not cols:
        raise KeyError(f"No columns {prefix}_<year> for years {years}")
    return df[cols].apply(pd.to_numeric, errors="coerce").eq(1).any(axis=1)


def categorize(x: pd.Series, cutoffs: list[float]) -> pd.Series:
    """0 -> 0, then (0, c1) -> 1, [c1, c2) -> 2, ..., >= last cutoff -> len(cutoffs) + 1."""
    conditions = [x.isna(), x.eq(0)] + [x < c for c in cutoffs]
    choices = [np.nan, 0] + list(range(1, len(cutoffs) + 1))
    return pd.Series(np.select(conditions, choices, default=len(cutoffs) + 1), index=x.index)


def drinks_per_day(days_per_week: pd.Series, per_occasion: pd.Series) -> pd.Series:
    """Average drinks per day. Missing amount counts as 0 only for people who never drink."""
    out = days_per_week * per_occasion / 7
    out = out.mask(per_occasion.isna() & days_per_week.eq(0), 0.0)
    return out.mask(days_per_week.isna())


def icd_regex(codes: list[str]) -> str:
    """'X' matches any one character and the pattern is a prefix; codes without 'X' match exactly."""
    parts = [re.escape(c).replace("X", ".") if "X" in c else re.escape(c) + "$" for c in codes]
    return "^(?:" + "|".join(parts) + ")"


def liver_disease_history(cfg: dict, ids: pd.Index) -> pd.DataFrame:
    """Ever-diagnosed flags (Table S2) from claims in the history window."""
    c = cfg["cohort"]
    raw_dir = paths(cfg)["raw"]
    id_col = cfg["id_column"]
    date_col = cfg["raw_columns"]["claims_date"]
    lo, hi = c["icd_history_years"]
    patterns = {name: icd_regex(codes) for name, codes in cfg["icd10"].items()}
    id_set = set(ids)
    parts = []
    for year in _years(c["icd_history_years"]):
        path = raw_dir / cfg["raw_files"]["claims_pattern"].format(year=year)
        if not path.exists():
            log.warning("claims file missing: %s", path)
            continue
        for chunk in pd.read_csv(path, dtype=str, chunksize=2_000_000):
            chunk.columns = [col.replace(" ", "") for col in chunk.columns]
            chunk = chunk[chunk[id_col].isin(id_set)]
            start = pd.to_numeric(chunk[date_col].str[:4], errors="coerce")
            chunk = chunk[start.between(lo, hi)]
            if chunk.empty:
                continue
            dx = [chunk[col].fillna("").str.strip() for col in c["diagnosis_columns"] if col in chunk.columns]
            flags = pd.DataFrame(index=chunk.index)
            for name, pattern in patterns.items():
                hit = pd.Series(False, index=chunk.index)
                for codes in dx:
                    hit |= codes.str.match(pattern)
                flags[name] = hit.astype(int)
            flags[id_col] = chunk[id_col].values
            parts.append(flags.groupby(id_col).max())
    if parts:
        history = pd.concat(parts).groupby(level=0).max()
    else:
        history = pd.DataFrame(columns=list(patterns))
    return history.reindex(ids).fillna(0).astype(int)


def build_cohort(cfg: dict) -> pd.DataFrame:
    p = paths(cfg)
    c = cfg["cohort"]
    rc = cfg["raw_columns"]
    files = cfg["raw_files"]
    id_col = cfg["id_column"]
    periods = {name: list(years) for name, years in c["periods"].items()}
    exam_years = sorted(y for years in periods.values() for y in years)
    flow: list[tuple[str, int, int]] = []  # (step, excluded, remaining)

    def record(step: str, before: int, after: int) -> None:
        flow.append((step, before - after, after))
        log.info("%-55s excluded %9d  remaining %9d", step, before - after, after)

    # --- base population ------------------------------------------------------------
    people = read_table(p["raw"] / files["cancer"], id_col)
    n0 = len(people)
    birth = pd.to_numeric(people[rc["cancer"]["birth_year"]], errors="coerce")
    people = people[(c["age_reference_year"] - birth).between(*c["age_range"])]
    record(f"Aged {c['age_range'][0]}-{c['age_range'][1]} in {c['age_reference_year']}", n0, len(people))

    screen = read_table(p["raw"] / files["screening"], id_col).reindex(people.index)
    bmi_prefix = rc["screening"]["bmi"]

    def attended(year: int) -> pd.Series:
        flag = f"{rc['attendance_flag']}_{year}"
        if flag in screen.columns:
            return pd.to_numeric(screen[flag], errors="coerce").eq(1)
        return screen[f"{bmi_prefix}_{year}"].notna()

    every_period = pd.concat(
        [pd.concat([attended(y) for y in years], axis=1).any(axis=1) for years in periods.values()], axis=1
    ).all(axis=1)
    n = len(people)
    people = people[every_period]
    record("Screened at least once in every period", n, len(people))

    # --- exclusions ---------------------------------------------------------------
    n = len(people)
    people = people[~any_flag(people, rc["cancer"]["any_cancer"], _years(c["washout_years"]))]
    record("Cancer before the index date", n, len(people))

    death_raw = people[rc["cancer"]["death_date"]].astype(str).str.replace(r"\D", "", regex=True)
    death_year = pd.to_numeric(death_raw.str[:4], errors="coerce")
    n = len(people)
    keep = ~death_year.between(*c["death_exclusion_years"])
    people, death_raw, death_year = people[keep], death_raw[keep], death_year[keep]
    record("Death before the index date", n, len(people))

    label_years = _years(c["label_years"])
    liver = any_flag(people, rc["cancer"]["liver_cancer"], label_years)
    other = any_flag(people, rc["cancer"]["any_cancer"], label_years)
    label = pd.Series(np.where(liver, 1.0, np.where(~other, 0.0, np.nan)), index=people.index)
    n = len(people)
    keep = label.notna()
    people, label, death_raw, death_year = people[keep], label[keep], death_raw[keep], death_year[keep]
    record("Another cancer during follow-up", n, len(people))

    # --- outcome and follow-up time ---------------------------------------------------
    out = pd.DataFrame(index=people.index)
    out["liver_label"] = label.astype(int)
    onset = pd.Series(np.nan, index=people.index)
    for year in reversed(label_years):
        col = f"{rc['cancer']['liver_cancer']}_{year}"
        if col in people.columns:
            onset = onset.mask(pd.to_numeric(people[col], errors="coerce").eq(1), year)
    index_date = pd.Timestamp(year=c["index_year"], month=1, day=1)
    end = float(c["label_years"][1] - c["index_year"] + 1)
    if "diagnosis_date" in people.columns:
        event_time = (pd.to_datetime(people["diagnosis_date"], errors="coerce") - index_date).dt.days / 365.25
    else:  # only the diagnosis year is known
        event_time = onset - c["index_year"] + (0.5 if c["event_time"] == "mid_year" else 0.0)
    death_time = (pd.to_datetime(death_raw.str[:8], format="%Y%m%d", errors="coerce") - index_date).dt.days / 365.25
    death_time = death_time.fillna(death_year - c["index_year"] + 0.5)
    died = death_time.between(0, end, inclusive="left") & out["liver_label"].eq(0)
    out["death_event"] = died.astype(int)
    out["fu_years"] = np.where(out["liver_label"].eq(1), event_time, np.where(died, death_time, end))

    # --- predictors ---------------------------------------------------------------
    sex_col = rc["cancer"]["sex"]
    out["sex"] = pd.to_numeric(people[sex_col], errors="coerce")
    out["age"] = c["age_at_index_from"] - pd.to_numeric(people[rc["cancer"]["birth_year"]], errors="coerce")

    for feature, prefix in rc["screening"].items():
        for t, years in periods.items():
            out[f"{feature}_{t}"] = first_of_period(screen, prefix, years)

    income_map = {level: group for group, levels in c["income_groups"].items() for level in levels}
    for t, years in periods.items():
        contribution = first_of_period(people, rc["cancer"]["contribution"], years)
        out[f"income_{t}"] = contribution.map(income_map)

    quest = read_table(p["raw"] / files["questionnaire"], id_col).reindex(people.index)
    q = rc["questionnaire"]
    yearly = pd.DataFrame(index=people.index)
    for y in exam_years:
        yearly[f"alcohol_dpd_{y}"] = drinks_per_day(
            numeric(quest, f"{q['drink_days_per_week']}_{y}"), numeric(quest, f"{q['drinks_per_occasion']}_{y}")
        )
        yearly[f"activity_dpw_{y}"] = (
            numeric(quest, f"{q['vigorous_days']}_{y}") + numeric(quest, f"{q['moderate_days']}_{y}")
        ) / 2
        yearly[f"alcohol_{y}"] = categorize(yearly[f"alcohol_dpd_{y}"], c["alcohol_cutoffs"])
        yearly[f"activity_{y}"] = categorize(yearly[f"activity_dpw_{y}"], c["activity_cutoffs"])
    for t, years in periods.items():
        for name in ["alcohol", "activity", "alcohol_dpd", "activity_dpw"]:
            out[f"{name}_{t}"] = first_of_period(yearly, name, years)

    # Self-reported history: a missing answer in a year the person was examined counts as "no".
    for feature, prefix in rc["history"].items():
        cols = []
        for y in exam_years:
            v = numeric(screen, f"{prefix}_{y}")
            examined = numeric(screen, f"{bmi_prefix}_{y}").notna()
            cols.append(v.mask(examined & v.isna(), 0.0))
        out[feature] = pd.concat(cols, axis=1).max(axis=1)

    family = read_table(p["raw"] / files["family"], id_col).reindex(people.index)
    for feature, prefix in rc["family"].items():
        cols = []
        for y in exam_years:
            v = numeric(family, f"{prefix}_{y}")
            answered = numeric(family, f"{rc['family_flag']}_{y}").notna()
            cols.append(v.mask(answered & v.isna(), 0.0))
        m = pd.concat(cols, axis=1)
        out[feature] = np.where(m.isna().all(axis=1), np.nan, m.eq(1).any(axis=1).astype(float))

    out = out.join(liver_disease_history(cfg, people.index))

    # --- complete cases -------------------------------------------------------------
    f = cfg["features"]
    model_cols = f["static_continuous"] + f["static_binary"] + [
        f"{v}_{t}" for v in f["temporal_continuous"] + f["temporal_ordinal"] for t in periods
    ]
    missing = [col for col in model_cols if col not in out.columns]
    if missing:
        raise KeyError(f"Predictors not built: {missing}")
    n = len(out)
    out = out.dropna(subset=model_cols)
    record("Missing data on key variables", n, len(out))

    out.index.name = "id"
    ensure_dirs(p["processed"], p["results"])
    out.reset_index().to_csv(p["processed"] / "cohort.csv", index=False)
    pd.DataFrame(flow, columns=["step", "excluded", "remaining"]).to_csv(p["results"] / "cohort_flow.csv", index=False)
    log.info("cohort: %d people, %d liver cancer cases", len(out), int(out["liver_label"].sum()))
    return out
