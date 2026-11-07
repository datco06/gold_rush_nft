from __future__ import annotations

import argparse
from collections.abc import Mapping
from io import BytesIO
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid

import httpx

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

_THANH_PHAN = ("nhiem_vu", "de_xuat_do_kho", "nhan_vat_ai")


class LoiDemoAI(RuntimeError):
    pass


def moi_truong_demo(goc: Mapping[str, str], thu_muc: Path, run_id: str) -> dict[str, str]:
    env = {k: v for k, v in goc.items()
           if not k.upper().startswith(("AI_", "LLM_", "UVICORN_"))
           and k.upper() != "WEB_CONCURRENCY"}
    app = ROOT.parent / "gold_rush"
    tiles = app / "assets" / "tiles"
    env.update({
        "APP_ROOT": str(ROOT), "APP_FLUTTER": str(app), "BAN_DO_DIR": str(tiles),
        "MAN_CHOI": str(tiles / "man_choi.json"),
        "ENABLED": ",".join(_THANH_PHAN),
        "LLM_ENABLED": "false", "AI_IMAGE_ENABLED": "false",
        "AI_QUEST_DEMO": "true", "AI_DIFFICULTY_DEMO": "true", "AI_IMAGE_DEMO": "true",
        "AI_QUEST_DB": str(thu_muc / "quests.sqlite3"),
        "AI_IMAGE_DB": str(thu_muc / "images.sqlite3"),
        "AI_QUOTA_DB": str(thu_muc / "quota.sqlite3"),
        "AI_IMAGE_TTL_SECONDS": "86400", "AI_IMAGE_MAX_IMAGES": "200",
        "NHAT_KY_DIR": str(thu_muc / "nhat_ky"), "SO_PHIEU": str(thu_muc / "phieu.jsonl"),
        "SO_VE": str(thu_muc / "ve.jsonl"), "MAX_NHAT_KY_KB": "64",
        "MO_HINH_DO_KHO": str(app / "assets" / "models" / "do_kho_v1.json"),
        "TRONG_TAI_KHOA": "", "HOP_DONG_CUA_HANG": "", "CHAIN_ID": "31337",
        "CORS_ORIGINS": "http://localhost:5000,http://127.0.0.1:5000,http://localhost:5173,http://localhost:8501",
        "AI_DEMO_RUN_ID": run_id, "PYTHONDONTWRITEBYTECODE": "1", "PYTHONIOENCODING": "utf-8",
    })
    return env


def ung_dung_demo():
    run_id = os.environ.get("AI_DEMO_RUN_ID", "")
    if not re.fullmatch(r"[0-9a-f]{32}", run_id):
        raise ValueError("Cần khởi chạy bằng scripts/chay_demo_ai.py")
    from api.main import app

    async def wrapper(scope, receive, send):
        async def gui(message):
            if (scope["type"] == "http" and scope["path"] == "/api/health"
                    and message["type"] == "http.response.start"):
                message = {**message, "headers": [*message.get("headers", []),
                                                (b"x-demo-run", run_id.encode("ascii"))]}
            await send(message)
        await app(scope, receive, gui)
    return wrapper


def cho_san_sang(process, client: httpx.Client, run_id: str) -> None:
    han = time.monotonic() + 15
    while time.monotonic() < han:
        if process.poll() is not None:
            raise LoiDemoAI("Máy chủ demo dừng trước khi sẵn sàng; kiểm tra cổng và log khởi động.")
        try:
            response = client.get("/api/health")
            if response.status_code == 200 and response.headers.get("x-demo-run") == run_id:
                health = response.json()
                da_nap = health.get("da_nap", {}) if isinstance(health, dict) else {}
                if not isinstance(da_nap, dict) or not all(da_nap.get(k) is True for k in _THANH_PHAN):
                    raise LoiDemoAI("Không nạp đủ ba API AI. Hãy xem log khởi động.")
                return
        except (httpx.HTTPError, ValueError):
            pass
        time.sleep(0.1)
    raise LoiDemoAI("Hết thời gian chờ máy chủ demo sẵn sàng.")


