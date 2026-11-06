"""Quản lý tiến trình người chơi (Cấp độ, EXP, Màn mở khóa, Nhân vật, Trang bị).

Quy tắc:
  * Người chơi bắt đầu ở Màn 1 (Đồng cỏ).
  * Hoàn thành Màn N sẽ ghi nhận vào `completed_stage_ids` và tự động mở khóa Màn N+1 vào `unlocked_stage_ids`.
  * Không cho phép mở khóa tùy tiện nếu chưa hoàn thành điều kiện.
  * Tích hợp tính toán Level dựa trên EXP lũy tiến.
"""
from __future__ import annotations

import json
import sqlite3
from typing import Any

from .csdl import bay_gio_iso, lay_csdl

# Mỗi cấp độ N yêu cầu: CẤP 1 -> 100 EXP -> CẤP 2 -> 250 EXP -> CẤP 3...
# Công thức: exp_can_de_len_cap(level) = level * 100
EXP_CO_BAN_MOI_CAP = 100


def tinh_cap_va_exp(tong_exp: int) -> dict[str, int]:
    """Tính cấp độ hiện tại, exp dư trong cấp hiện tại, và exp cần để lên cấp kế."""
    if tong_exp < 0:
        tong_exp = 0
    cap = 1
    con_lai = tong_exp
    while True:
        can = cap * EXP_CO_BAN_MOI_CAP
        if con_lai < can:
            return {
                "level": cap,
                "exp_hien_tai": con_lai,
                "exp_can_len_cap": can,
                "tong_exp": tong_exp,
            }
        con_lai -= can
        cap += 1


def lay_hoac_tao_nguoi_choi(
    conn: sqlite3.Connection,
    player_id: str,
    wallet_address: str | None = None,
    ten_hien_thi: str = "",
) -> dict[str, Any]:
    """Lấy thông tin người chơi, nếu chưa có thì tạo mới kèm tiến trình khởi đầu."""
    cur = conn.cursor()
    vi = wallet_address.lower() if wallet_address else None

    # Tìm theo player_id hoặc theo ví
    if vi:
        cur.execute("SELECT * FROM players WHERE wallet_address = ?", (vi,))
        p = cur.fetchone()
        if p:
            player_id = p["player_id"]
    else:
        cur.execute("SELECT * FROM players WHERE player_id = ?", (player_id,))
        p = cur.fetchone()

    gio = bay_gio_iso()
    if p is None:
        # Tạo người chơi mới
        cur.execute(
            """INSERT INTO players (player_id, wallet_address, ten_hien_thi, created_at, last_login)
               VALUES (?, ?, ?, ?, ?)""",
            (player_id, vi, ten_hien_thi or player_id, gio, gio),
        )
        # Tạo tiến trình ban đầu
        cur.execute(
            """INSERT INTO player_progress
               (player_id, level, exp, unlocked_stage_ids, completed_stage_ids,
                equipped_weapon_id, equipped_character_id, unlocked_characters, updated_at)
               VALUES (?, 1, 0, '[1]', '[]', 'kiem_go', 'george', '["george"]', ?)""",
            (player_id, gio),
        )
        # Tặng trang bị mặc định vào kho đồ
        cur.execute(
            """INSERT OR IGNORE INTO inventory (player_id, item_id, item_type, quantity, metadata, acquired_at)
               VALUES (?, 'kiem_go', 'weapon', 1, '{"ten": "Kiếm gỗ", "sat_thuong": 5}', ?)""",
            (player_id, gio),
        )
        cur.execute(
            """INSERT OR IGNORE INTO inventory (player_id, item_id, item_type, quantity, metadata, acquired_at)
               VALUES (?, 'george', 'character', 1, '{"ten": "George", "toc_do": 74}', ?)""",
            (player_id, gio),
        )
    else:
        # Cập nhật thời gian đăng nhập & ví (nếu có bổ sung)
        if vi and not p["wallet_address"]:
            cur.execute(
                "UPDATE players SET wallet_address = ?, last_login = ? WHERE player_id = ?",
                (vi, gio, player_id),
            )
        else:
            cur.execute(
                "UPDATE players SET last_login = ? WHERE player_id = ?",
                (gio, player_id),
            )

    return lay_tien_trinh(conn, player_id)


def lay_tien_trinh(conn: sqlite3.Connection, player_id: str) -> dict[str, Any] | None:
    """Đọc tiến trình đầy đủ của người chơi từ CSDL."""
    cur = conn.cursor()
    cur.execute(
        """SELECT p.player_id, p.wallet_address, p.ten_hien_thi, p.created_at, p.last_login,
                  pr.level, pr.exp, pr.unlocked_stage_ids, pr.completed_stage_ids,
                  pr.equipped_weapon_id, pr.equipped_character_id, pr.unlocked_characters,
                  pr.updated_at
           FROM players p
           JOIN player_progress pr ON p.player_id = pr.player_id
           WHERE p.player_id = ?""",
        (player_id,),
    )
    row = cur.fetchone()
    if row is None:
        return None

    unlocked_stages = json.loads(row["unlocked_stage_ids"])
    completed_stages = json.loads(row["completed_stage_ids"])
    unlocked_chars = json.loads(row["unlocked_characters"])
    exp_info = tinh_cap_va_exp(row["exp"])

    return {
        "player_id": row["player_id"],
        "wallet_address": row["wallet_address"],
        "ten_hien_thi": row["ten_hien_thi"],
        "level": exp_info["level"],
        "exp": row["exp"],
        "exp_hien_tai": exp_info["exp_hien_tai"],
        "exp_can_len_cap": exp_info["exp_can_len_cap"],
        "unlocked_stage_ids": sorted(list(set(unlocked_stages))),
        "completed_stage_ids": sorted(list(set(completed_stages))),
        "equipped_weapon_id": row["equipped_weapon_id"],
        "equipped_character_id": row["equipped_character_id"],
        "unlocked_characters": unlocked_chars,
        "updated_at": row["updated_at"],
    }


