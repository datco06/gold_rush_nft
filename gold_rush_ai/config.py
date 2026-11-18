"""Cấu hình tập trung — mọi giá trị ghi đè được bằng biến môi trường (giống notebook AI Web Apps)."""
import os
from decimal import Decimal, InvalidOperation
from pathlib import Path

ROOT = Path(os.environ.get("APP_ROOT", Path(__file__).resolve().parent))
DATA_DIR = ROOT / "data"
ART_DIR = ROOT / "artifacts"
KB_DIR = Path(os.environ.get("KB_DIR", DATA_DIR / "kb"))
NHAT_KY_DIR = Path(os.environ.get("NHAT_KY_DIR", DATA_DIR / "nhat_ky"))

# Mô hình độ khó đang phục vụ: đổi phiên bản = đổi biến môi trường, không sửa code
MO_HINH_DO_KHO = Path(os.environ.get("MO_HINH_DO_KHO", ART_DIR / "do_kho" / "do_kho_v1.json"))

# Thư mục app Flutter — script huấn luyện chép mô hình sang assets/models/ của app
APP_FLUTTER = Path(os.environ.get("APP_FLUTTER", ROOT.parent / "gold_rush"))

ENABLED = {m.strip() for m in os.environ.get("ENABLED", "do_kho,tro_ly,ban_do,nhat_ky,vang").split(",") if m.strip()}
CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "http://localhost:8501,http://localhost:5173,http://localhost:5000").split(",")
MAX_NHAT_KY_KB = int(os.environ.get("MAX_NHAT_KY_KB", "64"))

# ---- Blockchain (đề xuất cửa hàng nhân vật) — CHỈ mạng thử nghiệm ----
# Khoá bí mật của trọng tài: đặt bằng biến môi trường / Secrets, KHÔNG BAO GIỜ ghi vào mã hay Git.
TRONG_TAI_KHOA = os.environ.get("TRONG_TAI_KHOA", "")
CHAIN_ID = int(os.environ.get("CHAIN_ID", "31337"))                  # 31337 Hardhat · 11155111 Sepolia
HOP_DONG_CUA_HANG = os.environ.get("HOP_DONG_CUA_HANG", "")         # địa chỉ sau khi triển khai
HOP_DONG_VAT_PHAM = os.environ.get("HOP_DONG_VAT_PHAM", "")         # ERC-1155 vật phẩm transferable
HOP_DONG_SBT = os.environ.get("HOP_DONG_SBT", "")                   # ThanhTuuSBT ERC-721 soulbound
BLOCKCHAIN_RPC_URL = os.environ.get("BLOCKCHAIN_RPC_URL", os.environ.get("AI_BLOCKCHAIN_RPC_URL", ""))
RPC_TIMEOUT_SECONDS = float(os.environ.get("RPC_TIMEOUT_SECONDS", "5.0"))
# Chỉ phục vụ Hardhat local. Không bật trên Sepolia/mainnet.
LOCAL_FAUCET_ENABLED = os.environ.get("LOCAL_FAUCET_ENABLED", "false").lower() in ("true", "1")
LOCAL_FAUCET_AMOUNT_WEI = int(os.environ.get("LOCAL_FAUCET_AMOUNT_WEI", "10000000000000000000000"))

# Sepolia faucet — chỉ bật tường minh trên Backend, không dùng cho Hardhat local.
SEPOLIA_CHAIN_ID = 11155111
SEPOLIA_FAUCET_EXPECTED_ADDRESS = "0xa93BE13C54197457602437eC6EF9B8F7bA36B36A"
SEPOLIA_FAUCET_ENABLED = os.environ.get("SEPOLIA_FAUCET_ENABLED", "false").lower() in ("true", "1")
SEPOLIA_FAUCET_ADDRESS = os.environ.get(
    "SEPOLIA_FAUCET_ADDRESS", SEPOLIA_FAUCET_EXPECTED_ADDRESS
)
SEPOLIA_FAUCET_PRIVATE_KEY = os.environ.get("SEPOLIA_FAUCET_PRIVATE_KEY", "")


def _eth_sang_wei(ten: str, mac_dinh: str) -> int:
    try:
        value = Decimal(os.environ.get(ten, mac_dinh))
    except (InvalidOperation, ValueError):
        raise ValueError(f"{ten} phải là số ETH hợp lệ") from None
    if value < 0 or value.as_tuple().exponent < -18:
        raise ValueError(f"{ten} phải không âm và có tối đa 18 chữ số thập phân")
    return int(value * Decimal(10**18))


SEPOLIA_FAUCET_LOW_BALANCE_WEI = _eth_sang_wei("SEPOLIA_FAUCET_LOW_BALANCE_ETH", "0.001")
# Mỗi ví được bù số dư lên 0.5 Sepolia ETH. Các biến giới hạn bên dưới được
# giữ lại để tương thích cấu hình cũ, nhưng Faucet hiện không áp dụng chúng.
SEPOLIA_FAUCET_TARGET_BALANCE_WEI = _eth_sang_wei("SEPOLIA_FAUCET_TARGET_BALANCE_ETH", "0.5")
SEPOLIA_FAUCET_MAX_PER_WALLET_DAY_WEI = _eth_sang_wei(
    "SEPOLIA_FAUCET_MAX_PER_WALLET_DAY_ETH", "0.006"
)
SEPOLIA_FAUCET_MAX_TOTAL_DAY_WEI = _eth_sang_wei("SEPOLIA_FAUCET_MAX_TOTAL_DAY_ETH", "0.05")
SEPOLIA_FAUCET_COOLDOWN_SECONDS = int(os.environ.get("SEPOLIA_FAUCET_COOLDOWN_SECONDS", "3600"))
SEPOLIA_FAUCET_MAX_REQUESTS_PER_HOUR = int(
    os.environ.get("SEPOLIA_FAUCET_MAX_REQUESTS_PER_HOUR", "3")
)
SEPOLIA_FAUCET_RECEIPT_TIMEOUT_SECONDS = float(
    os.environ.get("SEPOLIA_FAUCET_RECEIPT_TIMEOUT_SECONDS", "30")
)

