"""Module thẩm định và xác minh bằng chứng hoàn thành màn chơi (Giai đoạn 8).

Cơ chế xác minh Zero-Trust:
1. Không tin tưởng client khai báo "completed=true".
2. Bằng chứng Trọng tài (Referee Validation):
   - Đối soát mã ván `ma_van` trong Sổ phiếu đã cấp (`SoPhieu`) hoặc nhật ký ván chơi (`NHAT_KY_DIR`).
   - Kiểm tra tính toán đường đi Dijkstra, tốc độ George, thời gian, số xu nhặt được qua `trong_tai.kiem_dinh`.
   - Đối chiếu địa chỉ ví đăng ký với ví SIWE đang đăng nhập.
3. Bằng chứng Blockchain (On-chain Event Verification):
   - Truy vấn transaction receipt qua Ethereum JSON-RPC node.
   - Thẩm định event `DaNhanVang(address indexed nguoiChoi, bytes32 indexed maVan, uint256 man, uint256 soVang, uint256 hoanCoc)`.
   - Xác minh ví `nguoiChoi` và `man` (stage_id) khớp 100% với phiên SIWE.
4. Chống tấn công Replay Attack: mỗi mã ván hoặc tx_hash chỉ được ghi nhận tiến trình đúng MỘT lần.
"""
from __future__ import annotations

import logging
from pathlib import Path
import re
from typing import Any

from core.blockchain_verifier import BlockchainVerifier, LoiBlockchainRPC
from core.eth_ky import keccak256
from core.luoi import doc_tmx
from core.man_choi import ManChoi
from core.nhat_ky import doc_tat_ca
from core.schemas_nhan_vat import NguoiChoiXacThuc
from core.tien_trinh_storage import (
    BanGhiTienTrinh,
    KhoTienTrinh,
    LoiQuyenTienTrinh,
    LoiReplayTienTrinh,
)
from core import trong_tai

log = logging.getLogger(__name__)

MA_VAN_REGEX = re.compile(r"^[A-Za-z0-9-]+$")
TX_HASH_REGEX = re.compile(r"^0x[0-9a-fA-F]{64}$")
TOPIC_DA_NHAN_VANG = "0x" + keccak256(b"DaNhanVang(address,bytes32,uint256,uint256,uint256)").hex().lower()


class LoiXacMinhTienTrinh(ValueError):
    """Lỗi thẩm định bằng chứng hoàn thành màn chơi."""
    pass


