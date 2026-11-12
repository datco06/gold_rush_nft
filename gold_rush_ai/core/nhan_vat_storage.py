from __future__ import annotations

from collections.abc import Callable
from contextlib import contextmanager
from datetime import UTC, datetime
from hashlib import sha256
import math
from pathlib import Path
import re
import sqlite3
import time
from uuid import uuid4

from .schemas_nhan_vat import (
    DuLieuChuanBiOnchain,
    KetQuaKiemTraHash,
    NguoiChoiXacThuc,
    ThongTinNhanVat,
    YeuCauLuuNhanVat,
    chuan_hoa_vi,
)
from .xu_ly_anh import chuan_hoa_anh


class LoiKhoNhanVat(RuntimeError):
    pass


class KhoNhanVatDay(LoiKhoNhanVat):
    pass


class VuotGioiHanNhanVat(LoiKhoNhanVat):
    pass


class NhanVatKhongTonTai(LoiKhoNhanVat):
    pass


class LoiToanVenNhanVat(LoiKhoNhanVat):
    pass


class LoiQuyenTruyCapNhanVat(LoiKhoNhanVat):
    pass


class LoiMigrationKhoNhanVat(LoiKhoNhanVat):
    pass


class GiaoDichDaDuocSuDung(LoiKhoNhanVat):
    pass


def tinh_character_hash(png_bytes: bytes) -> str:
    """Tính hash SHA-256 chính thức từ bytes ảnh PNG đã được chuẩn hóa.

    Quy định định dạng:
    - Bytes đầu vào là canonical PNG (RGBA, 128x128 pixel, 1 frame tĩnh).
    - Chuỗi trả về là 64 ký tự hex chữ thường (SHA-256).
    """
    if not isinstance(png_bytes, bytes) or not png_bytes:
        raise ValueError("Dữ liệu bytes ảnh không hợp lệ để tính hash")
    return sha256(png_bytes).hexdigest().lower()


