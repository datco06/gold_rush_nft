"""Quản lý nhiệm vụ (Cốt truyện, Hằng ngày và AI Quests từ Người 3).

Người 5 chịu trách nhiệm:
  * Lưu trữ và theo dõi tiến độ nhiệm vụ.
  * Cung cấp ngữ cảnh người chơi cho module AI của Người 3.
  * Kiểm tra điều kiện hoàn thành và phát thưởng (EXP, Vàng, Vật phẩm).
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from typing import Any

from .csdl import bay_gio_iso
from .kho_do import them_vat_pham
from .tien_trinh import cong_exp, lay_tien_trinh

# Danh sách các loại mục tiêu hợp lệ mà hệ thống game hỗ trợ
MUC_TIEU_HOP_LE = {
    "hoan_thanh_man": "Hoàn thành màn chơi chỉ định",
    "nhat_xu": "Nhặt đủ số lượng đồng xu",
    "choi_khong_trung_don": "Hoàn thành màn mà không bị trúng đòn",
    "toc_do": "Hoàn thành màn trong khoảng thời gian quy định",
}


def lay_ngu_canh_cho_ai(conn: sqlite3.Connection, player_id: str) -> dict[str, Any]:
    """Cung cấp ngữ cảnh tiến trình người chơi để Người 3 dùng cho prompt sinh AI Quest."""
    tt = lay_tien_trinh(conn, player_id)
    if tt is None:
        raise ValueError(f"Không tìm thấy người chơi {player_id}")

    cur = conn.cursor()
    cur.execute(
        """SELECT quest_id, title, target_type, status, created_at
           FROM quests
           WHERE player_id = ?
           ORDER BY created_at DESC LIMIT 5""",
        (player_id,),
    )
    lich_su = [dict(r) for r in cur.fetchall()]

    return {
        "player_id": player_id,
        "level": tt["level"],
        "unlocked_stage_ids": tt["unlocked_stage_ids"],
        "completed_stage_ids": tt["completed_stage_ids"],
        "equipped_weapon": tt["equipped_weapon_id"],
        "muc_tieu_hop_le": list(MUC_TIEU_HOP_LE.keys()),
        "nhiem_vu_gan_day": lich_su,
    }


def tao_nhiem_vu(
    conn: sqlite3.Connection,
    player_id: str,
    title: str,
    description: str,
    target_type: str,
    target_count: int = 1,
    reward_exp: int = 50,
    reward_gold: int = 0,
    reward_items: list[dict[str, Any]] | None = None,
    quest_type: str = "story",
    expires_at: str | None = None,
    quest_id: str | None = None,
) -> dict[str, Any]:
    """Tạo mới một nhiệm vụ cho người chơi."""
    if target_type not in MUC_TIEU_HOP_LE:
        raise ValueError(f"Mục tiêu '{target_type}' không hợp lệ. Cho phép: {list(MUC_TIEU_HOP_LE.keys())}")

    qid = quest_id or f"q_{uuid.uuid4().hex[:12]}"
    gio = bay_gio_iso()
    items_str = json.dumps(reward_items or [], ensure_ascii=False)

    cur = conn.cursor()
    cur.execute(
        """INSERT INTO quests
           (quest_id, player_id, quest_type, title, description, target_type, target_count,
            current_count, reward_exp, reward_gold, reward_items, status, created_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, 'dang_lam', ?, ?)""",
        (qid, player_id, quest_type, title, description, target_type, target_count,
         reward_exp, reward_gold, items_str, gio, expires_at),
    )
    return lay_chi_tiet_nhiem_vu(conn, qid)


def lay_chi_tiet_nhiem_vu(conn: sqlite3.Connection, quest_id: str) -> dict[str, Any] | None:
    """Lấy thông tin chi tiết một nhiệm vụ."""
    cur = conn.cursor()
    cur.execute("SELECT * FROM quests WHERE quest_id = ?", (quest_id,))
    r = cur.fetchone()
    if r is None:
        return None
    return {
        "quest_id": r["quest_id"],
        "player_id": r["player_id"],
        "quest_type": r["quest_type"],
        "title": r["title"],
        "description": r["description"],
        "target_type": r["target_type"],
        "target_count": r["target_count"],
        "current_count": r["current_count"],
        "reward_exp": r["reward_exp"],
        "reward_gold": r["reward_gold"],
        "reward_items": json.loads(r["reward_items"]) if r["reward_items"] else [],
        "status": r["status"],
        "created_at": r["created_at"],
        "expires_at": r["expires_at"],
    }


def lay_danh_sach_nhiem_vu(
    conn: sqlite3.Connection,
    player_id: str,
    status: str | None = None,
) -> list[dict[str, Any]]:
    """Lấy danh sách nhiệm vụ của người chơi (có thể lọc theo status: dang_lam, hoan_thanh, da_nhan)."""
    cur = conn.cursor()
    if status:
        cur.execute(
            """SELECT * FROM quests
               WHERE player_id = ? AND status = ?
               ORDER BY created_at DESC""",
            (player_id, status),
        )
    else:
        cur.execute(
            """SELECT * FROM quests
               WHERE player_id = ?
               ORDER BY
                 CASE status
                   WHEN 'hoan_thanh' THEN 1
                   WHEN 'dang_lam' THEN 2
                   WHEN 'da_nhan' THEN 3
                   ELSE 4
                 END, created_at DESC""",
            (player_id,),
        )

    ds = []
    for r in cur.fetchall():
        ds.append({
            "quest_id": r["quest_id"],
            "player_id": r["player_id"],
            "quest_type": r["quest_type"],
            "title": r["title"],
            "description": r["description"],
            "target_type": r["target_type"],
            "target_count": r["target_count"],
            "current_count": r["current_count"],
            "reward_exp": r["reward_exp"],
            "reward_gold": r["reward_gold"],
            "reward_items": json.loads(r["reward_items"]) if r["reward_items"] else [],
            "status": r["status"],
            "created_at": r["created_at"],
            "expires_at": r["expires_at"],
        })
    return ds


def cap_nhat_tien_do(
    conn: sqlite3.Connection,
    player_id: str,
    target_type: str,
    count_delta: int = 1,
) -> list[dict[str, Any]]:
    """Cập nhật tiến độ các nhiệm vụ đang thực hiện.

    Trả về danh sách các nhiệm vụ vừa chuyển sang trạng thái 'hoan_thanh'.
    """
    if count_delta <= 0:
        return []

    cur = conn.cursor()
    cur.execute(
        """SELECT quest_id, target_count, current_count
           FROM quests
           WHERE player_id = ? AND target_type = ? AND status = 'dang_lam'""",
        (player_id, target_type),
    )
    rows = cur.fetchall()

    vua_hoan_thanh = []
    for r in rows:
        moi = r["current_count"] + count_delta
        target = r["target_count"]
        if moi >= target:
            cur.execute(
                "UPDATE quests SET current_count = ?, status = 'hoan_thanh' WHERE quest_id = ?",
                (target, r["quest_id"]),
            )
            vua_hoan_thanh.append(lay_chi_tiet_nhiem_vu(conn, r["quest_id"]))
        else:
            cur.execute(
                "UPDATE quests SET current_count = ? WHERE quest_id = ?",
                (moi, r["quest_id"]),
            )

    return vua_hoan_thanh


def nhan_thuong(
    conn: sqlite3.Connection,
    player_id: str,
    quest_id: str,
) -> dict[str, Any]:
    """Nhận phần thưởng nhiệm vụ khi đã đạt trạng thái 'hoan_thanh'.

    Tự động cộng EXP và thêm vật phẩm vào kho đồ.
    """
    q = lay_chi_tiet_nhiem_vu(conn, quest_id)
    if q is None or q["player_id"] != player_id:
        raise ValueError(f"Không tìm thấy nhiệm vụ {quest_id} cho người chơi {player_id}")

    if q["status"] == "da_nhan":
        raise ValueError("Nhiệm vụ này đã nhận thưởng rồi")
    if q["status"] != "hoan_thanh":
        raise ValueError("Nhiệm vụ chưa hoàn thành, không thể nhận thưởng")

    cur = conn.cursor()
    cur.execute("UPDATE quests SET status = 'da_nhan' WHERE quest_id = ?", (quest_id,))

    # Cộng EXP
    if q["reward_exp"] > 0:
        cong_exp(conn, player_id, q["reward_exp"])

    # Thêm vật phẩm vào kho đồ (nếu có)
    for it in q["reward_items"]:
        them_vat_pham(
            conn,
            player_id=player_id,
            item_id=it["item_id"],
            item_type=it.get("item_type", "material"),
            quantity=it.get("quantity", 1),
            metadata=it.get("metadata", {}),
        )

    return {
        "quest_id": quest_id,
        "status": "da_nhan",
        "reward_exp": q["reward_exp"],
        "reward_gold": q["reward_gold"],
        "reward_items": q["reward_items"],
        "tien_trinh_hien_tai": lay_tien_trinh(conn, player_id),
    }

