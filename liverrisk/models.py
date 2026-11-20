"""Neural networks (Fig. 1, Methods S2).

MLP          : flat feature vector -> risk logit (baseline "MLP").
FusionModel  : static features -> MLP encoder; temporal features (variables x time points)
               -> 1D CNN encoder -> global average pooling over time; both embeddings are
               concatenated and passed to an MLP classifier (the "fusion model").
"""
from __future__ import annotations

import torch
from torch import nn


def activation(name: str) -> nn.Module:
    return getattr(nn, name)()


class MLP(nn.Module):
    """Fully connected stack. With an integer depth the hidden width halves at every layer."""

    def __init__(self, in_dim: int, out_dim: int | None = 1, fc_depth: int | list[int] = 2,
                 fc_hidden: int = 128, dropout: float = 0.0, batch_norm: bool = False,
                 fc_activation: str = "ReLU", last_act: str | None = None):
        super().__init__()
        sizes = [fc_hidden // (2 ** i) for i in range(fc_depth)] if isinstance(fc_depth, int) else list(fc_depth)
        if out_dim is not None:
            sizes.append(out_dim)
        layers: list[nn.Module] = []
        width = in_dim
        for i, size in enumerate(sizes):
            layers.append(nn.Linear(width, size))
            if batch_norm:
                layers.append(nn.BatchNorm1d(size))
            if i < len(sizes) - 1:
                layers.append(activation(fc_activation))
                if dropout > 0:
                    layers.append(nn.Dropout(dropout))
            elif last_act is not None:
                layers.append(activation(last_act))
            width = size
        self.net = nn.Sequential(*layers)
        self.out_features = width

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


class ResidualBlock(nn.Module):
    """Two 1D convolutions with a skip connection (1x1 conv when the channel count changes)."""

    def __init__(self, in_channels: int, out_channels: int, kernel_size: int, padding: int = 0,
                 batch_norm: bool = False, dropout: float = 0.0, act: str = "ReLU"):
        super().__init__()
        self.conv1 = nn.Conv1d(in_channels, out_channels, kernel_size, padding=padding, bias=not batch_norm)
        self.conv2 = nn.Conv1d(out_channels, out_channels, kernel_size, padding=padding, bias=not batch_norm)
        self.bn1 = nn.BatchNorm1d(out_channels) if batch_norm else nn.Identity()
        self.bn2 = nn.BatchNorm1d(out_channels) if batch_norm else nn.Identity()
        self.dropout = nn.Dropout(dropout) if dropout > 0 else nn.Identity()
        self.shortcut = (
            nn.Sequential(
                nn.Conv1d(in_channels, out_channels, kernel_size=1, bias=not batch_norm),
                nn.BatchNorm1d(out_channels) if batch_norm else nn.Identity(),
            )
            if in_channels != out_channels
            else nn.Identity()
        )
        self.act1 = activation(act)
        self.act2 = activation(act)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = self.shortcut(x)
        x = self.dropout(self.act1(self.bn1(self.conv1(x))))
        x = self.bn2(self.conv2(x))
        return self.act2(x + residual)


class FusionModel(nn.Module):
    def __init__(self, stat_feat_n: int, time_feat_n: int, num_classes: int = 1,
                 cnn_channels: int = 64, cnn_kernel_size: int = 3, cnn_depth: int = 2,
                 cnn_dropout: float = 0.0, cnn_batch_norm: bool = False, use_residual: bool = False,
                 cnn_activation: str = "ReLU", fc_static_depth: int = 2, fc_static_hidden: int = 128,
                 fc_combined_depth: int = 2, fc_combined_hidden: int = 128, fc_activation: str = "ReLU",
                 fc_dropout: float = 0.0, fc_batch_norm: bool = False, last_act: str | None = None):
        super().__init__()
        static_sizes = (
            [fc_static_hidden // (2 ** i) for i in range(fc_static_depth)]
            if isinstance(fc_static_depth, int) else list(fc_static_depth)
        )
        self.static_encoder = MLP(stat_feat_n, out_dim=None, fc_depth=static_sizes, dropout=fc_dropout,
                                  batch_norm=fc_batch_norm, fc_activation=fc_activation, last_act=fc_activation)

        blocks: list[nn.Module] = []
        channels = time_feat_n
        for _ in range(cnn_depth):
            if use_residual:
                blocks.append(ResidualBlock(channels, cnn_channels, cnn_kernel_size, padding=cnn_kernel_size // 2,
                                            batch_norm=cnn_batch_norm, dropout=cnn_dropout, act=cnn_activation))
            else:
                blocks.append(nn.Conv1d(channels, cnn_channels, cnn_kernel_size, padding=cnn_kernel_size // 2))
                if cnn_batch_norm:
                    blocks.append(nn.BatchNorm1d(cnn_channels))
                blocks.append(activation(cnn_activation))
                if cnn_dropout > 0:
                    blocks.append(nn.Dropout(cnn_dropout))
            channels = cnn_channels
        self.temporal_encoder = nn.Sequential(*blocks)

        self.classifier = MLP(static_sizes[-1] + cnn_channels, out_dim=num_classes, fc_depth=fc_combined_depth,
                              fc_hidden=fc_combined_hidden, dropout=fc_dropout, batch_norm=fc_batch_norm,
                              fc_activation=fc_activation, last_act=last_act)

    def forward(self, static_x: torch.Tensor, temporal_x: torch.Tensor) -> torch.Tensor:
        s = self.static_encoder(static_x)                      # (B, static_sizes[-1])
        t = self.temporal_encoder(temporal_x).mean(dim=-1)    # (B, C, T) -> (B, cnn_channels)
        return self.classifier(torch.cat([s, t], dim=1))
