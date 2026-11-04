"""Vẽ bản đồ (và bản đồ nhiệt sự kiện) thành hình matplotlib — dùng trong Streamlit và báo cáo."""
from __future__ import annotations

import matplotlib

matplotlib.use("Agg")                     # vẽ không cần màn hình (máy chủ, Colab, CI)
import matplotlib.pyplot as plt
import numpy as np

from .luoi import KICH_THUOC_O, BanDo

MAU = {"george": "#e3a008", "coin": "#ffd84d", "zombie": "#7eb86c", "skeleton": "#e8e6d8"}


def ve_ban_do(ban_do: BanDo, su_kien: list[dict] | None = None, tieu_de: str = ""):
    """Ô chặn màu tối, điểm xuất hiện có màu; `su_kien` (có x, y pixel) vẽ thành chấm đỏ mờ."""
    fig, ax = plt.subplots(figsize=(8, 6), dpi=100)
    ax.imshow(np.array(ban_do.chan, dtype=float), cmap="Greens", vmin=-0.3, vmax=1.4,
              extent=(0, ban_do.so_cot, ban_do.so_hang, 0))
    for ten, mau in MAU.items():
        diem = ban_do.cac_diem(ten)
        if diem:
            xs, ys = zip(*[(c + 0.5, h + 0.5) for c, h in diem])
            ax.scatter(xs, ys, s=60 if ten == "george" else 22, c=mau, edgecolors="black",
                       linewidths=0.5, label=ten, zorder=3)
    if su_kien:
        ax.scatter([e["x"] / KICH_THUOC_O for e in su_kien], [e["y"] / KICH_THUOC_O for e in su_kien],
                   s=90, c="#dc4a3d", alpha=0.25, edgecolors="none", label="trúng đòn", zorder=4)
    ax.set_xlim(0, ban_do.so_cot); ax.set_ylim(ban_do.so_hang, 0)
    ax.set_xticks([]); ax.set_yticks([])
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.01), ncol=5, fontsize=8, frameon=False)
    if tieu_de:
        ax.set_title(tieu_de, fontsize=10)
    fig.tight_layout()
    return fig
