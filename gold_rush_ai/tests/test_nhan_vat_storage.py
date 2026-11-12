from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import sqlite3
import pytest
from PIL import Image

from core.nhan_vat_storage import (
    GiaoDichDaDuocSuDung,
    KhoNhanVat,
    KhoNhanVatDay,
    LoiKhoNhanVat,
    LoiMigrationKhoNhanVat,
    LoiQuyenTruyCapNhanVat,
    LoiToanVenNhanVat,
    NhanVatKhongTonTai,
    VuotGioiHanNhanVat,
    tinh_character_hash,
)
from core.schemas_nhan_vat import NguoiChoiXacThuc
from core.xu_ly_anh import chuan_hoa_anh


def tao_anh_png_mau(color="blue"):
    with Image.new("RGBA", (128, 128), color) as img, BytesIO() as buf:
        img.save(buf, format="PNG")
        return buf.getvalue()


@pytest.fixture
def player_a():
    return NguoiChoiXacThuc(
        user_id="user_11111111-1111-1111-1111-111111111111",
        wallet_address="0x1111111111111111111111111111111111111111",
        username="PlayerOne",
    )


@pytest.fixture
def player_b():
    return NguoiChoiXacThuc(
        user_id="user_22222222-2222-2222-2222-222222222222",
        wallet_address="0x2222222222222222222222222222222222222222",
        username="PlayerTwo",
    )


def test_tinh_character_hash_on_dinh():
    raw_png = tao_anh_png_mau("red")
    chuan_png = chuan_hoa_anh(raw_png)
    hash_1 = tinh_character_hash(chuan_png)
    hash_2 = tinh_character_hash(chuan_png)
    assert hash_1 == hash_2
    assert len(hash_1) == 64
    assert hash_1.islower()
    different_png = chuan_hoa_anh(tao_anh_png_mau("green"))
    assert tinh_character_hash(different_png) != hash_1


def test_luu_va_doc_nhan_vat_thanh_cong(tmp_path, player_a):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("gold")
    image_id = "img_0123456789abcdef0123456789abcdef"

    char = kho.luu_nhan_vat(
        player=player_a,
        image_id=image_id,
        image_bytes=png_data,
        generation_source="image_model",
        name="Hiệp sĩ vàng",
    )

    assert char.character_id.startswith("char_")
    assert char.owner_user_id == player_a.user_id
    assert char.verified_wallet_address == player_a.wallet_address.lower()
    assert char.image_id == image_id
    assert char.name == "Hiệp sĩ vàng"
    assert char.generation_source == "image_model"
    assert char.character_status == "active"
    assert char.onchain_status == "not_registered"
    assert char.transaction_hash is None
    assert char.preview_ready is True
    assert char.playable_ready is False
    assert "storage://characters/" in char.image_storage_ref
    assert str(tmp_path) not in char.image_storage_ref

    doc_char = kho.doc_nhan_vat(char.character_id, nguoi_yeu_cau=player_a)
    assert doc_char.character_id == char.character_id
    assert doc_char.character_hash == char.character_hash

    meta, blob = kho.doc_anh_nhan_vat(char.character_id, nguoi_yeu_cau=player_a)
    assert meta.character_id == char.character_id
    assert tinh_character_hash(blob) == char.character_hash


def test_kho_nhan_vat_ton_tai_qua_restart_backend(tmp_path, player_a):
    db_path = tmp_path / "characters.sqlite3"
    kho_1 = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("purple")
    image_id = "img_abcdef0123456789abcdef0123456789"

    saved = kho_1.luu_nhan_vat(
        player=player_a,
        image_id=image_id,
        image_bytes=png_data,
        generation_source="image_model",
        name="Thợ mỏ tím",
    )

    del kho_1
    kho_2 = KhoNhanVat(db_path)

    reloaded = kho_2.doc_nhan_vat(saved.character_id, nguoi_yeu_cau=player_a)
    assert reloaded.character_id == saved.character_id
    assert reloaded.character_hash == saved.character_hash
    assert reloaded.owner_user_id == player_a.user_id

    _, blob = kho_2.doc_anh_nhan_vat(saved.character_id, nguoi_yeu_cau=player_a)
    assert tinh_character_hash(blob) == saved.character_hash


def test_luu_nhan_vat_idempotent_cung_image_id(tmp_path, player_a):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("cyan")
    image_id = "img_00000000000000000000000000000001"

    first = kho.luu_nhan_vat(
        player=player_a,
        image_id=image_id,
        image_bytes=png_data,
        generation_source="demo",
        name="Bản đầu",
    )

    second = kho.luu_nhan_vat(
        player=player_a,
        image_id=image_id,
        image_bytes=png_data,
        generation_source="demo",
        name="Bản thứ hai thử lưu trùng",
    )

    assert first.character_id == second.character_id
    assert first.character_hash == second.character_hash

    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0] == 1


