"""Asymmetric loss for class imbalance (Methods S2).

Binary cross-entropy with separate focusing terms for positives (gamma_pos) and negatives
(gamma_neg), plus a probability margin that shifts negative predictions down so easy negatives
contribute little. With gamma_pos = gamma_neg and margin = 0 it reduces to focal loss.
"""
from __future__ import annotations

import torch
import torch.nn.functional as F
from torch import nn


class AsymmetricLoss(nn.Module):
    def __init__(self, gamma_pos: float = 0.0, gamma_neg: float = 1.0, margin: float = 0.2, eps: float = 1e-6):
        super().__init__()
        self.gamma_pos = gamma_pos
        self.gamma_neg = gamma_neg
        self.margin = margin
        self.eps = eps

    def forward(self, logits: torch.Tensor, target: torch.Tensor, reduction: str = "mean") -> torch.Tensor:
        logits, target = logits.float(), target.float()
        if self.margin > 0:
            p_neg = torch.clamp(torch.sigmoid(logits) - self.margin, min=self.eps)
            neg_logits = torch.log(p_neg) - torch.log(1 - p_neg)
        else:
            neg_logits = logits
        shifted = logits * target + neg_logits * (1 - target)
        bce = F.binary_cross_entropy_with_logits(shifted, target, reduction="none")
        p_t = torch.exp(-bce)
        gamma = self.gamma_pos * target + self.gamma_neg * (1 - target)
        loss = bce * (1 - p_t) ** gamma
        return loss.mean() if reduction == "mean" else loss
