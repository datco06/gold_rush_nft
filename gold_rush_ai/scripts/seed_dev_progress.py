#!/usr/bin/env python3
"""Script DEV-ONLY: Cấp hoặc khôi phục tiến trình 6/6 phục vụ Local Development / Testing.

CHỈ DÀNH CHO MÔI TRƯỜNG PHÁT TRIỂN CỤC BỘ (LOCAL DEV/TEST VỚI HARDHAT CHAIN 31337).
TUYỆT ĐỐI KHÔNG SỬ DỤNG TRÊN PRODUCTION HOẶC PUBLIC BLOCKCHAIN.

Đặc tả bảo mật:
- Từ chối thực thi nếu phát hiện biến môi trường production hoặc chain khác 31337.
- Không tạo API public để cấp tiến trình.
- Không cho client tự ý gửi cờ completed_stage_ids qua HTTP.
- Không giả mạo referee_log hoặc blockchain transaction thật.
- Đánh dấu rõ ràng bản ghi là test fixture: verification_source="dev_test_fixture".
- Đối chiếu chính xác user_id gắn với ví SIWE trong bảng `users`, không chỉ dựa vào username.
- Hỗ trợ xem trạng thái (--status), cấp tiến trình (--seed), và dọn dẹp fixture (--cleanup) mà không làm mất chiến thắng thật.

Cách dùng:
    # 1. Xem trạng thái tiến trình của tài khoản datco6:
    python scripts/seed_dev_progress.py --username datco6 --status

    # 2. Cấp tiến trình 6/6 dev fixture:
    python scripts/seed_dev_progress.py --username datco6

    # 3. Dọn dẹp bản ghi fixture sau khi hoàn tất kiểm thử:
    python scripts/seed_dev_progress.py --username datco6 --cleanup
"""

from __future__ import annotations

import argparse
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import sqlite3
import sys
import unicodedata
import uuid

# Thêm thư mục gold_rush_ai vào sys.path
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import config
from core.tien_trinh_storage import KhoTienTrinh, LoiKhoTienTrinh

TEN_CAC_MAN: dict[int, str] = {
    1: "Đồng cỏ",
    2: "Rừng thưa",
    3: "Hang đá",
    4: "Rừng rậm",
    5: "Thung lũng xương",
    6: "Mỏ vàng",
}


def kiem_tra_moi_truong_an_toan() -> None:
    """Kiểm tra và ngăn chặn script thực thi trong môi trường production."""
    env = os.environ.get("ENVIRONMENT", "").strip().lower()
    app_env = os.environ.get("APP_ENV", "").strip().lower()
    node_env = os.environ.get("NODE_ENV", "").strip().lower()
    if any(p in (env, app_env, node_env) for p in ("prod", "production", "live")):
        raise SystemExit(
            "LỖI BẢO MẬT: Script seed_dev_progress.py chỉ được phép chạy trong môi trường LOCAL DEV/TEST. "
            "Đã phát hiện cờ môi trường Production. Hủy lệnh."
        )

    chain_id = int(os.environ.get("CHAIN_ID", str(config.CHAIN_ID)))
    if chain_id != 31337:
        raise SystemExit(
            f"LỖI BẢO MẬT: Script chỉ hỗ trợ mạng thử nghiệm Hardhat Localhost (Chain ID 31337). "
            f"Chain ID hiện tại là {chain_id}. Hủy lệnh."
        )


def chuan_hoa_key_ten(ten: str) -> str:
    """Chuẩn hóa username_key khớp với chuẩn xác thực SIWE trong auth/schemas.py."""
    clean = " ".join(ten.strip().split())
    return unicodedata.normalize("NFC", clean.casefold())


