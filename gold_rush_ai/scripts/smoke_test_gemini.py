#!/usr/bin/env python3
"""Smoke test thực tế độc lập cho Google Gemini Image Generation.

Mặc định sử dụng model thế hệ mới: gemini-nano-banana-2.1 qua endpoint :generateContent.
(Các model Imagen cũ như imagen-3.0-generate-002 đã bị Google đóng từ tháng 8/2026).

Chỉ chạy khi người dùng chủ động thực thi:
    cd gold_rush_ai
    GEMINI_API_KEY="your_api_key_here" python scripts/smoke_test_gemini.py
Hoặc:
    python scripts/smoke_test_gemini.py --api-key "your_api_key_here"
Hoặc kiểm tra danh sách models khả dụng (chỉ đọc, miễn phí):
    python scripts/smoke_test_gemini.py --list-models

Kịch bản:
1. Đọc GEMINI_API_KEY từ biến môi trường hoặc tham số dòng lệnh (bảo mật tuyệt đối, không log key).
2. Khởi tạo GeminiRestAnhProvider với model gemini-nano-banana-2.1 (hoặc model tùy chọn).
3. Gửi prompt pixel-art thợ mỏ vàng tới Google Generative Language API.
4. Nhận ảnh base64, giải mã bytes.
5. Chuẩn hóa qua chuan_hoa_anh() thành PNG 128x128 RGBA (chuẩn preview game).
6. Tính SHA-256 character hash (khớp với CharacterRegistry.sol on-chain).
7. Ghi file ảnh kết quả ra gemini_miner_preview.png để kiểm tra trực quan.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import os
from pathlib import Path
import sys

import httpx

# Thêm thư mục gốc gold_rush_ai vào sys.path để import core
ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from core.providers.gemini_anh import DEFAULT_MODEL, GeminiRestAnhProvider, LoiProviderAnh
from core.xu_ly_anh import LoiAnhKhongHopLe, chuan_hoa_anh


def liet_ke_models(api_key: str, base_url: str = "https://generativelanguage.googleapis.com") -> int:
    """Liệt kê danh sách models khả dụng từ Google AI Studio (chỉ đọc, không tốn phí sinh ảnh)."""
    headers = {
        "x-goog-api-key": api_key,
        "Accept": "application/json",
    }
    url = f"{base_url.rstrip('/')}/v1beta/models"
    print("=" * 70)
    print("GOOGLE AI STUDIO — TRUY VẤN DANH SÁCH MODELS (CHỈ ĐỌC)")
    print("=" * 70)
    print("• API Key: [ĐÃ CẤU HÌNH — BẢO MẬT AN TOÀN, KHÔNG IN LOG]")
    print("• Endpoint: GET /v1beta/models")
    print("-" * 70)
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.get(url, headers=headers)
        if resp.status_code != 200:
            print(f"[LỖI HTTP {resp.status_code}]: {resp.text[:300]}")
            return 1
        data = resp.json()
        models = data.get("models", [])
        print(f"✓ Tìm thấy {len(models)} models khả dụng với API key này:")
        print("-" * 70)
        image_capable = []
        for m in models:
            name = m.get("name", "").replace("models/", "")
            methods = m.get("supportedGenerationMethods", [])
            display = m.get("displayName", "")
            is_image = (
                any("image" in meth.lower() for meth in methods)
                or "image" in name.lower()
                or "banana" in name.lower()
            )
            if is_image:
                image_capable.append((name, display, methods))
            print(f"  • {name:<35} | {display}")

        print("-" * 70)
        if image_capable:
            print("CÁC MODELS CÓ KHẢ NĂNG TẠO ẢNH / ĐA PHƯƠNG THỨC:")
            for name, display, methods in image_capable:
                print(f"  ★ {name:<35} | Methods: {methods}")
        else:
            print("Lưu ý: Không tìm thấy model nào có nhãn image rõ ràng. Google khuyến nghị 'gemini-nano-banana-2.1'.")
        print("=" * 70)
        return 0
    except Exception as e:
        print(f"[LỖI KẾT NỐI]: {type(e).__name__}: {e}")
        return 1


def chay_smoke_test(
    api_key: str,
    model: str = DEFAULT_MODEL,
    prompt_mo_ta: str = "Thợ mỏ vàng dũng cảm, đội mũ bảo hộ gắn đèn chiếu sáng, cầm cuốc chim và túi quặng vàng",
    output_path: str = "gemini_miner_preview.png",
) -> int:
    print("=" * 70)
    print("GOLD RUSH BLOCKCHAIN — SMOKE TEST GOOGLE GEMINI IMAGE GENERATION")
    print("=" * 70)
    print(f"• Model: {model}")
    print(f"• Prompt: {prompt_mo_ta}")
    print("• API Key: [ĐÃ CẤU HÌNH — BẢO MẬT AN TOÀN, KHÔNG IN LOG]")
    print(f"• File xuất: {output_path}")
    print("-" * 70)
    print("⚠️  CẢNH BÁO CHI PHÍ & HẠN NGẠCH:")
    print("   Script này sẽ thực hiện DUY NHẤT 1 request HTTP thật đến Google Generative Language API.")
    print("   Lượt gọi có thể phát sinh chi phí hoặc tính vào hạn ngạch Google AI Studio của bạn.")
    print("   Script chạy độc lập, an toàn: KHÔNG ghi vào CSDL nhân vật thật, KHÔNG tạo voucher.")
    print("-" * 70)

    try:
        print("[1/4] Khởi tạo GeminiRestAnhProvider...")
        provider = GeminiRestAnhProvider(
            api_key=api_key,
            model=model,
            timeout_seconds=30.0,
        )

        print(f"[2/4] Gửi yêu cầu sinh ảnh pixel-art tới Google Generative Language API (model: {model})...")
        raw_bytes = provider.sinh(
            system_prompt=(
                "Create one full-body pixel-art game character, front view, centered and fully visible. "
                "Use a square composition, a single static image with transparent background, "
                "crisp square pixels and a limited color palette."
            ),
            user_prompt=prompt_mo_ta,
        )
        print(f"      ✓ Đã nhận {len(raw_bytes):,} bytes ảnh thô từ Gemini.")

        print("[3/4] Chuẩn hóa ảnh qua Pillow thành PNG 128x128 RGBA pixel-art...")
        png_128 = chuan_hoa_anh(raw_bytes)
        print(f"      ✓ Kích thước sau chuẩn hóa: {len(png_128):,} bytes PNG (128x128).")

        print("[4/4] Tính toán SHA-256 Character Hash và lưu file kiểm tra...")
        char_hash = sha256(png_128).hexdigest()
        out_file = Path(output_path).resolve()
        out_file.write_bytes(png_128)

        print("-" * 70)
        print("KẾT QUẢ SMOKE TEST: THÀNH CÔNG RỰC RỠ!")
        print(f"• Generation Source : {provider.generation_source}")
        print(f"• SHA-256 Hash      : 0x{char_hash}")
        print(f"• Đường dẫn ảnh PNG : {out_file}")
        print("• Lưu ý             : Ảnh xem trước tĩnh 128x128, sẵn sàng lưu vào CSDL")
        print("                      và ký EIP-712 Voucher để đăng ký on-chain.")
        print("=" * 70)
        return 0

    except LoiProviderAnh as e:
        print(f"\n[LỖI PROVIDER GEMINI]: {e}")
        return 1
    except LoiAnhKhongHopLe as e:
        print(f"\n[LỖI XỬ LÝ ẢNH]: Dữ liệu ảnh trả về không hợp lệ ({e})")
        return 2
    except Exception as e:
        print(f"\n[LỖI BẤT NGỜ]: {type(e).__name__}: {e}")
        return 3


def main() -> None:
    parser = argparse.ArgumentParser(description="Smoke test Gemini Image Generation cho Gold Rush AI")
    parser.add_argument("--api-key", default=None, help="Google Gemini API key (hoặc set GEMINI_API_KEY)")
    parser.add_argument("--model", default=DEFAULT_MODEL, help=f"Tên model sinh ảnh (mặc định: {DEFAULT_MODEL})")
    parser.add_argument("--prompt", default="Thợ mỏ vàng đội mũ bảo hộ gắn đèn, cầm cuốc chim và túi vàng", help="Mô tả nhân vật")
    parser.add_argument("--out", default="gemini_miner_preview.png", help="Đường dẫn file PNG lưu kết quả")
    parser.add_argument("--list-models", action="store_true", help="Liệt kê danh sách models khả dụng (chỉ đọc, không tốn phí)")
    args = parser.parse_args()

    key = args.api_key or os.environ.get("GEMINI_API_KEY", "").strip() or os.environ.get("AI_IMAGE_API_KEY", "").strip()
    if not key:
        print("CẢNH BÁO: Chưa tìm thấy GEMINI_API_KEY.")
        print("Hãy chạy:")
        print("    export GEMINI_API_KEY='your_api_key_here'")
        print("    python scripts/smoke_test_gemini.py")
        print("Hoặc:")
        print("    python scripts/smoke_test_gemini.py --api-key 'your_api_key_here'")
        sys.exit(1)

    if args.list_models:
        sys.exit(liet_ke_models(api_key=key))

    sys.exit(chay_smoke_test(api_key=key, model=args.model, prompt_mo_ta=args.prompt, output_path=args.out))


if __name__ == "__main__":
    main()
