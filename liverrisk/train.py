"""Step 3: train LR, XGBoost, MLP and the fusion model for each observation window.

Paper: Methods > Model development and validation; Table S4; Methods S2.

The training set is split once more (80/20, stratified on the outcome). Every model is fit on
the 80% part; the 20% part is used for early stopping, hyperparameter search (--search) and for
choosing the classification cutoff. The test set is never used for fitting, early stopping,
tuning or the cutoff; its predictions are only written out for the evaluate step.

In:  <processed_dir>/train.csv, test.csv
Out: <output_dir>/models/{model}__{window}.*, preprocessor.json
     <output_dir>/predictions/{model}__{window}.csv  (id, split, y, prob for valid and test rows)
"""
from __future__ import annotations

import copy
import json
import math
import pickle
from itertools import product

import numpy as np
import pandas as pd
import torch
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, TensorDataset
from xgboost import XGBClassifier

from .features import Preprocessor, to_arrays, window_spec
from .losses import AsymmetricLoss
from .models import MLP, FusionModel
from .split import read_cohort
from .utils import ensure_dirs, log, paths

SKLEARN_MODELS = ("lr", "xgb")
TORCH_MODELS = ("mlp", "fusion")
OPTIM_KEYS = ("optimizer", "learning_rate", "batch_size")
LOSS_KEYS = ("gamma_pos", "gamma_neg", "margin")


# ----------------------------------------------------------------------------- sklearn
def make_sklearn(name: str, params: dict, y_train: np.ndarray, seed: int):
    params = dict(params)
    if name == "lr":
        return LogisticRegression(random_state=seed, **params)
    if params.get("scale_pos_weight") == "auto":
        params["scale_pos_weight"] = float((y_train == 0).sum() / max((y_train == 1).sum(), 1))
    return XGBClassifier(random_state=seed, n_jobs=-1, **params)


def fit_sklearn(name, params, X_tr, y_tr, seed):
    model = make_sklearn(name, params, y_tr, seed)
    model.fit(X_tr, y_tr)
    return model


# ----------------------------------------------------------------------------- torch
def flat_params(model_cfg: dict) -> dict:
    return {**model_cfg["net"], **model_cfg["optim"], **model_cfg["loss"]}


def split_params(flat: dict) -> tuple[dict, dict, dict]:
    net = {k: v for k, v in flat.items() if k not in OPTIM_KEYS + LOSS_KEYS}
    optim = {k: flat[k] for k in OPTIM_KEYS}
    loss = {k: flat[k] for k in LOSS_KEYS}
    return net, optim, loss


def build_net(name: str, net: dict, spec: dict) -> torch.nn.Module:
    if name == "mlp":
        return MLP(in_dim=len(spec["flat"]), out_dim=1, **net)
    return FusionModel(stat_feat_n=len(spec["static"]), time_feat_n=len(spec["temporal"]), **net)


def inputs(name: str, arrays: dict) -> list[np.ndarray]:
    return [arrays["flat"]] if name == "mlp" else [arrays["static"], arrays["temporal"]]


def loader(xs: list[np.ndarray], y: np.ndarray | None, batch_size: int, shuffle: bool, workers: int) -> DataLoader:
    tensors = [torch.from_numpy(x) for x in xs]
    if y is not None:
        tensors.append(torch.from_numpy(y.astype(np.float32).reshape(-1, 1)))
    n = len(xs[0])
    return DataLoader(TensorDataset(*tensors), batch_size=batch_size, shuffle=shuffle, num_workers=workers,
                      pin_memory=torch.cuda.is_available(),
                      drop_last=shuffle and n % batch_size == 1)  # BatchNorm cannot take a batch of 1


@torch.no_grad()
def predict_torch(model, xs, batch_size, device, criterion=None, y=None):
    model.eval()
    probs, total, count = [], 0.0, 0
    for batch in loader(xs, y, batch_size, shuffle=False, workers=0):
        batch = [b.to(device) for b in batch]
        feats, target = (batch[:-1], batch[-1]) if y is not None else (batch, None)
        logits = model(*feats)
        probs.append(torch.sigmoid(logits).float().cpu().numpy().ravel())
        if criterion is not None:
            total += criterion(logits, target, reduction="none").sum().item()
            count += len(target)
    p = np.concatenate(probs)
    return (p, total / count) if criterion is not None else p