def test_kiem_soat_quyen_truy_cap_vi_a_khong_doc_duoc_vi_b(tmp_path, player_a, player_b):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("black")

    char_a = kho.luu_nhan_vat(
        player=player_a,
        image_id="img_11111111111111111111111111111111",
        image_bytes=png_data,
        generation_source="demo",
        name="Của A",
    )

    with pytest.raises(LoiQuyenTruyCapNhanVat):
        kho.doc_nhan_vat(char_a.character_id, nguoi_yeu_cau=player_b)

    with pytest.raises(LoiQuyenTruyCapNhanVat):
        kho.doc_anh_nhan_vat(char_a.character_id, nguoi_yeu_cau=player_b)

    danh_sach_a = kho.danh_sach_nhan_vat(player_a)
    assert len(danh_sach_a) == 1
    assert danh_sach_a[0].character_id == char_a.character_id

    danh_sach_b = kho.danh_sach_nhan_vat(player_b)
    assert len(danh_sach_b) == 0


def test_phat_hien_sai_lech_toan_ven_sha256_khi_du_lieu_bi_sua(tmp_path, player_a):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("orange")

    char = kho.luu_nhan_vat(
        player=player_a,
        image_id="img_22222222222222222222222222222222",
        image_bytes=png_data,
        generation_source="image_model",
    )

    kiem_tra = kho.kiem_tra_hash(char.character_id)
    assert kiem_tra.is_valid is True
    assert kiem_tra.computed_hash == char.character_hash

    tampered_bytes = b"fake-corrupted-image-content-bytes"
    with sqlite3.connect(db_path) as conn:
        conn.execute(
            "UPDATE nhan_vat SET image_blob = ? WHERE character_id = ?",
            (tampered_bytes, char.character_id),
        )

    kiem_tra_sau = kho.kiem_tra_hash(char.character_id)
    assert kiem_tra_sau.is_valid is False
    assert kiem_tra_sau.computed_hash != char.character_hash

    with pytest.raises(LoiToanVenNhanVat):
        kho.doc_anh_nhan_vat(char.character_id, nguoi_yeu_cau=player_a)


def test_gioi_han_so_nhan_vat_moi_nguoi_va_toan_kho(tmp_path, player_a, player_b):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path, so_nhan_vat_moi_nguoi=2, so_nhan_vat_toi_da=3)
    png_data = tao_anh_png_mau("blue")

    kho.luu_nhan_vat(player=player_a, image_id="img_00000000000000000000000000000001", image_bytes=png_data, generation_source="demo")
    kho.luu_nhan_vat(player=player_a, image_id="img_00000000000000000000000000000002", image_bytes=png_data, generation_source="demo")

    with pytest.raises(VuotGioiHanNhanVat):
        kho.luu_nhan_vat(player=player_a, image_id="img_00000000000000000000000000000003", image_bytes=png_data, generation_source="demo")

    kho.luu_nhan_vat(player=player_b, image_id="img_00000000000000000000000000000004", image_bytes=png_data, generation_source="demo")

    with pytest.raises(KhoNhanVatDay):
        kho.luu_nhan_vat(player=player_b, image_id="img_00000000000000000000000000000005", image_bytes=png_data, generation_source="demo")


def test_chuan_bi_va_xac_nhan_onchain(tmp_path, player_a, player_b):
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("yellow")

    char = kho.luu_nhan_vat(
        player=player_a,
        image_id="img_33333333333333333333333333333333",
        image_bytes=png_data,
        generation_source="image_model",
    )

    data_onchain = kho.chuan_bi_onchain(char.character_id, chain_id=31337, registry_contract="0x1234567890123456789012345678901234567890")
    assert data_onchain.character_id == char.character_id
    assert data_onchain.owner_wallet == player_a.wallet_address.lower()
    assert data_onchain.character_hash_bytes32 == f"0x{char.character_hash}"
    assert data_onchain.raw_sha256 == char.character_hash
    assert data_onchain.onchain_status == "not_registered"

    valid_tx = "0x" + "a" * 64
    with pytest.raises(LoiQuyenTruyCapNhanVat):
        kho.xac_nhan_giao_dich_onchain(char.character_id, valid_tx, nguoi_yeu_cau=player_b)

    updated = kho.xac_nhan_giao_dich_onchain(char.character_id, valid_tx, nguoi_yeu_cau=player_a)
    assert updated.onchain_status == "pending"
    assert updated.transaction_hash == valid_tx.lower()


# ==================== CÁC TEST MỚI CHO AI-002, AI-004, AI-005 ====================