# ThanhTuuSBT — chỉ ký phiếu; giao dịch mint vẫn do ví người chơi ký.
SBT_ENABLED = os.environ.get("SBT_ENABLED", "false").lower() in ("true", "1")
SBT_CHAIN_ID = int(os.environ.get("SBT_CHAIN_ID", str(CHAIN_ID)))
SBT_SIGNER_PRIVATE_KEY = os.environ.get("SBT_SIGNER_PRIVATE_KEY", "")
SBT_AUTHORIZED_SIGNER = os.environ.get("SBT_AUTHORIZED_SIGNER", "")
SBT_VOUCHER_TTL_SECONDS = int(os.environ.get("SBT_VOUCHER_TTL_SECONDS", "900"))
# Phí gas quy đổi cố định bằng vàng trong môi trường test. 0 = không trừ phí.
GAS_FEE_GOLD = int(os.environ.get("GAS_FEE_GOLD", "0"))
BAN_DO_DIR = Path(os.environ.get("BAN_DO_DIR", APP_FLUTTER / "assets" / "tiles"))
SO_PHIEU = Path(os.environ.get("SO_PHIEU", DATA_DIR / "phieu" / "da_cap.jsonl"))
SO_VE = Path(os.environ.get("SO_VE", DATA_DIR / "phieu" / "ve_da_bat_dau.jsonl"))
MAN_CHOI = Path(os.environ.get("MAN_CHOI", BAN_DO_DIR / "man_choi.json"))   # dùng chung với app + Ignition
CSDL_PATH = Path(os.environ.get("CSDL_PATH", DATA_DIR / "gold_rush.db"))
QUA_TANG_CODES_JSON = Path(os.environ.get("QUA_TANG_CODES_JSON", DATA_DIR / "qua_tang" / "codes.json"))

# Lưu trữ nhân vật AI bền vững (tách biệt khỏi preview cache có TTL)
AI_CHARACTER_DB = Path(os.environ.get("AI_CHARACTER_DB", DATA_DIR / "nhan_vat" / "characters.sqlite3"))
AI_MAX_CHARACTERS_PER_USER = int(os.environ.get("AI_MAX_CHARACTERS_PER_USER", "20"))
AI_MAX_CHARACTERS_TOTAL = int(os.environ.get("AI_MAX_CHARACTERS_TOTAL", "10000"))
HOP_DONG_DANG_KY_NHAN_VAT = os.environ.get("HOP_DONG_DANG_KY_NHAN_VAT", "")
AI_IMAGE_MIN_INTERVAL_SECONDS = float(os.environ.get("AI_IMAGE_MIN_INTERVAL_SECONDS", "20"))

# Blockchain RPC & Character Registry Verifier (AI-001)
AI_BLOCKCHAIN_RPC_URL = os.environ.get("AI_BLOCKCHAIN_RPC_URL", "")
AI_BLOCKCHAIN_CHAIN_ID = int(os.environ.get("AI_BLOCKCHAIN_CHAIN_ID", os.environ.get("CHAIN_ID", "31337")))
AI_CHARACTER_REGISTRY_ADDRESS = os.environ.get(
    "AI_CHARACTER_REGISTRY_ADDRESS",
    os.environ.get("HOP_DONG_DANG_KY_NHAN_VAT", ""),
)
AI_BLOCKCHAIN_MIN_CONFIRMATIONS = int(os.environ.get("AI_BLOCKCHAIN_MIN_CONFIRMATIONS", "1"))
AI_BLOCKCHAIN_TIMEOUT_SECONDS = float(os.environ.get("AI_BLOCKCHAIN_TIMEOUT_SECONDS", "5.0"))

# EIP-712 Character Voucher Signer (Giai đoạn 4)
AI_CHARACTER_SIGNER_PRIVATE_KEY = os.environ.get("AI_CHARACTER_SIGNER_PRIVATE_KEY", os.environ.get("TRONG_TAI_KHOA", ""))
AI_CHARACTER_AUTHORIZED_SIGNER = os.environ.get("AI_CHARACTER_AUTHORIZED_SIGNER", "")
AI_CHARACTER_VOUCHER_TTL_SECONDS = int(os.environ.get("AI_CHARACTER_VOUCHER_TTL_SECONDS", "1800"))
AI_CHARACTER_VOUCHER_ENABLED = os.environ.get("AI_CHARACTER_VOUCHER_ENABLED", "true").lower() in ("true", "1")

# Lưu trữ tiến trình màn chơi (1-6) gắn với SIWE Auth (Fail-Closed)
AI_PROGRESS_DB = Path(os.environ.get("AI_PROGRESS_DB", DATA_DIR / "progress" / "progress.sqlite3"))