class KhoNhanVat:
    """Hệ thống lưu trữ nhân vật bền vững gắn với tài khoản SIWE và MetaMask.

    Tách biệt hoàn toàn khỏi preview cache (anh_nhan_vat) có TTL.
    Ảnh và metadata được lưu vĩnh viễn trong database SQLite này, không bao giờ bị xóa
    bởi cơ chế dọn dẹp preview hết hạn.

    Quản lý transaction tường minh với isolation_level=None và PRAGMA busy_timeout,
    chống race condition, chống deadlock và bảo đảm tính nguyên tử (atomic).
    """

    def __init__(
        self,
        duong_dan: str | Path,
        *,
        so_nhan_vat_toi_da: int = 10000,
        so_nhan_vat_moi_nguoi: int = 20,
        lay_thoi_gian: Callable[[], float] = time.time,
    ):
        if str(duong_dan) == ":memory:":
            raise ValueError("Kho nhân vật cần đường dẫn file SQLite bền vững")
        if type(so_nhan_vat_toi_da) is not int or not 1 <= so_nhan_vat_toi_da <= 100000:
            raise ValueError("Sức chứa tối đa kho nhân vật phải là số nguyên trong 1..100000")
        if type(so_nhan_vat_moi_nguoi) is not int or not 1 <= so_nhan_vat_moi_nguoi <= 1000:
            raise ValueError("Số nhân vật tối đa mỗi người chơi phải là số nguyên trong 1..1000")
        if not callable(lay_thoi_gian):
            raise ValueError("Cần hàm lấy thời gian server")

        self.duong_dan = Path(duong_dan)
        self.so_nhan_vat_toi_da = so_nhan_vat_toi_da
        self.so_nhan_vat_moi_nguoi = so_nhan_vat_moi_nguoi
        self.lay_thoi_gian = lay_thoi_gian

        try:
            self.duong_dan.parent.mkdir(parents=True, exist_ok=True)
            # Khởi tạo WAL mode một lần ngoài transaction (trên file vật lý)
            init_conn = sqlite3.connect(self.duong_dan, timeout=10, isolation_level=None)
            init_conn.execute("PRAGMA journal_mode = WAL;")
            init_conn.execute("PRAGMA synchronous = NORMAL;")
            init_conn.close()
        except OSError:
            raise LoiKhoNhanVat("Không tạo được thư mục kho nhân vật") from None
        except sqlite3.Error:
            raise LoiKhoNhanVat("Không cấu hình được file CSDL kho nhân vật") from None

        # Khởi tạo bảng và chạy migration an toàn trong transaction
        with self._giao_dich() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS nhan_vat (
                    character_id TEXT PRIMARY KEY,
                    owner_user_id TEXT NOT NULL,
                    verified_wallet_address TEXT NOT NULL,
                    character_hash TEXT NOT NULL,
                    image_id TEXT NOT NULL,
                    image_storage_ref TEXT NOT NULL,
                    image_blob BLOB NOT NULL,
                    generation_source TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    character_status TEXT NOT NULL DEFAULT 'active',
                    onchain_status TEXT NOT NULL DEFAULT 'not_registered',
                    transaction_hash TEXT,
                    name TEXT,
                    description TEXT
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS ix_nhan_vat_owner ON nhan_vat(owner_user_id);")
            conn.execute("CREATE INDEX IF NOT EXISTS ix_nhan_vat_wallet ON nhan_vat(verified_wallet_address);")
            conn.execute("CREATE INDEX IF NOT EXISTS ix_nhan_vat_hash ON nhan_vat(character_hash);")
            self._chay_migration(conn)

    def _chay_migration(self, conn: sqlite3.Connection) -> None:
        """Thực thi migration an toàn cho cơ sở dữ liệu hiện có.

        Quy tắc an toàn:
        - Kiểm tra xung đột / trùng lặp dữ liệu trước khi tạo UNIQUE INDEX.
        - Nếu phát hiện trùng lặp, DỪNG migration và raise LoiMigrationKhoNhanVat,
          tuyệt đối KHÔNG tự ý xóa hoặc thay đổi dữ liệu cũ.
        """
        # 1. Migration AI-004: UNIQUE(owner_user_id, image_id)
        dups_owner_image = conn.execute(
            """SELECT owner_user_id, image_id, COUNT(*) as sl
               FROM nhan_vat
               GROUP BY owner_user_id, image_id
               HAVING sl > 1"""
        ).fetchall()
        if dups_owner_image:
            raise LoiMigrationKhoNhanVat(
                f"Phát hiện {len(dups_owner_image)} cặp (owner_user_id, image_id) bị trùng lặp "
                "trong CSDL hiện có. Dừng migration để bảo toàn dữ liệu."
            )
        conn.execute("DROP INDEX IF EXISTS ix_nhan_vat_owner_image;")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_nhan_vat_owner_image "
            "ON nhan_vat(owner_user_id, image_id);"
        )

        # 2. Migration AI-002: UNIQUE cho transaction_hash (chỉ khi khác NULL)
        dups_tx = conn.execute(
            """SELECT transaction_hash, COUNT(*) as sl
               FROM nhan_vat
               WHERE transaction_hash IS NOT NULL
               GROUP BY transaction_hash
               HAVING sl > 1"""
        ).fetchall()
        if dups_tx:
            raise LoiMigrationKhoNhanVat(
                f"Phát hiện {len(dups_tx)} transaction_hash bị trùng lặp "
                "trong CSDL hiện có. Dừng migration để bảo toàn dữ liệu."
            )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_nhan_vat_tx_hash "
            "ON nhan_vat(transaction_hash) WHERE transaction_hash IS NOT NULL;"
        )

    @contextmanager
    def _ket_noi_doc(self):
        """Kết nối chỉ đọc với isolation_level=None và busy_timeout=10000ms.

        Trong chế độ WAL, các thao tác đọc không khóa lẫn nhau và không chặn writer.
        """
        conn = None
        try:
            conn = sqlite3.connect(self.duong_dan, timeout=10, isolation_level=None)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA busy_timeout = 10000;")
            yield conn
        except sqlite3.Error:
            raise LoiKhoNhanVat("Không đọc được kho nhân vật") from None
        finally:
            if conn is not None:
                conn.close()

    @contextmanager
    def _giao_dich(self):
        """Transaction ghi tường minh: BEGIN IMMEDIATE -> COMMIT / ROLLBACK.

        Đảm bảo:
        - Khóa RESERVED được lấy ngay từ đầu (BEGIN IMMEDIATE), chống deadlock nâng khóa.
        - Tự động COMMIT khi khối lệnh hoàn thành thành công.
        - Tự động ROLLBACK khi có bất kỳ ngoại lệ nào phát sinh.
        - Không để lại transaction treo và giải phóng kết nối trong finally:.
        """
        conn = None
        try:
            conn = sqlite3.connect(self.duong_dan, timeout=10, isolation_level=None)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA busy_timeout = 10000;")
            conn.execute("BEGIN IMMEDIATE")
            yield conn
            conn.execute("COMMIT")
        except Exception:
            if conn is not None:
                try:
                    conn.execute("ROLLBACK")
                except sqlite3.Error:
                    pass
            raise
        finally:
            if conn is not None:
                conn.close()

    def _bay_gio(self) -> float:
        value = self.lay_thoi_gian()
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("Thời gian server không hợp lệ")
        try:
            val_float = float(value)
        except OverflowError:
            raise ValueError("Thời gian server không hợp lệ") from None
        if not math.isfinite(val_float) or val_float < 0:
            raise ValueError("Thời gian server không hợp lệ")
        return val_float

    def luu_nhan_vat(
        self,
        *,
        player: NguoiChoiXacThuc,
        image_id: str,
        image_bytes: bytes,
        generation_source: str,
        name: str | None = None,
        description: str | None = None,
    ) -> ThongTinNhanVat:
        """Lưu chính thức một nhân vật đã tạo cho người chơi đã xác thực.

        Quy trình nguyên tử:
        1. Chuẩn hóa canonical PNG bytes (128x128 RGBA) và tính SHA-256.
        2. Mở transaction BEGIN IMMEDIATE.
        3. Kiểm tra tính idempotent: nếu user đã lưu image_id này, trả về bản ghi cũ.
        4. Kiểm tra quota người chơi và sức chứa kho.
        5. Insert bản ghi và tự động commit.
        """
        if not isinstance(player, NguoiChoiXacThuc):
            raise ValueError("Cần thông tin người chơi đã xác thực")
        if not isinstance(image_id, str) or not re.fullmatch(r"^img_[0-9a-f]{32}$", image_id):
            raise ValueError("image_id không hợp lệ")
        if generation_source not in ("demo", "image_model"):
            raise ValueError("generation_source phải là demo hoặc image_model")

        # 1. Chuẩn hóa bytes và tính SHA-256
        png_chuan = chuan_hoa_anh(image_bytes)
        char_hash = tinh_character_hash(png_chuan)

        with self._giao_dich() as conn:
            # 2. Kiểm tra idempotent: Nếu user này đã lưu image_id này, trả về kết quả đã lưu
            row = conn.execute(
                "SELECT * FROM nhan_vat WHERE owner_user_id = ? AND image_id = ?",
                (player.user_id, image_id),
            ).fetchone()
            if row is not None:
                return self._row_to_model(row)

            # 3. Kiểm tra giới hạn số lượng nhân vật của người chơi này
            count_user = conn.execute(
                "SELECT COUNT(*) FROM nhan_vat WHERE owner_user_id = ?",
                (player.user_id,),
            ).fetchone()[0]
            if count_user >= self.so_nhan_vat_moi_nguoi:
                raise VuotGioiHanNhanVat(
                    f"Người chơi đã đạt giới hạn tối đa {self.so_nhan_vat_moi_nguoi} nhân vật"
                )

            # 4. Kiểm tra sức chứa toàn bộ hệ thống
            count_total = conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0]
            if count_total >= self.so_nhan_vat_toi_da:
                raise KhoNhanVatDay("Kho nhân vật đã đạt giới hạn dung lượng lưu trữ tối đa")

            # 5. Sinh character_id và storage ref
            char_id = f"char_{uuid4().hex}"
            storage_ref = f"storage://characters/{char_id}.png"
            now = self._bay_gio()

            try:
                conn.execute(
                    """INSERT INTO nhan_vat (
                        character_id, owner_user_id, verified_wallet_address,
                        character_hash, image_id, image_storage_ref, image_blob,
                        generation_source, created_at, character_status, onchain_status,
                        transaction_hash, name, description
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 'not_registered', NULL, ?, ?)""",
                    (
                        char_id,
                        player.user_id,
                        player.wallet_address,
                        char_hash,
                        image_id,
                        storage_ref,
                        png_chuan,
                        generation_source,
                        now,
                        name,
                        description,
                    ),
                )
            except sqlite3.IntegrityError as err:
                # Xử lý trường hợp có race condition đồng thời ghi cùng (owner_user_id, image_id)
                cu = conn.execute(
                    "SELECT * FROM nhan_vat WHERE owner_user_id = ? AND image_id = ?",
                    (player.user_id, image_id),
                ).fetchone()
                if cu is not None:
                    return self._row_to_model(cu)
                raise LoiKhoNhanVat(f"Lỗi toàn vẹn khi lưu nhân vật: {err}") from None

            saved_row = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (char_id,)
            ).fetchone()
            return self._row_to_model(saved_row)

    def doc_nhan_vat(
        self, character_id: str, *, nguoi_yeu_cau: NguoiChoiXacThuc | None = None
    ) -> ThongTinNhanVat:
        """Đọc metadata nhân vật. Nếu có nguoi_yeu_cau, kiểm tra quyền sở hữu."""
        if not isinstance(character_id, str) or not re.fullmatch(r"^char_[0-9a-f]{32}$", character_id):
            raise ValueError("ID nhân vật không hợp lệ")

        with self._ket_noi_doc() as conn:
            row = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()

        if row is None:
            raise NhanVatKhongTonTai("Nhân vật không tồn tại")

        # Kiểm tra quyền nếu có ngữ cảnh người yêu cầu
        if nguoi_yeu_cau is not None:
            if (
                row["owner_user_id"] != nguoi_yeu_cau.user_id
                and row["verified_wallet_address"].lower() != nguoi_yeu_cau.wallet_address.lower()
            ):
                raise LoiQuyenTruyCapNhanVat("Không có quyền truy cập nhân vật của người khác")

        return self._row_to_model(row)

    def doc_anh_nhan_vat(
        self, character_id: str, *, nguoi_yeu_cau: NguoiChoiXacThuc | None = None
    ) -> tuple[ThongTinNhanVat, bytes]:
        """Tải dữ liệu ảnh PNG của nhân vật và đối chiếu toàn vẹn với character_hash.

        Nếu dữ liệu trong DB bị thay đổi hoặc không khớp SHA-256, sẽ raise LoiToanVenNhanVat.
        """
        if not isinstance(character_id, str) or not re.fullmatch(r"^char_[0-9a-f]{32}$", character_id):
            raise ValueError("ID nhân vật không hợp lệ")

        with self._ket_noi_doc() as conn:
            row = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()

        if row is None:
            raise NhanVatKhongTonTai("Nhân vật không tồn tại")

        if nguoi_yeu_cau is not None:
            if (
                row["owner_user_id"] != nguoi_yeu_cau.user_id
                and row["verified_wallet_address"].lower() != nguoi_yeu_cau.wallet_address.lower()
            ):
                raise LoiQuyenTruyCapNhanVat("Không có quyền truy cập ảnh nhân vật này")

        blob = row["image_blob"]
        if not isinstance(blob, bytes):
            raise LoiToanVenNhanVat("Dữ liệu ảnh nhân vật bị hỏng trong cơ sở dữ liệu")

        # Đối chiếu toàn vẹn SHA-256
        computed_hash = tinh_character_hash(blob)
        if computed_hash != row["character_hash"]:
            raise LoiToanVenNhanVat(
                f"Kiểm tra toàn vẹn thất bại: hash tính được ({computed_hash}) "
                f"không khớp character_hash đã lưu ({row['character_hash']})"
            )

        return self._row_to_model(row), blob

    def danh_sach_nhan_vat(self, player: NguoiChoiXacThuc) -> list[ThongTinNhanVat]:
        """Xem danh sách nhân vật thuộc sở hữu của người chơi đã xác thực."""
        if not isinstance(player, NguoiChoiXacThuc):
            raise ValueError("Cần thông tin người chơi đã xác thực")

        with self._ket_noi_doc() as conn:
            rows = conn.execute(
                """SELECT * FROM nhan_vat
                   WHERE owner_user_id = ? OR verified_wallet_address = ?
                   ORDER BY created_at DESC""",
                (player.user_id, player.wallet_address.lower()),
            ).fetchall()

        return [self._row_to_model(r) for r in rows]

    def kiem_tra_hash(self, character_id: str) -> KetQuaKiemTraHash:
        """Kiểm tra tính toàn vẹn SHA-256 của ảnh nhân vật đã lưu."""
        if not isinstance(character_id, str) or not re.fullmatch(r"^char_[0-9a-f]{32}$", character_id):
            raise ValueError("ID nhân vật không hợp lệ")

        with self._ket_noi_doc() as conn:
            row = conn.execute(
                "SELECT character_id, character_hash, image_blob FROM nhan_vat WHERE character_id = ?",
                (character_id,),
            ).fetchone()

        if row is None:
            raise NhanVatKhongTonTai("Nhân vật không tồn tại")

        blob = row["image_blob"]
        computed = tinh_character_hash(blob) if isinstance(blob, bytes) else ""
        is_valid = computed == row["character_hash"]

        return KetQuaKiemTraHash(
            character_id=character_id,
            character_hash=row["character_hash"],
            computed_hash=computed,
            is_valid=is_valid,
            byte_count=len(blob) if isinstance(blob, bytes) else 0,
        )

    def chuan_bi_onchain(
        self, character_id: str, *, chain_id: int = 31337, registry_contract: str | None = None
    ) -> DuLieuChuanBiOnchain:
        """Cung cấp dữ liệu chuẩn bị đăng ký hash on-chain vào smart contract."""
        meta = self.doc_nhan_vat(character_id)
        # Chuẩn bị bytes32 cho Solidity
        hash_bytes32 = f"0x{meta.character_hash}"
        return DuLieuChuanBiOnchain(
            character_id=meta.character_id,
            owner_wallet=meta.verified_wallet_address,
            character_hash_bytes32=hash_bytes32,
            raw_sha256=meta.character_hash,
            onchain_status=meta.onchain_status,
            chain_id=chain_id,
            registry_contract=registry_contract,
        )

    def xac_nhan_giao_dich_onchain(
        self,
        character_id: str,
        transaction_hash: str,
        *,
        nguoi_yeu_cau: NguoiChoiXacThuc,
        trang_thai: str = "pending",
    ) -> ThongTinNhanVat:
        """Quy trình Backend ghi nhận giao dịch đăng ký on-chain.

        Quy tắc bảo mật:
        - Yêu cầu mã giao dịch transaction_hash hợp lệ (0x kèm 64 ký tự hex).
        - Kiểm tra chống REPLAY: Không cho phép hai nhân vật khác nhau dùng chung một transaction_hash.
        - Khóa cứng bằng UNIQUE INDEX uq_nhan_vat_tx_hash ở tầng CSDL.
        """
        if not isinstance(character_id, str) or not re.fullmatch(r"^char_[0-9a-f]{32}$", character_id):
            raise ValueError("ID nhân vật không hợp lệ")
        if not isinstance(transaction_hash, str) or not re.fullmatch(r"^0x[0-9a-fA-F]{64}$", transaction_hash):
            raise ValueError("Transaction hash không hợp lệ (cần 0x kèm 64 ký tự hex)")
        if trang_thai not in ("not_registered", "pending", "registered", "failed"):
            raise ValueError(f"Trạng thái onchain không hợp lệ: {trang_thai}")

        tx_lower = transaction_hash.lower()

        with self._giao_dich() as conn:
            row = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()
            if row is None:
                raise NhanVatKhongTonTai("Nhân vật không tồn tại")

            if (
                row["owner_user_id"] != nguoi_yeu_cau.user_id
                and row["verified_wallet_address"].lower() != nguoi_yeu_cau.wallet_address.lower()
            ):
                raise LoiQuyenTruyCapNhanVat("Không có quyền cập nhật nhân vật này")

            # Kiểm tra chống replay transaction_hash ở tầng ứng dụng
            trung = conn.execute(
                "SELECT character_id FROM nhan_vat WHERE transaction_hash = ? AND character_id != ?",
                (tx_lower, character_id),
            ).fetchone()
            if trung is not None:
                raise GiaoDichDaDuocSuDung(
                    f"Mã giao dịch {transaction_hash} đã được sử dụng cho nhân vật {trung['character_id']}"
                )

            try:
                conn.execute(
                    """UPDATE nhan_vat
                       SET onchain_status = ?, transaction_hash = ?
                       WHERE character_id = ?""",
                    (trang_thai, tx_lower, character_id),
                )
            except sqlite3.IntegrityError:
                raise GiaoDichDaDuocSuDung(
                    f"Mã giao dịch {transaction_hash} đã được sử dụng cho một nhân vật khác"
                ) from None

            updated = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()
            return self._row_to_model(updated)

    def cap_nhat_trang_thai_onchain(
        self,
        character_id: str,
        trang_thai: str,
        *,
        transaction_hash: str | None = None,
        nguoi_yeu_cau: NguoiChoiXacThuc | None = None,
    ) -> ThongTinNhanVat:
        """Cập nhật onchain_status ('pending', 'registered', 'failed') cho nhân vật."""
        if not isinstance(character_id, str) or not re.fullmatch(r"^char_[0-9a-f]{32}$", character_id):
            raise ValueError("ID nhân vật không hợp lệ")
        if trang_thai not in ("not_registered", "pending", "registered", "failed"):
            raise ValueError(f"Trạng thái onchain không hợp lệ: {trang_thai}")

        with self._giao_dich() as conn:
            row = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()
            if row is None:
                raise NhanVatKhongTonTai("Nhân vật không tồn tại")

            if nguoi_yeu_cau is not None:
                if (
                    row["owner_user_id"] != nguoi_yeu_cau.user_id
                    and row["verified_wallet_address"].lower() != nguoi_yeu_cau.wallet_address.lower()
                ):
                    raise LoiQuyenTruyCapNhanVat("Không có quyền cập nhật nhân vật này")

            if transaction_hash is not None:
                tx_lower = transaction_hash.lower()
                trung = conn.execute(
                    "SELECT character_id FROM nhan_vat WHERE transaction_hash = ? AND character_id != ?",
                    (tx_lower, character_id),
                ).fetchone()
                if trung is not None:
                    raise GiaoDichDaDuocSuDung(
                        f"Mã giao dịch {transaction_hash} đã được sử dụng cho nhân vật {trung['character_id']}"
                    )
                try:
                    conn.execute(
                        "UPDATE nhan_vat SET onchain_status = ?, transaction_hash = ? WHERE character_id = ?",
                        (trang_thai, tx_lower, character_id),
                    )
                except sqlite3.IntegrityError:
                    raise GiaoDichDaDuocSuDung(
                        f"Mã giao dịch {transaction_hash} đã được sử dụng cho một nhân vật khác"
                    ) from None
            else:
                conn.execute(
                    "UPDATE nhan_vat SET onchain_status = ? WHERE character_id = ?",
                    (trang_thai, character_id),
                )

            updated = conn.execute(
                "SELECT * FROM nhan_vat WHERE character_id = ?", (character_id,)
            ).fetchone()
            return self._row_to_model(updated)

    @staticmethod
    def _row_to_model(row: sqlite3.Row) -> ThongTinNhanVat:
        dt = datetime.fromtimestamp(row["created_at"], tz=UTC)
        created_str = dt.isoformat()
        char_id = row["character_id"]
        return ThongTinNhanVat(
            character_id=char_id,
            owner_user_id=row["owner_user_id"],
            verified_wallet_address=row["verified_wallet_address"],
            character_hash=row["character_hash"],
            image_id=row["image_id"],
            image_url=f"/api/ai/nhan-vat/{char_id}/anh",
            image_storage_ref=row["image_storage_ref"],
            generation_source=row["generation_source"],
            created_at=created_str,
            character_status=row["character_status"],
            onchain_status=row["onchain_status"],
            transaction_hash=row["transaction_hash"],
            name=row["name"],
        )