def tim_nguoi_dung_trong_auth_db(
    auth_db_path: Path,
    *,
    username: str | None = None,
    wallet: str | None = None,
    user_id: str | None = None,
) -> dict[str, str] | None:
    """Tìm thông tin người dùng từ cơ sở dữ liệu Auth SQLite."""
    if not auth_db_path.exists():
        raise FileNotFoundError(f"Không tìm thấy cơ sở dữ liệu Auth tại: {auth_db_path}")

    conn = sqlite3.connect(str(auth_db_path))
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        query = ""
        params: tuple = ()

        if user_id:
            uid_clean = user_id.strip()
            # Hỗ trợ cả chuỗi UUID có gạch nối và hex 32 ký tự
            try:
                parsed_uuid = uuid.UUID(uid_clean)
                query = "SELECT id, username, username_key, wallet_address FROM users WHERE id = ? OR id = ?"
                params = (str(parsed_uuid), parsed_uuid.hex)
            except ValueError:
                query = "SELECT id, username, username_key, wallet_address FROM users WHERE id = ?"
                params = (uid_clean,)
        elif wallet:
            w_clean = wallet.strip().lower()
            query = "SELECT id, username, username_key, wallet_address FROM users WHERE lower(wallet_address) = ?"
            params = (w_clean,)
        elif username:
            u_clean = username.strip()
            u_key = chuan_hoa_key_ten(u_clean)
            query = "SELECT id, username, username_key, wallet_address FROM users WHERE username_key = ? OR username = ?"
            params = (u_key, u_clean)
        else:
            return None

        row = cur.execute(query, params).fetchone()
        if not row:
            return None

        raw_id = row["id"]
        # Chuẩn hóa id thành string UUID chuẩn (có gạch nối) để khớp với str(me.user.id) trong auth_adapter
        try:
            uid_str = str(uuid.UUID(str(raw_id)))
        except ValueError:
            uid_str = str(raw_id)

        return {
            "id": uid_str,
            "username": str(row["username"]),
            "username_key": str(row["username_key"]),
            "wallet_address": str(row["wallet_address"]).lower(),
        }
    finally:
        conn.close()


def xem_tien_trinh(
    kho: KhoTienTrinh,
    user_info: dict[str, str],
) -> dict:
    """Đọc và định dạng chi tiết tiến trình của tài khoản."""
    owner_id = user_info["id"]
    wallet = user_info["wallet_address"]
    ban_ghis = kho.lay_tien_trinh(owner_id)
    ban_ghi_map = {bg.stage_id: bg for bg in ban_ghis if bg.completion_status == "completed"}

    completed_ids = sorted(ban_ghi_map.keys())
    total_completed = len(completed_ids)
    is_unlocked = frozenset(range(1, 7)) <= frozenset(completed_ids)

    print("=" * 70)
    print("TIẾN TRÌNH VƯỢT MÀN (LOCAL DEV/TEST)")
    print("=" * 70)
    print(f"• Người chơi:       {user_info['username']}")
    print(f"• User ID (UUID):   {owner_id}")
    print(f"• Ví SIWE:          {wallet}")
    print(f"• Tổng hoàn thành:  {total_completed}/6 màn")
    print(f"• Mở khóa AI:       {'✓ ĐÃ MỞ KHÓA' if is_unlocked else '✗ ĐANG KHÓA (Cần đủ màn 1-6)'}")
    print("-" * 70)
    print(f"{'Màn':<6} | {'Tên màn':<18} | {'Trạng thái':<14} | {'Nguồn xác minh':<22}")
    print("-" * 70)
    for s_id in range(1, 7):
        name = TEN_CAC_MAN.get(s_id, f"Màn {s_id}")
        if s_id in ban_ghi_map:
            bg = ban_ghi_map[s_id]
            st = "ĐÃ HOÀN THÀNH"
            src = bg.verification_source
        else:
            st = "CHƯA HOÀN THÀNH"
            src = "—"
        print(f"{s_id:<6} | {name:<18} | {st:<14} | {src:<22}")
    print("=" * 70)

    return {
        "user": user_info,
        "completed_ids": completed_ids,
        "total_completed": total_completed,
        "is_unlocked": is_unlocked,
    }


def cap_tien_trinh_fixture(
    kho: KhoTienTrinh,
    user_info: dict[str, str],
    stages: list[int] | None = None,
) -> int:
    """Cấp bản ghi tiến trình dev_test_fixture cho các màn chỉ định."""
    stages_to_seed = stages or list(range(1, 7))
    owner_id = user_info["id"]
    wallet = user_info["wallet_address"]
    now_iso = datetime.now(UTC).isoformat(timespec="seconds")
    count_new = 0

    for s in stages_to_seed:
        if s < 1 or s > 6:
            continue
        existing = kho.lay_ban_ghi(owner_id, s)
        if existing and existing.completion_status == "completed":
            # Đã có bản ghi hoàn thành (giữ nguyên bằng chứng nếu là gameplay thật)
            continue

        replay_key = f"dev_fixture:{wallet}:{s}"
        evidence = {
            "fixture": True,
            "verification_source": "dev_test_fixture",
            "reason": "local_dev_test_unlock",
            "chain_id": 31337,
            "username": user_info["username"],
            "seeded_at": now_iso,
        }
        kho.ghi_nhan_hoan_thanh(
            owner_user_id=owner_id,
            verified_wallet_address=wallet,
            stage_id=s,
            completion_status="completed",
            verification_source="dev_test_fixture",
            completion_evidence=evidence,
            replay_key=replay_key,
            completed_at=now_iso,
        )
        count_new += 1

    return count_new


