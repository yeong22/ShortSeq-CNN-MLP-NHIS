# Notes on reproducibility

Data preparation follows the original analysis notebooks, so the cohort and predictors match the published models; training and evaluation follow the paper's Methods. A run on the NHIS data may therefore not match every published number.

| Topic | Original notebooks | This code |
|---|---|---|
| Train/test split | best of five seeds, chosen by LR test AUROC | one seeded stratified split |
| Early stopping | fusion monitored the test set (≤300 epochs, last-epoch weights kept); the MLP ran all 200 epochs | validation split, ≤100 epochs, best-epoch weights (Methods S2) |
| Final fit | refit on the full training set after the search | 80% of the training set; 20% for early stopping, search and cutoff |
| Hyperparameter search | one 80/20 split per window (the paper says five-fold CV) | Table S4 values for every window; `--search` tunes each window on the 20% split |
| LR/XGBoost window features | the five shorter windows indexed columns by position in a differently ordered table | selected by name; those five Table S7 rows may not reproduce (main window unaffected) |
| Value per screening period | first exam of the interval (the paper says the most recent) | first exam; `cohort.period_value: last` follows the paper |
| Alcohol and activity classes | cut-offs <1, <2, <4 (Table S3 words them as ≤1, ≤2, ≤4) | notebook cut-offs; the SAS Cox covariates use Table S3's |
| ICD-10 code lists | Table S2 prints a few codes differently; MASLD includes I10 | notebook lists |
| Household income | contribution levels 10 and 16 unassigned (treated as missing) | same; Table S1's missing counts suggest the published cohort may have kept them |
| Complete cases | also required some non-model columns (e.g. a stomach-cancer screening result) | model predictors only, so the cohort can be slightly larger |
| Follow-up | 2016–2020, as in Fig. 1 (the text says to 2021) | 2016–2020 |
| Risk quintiles | groups of unequal size; crude cases per 100,000 | equal-size quintiles; crude and Kaplan–Meier incidence |
| 95% CIs | method not stated in the paper | percentile bootstrap |
| SHAP | DeepExplainer treated SiLU layers as plain gradients (approximate) | exact rescale rule for SiLU (`explain.silu_rule: gradient` restores the original) |
| Calibration | not in the paper; a later notebook fit and scored it on the test set | fit on validation, scored on test |
| Fine-Gray (Table S9) | SAS, not released | not included |