def cong_exp(conn: sqlite3.Connection, player_id: str, exp_cong: int) -> dict[str, Any]:
    """Cộng EXP cho người chơi, cập nhật lại level tương ứng."""
    if exp_cong <= 0:
        return lay_tien_trinh(conn, player_id)

    cur = conn.cursor()
    cur.execute("SELECT exp FROM player_progress WHERE player_id = ?", (player_id,))
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"Không tìm thấy người chơi {player_id}")

    tong_exp_moi = row["exp"] + exp_cong
    cap_moi = tinh_cap_va_exp(tong_exp_moi)["level"]
    gio = bay_gio_iso()

    cur.execute(
        """UPDATE player_progress
           SET exp = ?, level = ?, updated_at = ?
           WHERE player_id = ?""",
        (tong_exp_moi, cap_moi, gio, player_id),
    )
    return lay_tien_trinh(conn, player_id)


def mo_khoa_man(conn: sqlite3.Connection, player_id: str, stage_id: int) -> dict[str, Any]:
    """Mở khóa một màn chơi cụ thể cho người chơi."""
    cur = conn.cursor()
    cur.execute("SELECT unlocked_stage_ids FROM player_progress WHERE player_id = ?", (player_id,))
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"Không tìm thấy người chơi {player_id}")

    ds = set(json.loads(row["unlocked_stage_ids"]))
    if stage_id not in ds:
        ds.add(stage_id)
        gio = bay_gio_iso()
        cur.execute(
            """UPDATE player_progress
               SET unlocked_stage_ids = ?, updated_at = ?
               WHERE player_id = ?""",
            (json.dumps(sorted(list(ds))), gio, player_id),
        )
    return lay_tien_trinh(conn, player_id)


def hoan_thanh_man(
    conn: sqlite3.Connection,
    player_id: str,
    stage_id: int,
    exp_thuong: int = 50,
    so_man_toi_da: int = 6,
) -> dict[str, Any]:
    """Ghi nhận hoàn thành màn chơi, tự động mở khóa màn kế tiếp và cộng EXP thưởng."""
    cur = conn.cursor()
    cur.execute(
        "SELECT unlocked_stage_ids, completed_stage_ids, exp FROM player_progress WHERE player_id = ?",
        (player_id,),
    )
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"Không tìm thấy người chơi {player_id}")

    unlocked = set(json.loads(row["unlocked_stage_ids"]))
    completed = set(json.loads(row["completed_stage_ids"]))

    # Màn phải đã mở thì mới được hoàn thành
    if stage_id not in unlocked:
        unlocked.add(stage_id)

    completed.add(stage_id)

    # Mở khóa màn kế tiếp nếu chưa vượt quá số màn tối đa
    man_ke = stage_id + 1
    if man_ke <= so_man_toi_da:
        unlocked.add(man_ke)

    tong_exp_moi = row["exp"] + exp_thuong
    cap_moi = tinh_cap_va_exp(tong_exp_moi)["level"]
    gio = bay_gio_iso()

    cur.execute(
        """UPDATE player_progress
           SET unlocked_stage_ids = ?, completed_stage_ids = ?, exp = ?, level = ?, updated_at = ?
           WHERE player_id = ?""",
        (json.dumps(sorted(list(unlocked))), json.dumps(sorted(list(completed))),
         tong_exp_moi, cap_moi, gio, player_id),
    )
    return lay_tien_trinh(conn, player_id)


def doi_trang_bi(
    conn: sqlite3.Connection,
    player_id: str,
    loai: str,
    item_id: str,
) -> dict[str, Any]:
    """Đổi trang bị đang dùng ('weapon' hoặc 'character').

    Chỉ cho phép đổi nếu người chơi đang sở hữu vật phẩm đó trong kho đồ.
    """
    if loai not in ("weapon", "character"):
        raise ValueError(f"Loại trang bị không hợp lệ: {loai}. Cần 'weapon' hoặc 'character'")

    cur = conn.cursor()
    # Kiểm tra xem có trong kho đồ không
    cur.execute(
        "SELECT quantity FROM inventory WHERE player_id = ? AND item_id = ? AND item_type = ?",
        (player_id, item_id, loai),
    )
    inv = cur.fetchone()
    if inv is None or inv["quantity"] <= 0:
        raise ValueError(f"Người chơi {player_id} không sở hữu {loai} '{item_id}'")

    gio = bay_gio_iso()
    if loai == "weapon":
        cur.execute(
            "UPDATE player_progress SET equipped_weapon_id = ?, updated_at = ? WHERE player_id = ?",
            (item_id, gio, player_id),
        )
    elif loai == "character":
        cur.execute(
            "UPDATE player_progress SET equipped_character_id = ?, updated_at = ? WHERE player_id = ?",
            (item_id, gio, player_id),
        )

    return lay_tien_trinh(conn, player_id)

