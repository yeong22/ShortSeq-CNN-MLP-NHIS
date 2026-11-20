"""Liver cancer risk prediction from Korean national health screening data.

    python main.py --step build                         # NHIS tables -> analytic cohort
    python main.py --step split                         # 80/20 patient-level split
    python main.py --step train --model fusion          # train (default: main window t1+t2+t3)
    python main.py --step train --model all --window all
    python main.py --step evaluate                      # metrics, DeLong, KNKPC, risk quintiles
    python main.py --step explain                       # SHAP for the fusion model
    python main.py --step all --config configs/toy.yaml # everything, on synthetic data
"""
from __future__ import annotations

import argparse
import logging

import torch

from liverrisk.utils import load_config, set_seed, windows_from_arg

STEPS = ["build", "split", "train", "evaluate", "explain"]
MODELS = ["lr", "xgb", "mlp", "fusion"]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default="configs/default.yaml")
    ap.add_argument("--step", required=True, choices=STEPS + ["all"])
    ap.add_argument("--model", default="all", choices=MODELS + ["all"])
    ap.add_argument("--window", default="main", help="t3, t2+t3, t1+t2+t3, t1, t2, t1+t2, main, or all")
    ap.add_argument("--search", action="store_true", help="re-run the group-wise hyperparameter search")
    ap.add_argument("--device", default="auto", help="auto, cpu, cuda, cuda:1, mps")
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    cfg = load_config(args.config)
    set_seed(cfg["seed"])
    device = torch.device(("cuda" if torch.cuda.is_available() else "cpu") if args.device == "auto" else args.device)
    steps = STEPS if args.step == "all" else [args.step]
    models = MODELS if args.model == "all" else [args.model]
    windows = windows_from_arg(cfg, args.window)

    if "build" in steps:
        from liverrisk.cohort import build_cohort
        build_cohort(cfg)
    if "split" in steps:
        from liverrisk.split import split_cohort
        split_cohort(cfg)
    if "train" in steps:
        from liverrisk.train import run_train
        run_train(cfg, models, windows, args.search, device)
    if "evaluate" in steps:
        from liverrisk.evaluate import run_evaluate
        run_evaluate(cfg)
    if "explain" in steps:
        from liverrisk.explain import run_explain
        run_explain(cfg, device)


if __name__ == "__main__":
    main()
