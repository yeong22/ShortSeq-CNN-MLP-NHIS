# Use it on your own EHR / EMR data

The models need one row per patient. Put the table at `data/processed/cohort.csv` and start from `--step split`; the NHIS-specific build step is skipped.

| Column | Example | Notes |
|---|---|---|
| `id` | `P0001` | patient identifier |
| outcome | `outcome` = 0 / 1 | event in the prediction window; name it in `label_column` |
| static predictors | `age`, `sex`, `diabetes` | listed in `features.static_continuous` and `features.static_binary` |
| repeated predictors | `sbp_t1`, `sbp_t2`, `sbp_t3` | `<variable>_<time point>`; variables in `features.temporal_continuous` / `temporal_ordinal`, time points in `cohort.periods` |
| `fu_years` (optional) | `4.2` | follow-up time; enables Kaplan–Meier and Cox by risk quintile |

Copy `configs/default.yaml` to `configs/mydata.yaml` and edit these keys:
```yaml
label_column: outcome
cohort:
  periods: {t1: [], t2: [], t3: []}     # names of your time points (oldest first); the years are not used
features:
  temporal_continuous: [sbp, hba1c, egfr]
  temporal_ordinal: [smoking]
  static_continuous: [age]
  static_binary: [sex, diabetes]
  windows: {full: [t1, t2, t3]}
  main_window: full
split:
  stratify_on: [outcome, sex]
evaluate:
  knkpc_markers: []                     # the KNKPC baseline is specific to liver cancer
```

```bash
python main.py --config configs/mydata.yaml --step split
python main.py --config configs/mydata.yaml --step train --model all --search
python main.py --config configs/mydata.yaml --step evaluate
python main.py --config configs/mydata.yaml --step explain
```
