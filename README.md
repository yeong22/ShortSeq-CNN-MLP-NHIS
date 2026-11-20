[BMC Med Inform Decis Mak 2026] Liver Cancer Risk Stratification Using Deep Learning on Nationwide Longitudinal Health Screening Data
=================================================================================================================================

📄 [Paper](https://doi.org/10.1186/s12911-025-03323-x) &nbsp; 📑 [Supplementary](https://doi.org/10.1186/s12911-025-03323-x) (Additional file 1 on the article page)

Korea's liver cancer surveillance targets people with viral hepatitis or cirrhosis, but a growing share of new cases comes from metabolic and alcohol-related liver disease. We built a **fusion model** that reads three biennial health screenings (2010–2015) with a 1D CNN and static predictors with an MLP, and predicts 5-year liver cancer risk for **3,962,209** adults aged 50–69 using only data the national screening program already collects. On the held-out test set it reached an AUROC of **0.810** and a sensitivity of **0.736**, against **0.552** and **0.112** for the current surveillance criteria (KNKPC). The highest-risk quintile held **65%** of incident cases with a **27-fold** hazard compared with the lowest.

<p align="center">
  <a href="imgs/workflow.jpg"><img src="imgs/workflow.jpg" width="90%"></a><br>
  <em>Study workflow (Fig. 1 of the paper).</em>
</p>

## Quick Start

Create an environment and install the packages:
```bash
conda create -n liverrisk python=3.10 -y
conda activate liverrisk
pip install -r requirements.txt
```

Run the whole pipeline on **synthetic** data (about 3 minutes on a laptop CPU):
```bash
python scripts/make_toy_data.py
python main.py --step all --window all --config configs/toy.yaml
```
Results go to `outputs/toy/`. The synthetic tables have a made-up risk signal, so their numbers say nothing about real liver cancer risk.

## Data

The study used the Korean National Health Insurance Service (NHIS) database, which cannot be shared. Qualified researchers can apply at [nhiss.nhis.or.kr](https://nhiss.nhis.or.kr/). Put the NHIS tables here:
```
data/raw/
├── target_cancer.csv     # demographics, insurance contribution, yearly cancer flags, death
├── target_g1eq.csv       # health screening results, self-reported history
├── g1eq_total.csv        # questionnaire (alcohol, exercise)
├── target_cq.csv         # family history of cancer
└── t20/t20_2007.csv ... t20_2015.csv   # claims with ICD-10 codes
```
Columns, coding and how each predictor is derived: [data/README.md](data/README.md).

## Usage

All settings (cohort years, ICD-10 codes, feature lists, hyperparameters) are in [configs/default.yaml](configs/default.yaml).

| Step | Command | What it does |
|---|---|---|
| 1 | `python main.py --step build` | NHIS tables → analytic cohort (`data/processed/cohort.csv`) and flowchart counts |
| 2 | `python main.py --step split` | 80/20 patient-level split, stratified by outcome, age decade and sex |
| 3 | `python main.py --step train --model all` | LR, XGBoost, MLP, fusion model with the Table S4 hyperparameters |
| 4 | `python main.py --step evaluate` | AUROC / AUPRC / sensitivity / specificity with 95% CIs, DeLong tests, KNKPC rule, risk quintiles, calibration |
| 5 | `python main.py --step explain` | SHAP values for the fusion model |

Useful options:
```bash
python main.py --step train --model fusion --window t3        # one observation window
python main.py --step train --model all --window all          # sensitivity analysis (Table S7)
python main.py --step train --model fusion --search           # re-run the group-wise hyperparameter search
python main.py --step train --model fusion --device cuda:1
```
Windows: `t1` (2010–11), `t2` (2012–13), `t3` (2014–15), `t1+t2`, `t2+t3`, `t1+t2+t3` (main analysis).

## Models

| Model | Input | Class imbalance |
|---|---|---|
| KNKPC | rule: flagged if HBV, HCV or cirrhosis (2022 KLCA–NCC surveillance targets) | – |
| LR | all predictors as one vector | balanced class weights |
| XGBoost | all predictors as one vector | `scale_pos_weight` |
| MLP | all predictors as one vector | asymmetric focal loss |
| **Fusion** | static predictors → MLP; temporal predictors (10 variables × time points) → 1D CNN with residual blocks; concatenated → MLP classifier | asymmetric focal loss |

Static predictors (15): age, sex, history of stroke, heart disease, hypertension, diabetes, dyslipidemia, HBV, HCV, ALD, MASLD, cryptogenic liver disease, cirrhosis, family history of liver and other cancers.
Temporal predictors (10 per screening period): BMI, hemoglobin, fasting glucose, waist circumference, total cholesterol, HDL cholesterol, alcohol, physical activity, smoking, household income.

All models are fit on 80% of the training set. The other 20% is used for early stopping (validation loss), the hyperparameter search and the Youden cutoff. The test set is used only in the evaluate step.

## Main Results

Test set, main window t1+t2+t3, as reported in the paper (Table S7; n = 792,442, 2,480 cases).

| Model | AUROC (95% CI) | AUPRC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|
| KNKPC | 0.552 (0.545–0.558) | 0.007 (0.006–0.008) | 0.113 (0.099–0.125) | 0.991 (0.991–0.991) |
| LR | 0.793 (0.784–0.803) | 0.022 (0.019–0.024) | 0.721 (0.704–0.739) | 0.727 (0.726–0.728) |
| XGBoost | 0.797 (0.788–0.806) | 0.025 (0.022–0.029) | 0.701 (0.684–0.719) | 0.753 (0.752–0.754) |
| MLP | 0.803 (0.793–0.811) | 0.028 (0.024–0.032) | 0.727 (0.710–0.744) | 0.731 (0.730–0.732) |
| **Fusion** | **0.810 (0.802–0.818)** | **0.029 (0.026–0.034)** | **0.736 (0.720–0.753)** | 0.732 (0.731–0.733) |

All AUROC differences from the fusion model: P < 0.001 (DeLong).

<p align="center">
  <a href="imgs/performance.jpg"><img src="imgs/performance.jpg" width="95%"></a><br>
  <em>(A) ROC curves. (B) 5-year cumulative liver cancer risk by predicted-risk quintile (Fig. 2 of the paper).</em>
</p>

| Risk quintile | Cases | 5-year incidence per 100,000 | Hazard ratio (95% CI) |
|---|---|---|---|
| Q1 | 62 | 38.8 | 1.00 (reference) |
| Q2 | 130 | 77.2 | 1.99 (1.47–2.70) |
| Q3 | 220 | 145.8 | 3.77 (2.84–5.00) |
| Q4 | 457 | 286.4 | 7.42 (5.69–9.68) |
| Q5 | 1,611 | 1,047.2 | 27.42 (21.28–35.34) |

## Sensitivity Analysis: Observation Windows

AUROC on the test set by which screening periods the models see (Table S7).

| Window | LR | XGBoost | MLP | Fusion |
|---|---|---|---|---|
| t1 | 0.758 | 0.767 | 0.785 | 0.784 |
| t2 | 0.761 | 0.765 | 0.792 | 0.792 |
| t3 | 0.765 | 0.768 | 0.796 | 0.794 |
| t1+t2 | 0.776 | 0.782 | 0.797 | 0.800 |
| t2+t3 | 0.785 | 0.793 | 0.803 | 0.808 |
| **t1+t2+t3** | 0.793 | 0.797 | 0.803 | **0.810** |

Using all three screenings works best, and the most recent single screening (t3) beats the earlier ones.

## Interpretability

<p align="center">
  <a href="imgs/shap.jpg"><img src="imgs/shap.jpg" width="95%"></a><br>
  <em>Mean |SHAP| and beeswarm plot for the fusion model (Fig. 3 of the paper).</em>
</p>

HBV, family history of liver cancer, sex and total cholesterol at t3 contribute most. The Cox models for Table 2 and Table S8 are in [stats/table1_cox.sas](stats/table1_cox.sas) (SAS 9.4; reads `cohort.csv` from the build step).

## Repository Structure
```
├── main.py                  # one entry point: --step build | split | train | evaluate | explain | all
├── configs/
│   ├── default.yaml         # every setting used in the paper
│   └── toy.yaml             # small, fast settings for the synthetic data
├── liverrisk/
│   ├── cohort.py            # inclusion/exclusion, outcome, predictors, ICD-10 history
│   ├── split.py             # stratified patient-level split
│   ├── features.py          # observation windows, scaling and encoding (Methods S1)
│   ├── models.py            # MLP, residual 1D CNN, fusion model (Methods S2)
│   ├── losses.py            # asymmetric focal loss
│   ├── train.py             # training, early stopping, group-wise search
│   ├── evaluate.py          # CIs, DeLong, KNKPC, risk quintiles, calibration
│   └── explain.py           # SHAP
├── stats/table1_cox.sas     # Table 1, person-years, Cox models, VIF
├── scripts/make_toy_data.py # synthetic NHIS-like tables
├── data/README.md           # data access and column definitions
└── imgs/                    # figures from the paper
```

## Notes on Reproducibility

This code follows the procedure described in the paper. The original analysis notebooks differed in a few places, so a run on the NHIS data may not match the published numbers exactly.

- **Early stopping**: the notebooks monitored the test set during the final training of the MLP and fusion model. Here a validation split of the training set is used, as described in Methods S2.
- **Train/test split**: the notebooks drew five stratified splits and kept the one where logistic regression had the highest test AUROC. Here a single seeded stratified split is used.
- **Hyperparameter search**: run on one 80/20 split of the training set, not five-fold cross-validation as stated in the Methods. The defaults are the final values in Table S4.
- **Follow-up**: outcomes are counted from 2016 through 2020 (five years, Fig. 1). The main text gives December 31, 2021.
- **Income**: insurance contribution levels 10 and 16 were not assigned to an income group and are treated as missing (`cohort.income_groups` in the config).
- **Written from the Methods**: bootstrap CIs, DeLong tests, the KNKPC rule, and the risk-quintile Kaplan–Meier and Cox analysis. The Fine-Gray model (Table S9) is not included.

## Citation
```bibtex
@article{choi2026liver,
  title   = {Liver cancer risk stratification using deep learning on nationwide longitudinal health screening data: a retrospective cohort study},
  author  = {Choi, Yewon and Cho, Sungmin and Gu, Changdai and Kim, Chungho and Park, Bomi and Kim, Hwiyoung},
  journal = {BMC Medical Informatics and Decision Making},
  volume  = {26},
  pages   = {44},
  year    = {2026},
  doi     = {10.1186/s12911-025-03323-x}
}
```

## Funding
National R&D Program for Cancer Control, Ministry of Health and Welfare, Republic of Korea (HA23C0083); Technology Innovation Program (RS-2025-02220286), Ministry of Trade, Industry & Resources, Korea.

## Contact
Yewon Choi. For questions about the code, please open an issue.

## License
Figures in `imgs/` are from the paper, © The Author(s), licensed under [CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/).
