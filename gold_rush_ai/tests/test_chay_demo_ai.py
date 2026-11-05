"""Runner demo phải cô lập dữ liệu, tắt provider và dừng đúng tiến trình sở hữu."""
import os
from pathlib import Path
import socket
import subprocess
import sys

import httpx
import pytest

ROOT = Path(__file__).resolve().parents[1]


def module_demo():
    from scripts import chay_demo_ai
    return chay_demo_ai


def test_moi_truong_demo_co_lap_khong_sua_env_nguoi_dung(tmp_path):
    m = module_demo()
    goc = {
        "PATH": "unchanged", "ENABLED": "vang,tro_ly", "LLM_ENABLED": "true",
        "LLM_API_KEY": "secret-llm", "AI_IMAGE_ENABLED": "true", "AI_IMAGE_API_KEY": "secret-image",
        "AI_IMAGE_DB": "real-images.sqlite3", "AI_QUEST_DB": "real-quests.sqlite3",
        "APP_ROOT": "wrong", "APP_FLUTTER": "wrong", "BAN_DO_DIR": "wrong", "MAN_CHOI": "wrong",
        "CHAIN_ID": "invalid", "MAX_NHAT_KY_KB": "invalid", "TRONG_TAI_KHOA": "secret-chain",
        "UVICORN_RELOAD": "true", "WEB_CONCURRENCY": "8",
    }
    env = m.moi_truong_demo(goc, tmp_path, "a" * 32)
    assert goc["LLM_ENABLED"] == "true"
    assert goc["AI_IMAGE_DB"] == "real-images.sqlite3"
    assert env["PATH"] == "unchanged"
    assert set(env["ENABLED"].split(",")) == {"nhiem_vu", "de_xuat_do_kho", "nhan_vat_ai"}
    assert env["LLM_ENABLED"] == env["AI_IMAGE_ENABLED"] == "false"
    assert env["AI_QUEST_DEMO"] == env["AI_DIFFICULTY_DEMO"] == env["AI_IMAGE_DEMO"] == "true"
    assert "LLM_API_KEY" not in env
    assert "AI_IMAGE_API_KEY" not in env
    assert not env["TRONG_TAI_KHOA"]
    assert "UVICORN_RELOAD" not in env
    assert "WEB_CONCURRENCY" not in env
    assert Path(env["AI_QUEST_DB"]).parent == tmp_path
    assert Path(env["AI_IMAGE_DB"]).parent == tmp_path
    assert Path(env["MAN_CHOI"]).is_file()
    assert Path(env["APP_FLUTTER"]).is_dir()


@pytest.mark.parametrize("args", [["--port", "0"], ["--port", "65536"], ["--port", "abc"], ["--player", "../bad"], ["--player", ""], ["--player", "a" * 65]])
def test_cli_sai_khong_khoi_chay_server(monkeypatch, args):
    m = module_demo()
    def khong_goi(*a, **kw):
        raise AssertionError("Không được khởi chạy với đầu vào sai")
    monkeypatch.setattr(m.subprocess, "Popen", khong_goi)
    with pytest.raises(SystemExit) as exc:
        m.main(args)
    assert exc.value.code == 2


def test_loi_khoi_dong_dung_process_va_xoa_du_lieu_tam(monkeypatch, tmp_path, capsys):
    m = module_demo()
    saved = {}
    class Process:
        stopped = False
        def poll(self): return 0 if self.stopped else None
        def terminate(self): self.stopped = True
        def wait(self, timeout=None): return 0
    process = Process()
    def popen(args, **kw):
        saved.update(kw)
        saved["args"] = args
        assert kw["cwd"] == ROOT
        Path(kw["env"]["AI_QUEST_DB"]).write_bytes(b"demo")
        return process
    def loi(*args):
        raise m.LoiDemoAI("Không nạp đủ ba API AI.")
    monkeypatch.setattr(m.subprocess, "Popen", popen)
    monkeypatch.setattr(m, "cho_san_sang", loi)
    monkeypatch.setattr(m.tempfile, "gettempdir", lambda: str(tmp_path))
    assert m.main(["--kiem-tra", "--port", "8100"]) == 1
    assert process.stopped
    assert not Path(saved["env"]["AI_QUEST_DB"]).parent.exists()
    assert "--factory" in saved["args"]
    assert saved["args"][saved["args"].index("--host") + 1] == "127.0.0.1"
    assert "Không nạp đủ ba API AI." in capsys.readouterr().err


