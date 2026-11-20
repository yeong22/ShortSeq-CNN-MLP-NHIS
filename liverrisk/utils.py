"""Config loading, paths, seeds."""
from __future__ import annotations

import copy
import logging
import random
from pathlib import Path

import numpy as np
import yaml

log = logging.getLogger("liverrisk")


def _merge(base: dict, override: dict) -> dict:
    out = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def load_config(path: str | Path) -> dict:
    """Read a YAML config. A config with `inherit: other.yaml` is merged on top of that file."""
    path = Path(path)
    cfg = yaml.safe_load(path.read_text())
    parent = cfg.pop("inherit", None)
    if parent:
        cfg = _merge(load_config(path.parent / parent), cfg)
    return cfg


def paths(cfg: dict) -> dict[str, Path]:
    p = cfg["paths"]
    out = {
        "raw": Path(p["raw_dir"]),
        "processed": Path(p["processed_dir"]),
        "output": Path(p["output_dir"]),
    }
    out["models"] = out["output"] / "models"
    out["predictions"] = out["output"] / "predictions"
    out["results"] = out["output"] / "results"
    out["figures"] = out["output"] / "figures"
    return out


def ensure_dirs(*dirs: Path) -> None:
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    try:
        import torch

        torch.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)
    except ImportError:
        pass


def windows_from_arg(cfg: dict, arg: str) -> list[str]:
    names = list(cfg["features"]["windows"])
    if arg == "all":
        return names
    if arg == "main":
        return [cfg["features"]["main_window"]]
    if arg not in names:
        raise ValueError(f"--window must be one of {names + ['main', 'all']}, got {arg!r}")
    return [arg]
