from __future__ import annotations

import base64
from collections.abc import Mapping
from contextlib import nullcontext
from dataclasses import dataclass
import json
import logging
import math
import os
import re
from typing import Literal

import httpx

from .anh import LoiProviderAnh

log = logging.getLogger(__name__)

_GIOI_HAN_JSON = 8 * 1024 * 1024
_GIOI_HAN_ANH = 5 * 1024 * 1024


DEFAULT_MODEL = "gemini-3.1-flash-image"


@dataclass(frozen=True)
class ChanDoanLoi429:
    """Cấu trúc dữ liệu chẩn đoán chi tiết lỗi HTTP 429 từ Google Gemini API."""

    loai_quota: Literal["quota_zero", "rate_limit_minute", "daily_quota_exhausted", "insufficient_info"]
    mo_ta_loai: str
    status: str
    message: str
    quota_metric: str | None = None
    quota_id: str | None = None
    quota_value: str | None = None
    retry_delay: str | None = None
    retry_after: str | None = None
    huong_dan_khac_phuc: str = ""


class LoiQuotaGemini(LoiProviderAnh):
    """Lỗi hạn ngạch HTTP 429 từ Google Gemini API kèm thông tin chẩn đoán có cấu trúc."""

    def __init__(self, message: str, chan_doan: ChanDoanLoi429):
        super().__init__(message)
        self.chan_doan = chan_doan