def test_ctrl_c_dung_process_so_huu_va_xoa_du_lieu(monkeypatch, tmp_path):
    m = module_demo()
    saved = {}
    class Process:
        stopped = False
        def poll(self): return 0 if self.stopped else None
        def terminate(self): self.stopped = True
        def wait(self, timeout=None):
            if not self.stopped: raise KeyboardInterrupt
            return 0
    process = Process()
    def popen(*args, **kw):
        saved.update(kw)
        return process
    monkeypatch.setattr(m.subprocess, "Popen", popen)
    monkeypatch.setattr(m, "cho_san_sang", lambda *args: None)
    monkeypatch.setattr(m.tempfile, "gettempdir", lambda: str(tmp_path))
    assert m.main(["--port", "8100"]) == 130
    assert process.stopped
    assert not Path(saved["env"]["AI_IMAGE_DB"]).parent.exists()


def test_kill_chi_khi_process_so_huu_khong_dung_trong_han():
    m = module_demo()
    class Process:
        killed = False
        def poll(self): return None
        def terminate(self): pass
        def wait(self, timeout=None):
            if not self.killed: raise subprocess.TimeoutExpired("own-demo", timeout)
            return 0
        def kill(self): self.killed = True
    p = Process()
    m.dung_server(p)
    assert p.killed


def test_readiness_khong_nhan_nham_server_khac(monkeypatch):
    m = module_demo()
    class Process:
        def poll(self): return None
    times = iter([0, 0, 100])
    monkeypatch.setattr(m.time, "monotonic", lambda: next(times))
    monkeypatch.setattr(m.time, "sleep", lambda _: None)
    calls = []
    def handler(r):
        calls.append(r.url.path)
        return httpx.Response(200, json={"da_nap": {"nhiem_vu": True, "de_xuat_do_kho": True, "nhan_vat_ai": True}})
    with httpx.Client(transport=httpx.MockTransport(handler), base_url="http://127.0.0.1:8100") as c:
        with pytest.raises(m.LoiDemoAI):
            m.cho_san_sang(Process(), c, "a" * 32)
    assert calls == ["/api/health"]


def test_readiness_khong_coi_http_200_la_da_nap_day_du():
    m = module_demo()
    class Process:
        def poll(self): return None
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200,
        headers={"X-Demo-Run": "a" * 32}, json={"da_nap": {"nhiem_vu": False}})),
        base_url="http://127.0.0.1:8100") as c:
        with pytest.raises(m.LoiDemoAI, match="Không nạp đủ"):
            m.cho_san_sang(Process(), c, "a" * 32)


def test_cli_that_kiem_tra_ca_ba_api_va_don_tam(tmp_path):
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    env = os.environ.copy()
    env.update(TEMP=str(tmp_path), TMP=str(tmp_path), PYTHONIOENCODING="utf-8",
        APP_ROOT="wrong", APP_FLUTTER="wrong", ENABLED="vang", LLM_ENABLED="true", AI_IMAGE_ENABLED="true",
        LLM_CHAT_URL="http://127.0.0.1:1/never", AI_IMAGE_URL="http://127.0.0.1:1/never")
    result = subprocess.run([sys.executable, "-B", str(ROOT / "scripts/chay_demo_ai.py"), "--kiem-tra", "--port", str(port)],
        cwd=tmp_path, env=env, capture_output=True, text=True, encoding="utf-8", timeout=45)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Nhiệm vụ: OK" in result.stdout
    assert "Độ khó: OK" in result.stdout
    assert "Ảnh nhân vật: OK" in result.stdout
    assert "GOLD_RUSH_IMAGE_DEMO_PLAYER=demo_ai" in result.stdout
    assert not list(tmp_path.glob("gold-rush-ai-demo-*"))
    with socket.socket() as sock:
        assert sock.connect_ex(("127.0.0.1", port)) != 0

def test_cong_da_dung_khong_gui_post_hoac_dung_server_cua_nguoi_khac(monkeypatch, tmp_path):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from threading import Thread
    m = module_demo()
    posts = []
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = b'{"da_nap":{"nhiem_vu":true,"de_xuat_do_kho":true,"nhan_vat_ai":true}}'
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_POST(self):
            posts.append(self.path)
            self.send_response(500)
            self.send_header("Content-Length", "0")
            self.end_headers()
        def log_message(self, *args):
            pass
    monkeypatch.setattr(m.tempfile, "gettempdir", lambda: str(tmp_path))
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as other:
        thread = Thread(target=other.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        thread.start()
        try:
            assert m.main(["--kiem-tra", "--port", str(other.server_port)]) == 1
            with httpx.Client(trust_env=False) as c:
                assert c.get(f"http://127.0.0.1:{other.server_port}/api/health", timeout=2).status_code == 200
        finally:
            other.shutdown()
            thread.join(timeout=5)
    assert not posts
    assert not list(tmp_path.glob("gold-rush-ai-demo-*"))