def fit_torch(name, flat, spec, data, train_cfg, schedule, max_epochs, patience, device, seed):
    """Train on data['train'], early-stop on validation loss, return the best-epoch model."""
    torch.manual_seed(seed)
    net_p, opt_p, loss_p = split_params(flat)
    model = build_net(name, net_p, spec).to(device)
    optimizer = getattr(torch.optim, opt_p["optimizer"])(model.parameters(), lr=opt_p["learning_rate"])
    scheduler = torch.optim.lr_scheduler.CosineAnnealingWarmRestarts(
        optimizer, T_0=schedule["T_0"], T_mult=schedule["T_mult"], eta_min=schedule["eta_min"])
    criterion = AsymmetricLoss(**loss_p)
    use_amp = bool(train_cfg["amp"]) and device.type == "cuda"
    scaler = torch.amp.GradScaler("cuda", enabled=use_amp)

    x_tr, y_tr = inputs(name, data["train"]["arrays"]), data["train"]["y"]
    x_va, y_va = inputs(name, data["valid"]["arrays"]), data["valid"]["y"]
    train_loader = loader(x_tr, y_tr, opt_p["batch_size"], shuffle=True, workers=train_cfg["num_workers"])

    best_loss, best_state, best_epoch, waited = math.inf, None, -1, 0
    history = []
    for epoch in range(max_epochs):
        model.train()
        running, seen = 0.0, 0
        for *feats, target in train_loader:
            # async copies are only safe from pinned memory, which the loader uses on CUDA alone
            asynchronous = device.type == "cuda"
            feats = [f.to(device, non_blocking=asynchronous) for f in feats]
            target = target.to(device, non_blocking=asynchronous)
            optimizer.zero_grad(set_to_none=True)
            with torch.autocast(device_type=device.type, enabled=use_amp):
                loss = criterion(model(*feats), target)
            scaler.scale(loss).backward()
            if train_cfg["grad_clip"] > 0:
                scaler.unscale_(optimizer)
                torch.nn.utils.clip_grad_norm_(model.parameters(), train_cfg["grad_clip"])
            scaler.step(optimizer)
            scaler.update()
            running += loss.item() * len(target)
            seen += len(target)
        scheduler.step()
        prob_va, loss_va = predict_torch(model, x_va, opt_p["batch_size"], device, criterion, y_va)
        auc_va = roc_auc_score(y_va, prob_va) if 0 < y_va.sum() < len(y_va) else float("nan")
        history.append({"epoch": epoch + 1, "train_loss": running / seen, "valid_loss": loss_va, "valid_auroc": auc_va})
        log.info("  epoch %3d  train %.4f  valid %.4f  valid AUROC %.4f", epoch + 1, running / seen, loss_va, auc_va)
        if loss_va < best_loss:
            best_loss, best_state, best_epoch, waited = loss_va, copy.deepcopy(model.state_dict()), epoch + 1, 0
        else:
            waited += 1
            if waited >= patience:
                log.info("  early stop; best epoch %d", best_epoch)
                break
    model.load_state_dict(best_state)
    return model, {"best_epoch": best_epoch, "best_valid_loss": best_loss, "history": history}


# ----------------------------------------------------------------------------- search
def greedy_search(groups, candidates, start, score, maximize):
    """Group-wise search: try every combination within a group, keep the best, go to the next group."""
    best = dict(start)
    trials = []
    for group in groups:
        round_best, round_score = None, -math.inf if maximize else math.inf
        for combo in product(*(candidates[k] for k in group)):
            trial = {**best, **dict(zip(group, combo))}
            try:
                s = score(trial)
            except Exception as err:  # e.g. an invalid solver/penalty pair
                log.warning("  skip %s: %s", dict(zip(group, combo)), err)
                continue
            trials.append({"params": trial, "score": s})
            log.info("  %s -> %.4f", dict(zip(group, combo)), s)
            if (s > round_score) if maximize else (s < round_score):
                round_best, round_score = trial, s
        if round_best is not None:
            best = round_best
    return best, trials


# ----------------------------------------------------------------------------- driver
def _json_safe(obj):
    return json.loads(json.dumps(obj, default=lambda o: o.item() if hasattr(o, "item") else str(o)))