def phan_tich_loi_429(
    body: bytes,
    headers: Mapping[str, str] | None = None,
    api_key: str | None = None,
) -> ChanDoanLoi429:
    """Phân tích cấu trúc lỗi JSON chi tiết từ Google khi gặp HTTP 429 (RESOURCE_EXHAUSTED).

    Phân tích:
    - status, message
    - QuotaFailure (violations: quotaMetric, quotaId, quotaValue, description)
    - RetryInfo (retryDelay)
    - ErrorInfo (reason, metadata)
    - Header Retry-After
    - Phân loại: quota_zero | rate_limit_minute | daily_quota_exhausted | insufficient_info
    - Khử toàn bộ API key hoặc thông tin nhạy cảm.
    """
    status = "RESOURCE_EXHAUSTED"
    message = ""
    quota_metric: str | None = None
    quota_id: str | None = None
    quota_value: str | None = None
    retry_delay: str | None = None
    description_text = ""

    retry_after: str | None = None
    if headers:
        for k, v in headers.items():
            if k.lower() == "retry-after":
                retry_after = str(v).strip()
                break

    try:
        data = json.loads(body)
        if isinstance(data, dict) and "error" in data:
            err = data["error"]
            if isinstance(err, dict):
                status = str(err.get("status") or "RESOURCE_EXHAUSTED")
                message = str(err.get("message") or "")
                details = err.get("details")
                if isinstance(details, list):
                    for d in details:
                        if not isinstance(d, dict):
                            continue
                        dtype = str(d.get("@type", ""))
                        if "QuotaFailure" in dtype:
                            violations = d.get("violations", [])
                            if isinstance(violations, list) and violations:
                                v0 = violations[0]
                                if isinstance(v0, dict):
                                    quota_metric = v0.get("quotaMetric") or quota_metric
                                    quota_id = v0.get("quotaId") or quota_id
                                    if v0.get("quotaValue") is not None:
                                        quota_value = str(v0.get("quotaValue"))
                                    description_text = str(v0.get("description") or "")
                        elif "RetryInfo" in dtype:
                            retry_delay = d.get("retryDelay") or retry_delay
                        elif "ErrorInfo" in dtype:
                            meta = d.get("metadata", {})
                            if isinstance(meta, dict):
                                quota_metric = meta.get("quota_metric") or quota_metric
                                q_val = meta.get("quota_limit_value") or meta.get("quota_limit")
                                if q_val is not None:
                                    quota_value = str(q_val)
                                quota_id = meta.get("quota_id") or quota_id
            else:
                message = str(err)
    except Exception:
        message = body.decode("utf-8", errors="replace")[:300]

    # Khử vết tích khóa bí mật
    if api_key:
        message = message.replace(api_key, "[REDACTED_API_KEY]")
        description_text = description_text.replace(api_key, "[REDACTED_API_KEY]")
    message = re.sub(r"AIza[0-9A-Za-z-_]{35}", "[REDACTED_API_KEY]", message)
    description_text = re.sub(r"AIza[0-9A-Za-z-_]{35}", "[REDACTED_API_KEY]", description_text)

    combined_text = f"{message} {description_text} {quota_id or ''} {quota_metric or ''}".lower()

    # Phân loại:
    # 1. Hạn ngạch bằng 0: quota_value là '0' hoặc thông báo nói rõ limit = 0
    is_quota_zero = (
        quota_value in ("0", "0.0")
        or "limit: 0" in combined_text
        or "limit of 0" in combined_text
        or "limit is 0" in combined_text
        or "quota limit is 0" in combined_text
        or "quota is 0" in combined_text
        or "quota of 0" in combined_text
        or "quota value is 0" in combined_text
        or "limit '0'" in combined_text
        or "limit: '0'" in combined_text
    )

    if is_quota_zero:
        loai = "quota_zero"
        mo_ta = "Hạn ngạch bằng 0 (Quota = 0 / Chưa kích hoạt gói trả phí hoặc model chưa được cấp quota cho API key này)"
        huong_dan = (
            "Model tạo ảnh này đang có hạn ngạch bằng 0 trên tài khoản Google AI Studio / Google Cloud của bạn. "
            "Nguyên nhân phổ biến: Google áp dụng hạn ngạch 0 RPM/RPD cho model tạo ảnh đối với các API key "
            "thuộc gói miễn phí (Free Tier) chưa liên kết thanh toán (Billing), hoặc model chưa được mở cho khu vực của bạn. "
            "Hãy kiểm tra gói cước tại https://aistudio.google.com hoặc console.cloud.google.com/billing."
        )
    elif (
        "per minute" in combined_text
        or "minute" in (quota_id or "").lower()
        or "rpm" in (quota_id or "").lower()
        or "requests_per_minute" in combined_text
        or (retry_delay is not None and not is_quota_zero)
        or (retry_after is not None and not is_quota_zero)
    ):
        loai = "rate_limit_minute"
        mo_ta = "Vượt giới hạn lượt gọi theo phút (Requests Per Minute - RPM)"
        wait_time = retry_delay or retry_after or "60s"
        huong_dan = (
            f"Bạn đã gửi quá số yêu cầu tạo ảnh cho phép trong 1 phút. "
            f"Vui lòng tạm dừng và chờ ít nhất {wait_time} trước khi gửi lại yêu cầu."
        )
    elif (
        "per day" in combined_text
        or "day" in (quota_id or "").lower()
        or "rpd" in (quota_id or "").lower()
        or "daily" in combined_text
        or "requests_per_day" in combined_text
    ):
        loai = "daily_quota_exhausted"
        mo_ta = "Hết hạn ngạch theo ngày (Requests Per Day - RPD)"
        huong_dan = (
            "Bạn đã sử dụng hết toàn bộ số lượt gọi tạo ảnh cho phép trong ngày của API key này. "
            "Hạn ngạch ngày sẽ tự động được đặt lại vào 00:00 UTC (07:00 sáng giờ VN)."
        )
    else:
        loai = "insufficient_info"
        mo_ta = "Chưa đủ thông tin phân loại từ Google (Generic RESOURCE_EXHAUSTED)"
        huong_dan = (
            "Google trả về mã RESOURCE_EXHAUSTED mà không đính kèm chi tiết QuotaFailure hay RetryInfo. "
            "Nếu bạn chưa từng tạo ảnh thành công nào mà vẫn nhận 429, khả năng cao nhất là hạn ngạch "
            "tạo ảnh của dự án đang bị đặt là 0 trên gói Free Tier."
        )

    return ChanDoanLoi429(
        loai_quota=loai,
        mo_ta_loai=mo_ta,
        status=status,
        message=message,
        quota_metric=quota_metric,
        quota_id=quota_id,
        quota_value=quota_value,
        retry_delay=retry_delay,
        retry_after=retry_after,
        huong_dan_khac_phuc=huong_dan,
    )