def test_chong_replay_transaction_hash_ai_002(tmp_path, player_a, player_b):
    """Nhiệm vụ 1: Chống replay transaction hash giữa các nhân vật."""
    db_path = tmp_path / "characters.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("white")

    char_1 = kho.luu_nhan_vat(player=player_a, image_id="img_10000000000000000000000000000001", image_bytes=png_data, generation_source="demo")
    char_2 = kho.luu_nhan_vat(player=player_a, image_id="img_10000000000000000000000000000002", image_bytes=png_data, generation_source="demo")
    char_3 = kho.luu_nhan_vat(player=player_b, image_id="img_10000000000000000000000000000003", image_bytes=png_data, generation_source="demo")

    tx_shared = "0x" + "e" * 64

    # Nhân vật 1 gán tx_shared thành công
    kho.xac_nhan_giao_dich_onchain(char_1.character_id, tx_shared, nguoi_yeu_cau=player_a)

    # Nhân vật 2 (cùng ví A) thử dùng lại tx_shared -> bị chặn
    with pytest.raises(GiaoDichDaDuocSuDung) as exc:
        kho.xac_nhan_giao_dich_onchain(char_2.character_id, tx_shared, nguoi_yeu_cau=player_a)
    assert "đã được sử dụng" in str(exc.value)

    # Nhân vật 3 (ví B khác) thử dùng lại tx_shared -> cũng bị chặn
    with pytest.raises(GiaoDichDaDuocSuDung):
        kho.xac_nhan_giao_dich_onchain(char_3.character_id, tx_shared, nguoi_yeu_cau=player_b)

    # Nhân vật 1 gửi lại chính tx_shared (idempotent update cho chính mình) -> được phép
    kho.xac_nhan_giao_dich_onchain(char_1.character_id, tx_shared, nguoi_yeu_cau=player_a)

    # Nhiều nhân vật cùng có transaction_hash=NULL không xung đột UNIQUE
    assert char_2.transaction_hash is None
    assert char_3.transaction_hash is None