def xoa_fixture_tien_trinh(
    progress_db_path: Path,
    owner_user_id: str,
) -> int:
    """Dọn dẹp DUY NHẤT các bản ghi dev_test_fixture, bảo toàn các chiến thắng gameplay thật."""
    if not progress_db_path.exists():
        return 0

    conn = sqlite3.connect(str(progress_db_path))
    try:
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM tien_trinh_man WHERE owner_user_id = ? AND verification_source = 'dev_test_fixture'",
            (owner_user_id,),
        )
        deleted = cur.rowcount
        conn.commit()
        return deleted
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Script cấp hoặc khôi phục tiến trình 6/6 an toàn dành riêng cho Local Dev/Test."
    )
    parser.add_argument("--username", "-u", default="datco6", help="Tên tài khoản game (mặc định: datco6)")
    parser.add_argument("--wallet", "-w", help="Địa chỉ ví SIWE (0x...)")
    parser.add_argument("--user-id", help="User ID (UUID)")
    parser.add_argument("--status", action="store_true", help="Chỉ kiểm tra và in trạng thái tiến trình hiện tại")
    parser.add_argument("--cleanup", action="store_true", help="Xóa các bản ghi fixture đã cấp, khôi phục trạng thái ban đầu")
    parser.add_argument("--stages", help="Danh sách màn cần cấp (phân cách bởi dấu phẩy, mặc định: 1,2,3,4,5,6)")
    parser.add_argument(
        "--auth-db",
        default=os.environ.get("AUTH_DATABASE_URL", "data/auth/gold_rush_auth.db").replace("sqlite:///", ""),
        help="Đường dẫn file Auth SQLite database",
    )
    parser.add_argument(
        "--progress-db",
        default=str(os.environ.get("AI_PROGRESS_DB", config.AI_PROGRESS_DB)),
        help="Đường dẫn file Progress SQLite database",
    )

    args = parser.parse_args()

    # 1. Kiểm tra an toàn môi trường
    kiem_tra_moi_truong_an_toan()

    # 2. Xác định đường dẫn databases
    auth_db_path = Path(args.auth_db)
    if not auth_db_path.is_absolute():
        auth_db_path = ROOT_DIR / auth_db_path

    progress_db_path = Path(args.progress_db)
    if not progress_db_path.is_absolute():
        progress_db_path = ROOT_DIR / progress_db_path

    # 3. Tra cứu người dùng từ Auth database
    user_info = tim_nguoi_dung_trong_auth_db(
        auth_db_path,
        username=args.username,
        wallet=args.wallet,
        user_id=args.user_id,
    )

    if not user_info:
        print(f"[LỖI]: Không tìm thấy tài khoản người chơi trong Auth database ({auth_db_path}).")
        print("Gợi ý: Hãy đăng nhập game qua MetaMask trên Chrome trước để tài khoản được khởi tạo.")
        return 1

    kho = KhoTienTrinh(progress_db_path)

    # 4. Thực hiện hành động
    if args.status:
        xem_tien_trinh(kho, user_info)
        return 0

    if args.cleanup:
        print(f"Đang dọn dẹp các bản ghi dev_test_fixture cho user '{user_info['username']}'...")
        deleted = xoa_fixture_tien_trinh(progress_db_path, user_info["id"])
        print(f"✓ Đã xóa {deleted} bản ghi fixture. Trạng thái sau dọn dẹp:")
        xem_tien_trinh(kho, user_info)
        return 0

    # Mặc định: Seeding 6/6
    stages = [1, 2, 3, 4, 5, 6]
    if args.stages:
        stages = [int(s.strip()) for s in args.stages.split(",") if s.strip().isdigit()]

    print(f"Bắt đầu cấp tiến trình test fixture cho tài khoản '{user_info['username']}'...")
    count_new = cap_tien_trinh_fixture(kho, user_info, stages=stages)
    print(f"✓ Đã ghi nhận {count_new} màn mới vào kho tiến trình.")
    xem_tien_trinh(kho, user_info)
    return 0


if __name__ == "__main__":
    sys.exit(main())