def prepare(cfg: dict):
    p = paths(cfg)
    train_df = read_cohort(p["processed"] / "train.csv")
    test_df = read_cohort(p["processed"] / "test.csv")
    pre = Preprocessor(cfg).fit(train_df)
    ensure_dirs(p["models"], p["predictions"])
    pre.save(p["models"] / "preprocessor.json")
    tr_idx, va_idx = train_test_split(np.arange(len(train_df)), test_size=cfg["split"]["valid_size"],
                                      stratify=train_df[cfg["label_column"]], random_state=cfg["split"]["valid_seed"])
    X_train = pre.transform(train_df)
    X_test = pre.transform(test_df)
    parts = {
        "train": (X_train.iloc[tr_idx], train_df.iloc[tr_idx]),
        "valid": (X_train.iloc[va_idx], train_df.iloc[va_idx]),
        "test": (X_test, test_df),
    }
    return parts


def run_train(cfg: dict, models: list[str], windows: list[str], search: bool, device: torch.device) -> None:
    p = paths(cfg)
    seed = cfg["seed"]
    label = cfg["label_column"]
    parts = prepare(cfg)
    for window in windows:
        spec = window_spec(cfg, window)
        data = {k: {"arrays": to_arrays(X, spec), "y": raw[label].to_numpy(), "id": raw["id"].to_numpy()}
                for k, (X, raw) in parts.items()}
        for name in models:
            log.info("== %s | window %s | %d features", name, window, len(spec["flat"]))
            tag = f"{name}__{window}"
            if name in SKLEARN_MODELS:
                params = dict(cfg["models"][name])
                # float64 as in the original notebook (newton-cg stops elsewhere in float32)
                X_tr, y_tr = data["train"]["arrays"]["flat"].astype(np.float64), data["train"]["y"]
                X_va, y_va = data["valid"]["arrays"]["flat"].astype(np.float64), data["valid"]["y"]
                if search:
                    sc = cfg["search"][name]
                    params, trials = greedy_search(
                        sc["groups"], sc["candidates"], params,
                        lambda prm: roc_auc_score(y_va, fit_sklearn(name, prm, X_tr, y_tr, seed).predict_proba(X_va)[:, 1]),
                        maximize=True)
                    (p["models"] / f"{tag}.search.json").write_text(json.dumps(_json_safe(trials), indent=1))
                model = fit_sklearn(name, params, X_tr, y_tr, seed)
                predict = lambda arr: model.predict_proba(arr["flat"].astype(np.float64))[:, 1]  # noqa: E731
                with open(p["models"] / f"{tag}.pkl", "wb") as fh:
                    pickle.dump(model, fh)
                info = {"params": params}
            else:
                flat = flat_params(cfg["models"][name])
                sched = cfg["models"][name]["schedule"]
                if search:
                    sc = cfg["search"][name]
                    epochs = cfg["search"]["torch_epochs"][name]
                    by_auroc = cfg["search"]["scoring"][name] == "auroc"  # notebooks: MLP by AUROC, fusion by loss

                    def score(prm):
                        info_ = fit_torch(name, prm, spec, data, cfg["train"], sched, epochs,
                                          cfg["search"]["torch_patience"], device, seed)[1]
                        if by_auroc:
                            return max(h["valid_auroc"] for h in info_["history"])
                        return info_["best_valid_loss"]

                    flat, trials = greedy_search(sc["groups"], sc["candidates"], flat, score, maximize=by_auroc)
                    (p["models"] / f"{tag}.search.json").write_text(json.dumps(_json_safe(trials), indent=1))
                model, info = fit_torch(name, flat, spec, data, cfg["train"], sched, cfg["train"]["max_epochs"],
                                        cfg["train"]["early_stopping_patience"], device, seed)
                net_p, opt_p, _ = split_params(flat)
                torch.save({"model": name, "window": window, "net_params": net_p, "spec": spec,
                            "state_dict": model.state_dict(), "params": flat}, p["models"] / f"{tag}.pt")
                predict = lambda arr: predict_torch(model, inputs(name, arr), opt_p["batch_size"], device)  # noqa: E731
                info["params"] = flat

            rows = []
            for split in ("valid", "test"):
                rows.append(pd.DataFrame({"id": data[split]["id"], "split": split,
                                          "y": data[split]["y"], "prob": predict(data[split]["arrays"])}))
            pd.concat(rows).to_csv(p["predictions"] / f"{tag}.csv", index=False)
            (p["models"] / f"{tag}.info.json").write_text(json.dumps(_json_safe(info), indent=1))
            valid = rows[0]
            log.info("   valid AUROC %.4f", roc_auc_score(valid["y"], valid["prob"]))