class DichVuXacMinhTienTrinh:
    """Dịch vụ xác thực bằng chứng hoàn thành màn chơi và ghi nhận vào KhoTienTrinh."""

    def __init__(
        self,
        kho: KhoTienTrinh,
        *,
        nhat_ky_dir: Path | str | None = None,
        so_phieu_path: Path | str | None = None,
        so_ve_path: Path | str | None = None,
        cac_man: dict[int, ManChoi] | None = None,
        ban_do_dir: Path | str | None = None,
        blockchain_verifier: BlockchainVerifier | None = None,
    ):
        self.kho = kho
        self.nhat_ky_dir = Path(nhat_ky_dir) if nhat_ky_dir else None
        self.so_phieu_path = Path(so_phieu_path) if so_phieu_path else None
        self.so_ve_path = Path(so_ve_path) if so_ve_path else None
        self.cac_man = cac_man or {}
        self.ban_do_dir = Path(ban_do_dir) if ban_do_dir else None
        self.blockchain_verifier = blockchain_verifier

    def xac_minh_referee_log(
        self,
        player: NguoiChoiXacThuc,
        stage_id: int,
        ma_van: str,
    ) -> BanGhiTienTrinh:
        """Xác minh bằng chứng hoàn thành màn qua nhật ký trọng tài backend."""
        if stage_id < 1 or stage_id > 6:
            raise LoiXacMinhTienTrinh(f"stage_id không hợp lệ (phải từ 1 đến 6): {stage_id}")

        if not MA_VAN_REGEX.match(ma_van):
            raise LoiXacMinhTienTrinh("Định dạng mã ván (ma_van) không hợp lệ")

        user_wallet = player.wallet_address.lower()
        replay_key = f"referee:{ma_van}"

        # 1. Thử tìm trong Sổ Phiếu đã cấp (phiếu do máy chủ trọng tài đã thẩm định và ký)
        if self.so_phieu_path and self.so_phieu_path.exists():
            so = trong_tai.SoPhieu(self.so_phieu_path)
            phieu = so.lay(ma_van)
            if phieu is not None:
                # Kiểm tra quyền sở hữu ví trước
                if phieu.get("vi", "").lower() != user_wallet:
                    raise LoiQuyenTienTrinh("Mã ván này thuộc về địa chỉ ví khác, không thể dùng để xác minh")

                # Kiểm tra màn chơi
                p_man = int(phieu.get("man", 1))
                if p_man != stage_id:
                    raise LoiXacMinhTienTrinh(f"Mã ván này thuộc màn {p_man}, không khớp màn {stage_id}")

                evidence = {
                    "ma_van": ma_van,
                    "so_vang": phieu.get("so_vang", 0),
                    "ve": phieu.get("ve", 0),
                    "ngay": phieu.get("ngay", ""),
                }
                return self.kho.ghi_nhan_hoan_thanh(
                    owner_user_id=player.user_id,
                    verified_wallet_address=user_wallet,
                    stage_id=stage_id,
                    completion_status="completed",
                    verification_source="referee_validation",
                    completion_evidence=evidence,
                    replay_key=replay_key,
                )

        # 2. Thử tìm trong thư mục nhật ký raw (NHAT_KY_DIR) và chạy kiểm định trọng tài
        if self.nhat_ky_dir and self.nhat_ky_dir.exists():
            cac_van = doc_tat_ca(self.nhat_ky_dir)
            van = next((v for v in cac_van if v.get("ma_van") == ma_van), None)
            if van is not None:
                v_man = int(van.get("man", 1))
                if v_man != stage_id:
                    raise LoiXacMinhTienTrinh(f"Nhật ký thuộc màn {v_man}, không khớp màn {stage_id}")

                if van.get("ket_qua") != "thang":
                    raise LoiXacMinhTienTrinh("Ván chơi chưa có kết quả thắng hoàn thành màn")

                m = self.cac_man.get(stage_id)
                if m is not None and self.ban_do_dir:
                    tep_ban_do = self.ban_do_dir / m.tep
                    if tep_ban_do.exists():
                        kq = trong_tai.kiem_dinh(van, doc_tmx(tep_ban_do), m)
                        if not kq.hop_le:
                            raise LoiXacMinhTienTrinh(f"Nhật ký không vượt qua kiểm định trọng tài: {kq.ly_do}")

                # Nếu là màn có cọc, kiểm tra thêm vé đã bắt đầu
                if m is not None and not m.mien_phi and self.so_ve_path and self.so_ve_path.exists():
                    so_ve = trong_tai.SoVe(self.so_ve_path)
                    bd = so_ve.lay_theo_van(ma_van)
                    if bd is None or bd.get("vi", "").lower() != user_wallet:
                        raise LoiQuyenTienTrinh("Ván màn có cọc không được đăng ký với ví của người chơi")

                evidence = {
                    "ma_van": ma_van,
                    "diem": van.get("diem", 0),
                    "giay": van.get("giay", 0),
                    "so_xu": len([e for e in van.get("su_kien", []) if e.get("loai") == "nhat_xu"]),
                }
                return self.kho.ghi_nhan_hoan_thanh(
                    owner_user_id=player.user_id,
                    verified_wallet_address=user_wallet,
                    stage_id=stage_id,
                    completion_status="completed",
                    verification_source="referee_validation",
                    completion_evidence=evidence,
                    replay_key=replay_key,
                )

        raise LoiXacMinhTienTrinh(f"Không tìm thấy nhật ký ván chơi hợp lệ cho mã ván '{ma_van}'")

    def xac_minh_blockchain_tx(
        self,
        player: NguoiChoiXacThuc,
        stage_id: int,
        tx_hash: str,
    ) -> BanGhiTienTrinh:
        """Xác minh bằng chứng hoàn thành màn qua transaction receipt on-chain."""
        if stage_id < 1 or stage_id > 6:
            raise LoiXacMinhTienTrinh(f"stage_id không hợp lệ (phải từ 1 đến 6): {stage_id}")

        if not TX_HASH_REGEX.match(tx_hash):
            raise LoiXacMinhTienTrinh("Định dạng transaction hash không hợp lệ (cần 0x + 64 ký tự hex)")

        replay_key = f"tx:{tx_hash.lower()}"
        if self.kho.da_su_dung_replay_key(replay_key):
            bg = self.kho.lay_ban_ghi(player.user_id, stage_id)
            if bg and bg.replay_key == replay_key:
                return bg
            raise LoiReplayTienTrinh(f"Giao dịch '{tx_hash}' đã được sử dụng để xác minh tiến trình")

        if not self.blockchain_verifier or not self.blockchain_verifier.da_cau_hinh():
            raise LoiBlockchainRPC("Blockchain Verifier chưa được cấu hình RPC URL")

        user_wallet = player.wallet_address.lower()

        # 1. Truy vấn transaction receipt từ node
        receipt = self.blockchain_verifier._gui_rpc("eth_getTransactionReceipt", [tx_hash])
        if not receipt:
            raise LoiXacMinhTienTrinh(f"Giao dịch '{tx_hash}' chưa được mined hoặc không tồn tại trên chuỗi")

        status = receipt.get("status")
        if status not in ("0x1", "0x01", 1):
            raise LoiXacMinhTienTrinh(f"Giao dịch '{tx_hash}' thất bại trên blockchain (status: {status})")

        # 2. Tìm event DaNhanVang trong logs
        logs = receipt.get("logs", [])
        found_event = False
        event_stage = None
        event_ma_van = None

        for lg in logs:
            topics = lg.get("topics", [])
            if not topics or topics[0].lower() != TOPIC_DA_NHAN_VANG:
                continue

            # Topic 1: address indexed nguoiChoi (đệm 24 ký tự 0 phía trước)
            if len(topics) >= 2:
                event_wallet = "0x" + topics[1][-40:].lower()
                if event_wallet != user_wallet:
                    raise LoiQuyenTienTrinh(
                        f"Giao dịch thuộc về ví {event_wallet}, không khớp với ví {user_wallet}"
                    )

            if len(topics) >= 3:
                event_ma_van = topics[2]

            # Data: uint256 man, uint256 soVang, uint256 hoanCoc (mỗi số 64 hex chars)
            data_hex = lg.get("data", "").removeprefix("0x")
            if len(data_hex) >= 64:
                event_stage = int(data_hex[:64], 16)
                found_event = True
                break

        if not found_event:
            raise LoiXacMinhTienTrinh(
                f"Giao dịch '{tx_hash}' không chứa sự kiện DaNhanVang hợp lệ từ CuaHangGoldRush"
            )

        if event_stage != stage_id:
            raise LoiXacMinhTienTrinh(
                f"Sự kiện trên chuỗi xác nhận hoàn thành màn {event_stage}, không khớp màn {stage_id}"
            )

        evidence = {
            "transaction_hash": tx_hash.lower(),
            "block_number": receipt.get("blockNumber"),
            "event_stage": event_stage,
            "event_ma_van": event_ma_van,
        }

        return self.kho.ghi_nhan_hoan_thanh(
            owner_user_id=player.user_id,
            verified_wallet_address=user_wallet,
            stage_id=stage_id,
            completion_status="completed",
            verification_source="blockchain_event",
            completion_evidence=evidence,
            replay_key=replay_key,
        )
