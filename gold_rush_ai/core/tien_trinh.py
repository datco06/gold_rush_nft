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
        raise ValueError("EXP không được âm")
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
    """Lấy thông tin người chơi, nếu chưa có thì tạo mới kèm tiến trình khởi đầu.

    Bảo mật:
    - Không tự động liên kết hai tài khoản khác nhau khi trùng ví.
    - Một ví chỉ thuộc về duy nhất một player_id đã xác thực.
    """
    if not player_id or not isinstance(player_id, str):
        raise ValueError("player_id không hợp lệ")

    cur = conn.cursor()
    vi = wallet_address.lower() if isinstance(wallet_address, str) and wallet_address.strip() else None
    ten = ten_hien_thi if isinstance(ten_hien_thi, str) else ""

    # Kiểm tra xem ví đã được người chơi khác liên kết chưa
    if vi:
        cur.execute("SELECT player_id FROM players WHERE wallet_address = ?", (vi,))
        p_vi = cur.fetchone()
        if p_vi and p_vi["player_id"] != player_id:
            raise ValueError(f"Địa chỉ ví '{vi}' đã được liên kết với tài khoản khác ({p_vi['player_id']}).")

    cur.execute("SELECT * FROM players WHERE player_id = ?", (player_id,))
    p = cur.fetchone()

    gio = bay_gio_iso()
    if p is None:
        # Tạo người chơi mới
        cur.execute(
            """INSERT INTO players (player_id, wallet_address, ten_hien_thi, created_at, last_login)
               VALUES (?, ?, ?, ?, ?)""",
            (player_id, vi, ten or player_id, gio, gio),
        )
        # Tạo tiến trình ban đầu: Màn 1 mở, cấp 1, kiếm gỗ, nhân vật george
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
        # Nếu tài khoản đã có ví nhưng ví gửi lên khác -> từ chối
        if vi and p["wallet_address"] and p["wallet_address"].lower() != vi:
            raise ValueError(f"Tài khoản {player_id} đã được liên kết với ví khác ({p['wallet_address']}).")

        # Cập nhật thời gian đăng nhập & ví (nếu trước đó chưa có)
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
    if exp_cong < 0:
        raise ValueError("Lượng EXP cộng không được âm")
    if exp_cong == 0:
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


def mo_khoa_man(conn: sqlite3.Connection, player_id: str, stage_id: int, so_man_toi_da: int = 6) -> dict[str, Any]:
    """Mở khóa một màn chơi cụ thể cho người chơi.

    Quy tắc:
    - Chỉ chấp nhận stage_id từ 1 đến 6.
    - Màn 1 luôn được phép mở.
    - Màn N (N > 1) chỉ được mở nếu màn N - 1 đã hoàn thành.
    """
    if not isinstance(stage_id, int) or stage_id < 1 or stage_id > so_man_toi_da:
        raise ValueError(f"Màn {stage_id} không hợp lệ. Chỉ chấp nhận các màn từ 1 đến {so_man_toi_da}.")

    cur = conn.cursor()
    cur.execute("SELECT unlocked_stage_ids, completed_stage_ids FROM player_progress WHERE player_id = ?", (player_id,))
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"Không tìm thấy người chơi {player_id}")

    unlocked = set(json.loads(row["unlocked_stage_ids"]))
    completed = set(json.loads(row["completed_stage_ids"]))

    if stage_id > 1 and (stage_id - 1) not in completed:
        raise ValueError(f"Không thể mở màn {stage_id} khi chưa hoàn thành màn {stage_id - 1}.")

    if stage_id not in unlocked:
        unlocked.add(stage_id)
        gio = bay_gio_iso()
        cur.execute(
            """UPDATE player_progress
               SET unlocked_stage_ids = ?, updated_at = ?
               WHERE player_id = ?""",
            (json.dumps(sorted(list(unlocked))), gio, player_id),
        )
    return lay_tien_trinh(conn, player_id)


def hoan_thanh_man(
    conn: sqlite3.Connection,
    player_id: str,
    stage_id: int,
    evidence_id: str,
    so_man_toi_da: int = 6,
) -> dict[str, Any]:
    """Ghi nhận hoàn thành màn chơi an toàn, chống replay và mở khóa màn kế tiếp.

    Quy tắc nghiệp vụ:
    - Bắt buộc phải có evidence_id hợp lệ (Zero-Trust, không chấp nhận None hay rỗng).
    - Chỉ chấp nhận 6 màn Gameplay chính (1 <= stage_id <= 6).
    - Màn phải đã được mở khóa trước đó (không tự hợp thức hóa màn chưa mở).
    - Hoàn thành lần đầu: cộng EXP đầy đủ (50 EXP) và tự mở khóa màn kế tiếp.
    - Chơi lại (Replay): thưởng EXP giới hạn (10 EXP), có trần giới hạn chống cày cuốc vô hạn.
    - Idempotency & Concurrency: ghi nhận vào `stage_rewards` với ràng buộc UNIQUE(evidence_id).
      Cùng một bằng chứng không thể nhận thưởng hai lần hoặc bị dùng chéo giữa các tài khoản.
    """
    if not evidence_id or not isinstance(evidence_id, str) or not evidence_id.strip():
        raise ValueError("Bắt buộc phải có evidence_id (bằng chứng hợp lệ) để ghi nhận hoàn thành màn.")
    evidence_id = evidence_id.strip()

    if not isinstance(stage_id, int) or stage_id < 1 or stage_id > so_man_toi_da:
        raise ValueError(f"Màn {stage_id} không hợp lệ. Chỉ chấp nhận các màn từ 1 đến {so_man_toi_da}.")

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

    # Màn phải đã mở thì mới được phép hoàn thành (tuyệt đối không tự thêm vào unlocked)
    if stage_id not in unlocked:
        raise ValueError(f"Màn {stage_id} chưa được mở khóa.")

    # Chống replay bằng chứng: kiểm tra xem evidence_id đã được sử dụng ở bất kỳ đâu chưa
    cur.execute("SELECT player_id FROM stage_rewards WHERE evidence_id = ?", (evidence_id,))
    da_dung = cur.fetchone()
    if da_dung is not None:
        raise ValueError(f"Bằng chứng '{evidence_id}' đã được sử dụng.")

    gio = bay_gio_iso()
    la_lan_dau = stage_id not in completed

    # Chính sách EXP do Server quyết định, client không được tự ý can thiệp
    if la_lan_dau:
        exp_cong = 50
        completed.add(stage_id)
        man_ke = stage_id + 1
        if man_ke <= so_man_toi_da:
            unlocked.add(man_ke)
    else:
        # Chơi lại: thưởng EXP tượng trưng (10 EXP) và kẹp trần tối đa 3 lần replay có EXP
        cur.execute(
            "SELECT COUNT(*) FROM stage_rewards WHERE player_id = ? AND stage_id = ?",
            (player_id, stage_id),
        )
        so_lan_replay = cur.fetchone()[0]
        exp_cong = 10 if so_lan_replay < 4 else 0

    try:
        cur.execute(
            """INSERT INTO stage_rewards (evidence_id, player_id, stage_id, exp_awarded, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (evidence_id, player_id, stage_id, exp_cong, gio),
        )
    except sqlite3.IntegrityError:
        raise ValueError(f"Bằng chứng '{evidence_id}' đã được sử dụng.")

    tong_exp_moi = row["exp"] + exp_cong
    cap_moi = tinh_cap_va_exp(tong_exp_moi)["level"]

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

