"""Write small synthetic tables in the NHIS layout to try the pipeline without NHIS data.

All values are simulated with a planted risk signal; none come from NHIS data.

    python scripts/make_toy_data.py                 # 20,000 people -> data/toy/raw
    python scripts/make_toy_data.py --n 50000 --out data/toy/raw
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

EXAM_YEARS = range(2010, 2016)
CANCER_YEARS = range(2007, 2022)
CLAIM_YEARS = range(2007, 2016)
NOISE_CODES = ["J209", "M545", "K297", "H520", "N390", "J0390", "R51"]
CONDITION_CODES = {"hbv": "B181", "hcv": "B182", "cirrhosis": "K7469", "ald": "K700",
                   "masld": "K760", "cryptogenic": "K754"}


def main(n: int, out: Path, seed: int) -> None:
    rng = np.random.default_rng(seed)
    out.mkdir(parents=True, exist_ok=True)
    (out / "t20").mkdir(exist_ok=True)
    ids = np.array([f"TOY{i:07d}" for i in range(n)])
    sex = rng.choice([1, 2], n, p=[0.45, 0.55])
    male = sex == 1
    byear = rng.integers(1941, 1965, n)  # a few fall outside age 50-69 in 2012
    age = 2016 - byear
    cond = {"hbv": rng.random(n) < 0.04, "hcv": rng.random(n) < 0.01, "cirrhosis": rng.random(n) < 0.01,
            "ald": rng.random(n) < 0.015, "masld": rng.random(n) < 0.10, "cryptogenic": rng.random(n) < 0.003}
    family_liver = rng.random(n) < 0.03
    heavy_drinker = rng.random(n) < np.where(male, 0.15, 0.03)

    logit = (-4.3 + 2.2 * cond["hbv"] + 1.8 * cond["hcv"] + 2.5 * cond["cirrhosis"] + 1.0 * cond["ald"]
             + 0.8 * family_liver + 0.06 * (age - 62) + 0.9 * male + 0.5 * heavy_drinker)
    liver = rng.random(n) < 1 / (1 + np.exp(-logit))
    other_cancer = ~liver & (rng.random(n) < 0.04)
    prior_cancer = rng.random(n) < 0.03

    # ---- cancer / demographics table -------------------------------------------------
    cancer = pd.DataFrame({"INDI_DSCM_NO": ids, "SEX_TYPE": sex, "BYEAR": byear})
    ctrb = rng.integers(0, 21, n)
    for y in range(2006, 2017):
        cancer[f"CTRB_ {y}"] = np.clip(ctrb + rng.integers(-1, 2, n), 0, 20)  # NHIS export has a space here
    for y in CANCER_YEARS:
        cancer[f"all_cancer_{y}"] = 0
        cancer[f"liver_sex_{y}"] = 0
    onset = rng.integers(2016, 2021, n)
    for i in np.where(liver)[0]:
        cancer.loc[i, [f"all_cancer_{onset[i]}", f"liver_sex_{onset[i]}"]] = 1
    for i in np.where(other_cancer)[0]:
        cancer.loc[i, f"all_cancer_{onset[i]}"] = 1
    for i in np.where(prior_cancer)[0]:
        cancer.loc[i, f"all_cancer_{rng.integers(2007, 2016)}"] = 1
    death = np.full(n, "", dtype=object)
    early, later = rng.random(n) < 0.005, rng.random(n) < 0.02
    for i in np.where(early | later)[0]:
        y = rng.integers(2014, 2016) if early[i] else rng.integers(2016, 2021)
        death[i] = f"{y}{rng.integers(1, 13):02d}{rng.integers(1, 29):02d}"
    cancer["DTH_ASSMD_DT"] = death
    cancer.to_csv(out / "target_cancer.csv", index=False)

    # ---- screening, questionnaire, family history --------------------------------------
    attend = rng.random((n, 6)) < 0.6
    for k in range(3):  # most people attend at least once per two-year period
        miss = ~attend[:, 2 * k] & ~attend[:, 2 * k + 1] & (rng.random(n) < 0.9)
        attend[miss, 2 * k] = True
    screen = pd.DataFrame({"INDI_DSCM_NO": ids})
    quest = pd.DataFrame({"INDI_DSCM_NO": ids})
    family = pd.DataFrame({"INDI_DSCM_NO": ids})
    base = {"bmi": rng.normal(24, 3, n), "hgb": rng.normal(np.where(male, 14.8, 13.0), 1.1),
            "fbs": rng.normal(100, 18, n) + 15 * cond["masld"], "wstc": rng.normal(82, 8, n),
            "chol": rng.normal(198, 36, n), "hdl": rng.normal(55, 13, n)}
    smoke = np.where(male, rng.choice([1, 2, 3], n, p=[0.4, 0.3, 0.3]), rng.choice([1, 2, 3], n, p=[0.9, 0.05, 0.05]))
    ever = {k: rng.random(n) < p for k, p in
            {"stork": 0.02, "heart": 0.05, "hyper": 0.35, "diabetes": 0.13, "lipid": 0.15}.items()}
    for j, y in enumerate(EXAM_YEARS):
        a = attend[:, j]
        nan = lambda v: np.where(a, v, np.nan)  # noqa: E731
        if y != 2013:  # the NHIS extract had no attendance flag for 2013; BMI is used instead
            screen[f"check_g1eq_{y}"] = np.where(a, 1, np.nan)
        drift = -4.0 * (j - 2.5) * liver  # cholesterol falls before diagnosis (planted temporal signal)
        screen[f"G1E_BMI_{y}"] = nan(np.round(base["bmi"] + rng.normal(0, 0.5, n), 1))
        screen[f"G1E_HGB_{y}"] = nan(np.round(base["hgb"] + rng.normal(0, 0.4, n), 1))
        screen[f"G1E_FBS_{y}"] = nan(np.round(base["fbs"] + rng.normal(0, 6, n)))
        screen[f"G1E_WSTC_{y}"] = nan(np.round(base["wstc"] + rng.normal(0, 1.5, n)))
        screen[f"G1E_TOT_CHOL_{y}"] = nan(np.round(base["chol"] + drift + rng.normal(0, 10, n)))
        hdl = base["hdl"] + rng.normal(0, 4, n)
        screen[f"G1E_HDL_{y}"] = nan(np.where(rng.random(n) < 0.02, np.nan, np.round(hdl)))
        screen[f"smoke_f_{y}"] = nan(smoke)
        for k, flag in ever.items():
            answer = np.where(rng.random(n) < 0.05, np.nan, (flag & (rng.random(n) < 0.8)).astype(float))
            screen[f"{k}_{y}"] = nan(answer)
        freq = np.where(heavy_drinker, rng.integers(3, 8, n), rng.choice(range(8), n, p=[.5, .15, .12, .08, .06, .04, .03, .02]))
        amount = np.where(freq == 0, np.nan, np.where(heavy_drinker, rng.integers(5, 15, n), rng.integers(1, 6, n)))
        quest[f"Q_DRK_FRQ_V09N_{y}"] = nan(freq)
        quest[f"Q_DRK_AMT_V09N_{y}"] = nan(amount)
        quest[f"Q_PA_VD_{y}"] = nan(rng.integers(0, 8, n))
        quest[f"Q_PA_MD_{y}"] = nan(rng.integers(0, 8, n))
        family[f"check_{y}"] = np.where(a, 1, np.nan)
        family[f"f_clv_{y}"] = nan(np.where(rng.random(n) < 0.1, np.nan, family_liver.astype(float)))
        family[f"f_clv_other_{y}"] = nan((rng.random(n) < 0.12).astype(float))
    screen.to_csv(out / "target_g1eq.csv", index=False)
    quest.to_csv(out / "g1eq_total.csv", index=False)
    family.to_csv(out / "target_cq.csv", index=False)

    # ---- claims (diagnosis codes) ----------------------------------------------------------
    first_year = {k: rng.integers(2007, 2016, n) for k in CONDITION_CODES}
    for y in CLAIM_YEARS:
        rows = []
        counts = rng.poisson(1.5, n)
        for i in range(n):
            codes = list(rng.choice(NOISE_CODES, counts[i]))
            codes += [code for k, code in CONDITION_CODES.items() if cond[k][i] and first_year[k][i] <= y]
            for code in codes:
                dx = [code] + list(rng.choice(NOISE_CODES, 4))
                rng.shuffle(dx)
                rows.append([ids[i], *dx, f"{y}{rng.integers(1, 13):02d}{rng.integers(1, 29):02d}"])
        cols = ["INDI_DSCM_NO", "SICK_SYM1", "SICK_SYM2", "SICK_SYM3", "SICK_SYM4", "SICK_SYM5", "MDCARE_STRT_DT"]
        pd.DataFrame(rows, columns=cols).to_csv(out / "t20" / f"t20_{y}.csv", index=False)
    print(f"synthetic tables for {n} people -> {out}  (planted liver cancer cases: {liver.sum()})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=20000)
    ap.add_argument("--out", type=Path, default=Path("data/toy/raw"))
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    main(args.n, args.out, args.seed)
