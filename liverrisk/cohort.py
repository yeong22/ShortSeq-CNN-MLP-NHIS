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


def read_table(path: Path, id_col: str, exact=(), prefixes=()) -> pd.DataFrame:
    """Read only the ID, the `exact` columns and yearly columns '<prefix>_<year>'."""
    wanted = {id_col, *exact}

    def keep(col: str) -> bool:
        name = col.replace(" ", "")  # NHIS exports contain names like "CTRB_ 2010"
        return name in wanted or any(name.startswith(p + "_") for p in prefixes)

    df = pd.read_csv(path, dtype={id_col: str}, usecols=keep, low_memory=False)
    df.columns = [c.replace(" ", "") for c in df.columns]
    return df.set_index(id_col)


def period_value(df: pd.DataFrame, prefix: str, years: list[int], rule: str = "first") -> pd.Series:
    """Value for one two-year screening period.

    first: the first exam of the period; the second year fills a gap (the analysis notebooks).
    last:  the most recent exam of the period; the first year fills a gap (the paper's wording).
    """
    if rule not in ("first", "last"):
        raise ValueError(f"cohort.period_value must be 'first' or 'last', got {rule!r}")
    order = years if rule == "first" else list(reversed(years))
    cols = [f"{prefix}_{y}" for y in order if f"{prefix}_{y}" in df.columns]
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


def parse_yyyymmdd(s: pd.Series) -> tuple[pd.Series, pd.Series]:
    """Dates stored as YYYYMMDD (often read as floats because of blanks) -> (date, year).

    A value with only a year or year-month gives NaT for the date and still returns the year.
    """
    num = pd.to_numeric(s, errors="coerce")
    digits = num.round().astype("Int64").astype("string").where(num.notna())
    digits = digits.fillna(s.astype("string").str.replace(r"\D", "", regex=True))
    full = (digits.str.len() == 8).fillna(False)
    date = pd.to_datetime(digits.where(full), format="%Y%m%d", errors="coerce")
    # plain float, so a missing year compares as False rather than as a nullable NA
    year = pd.to_numeric(digits.str[:4], errors="coerce").astype(float)
    return date, year


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
    """Ever-diagnosed flags from claims in the history window (codes in `icd10`).

    Only the IDs with a hit are kept in memory.
    """
    c = cfg["cohort"]
    raw_dir = paths(cfg)["raw"]
    id_col = cfg["id_column"]
    date_col = cfg["raw_columns"]["claims_date"]
    lo, hi = c["icd_history_years"]
    patterns = {name: icd_regex(codes) for name, codes in cfg["icd10"].items()}
    wanted = {id_col, date_col, *c["diagnosis_columns"]}
    id_set = set(ids)
    hits: dict[str, set] = {name: set() for name in patterns}
    total_rows = 0
    for year in _years(c["icd_history_years"]):
        path = raw_dir / cfg["raw_files"]["claims_pattern"].format(year=year)
        if not path.exists():
            raise FileNotFoundError(f"Claims file for {year} not found: {path} (see raw_files.claims_pattern)")
        rows = 0
        for chunk in pd.read_csv(path, dtype=str, chunksize=2_000_000,
                                 usecols=lambda col: col.replace(" ", "") in wanted):
            chunk.columns = [col.replace(" ", "") for col in chunk.columns]
            chunk = chunk[chunk[id_col].isin(id_set)]
            start = pd.to_numeric(chunk[date_col].str[:4], errors="coerce")
            chunk = chunk[start.between(lo, hi)]
            if chunk.empty:
                continue
            rows += len(chunk)
            dx = [chunk[col].fillna("").str.strip() for col in c["diagnosis_columns"] if col in chunk.columns]
            codes = pd.Series(pd.unique(pd.concat(dx, ignore_index=True)))
            for name, pattern in patterns.items():
                matching = set(codes[codes.str.match(pattern)])
                if not matching:
                    continue
                mask = np.zeros(len(chunk), dtype=bool)
                for col in dx:
                    mask |= col.isin(matching).to_numpy()
                hits[name].update(chunk.loc[mask, id_col])
        log.info("claims %d: %d rows of cohort members in the window", year, rows)
        total_rows += rows
    if total_rows == 0:
        raise ValueError("No claims rows matched a cohort ID. Check the ID format (e.g. '123' vs '123.0') "
                         "and the claims date column.")
    return pd.DataFrame({name: ids.isin(list(found)).astype(int) for name, found in hits.items()}, index=ids)