class GeminiRestAnhProvider:
    """Adapter tích hợp Gemini / Imagen Image Generation qua REST API của Google AI Studio.

    Hỗ trợ:
    - Endpoint generateContent với responseModalities=['IMAGE'] và imageConfig (mặc định: `gemini-3.1-flash-image`).
    - Hỗ trợ các model Gemini tạo ảnh thế hệ mới (gemini-3.1-flash-image, gemini-nano-banana-2.1, gemini-2.5-flash-image).
    - Endpoint predict (hỗ trợ tương thích ngược nếu kết nối proxy Imagen legacy).
    - Endpoint generateImages và interactions.
    Bảo đảm:
    - Tuyệt đối không hardcode API key.
    - Không log secret hay thông tin xác thực vào nhật ký.
    - Kiểm soát timeout, dung lượng JSON và kích thước ảnh.
    - Xử lý chi tiết các mã lỗi HTTP (400 tham số sai, 401/403 sai key, 404 sai model/hết hạn, 429 quá quota, 500 server lỗi).
    - Bẫy lỗi và hướng dẫn khi mô hình chỉ trả văn bản thay vì ảnh.
    - Tuân thủ protocol NhaCungCapAnh với generation_source='image_model'.
    """

    generation_source: Literal["image_model"] = "image_model"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        model: str = DEFAULT_MODEL,
        base_url: str = "https://generativelanguage.googleapis.com",
        timeout_seconds: float = 20.0,
        client: httpx.Client | None = None,
    ):
        if not isinstance(model, str) or not model.strip():
            raise ValueError("Cần cấu hình model Gemini")
        try:
            endpoint = httpx.URL(base_url)
        except (httpx.InvalidURL, ValueError, TypeError):
            raise ValueError("Base URL Gemini không hợp lệ") from None
        if endpoint.scheme not in ("http", "https") or not endpoint.host:
            raise ValueError("Base URL Gemini cần scheme HTTP(S)")
        if (
            isinstance(timeout_seconds, bool)
            or not isinstance(timeout_seconds, (int, float))
            or not math.isfinite(timeout_seconds)
            or not 0 < timeout_seconds <= 60
        ):
            raise ValueError("Timeout Gemini phải nằm trong (0, 60] giây")
        if api_key is not None and (
            not isinstance(api_key, str)
            or not 1 <= len(api_key) <= 4096
            or not api_key.isascii()
            or any(ord(c) <= 32 or ord(c) >= 127 for c in api_key)
        ):
            raise ValueError("API key Gemini không hợp lệ")

        self.model = model.strip()
        self.base_url = endpoint
        self.timeout_seconds = float(timeout_seconds)
        self._api_key = api_key
        self._client = client

    def _xay_dung_prompt(self, system_prompt: str, user_prompt: str) -> str:
        """Tạo prompt pixel-art chuyên biệt cho game phiêu lưu đào vàng."""
        mo_ta = user_prompt.strip()
        try:
            parsed = json.loads(user_prompt)
            if isinstance(parsed, dict) and "description" in parsed:
                mo_ta = str(parsed["description"]).strip()
        except Exception:
            pass

        return (
            "A single full-body pixel-art video game character sprite for a 16-bit retro gold mining adventure game.\n"
            f"Character concept and details: {mo_ta}\n"
            "Visual requirements:\n"
            "- Full-body standing character, completely visible from head to feet, centered in frame.\n"
            "- 16-bit retro pixel art style, sharp square pixels, vibrant game palette, clean silhouette.\n"
            "- Theme: gold miner, adventurer, explorer, prospector or dungeon delver.\n"
            "- Solid plain neutral background or transparent background, no scenery or landscape.\n"
            "- Single still frame illustration only, not a sprite sheet, no animation frames."
        )

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        try:
            for prompt in (system_prompt, user_prompt):
                if (
                    not isinstance(prompt, str)
                    or not prompt.strip()
                    or len(prompt.encode("utf-8")) > 16000
                ):
                    raise LoiProviderAnh("Prompt sinh ảnh Gemini không hợp lệ")
        except UnicodeError:
            raise LoiProviderAnh("Prompt sinh ảnh Gemini không hợp lệ") from None

        full_prompt = self._xay_dung_prompt(system_prompt, user_prompt)

        # Định tuyến endpoint dựa trên loại model
        if self.model.startswith("imagen"):
            # Hỗ trợ tương thích ngược cho endpoint Imagen legacy/proxy (:predict)
            url = f"{str(self.base_url).rstrip('/')}/v1beta/models/{self.model}:predict"
            payload = {
                "instances": [{"prompt": full_prompt}],
                "parameters": {
                    "sampleCount": 1,
                    "aspectRatio": "1:1",
                    "outputOptions": {"mimeType": "image/png"},
                },
            }
        else:
            # Model Gemini tạo ảnh thế hệ mới qua :generateContent (gemini-3.1-flash-image, v.v.)
            url = f"{str(self.base_url).rstrip('/')}/v1beta/models/{self.model}:generateContent"
            payload = {
                "contents": [{"parts": [{"text": full_prompt}]}],
                "generationConfig": {
                    "responseModalities": ["IMAGE"],
                    "imageConfig": {
                        "aspectRatio": "1:1",
                    },
                },
            }

        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Accept-Encoding": "identity",
        }
        if self._api_key:
            headers["x-goog-api-key"] = self._api_key

        try:
            manager = nullcontext(self._client) if self._client is not None else httpx.Client()
            with manager as client:
                with client.stream(
                    "POST",
                    url,
                    json=payload,
                    headers=headers,
                    timeout=self.timeout_seconds,
                    follow_redirects=False,
                ) as response:
                    body = bytearray()
                    for chunk in response.iter_bytes(chunk_size=4096):
                        if len(body) + len(chunk) > _GIOI_HAN_JSON:
                            raise LoiProviderAnh("Phản hồi Gemini vượt giới hạn dung lượng")
                        body.extend(chunk)

                    if response.status_code != 200:
                        self._xu_ly_loi_http(response.status_code, bytes(body), headers=response.headers)

                    if response.headers.get("content-encoding", "identity").strip().lower() != "identity":
                        raise LoiProviderAnh("Phản hồi Gemini dùng encoding chưa hỗ trợ")

            data = json.loads(body)
            raw_base64 = self._trich_xuat_base64(data)
            raw_bytes = base64.b64decode(raw_base64, validate=True)
            if not raw_bytes or len(raw_bytes) > _GIOI_HAN_ANH:
                raise LoiProviderAnh("Dữ liệu ảnh Gemini rỗng hoặc vượt giới hạn dung lượng")
            return raw_bytes
        except LoiProviderAnh:
            raise
        except httpx.TimeoutException:
            raise LoiProviderAnh(f"Hết thời gian chờ phản hồi từ Gemini API sau {self.timeout_seconds}s (Timeout)") from None
        except (httpx.ConnectError, httpx.NetworkError):
            raise LoiProviderAnh("Không thể kết nối tới máy chủ Google Gemini (Lỗi mạng)") from None
        except (httpx.HTTPError, ValueError, TypeError, RecursionError) as e:
            raise LoiProviderAnh(f"Không nhận được phản hồi sinh ảnh Gemini hợp lệ: {type(e).__name__}") from None

    def phan_tich_loi_429(
        self, body: bytes, headers: Mapping[str, str] | None = None
    ) -> ChanDoanLoi429:
        """Phương thức tiện ích trên provider để phân tích lỗi 429 an toàn."""
        return phan_tich_loi_429(body, headers=headers, api_key=self._api_key)

    def _xu_ly_loi_http(
        self,
        status_code: int,
        body: bytes,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        """Phân loại và định danh lỗi từ Google API mà không làm lộ secret."""
        err_msg = ""
        err_status = ""
        try:
            err_json = json.loads(body)
            if isinstance(err_json, dict) and "error" in err_json:
                e = err_json["error"]
                if isinstance(e, dict):
                    err_msg = str(e.get("message", ""))
                    err_status = str(e.get("status", ""))
                else:
                    err_msg = str(e)
        except Exception:
            pass

        # Bảo mật: khử mọi vết tích nếu API key vô tình xuất hiện trong error message của upstream
        if self._api_key and self._api_key in err_msg:
            err_msg = err_msg.replace(self._api_key, "[REDACTED_API_KEY]")
        err_msg = re.sub(r"AIza[0-9A-Za-z-_]{35}", "[REDACTED_API_KEY]", err_msg)

        if status_code in (401, 403) or "API_KEY_INVALID" in err_status or "API key not valid" in err_msg:
            raise LoiProviderAnh("API key Gemini không hợp lệ hoặc không có quyền truy cập (HTTP 401/403).")
        if status_code == 404 or "NOT_FOUND" in err_status:
            huong_dan = ""
            if "imagen" in self.model.lower():
                huong_dan = (
                    " Lưu ý: Google đã chính thức ngừng hỗ trợ các mô hình Imagen cũ (như imagen-3.0-generate-002) "
                    "từ tháng 8/2026. Hãy chuyển sang mô hình tạo ảnh qua :generateContent (như 'gemini-nano-banana-2.1')."
                )
            raise LoiProviderAnh(f"Mô hình Gemini '{self.model}' không tồn tại hoặc không hỗ trợ endpoint này (HTTP 404).{huong_dan}")
        if status_code == 400 or "INVALID_ARGUMENT" in err_status:
            raise LoiProviderAnh(f"Yêu cầu gửi tới mô hình Gemini '{self.model}' không hợp lệ (HTTP 400): {err_msg}")
        if status_code == 429 or "RESOURCE_EXHAUSTED" in err_status:
            cd = self.phan_tich_loi_429(body, headers=headers)
            dong_thong_bao = [
                "Đã vượt quá hạn ngạch gọi Gemini API (Rate Limit / Quota Exceeded HTTP 429).",
                f"• Phân loại hạn ngạch : {cd.mo_ta_loai}",
                f"• Mã lỗi Google       : {cd.status}",
            ]
            if cd.quota_metric:
                dong_thong_bao.append(f"• Quota Metric        : {cd.quota_metric}")
            if cd.quota_id:
                dong_thong_bao.append(f"• Quota ID            : {cd.quota_id}")
            if cd.quota_value is not None:
                dong_thong_bao.append(f"• Quota Value         : {cd.quota_value}")
            if cd.retry_delay:
                dong_thong_bao.append(f"• Retry Delay         : {cd.retry_delay}")
            if cd.retry_after:
                dong_thong_bao.append(f"• Header Retry-After  : {cd.retry_after}")
            if cd.message:
                dong_thong_bao.append(f"• Chi tiết từ Google  : {cd.message}")
            dong_thong_bao.append(f"• Hướng dẫn khắc phục : {cd.huong_dan_khac_phuc}")
            raise LoiQuotaGemini("\n".join(dong_thong_bao), chan_doan=cd)
        if status_code in (500, 502, 503, 504):
            raise LoiProviderAnh(f"Dịch vụ Google Gemini đang bận hoặc gặp sự cố tạm thời (HTTP {status_code}).")

        detail = f": {err_msg}" if err_msg else ""
        raise LoiProviderAnh(f"Dịch vụ Gemini trả mã lỗi {status_code}{detail}")

    def _trich_xuat_base64(self, data: dict) -> str:
        if not isinstance(data, dict):
            raise LoiProviderAnh("Phản hồi Gemini không phải là JSON object")
        if "error" in data:
            err = data["error"]
            msg = err.get("message", "Lỗi dịch vụ Gemini") if isinstance(err, dict) else str(err)
            raise LoiProviderAnh(f"Phản hồi Gemini chứa thông báo lỗi: {msg}")

        # 1. Format generateContent (Gemini multimodal: candidates[0].content.parts)
        candidates = data.get("candidates")
        if isinstance(candidates, list) and len(candidates) >= 1 and isinstance(candidates[0], dict):
            cand = candidates[0]
            finish_reason = cand.get("finishReason")
            if finish_reason in ("SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII"):
                raise LoiProviderAnh(f"Yêu cầu tạo ảnh bị bộ lọc an toàn của Google từ chối (finishReason: {finish_reason})")

            parts = cand.get("content", {}).get("parts", [])
            # Quét tất cả các part để ưu tiên trích xuất inlineData ảnh
            for part in parts:
                if isinstance(part, dict):
                    inline = part.get("inlineData", {})
                    if isinstance(inline, dict):
                        b64 = inline.get("data")
                        if isinstance(b64, str) and b64.strip():
                            return b64.strip()

            # Nếu không có ảnh, kiểm tra xem có text giải thích từ mô hình không
            text_parts = [
                str(part["text"]).strip()
                for part in parts
                if isinstance(part, dict) and "text" in part and part["text"]
            ]
            if text_parts:
                preview = " ".join(text_parts)[:200]
                raise LoiProviderAnh(
                    f"Mô hình Gemini '{self.model}' trả về văn bản thay vì hình ảnh. "
                    f"Vui lòng cấu hình mô hình hỗ trợ sinh ảnh (như '{DEFAULT_MODEL}'). "
                    f"Nội dung nhận được: {preview}"
                )

        # 2. Format Imagen (:predict -> predictions[0].bytesBase64Encoded)
        predictions = data.get("predictions")
        if isinstance(predictions, list) and len(predictions) >= 1 and isinstance(predictions[0], dict):
            b64 = predictions[0].get("bytesBase64Encoded")
            if isinstance(b64, str) and b64.strip():
                return b64.strip()

        # 3. Format generateImages -> generatedImages[0].image.imageBytes
        gen_images = data.get("generatedImages")
        if isinstance(gen_images, list) and len(gen_images) >= 1 and isinstance(gen_images[0], dict):
            img_obj = gen_images[0].get("image")
            if isinstance(img_obj, dict):
                b64 = img_obj.get("imageBytes")
                if isinstance(b64, str) and b64.strip():
                    return b64.strip()

        # 4. Format Interactions API (output_image.data)
        out_img = data.get("output_image")
        if isinstance(out_img, dict):
            b64 = out_img.get("data") or out_img.get("bytesBase64Encoded")
            if isinstance(b64, str) and b64.strip():
                return b64.strip()

        raise LoiProviderAnh(f"Cấu trúc phản hồi ảnh từ mô hình '{self.model}' không đúng định dạng mong đợi")


def gemini_provider_tu_moi_truong(
    moi_truong: Mapping[str, str] | None = None, *, client: httpx.Client | None = None
) -> GeminiRestAnhProvider | None:
    """Tạo provider Gemini nếu môi trường bật AI_IMAGE_ENABLED=true và cấu hình GEMINI_API_KEY hoặc AI_IMAGE_PROVIDER=gemini."""
    env = os.environ if moi_truong is None else moi_truong
    bat = env.get("AI_IMAGE_ENABLED", "false").strip().lower()
    if bat not in ("true", "1"):
        return None

    provider_type = env.get("AI_IMAGE_PROVIDER", "").strip().lower()
    gemini_key = env.get("GEMINI_API_KEY", "").strip() or env.get("AI_IMAGE_API_KEY", "").strip()

    # Chỉ kích hoạt adapter Gemini nếu chỉ định rõ hoặc có GEMINI_API_KEY mà không có AI_IMAGE_URL
    if provider_type != "gemini" and not (gemini_key and not env.get("AI_IMAGE_URL")):
        return None

    timeout_str = env.get("AI_IMAGE_TIMEOUT_SECONDS", "").strip() or env.get("GEMINI_TIMEOUT_SECONDS", "20").strip()
    try:
        timeout = float(timeout_str)
    except ValueError:
        raise ValueError("AI_IMAGE_TIMEOUT_SECONDS không hợp lệ") from None

    model = env.get("AI_IMAGE_MODEL", "").strip() or env.get("GEMINI_IMAGE_MODEL", "").strip() or DEFAULT_MODEL
    base_url = env.get("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com").strip()

    return GeminiRestAnhProvider(
        api_key=gemini_key or None,
        model=model,
        base_url=base_url,
        timeout_seconds=timeout,
        client=client,
    )