def test_migration_database_cu_thanh_cong(tmp_path, player_a):
    """Nhiệm vụ 1 & 2: Database phiên bản cũ được nâng cấp tạo UNIQUE INDEX an toàn."""
    db_path = tmp_path / "old_characters.sqlite3"

    # Tạo thủ công CSDL phiên bản cũ (không có uq_nhan_vat_owner_image và uq_nhan_vat_tx_hash)
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE nhan_vat (
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
        conn.execute("CREATE INDEX ix_nhan_vat_owner_image ON nhan_vat(owner_user_id, image_id);")
        # Chèn bản ghi hợp lệ
        old_char_id = "char_" + "1" * 32
        old_img_id = "img_" + "1" * 32
        png = tao_anh_png_mau("teal")
        h = tinh_character_hash(chuan_hoa_anh(png))
        conn.execute("""
            INSERT INTO nhan_vat VALUES
            (?, 'user_1', '0x1111111111111111111111111111111111111111', ?, ?, 'ref1', ?, 'demo', 1000.0, 'active', 'not_registered', NULL, 'Old 1', 'desc')
        """, (old_char_id, h, old_img_id, png))

    # Khởi tạo KhoNhanVat trên CSDL cũ -> Kích hoạt migration tự động
    kho = KhoNhanVat(db_path)

    # Kiểm tra bản ghi cũ vẫn còn nguyên vẹn
    reloaded = kho.doc_nhan_vat(old_char_id)
    assert reloaded.character_id == old_char_id
    assert reloaded.character_hash == h
    _, blob = kho.doc_anh_nhan_vat(old_char_id)
    assert tinh_character_hash(blob) == h

    # Kiểm tra các unique index mới đã được tạo thành công
    with sqlite3.connect(db_path) as conn:
        indexes = {row[1] for row in conn.execute("PRAGMA index_list('nhan_vat')").fetchall()}
        assert "uq_nhan_vat_owner_image" in indexes
        assert "uq_nhan_vat_tx_hash" in indexes
        assert "ix_nhan_vat_owner_image" not in indexes


def test_migration_dung_khi_phat_hien_trung_lap_owner_image(tmp_path):
    """Nhiệm vụ 2: Dừng migration và bảo toàn dữ liệu khi phát hiện trùng lặp (owner_user_id, image_id)."""
    db_path = tmp_path / "dup_image_db.sqlite3"
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE nhan_vat (
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
        # Chèn 2 bản ghi cố tình trùng (user_1, img_same)
        png = tao_anh_png_mau("pink")
        h = tinh_character_hash(chuan_hoa_anh(png))
        conn.execute("INSERT INTO nhan_vat VALUES ('char_dup1', 'user_1', '0x1111', ?, 'img_same', 'ref', ?, 'demo', 100.0, 'active', 'not_reg', NULL, NULL, NULL)", (h, png))
        conn.execute("INSERT INTO nhan_vat VALUES ('char_dup2', 'user_1', '0x1111', ?, 'img_same', 'ref', ?, 'demo', 101.0, 'active', 'not_reg', NULL, NULL, NULL)", (h, png))

    # Migration phải dừng và báo lỗi, tuyệt đối không tự xóa dữ liệu
    with pytest.raises(LoiMigrationKhoNhanVat) as exc:
        KhoNhanVat(db_path)
    assert "bị trùng lặp" in str(exc.value)

    # Dữ liệu cũ phải được giữ nguyên vẹn 2 bản ghi
    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0] == 2


def test_migration_dung_khi_phat_hien_trung_lap_tx_hash(tmp_path):
    """Nhiệm vụ 1: Dừng migration và bảo toàn dữ liệu khi phát hiện trùng lặp transaction_hash."""
    db_path = tmp_path / "dup_tx_db.sqlite3"
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE nhan_vat (
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
        png = tao_anh_png_mau("pink")
        h = tinh_character_hash(chuan_hoa_anh(png))
        same_tx = "0x" + "9" * 64
        conn.execute("INSERT INTO nhan_vat VALUES ('char_tx1', 'user_1', '0x1111', ?, 'img_1', 'ref', ?, 'demo', 100.0, 'active', 'pending', ?, NULL, NULL)", (h, png, same_tx))
        conn.execute("INSERT INTO nhan_vat VALUES ('char_tx2', 'user_2', '0x2222', ?, 'img_2', 'ref', ?, 'demo', 101.0, 'active', 'pending', ?, NULL, NULL)", (h, png, same_tx))

    with pytest.raises(LoiMigrationKhoNhanVat) as exc:
        KhoNhanVat(db_path)
    assert "transaction_hash bị trùng lặp" in str(exc.value)

    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0] == 2


def test_transaction_rollback_khi_phat_sinh_loi_ai_005(tmp_path, player_a, monkeypatch):
    """Nhiệm vụ 3: Đảm bảo transaction được rollback sạch sẽ khi có lỗi phát sinh giữa chừng."""
    db_path = tmp_path / "rollback_test.sqlite3"
    kho = KhoNhanVat(db_path)
    png_data = tao_anh_png_mau("red")

    # Giả lập lỗi ở bước cuối cùng sau khi đã INSERT nhưng trước khi return
    original_row_to_model = kho._row_to_model
    def loi_gia_lap(row):
        raise RuntimeError("Lỗi bất ngờ trong quá trình parse model")

    monkeypatch.setattr(kho, "_row_to_model", loi_gia_lap)

    with pytest.raises(RuntimeError) as exc:
        kho.luu_nhan_vat(
            player=player_a,
            image_id="img_" + "e" * 32,
            image_bytes=png_data,
            generation_source="demo",
        )
    assert "Lỗi bất ngờ" in str(exc.value)

    # Khôi phục hàm cũ và kiểm tra: CSDL hoàn toàn không có bản ghi nào bị lưu dở dang
    monkeypatch.setattr(kho, "_row_to_model", original_row_to_model)
    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0] == 0


def test_luu_dong_thoi_cung_image_id_va_khac_image_id(tmp_path, player_a):
    """Nhiệm vụ 3 & 4: Kiểm tra khả năng xử lý concurrency nhiều thread gọi đồng thời."""
    db_path = tmp_path / "concurrent.sqlite3"
    kho = KhoNhanVat(db_path, so_nhan_vat_moi_nguoi=20)
    png_data = tao_anh_png_mau("green")

    # 1. 10 thread cùng lưu một image_id -> Đảm bảo chỉ tạo đúng 1 bản ghi và đều nhận kết quả thành công
    same_img = "img_" + "a" * 32
    def save_same():
        return kho.luu_nhan_vat(player=player_a, image_id=same_img, image_bytes=png_data, generation_source="demo")

    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(lambda _: save_same(), range(10)))

    # Tất cả các thread đều nhận cùng character_id
    first_char_id = results[0].character_id
    assert all(r.character_id == first_char_id for r in results)
    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat WHERE image_id = ?", (same_img,)).fetchone()[0] == 1

    # 2. 5 thread lưu 5 image_id khác nhau đồng thời -> Không bị deadlock, tất cả đều thành công
    def save_diff(i):
        img_id = f"img_{i:032x}"
        return kho.luu_nhan_vat(player=player_a, image_id=img_id, image_bytes=png_data, generation_source="demo")

    with ThreadPoolExecutor(max_workers=5) as pool:
        diff_results = list(pool.map(save_diff, range(5)))

    assert len({r.character_id for r in diff_results}) == 5
    with sqlite3.connect(db_path) as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat").fetchone()[0] == 6  # 1 bản ghi đầu + 5 bản ghi mới
