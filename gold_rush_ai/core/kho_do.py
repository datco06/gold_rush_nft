"""Quản lý kho đồ người chơi (Vũ khí, Trang phục/Nhân vật, Vật phẩm tiêu hao, Nguyên liệu)."""
from __future__ import annotations

import json
import sqlite3
from typing import Any

from .csdl import bay_gio_iso


def lay_kho_do(
    conn: sqlite3.Connection,
    player_id: str,
    loai: str | None = None,
) -> list[dict[str, Any]]:
    """Lấy danh sách vật phẩm của người chơi trong kho đồ, kèm metadata."""
    cur = conn.cursor()
    if loai:
        cur.execute(
            """SELECT id, player_id, item_id, item_type, quantity, metadata, acquired_at
               FROM inventory
               WHERE player_id = ? AND item_type = ? AND quantity > 0
               ORDER BY acquired_at DESC""",
            (player_id, loai),
        )
    else:
        cur.execute(
            """SELECT id, player_id, item_id, item_type, quantity, metadata, acquired_at
               FROM inventory
               WHERE player_id = ? AND quantity > 0
               ORDER BY item_type, acquired_at DESC""",
            (player_id,),
        )

    ket_qua = []
    for r in cur.fetchall():
        meta = {}
        try:
            meta = json.loads(r["metadata"]) if r["metadata"] else {}
        except (ValueError, TypeError):
            pass
        ket_qua.append({
            "id": r["id"],
            "player_id": r["player_id"],
            "item_id": r["item_id"],
            "item_type": r["item_type"],
            "quantity": r["quantity"],
            "metadata": meta,
            "acquired_at": r["acquired_at"],
        })
    return ket_qua


def them_vat_pham(
    conn: sqlite3.Connection,
    player_id: str,
    item_id: str,
    item_type: str,
    quantity: int = 1,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Thêm vật phẩm vào kho đồ người chơi (cộng dồn nếu đã có)."""
    if quantity <= 0:
        raise ValueError("Số lượng thêm vào phải lớn hơn 0")

    cur = conn.cursor()
    cur.execute(
        "SELECT id, quantity, metadata FROM inventory WHERE player_id = ? AND item_id = ?",
        (player_id, item_id),
    )
    row = cur.fetchone()
    gio = bay_gio_iso()

    if row is None:
        meta_str = json.dumps(metadata or {}, ensure_ascii=False)
        cur.execute(
            """INSERT INTO inventory (player_id, item_id, item_type, quantity, metadata, acquired_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (player_id, item_id, item_type, quantity, meta_str, gio),
        )
    else:
        sl_moi = row["quantity"] + quantity
        meta = json.loads(row["metadata"]) if row["metadata"] else {}
        if metadata:
            meta.update(metadata)
        cur.execute(
            "UPDATE inventory SET quantity = ?, metadata = ? WHERE id = ?",
            (sl_moi, json.dumps(meta, ensure_ascii=False), row["id"]),
        )

    # Nếu là nhân vật mới, cập nhật vào danh sách unlocked_characters của tiến trình
    if item_type == "character":
        cur.execute("SELECT unlocked_characters FROM player_progress WHERE player_id = ?", (player_id,))
        p = cur.fetchone()
        if p:
            ds_nv = set(json.loads(p["unlocked_characters"]))
            if item_id not in ds_nv:
                ds_nv.add(item_id)
                cur.execute(
                    "UPDATE player_progress SET unlocked_characters = ?, updated_at = ? WHERE player_id = ?",
                    (json.dumps(sorted(list(ds_nv))), gio, player_id),
                )

    cur.execute("SELECT * FROM inventory WHERE player_id = ? AND item_id = ?", (player_id, item_id))
    r = cur.fetchone()
    return {
        "item_id": r["item_id"],
        "item_type": r["item_type"],
        "quantity": r["quantity"],
        "metadata": json.loads(r["metadata"]) if r["metadata"] else {},
    }


def tru_vat_pham(
    conn: sqlite3.Connection,
    player_id: str,
    item_id: str,
    quantity: int = 1,
) -> bool:
    """Tiêu hao vật phẩm trong kho đồ. Trả về True nếu trừ thành công, False nếu không đủ."""
    if quantity <= 0:
        raise ValueError("Số lượng trừ phải lớn hơn 0")

    cur = conn.cursor()
    cur.execute(
        "SELECT id, quantity FROM inventory WHERE player_id = ? AND item_id = ?",
        (player_id, item_id),
    )
    row = cur.fetchone()
    if row is None or row["quantity"] < quantity:
        return False

    sl_moi = row["quantity"] - quantity
    if sl_moi == 0:
        cur.execute("DELETE FROM inventory WHERE id = ?", (row["id"],))
    else:
        cur.execute("UPDATE inventory SET quantity = ? WHERE id = ?", (sl_moi, row["id"]))
    return True


def so_huu_vat_pham(conn: sqlite3.Connection, player_id: str, item_id: str) -> bool:
    """Kiểm tra nhanh xem người chơi có sở hữu vật phẩm này không."""
    cur = conn.cursor()
    cur.execute(
        "SELECT 1 FROM inventory WHERE player_id = ? AND item_id = ? AND quantity > 0",
        (player_id, item_id),
    )
    return cur.fetchone() is not None

