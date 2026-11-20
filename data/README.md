# Data

The study used the Korean National Health Insurance Service (NHIS) database. The data cannot be
shared. Qualified researchers can apply through the NHIS data sharing service
(https://nhiss.nhis.or.kr/) and the NHIS Institutional Data Access / Ethics Committee.
Analyses run inside the NHIS environment; only aggregate results that pass NHIS export review
can be taken out.

To try the code without NHIS data, make synthetic tables in the same layout:

```bash
python scripts/make_toy_data.py          # writes data/toy/raw
```

## Expected layout

```
data/
├── raw/
│   ├── target_cancer.csv     # demographics, insurance contribution, yearly cancer flags, death
│   ├── target_g1eq.csv       # health screening results and self-reported history
│   ├── g1eq_total.csv        # questionnaire answers (alcohol, exercise)
│   ├── target_cq.csv         # family history of cancer
│   └── t20/
│       ├── t20_2007.csv      # claims, one file per year
│       ├── ...
│       └── t20_2015.csv
└── processed/                # written by the build and split steps
    ├── cohort.csv
    ├── train.csv
    └── test.csv
```

File names and column prefixes are set in `configs/default.yaml` (`raw_files`, `raw_columns`).
Yearly columns are named `<prefix>_<year>`, e.g. `G1E_BMI_2014`.

## Columns used

| File | Columns | Years |
|---|---|---|
| target_cancer.csv | `INDI_DSCM_NO`, `SEX_TYPE` (1 men, 2 women), `BYEAR`, `CTRB_<y>` (insurance contribution level 0–20), `all_cancer_<y>` and `liver_sex_<y>` (1 = diagnosed that year), `DTH_ASSMD_DT` (YYYYMMDD) | contribution 2010–2015; cancer 2007–2020 |
| target_g1eq.csv | `INDI_DSCM_NO`, `check_g1eq_<y>` (1 = attended), `G1E_BMI_<y>`, `G1E_HGB_<y>`, `G1E_FBS_<y>`, `G1E_WSTC_<y>`, `G1E_TOT_CHOL_<y>`, `G1E_HDL_<y>`, `smoke_f_<y>` (1 never, 2 former, 3 current), self-reported history `stork_<y>`, `heart_<y>`, `hyper_<y>`, `diabetes_<y>`, `lipid_<y>` (1 = yes) | 2010–2015 |
| g1eq_total.csv | `INDI_DSCM_NO`, `Q_DRK_FRQ_V09N_<y>` (drinking days/week), `Q_DRK_AMT_V09N_<y>` (drinks per occasion), `Q_PA_VD_<y>`, `Q_PA_MD_<y>` (vigorous / moderate exercise days/week) | 2010–2015 |
| target_cq.csv | `INDI_DSCM_NO`, `check_<y>` (answered that year), `f_clv_<y>` (family history of liver cancer), `f_clv_other_<y>` (other cancers) | 2010–2015 |
| t20/t20_<y>.csv | `INDI_DSCM_NO`, `SICK_SYM1`–`SICK_SYM5` (ICD-10 without dot), `MDCARE_STRT_DT` (YYYYMMDD) | 2007–2015 |

`liver_sex_<y>` is the sex-specific liver cancer definition: ICD-10 C22.0 or C22.9 as the
primary diagnosis for men, C22.0 for women. If a `diagnosis_date` column (YYYYMMDD) is present in
target_cancer.csv, it is used for follow-up time; otherwise the middle of the diagnosis year is used.
Death dates (`DTH_ASSMD_DT`) are read the same way.

## How each predictor is built (`liverrisk/cohort.py`)

| Predictor | Rule |
|---|---|
| Period value (t1 2010–11, t2 2012–13, t3 2014–15) | first exam in the period; the second year fills a missing first year, as in the analysis notebooks (`cohort.period_value: last` takes the most recent exam, as the paper words it) |
| Alcohol | drinks/day = days/week × drinks per occasion / 7 (a missing amount counts as 0 only when days/week is 0); 0, <1, <2, <4, ≥4 → 0–4 |
| Physical activity | (vigorous + moderate days/week) / 2; 0, <2, <4, ≥4 → 0–3 |
| Household income | contribution levels 17–20, 11–15, 5–9, 0–4 → four groups, 1 (highest) to 4; levels 10 and 16 are treated as missing, as in the notebooks |
| Self-reported history | ever reported 2010–2015; a blank answer in an exam year counts as no |
| Family history | ever reported 2010–2015; a blank answer in a year with a questionnaire counts as no |
| HBV, HCV, ALD, MASLD, cryptogenic liver disease, cirrhosis | any claim 2007–2015 with a code in `icd10` in any of the five diagnosis fields (the notebook lists; Table S2 prints a few codes differently) |
| Age | 2016 − birth year |