def build_cohort(cfg: dict) -> pd.DataFrame:
    p = paths(cfg)
    c = cfg["cohort"]
    rc = cfg["raw_columns"]
    rcc = rc["cancer"]
    files = cfg["raw_files"]
    id_col = cfg["id_column"]
    label_col = cfg["label_column"]
    rule = c["period_value"]
    offset = 0.5 if c["event_time"] == "mid_year" else 0.0
    periods = {name: list(years) for name, years in c["periods"].items()}
    exam_years = sorted(y for years in periods.values() for y in years)
    flow: list[tuple[str, int, int]] = []  # (step, excluded, remaining)

    def record(step: str, before: int, after: int) -> None:
        flow.append((step, before - after, after))
        log.info("%-55s excluded %9d  remaining %9d", step, before - after, after)

    # --- base population ------------------------------------------------------------
    people = read_table(p["raw"] / files["cancer"], id_col,
                        exact=[rcc["sex"], rcc["birth_year"], rcc["death_date"], rcc["diagnosis_date"]],
                        prefixes=[rcc["contribution"], rcc["any_cancer"], rcc["liver_cancer"]])
    n0 = len(people)
    birth = pd.to_numeric(people[rcc["birth_year"]], errors="coerce")
    people = people[(c["age_reference_year"] - birth).between(*c["age_range"])]
    record(f"Aged {c['age_range'][0]}-{c['age_range'][1]} in {c['age_reference_year']}", n0, len(people))

    screen = read_table(p["raw"] / files["screening"], id_col,
                        prefixes=[*rc["screening"].values(), rc["attendance_flag"], *rc["history"].values()])
    screen = screen.reindex(people.index)
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
    people = people[~any_flag(people, rcc["any_cancer"], _years(c["washout_years"]))]
    record("Cancer before the index date", n, len(people))

    death_date, death_year = parse_yyyymmdd(people[rcc["death_date"]])
    n = len(people)
    keep = ~death_year.between(*c["death_exclusion_years"])
    people, death_date, death_year = people[keep], death_date[keep], death_year[keep]
    record("Death before the index date", n, len(people))

    label_years = _years(c["label_years"])
    liver = any_flag(people, rcc["liver_cancer"], label_years)
    other = any_flag(people, rcc["any_cancer"], label_years)
    label = pd.Series(np.where(liver, 1.0, np.where(~other, 0.0, np.nan)), index=people.index)
    n = len(people)
    keep = label.notna()
    people, label, death_date, death_year = people[keep], label[keep], death_date[keep], death_year[keep]
    record("Another cancer during follow-up", n, len(people))
    screen = screen.loc[people.index]

    # --- outcome and follow-up time ---------------------------------------------------
    out = pd.DataFrame(index=people.index)
    out[label_col] = label.astype(int)
    onset = pd.Series(np.nan, index=people.index)
    for year in reversed(label_years):
        col = f"{rcc['liver_cancer']}_{year}"
        if col in people.columns:
            onset = onset.mask(pd.to_numeric(people[col], errors="coerce").eq(1), year)
    index_date = pd.Timestamp(year=c["index_year"], month=1, day=1)
    end = float(c["label_years"][1] - c["index_year"] + 1)
    event_time = onset - c["index_year"] + offset  # only the diagnosis year is known
    if rcc["diagnosis_date"] in people.columns:
        dx_date, _ = parse_yyyymmdd(people[rcc["diagnosis_date"]])
        event_time = ((dx_date - index_date).dt.days / 365.25).fillna(event_time)
    death_time = ((death_date - index_date).dt.days / 365.25).fillna(death_year - c["index_year"] + offset)
    died = death_time.between(0, end, inclusive="left") & out[label_col].eq(0)
    out["death_event"] = died.astype(int)
    out["fu_years"] = np.where(out[label_col].eq(1), event_time, np.where(died, death_time, end))

    # --- predictors ---------------------------------------------------------------
    out["sex"] = pd.to_numeric(people[rcc["sex"]], errors="coerce")
    out["age"] = c["age_at_index_from"] - pd.to_numeric(people[rcc["birth_year"]], errors="coerce")

    for feature, prefix in rc["screening"].items():
        for t, years in periods.items():
            out[f"{feature}_{t}"] = period_value(screen, prefix, years, rule)

    income_map = {level: group for group, levels in c["income_groups"].items() for level in levels}
    for t, years in periods.items():
        contribution = period_value(people, rcc["contribution"], years, rule)
        out[f"income_{t}"] = contribution.map(income_map)

    q = rc["questionnaire"]
    quest = read_table(p["raw"] / files["questionnaire"], id_col, prefixes=list(q.values())).reindex(people.index)
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
            out[f"{name}_{t}"] = period_value(yearly, name, years, rule)

    # Self-reported history: a missing answer in a year the person was examined counts as "no".
    for feature, prefix in rc["history"].items():
        cols = []
        for y in exam_years:
            v = numeric(screen, f"{prefix}_{y}")
            examined = numeric(screen, f"{bmi_prefix}_{y}").notna()
            cols.append(v.mask(examined & v.isna(), 0.0))
        out[feature] = pd.concat(cols, axis=1).max(axis=1)

    family = read_table(p["raw"] / files["family"], id_col,
                        prefixes=[*rc["family"].values(), rc["family_flag"]]).reindex(people.index)
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
    log.info("cohort: %d people, %d cases", len(out), int(out[label_col].sum()))
    return out
