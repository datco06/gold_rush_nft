"""Cấu hình tập trung — mọi giá trị ghi đè được bằng biến môi trường (giống notebook AI Web Apps)."""
import os
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
BAN_DO_DIR = Path(os.environ.get("BAN_DO_DIR", APP_FLUTTER / "assets" / "tiles"))
SO_PHIEU = Path(os.environ.get("SO_PHIEU", DATA_DIR / "phieu" / "da_cap.jsonl"))
SO_VE = Path(os.environ.get("SO_VE", DATA_DIR / "phieu" / "ve_da_bat_dau.jsonl"))
MAN_CHOI = Path(os.environ.get("MAN_CHOI", BAN_DO_DIR / "man_choi.json"))   # dùng chung với app + Ignition