def kiem_tra_demo(client: httpx.Client, player: str) -> None:
    from PIL import Image
    from core.ca_nhan_hoa_do_kho import DeXuatDoKho
    from core.nhan_vat_ai import AnhNhanVat
    from core.nhiem_vu import NhiemVu

    headers = {"X-Demo-Player": player}
    def post(path, body, key=None):
        response = client.post(path, json=body,
            headers={**headers, **({"Idempotency-Key": key} if key else {})}, timeout=5)
        response.raise_for_status()
        return response.json()

    key = uuid.uuid4().hex
    quest_path = "/api/ai/nhiem-vu/tao"
    q = post(quest_path, {"stage_id": 1}, key)
    quest = NhiemVu.model_validate({k: v for k, v in q.items() if k != "context_source"})
    if (q.get("context_source") != "demo" or quest.generation_source not in ("demo", "rule_based")
            or quest.stage_id != 1 or post(quest_path, {"stage_id": 1}, key) != q):
        raise LoiDemoAI("Demo nhiệm vụ hoặc cache retry không đúng.")
    print("Nhiệm vụ: OK (demo, retry giữ nguyên kết quả)", flush=True)

    d = post("/api/ai/do-kho/de-xuat", {"stage_id": 1})
    difficulty = DeXuatDoKho.model_validate({k: v for k, v in d.items() if k not in ("context_source", "stage_id")})
    if (d.get("context_source") != "demo" or d.get("stage_id") != 1
            or difficulty.sample_count != 0 or difficulty.performance_score is not None
            or difficulty.adjustments.enemy_speed_multiplier != 1.0):
        raise LoiDemoAI("Demo độ khó không đúng ngữ cảnh lịch sử rỗng.")
    print("Độ khó: OK (demo, lịch sử rỗng)", flush=True)

    path = "/api/ai/nhan-vat/tao"
    body = {"description": "Thợ mỏ đội mũ vàng"}
    meta = post(path, body, key)
    anh = AnhNhanVat.model_validate({k: v for k, v in meta.items() if k != "context_source"})
    if meta.get("context_source") != "demo" or anh.generation_source != "demo" or post(path, body, key) != meta:
        raise LoiDemoAI("Demo ảnh hoặc cache retry không đúng.")
    response = client.get(anh.image_url, headers=headers, timeout=5)
    response.raise_for_status()
    if response.headers.get("content-type") != "image/png" or len(response.content) > 1024 * 1024:
        raise LoiDemoAI("Ảnh demo sai định dạng hoặc quá dung lượng.")
    with Image.open(BytesIO(response.content)) as image:
        if image.format != "PNG" or image.size != (128, 128) or image.mode != "RGBA" or image.n_frames != 1:
            raise LoiDemoAI("Ảnh demo không phải PNG tĩnh RGBA 128x128.")
        image.verify()
    with Image.open(BytesIO(response.content)) as image:
        image.load()
    other = "other_" + uuid.uuid4().hex
    if client.get(anh.image_url, headers={"X-Demo-Player": other}, timeout=5).status_code != 404:
        raise LoiDemoAI("Ảnh demo bị đọc chéo giữa người chơi.")
    print("Ảnh nhân vật: OK (PNG 128x128, cache và quyền tải ảnh)", flush=True)


def dung_server(process) -> None:
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def _cong(value: str) -> int:
    try:
        port = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("Cổng phải là số nguyên từ 1 đến 65535") from None
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("Cổng phải nằm trong 1..65535")
    return port


def _nguoi_choi(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
        raise argparse.ArgumentTypeError("Mã demo cần 1..64 ký tự ASCII: chữ, số, _ hoặc -")
    return value


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Chạy ba API AI ở chế độ demo offline, dữ liệu tạm riêng.")
    parser.add_argument("--port", type=_cong, default=8000)
    parser.add_argument("--player", type=_nguoi_choi, default="demo_ai")
    parser.add_argument("--kiem-tra", action="store_true", help="Tự thử ba API rồi dừng server và dọn dữ liệu")
    args = parser.parse_args(argv)
    process = None
    tmp_root = Path(tempfile.gettempdir()).resolve()
    try:
        with tempfile.TemporaryDirectory(prefix="gold-rush-ai-demo-", dir=tmp_root) as temp:
            data = Path(temp).resolve()
            if not data.is_relative_to(tmp_root):
                raise LoiDemoAI("Thư mục demo nằm ngoài thư mục tạm cho phép.")
            run_id = uuid.uuid4().hex
            env = moi_truong_demo(os.environ, data, run_id)
            try:
                process = subprocess.Popen(
                    [sys.executable, "-B", "-m", "uvicorn", "scripts.chay_demo_ai:ung_dung_demo", "--factory",
                     "--host", "127.0.0.1", "--port", str(args.port), "--workers", "1", "--no-access-log"],
                    cwd=ROOT, env=env,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                )
                base = f"http://127.0.0.1:{args.port}"
                with httpx.Client(base_url=base, timeout=0.5, follow_redirects=False, trust_env=False) as client:
                    cho_san_sang(process, client, run_id)
                    print(f"Demo AI sẵn sàng: {base}/docs", flush=True)
                    print("Dữ liệu demo sẽ được xóa khi dừng. Provider trả phí đã tắt.", flush=True)
                    print(f"Flutter web cùng máy (--web-port=5000): --dart-define=GOLD_RUSH_API={base}", flush=True)
                    for feature in ("QUEST", "DIFFICULTY", "IMAGE"):
                        print(f"--dart-define=GOLD_RUSH_{feature}_DEMO_PLAYER={args.player}", flush=True)
                    if args.kiem_tra:
                        kiem_tra_demo(client, args.player)
                        return 0
                print("Nhấn Ctrl+C để dừng demo.", flush=True)
                return process.wait()
            finally:
                dung_server(process)
    except KeyboardInterrupt:
        print("Đã dừng demo AI.", flush=True)
        return 130
    except (LoiDemoAI, OSError, httpx.HTTPError, ValueError) as e:
        message = str(e) if isinstance(e, LoiDemoAI) else type(e).__name__
        print(f"Demo AI chưa hoàn tất: {message}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
