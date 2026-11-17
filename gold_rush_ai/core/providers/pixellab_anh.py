from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from io import BytesIO
import json
import math
import os
from typing import Literal, Mapping

import httpx
from PIL import Image, UnidentifiedImageError

from .anh import LoiProviderAnh, NhaCungCapAnh

_GIOI_HAN_JSON = 8 * 1024 * 1024
_GIOI_HAN_ANH = 5 * 1024 * 1024
_HUONG = ("south", "west", "east", "north")


def _loi_api(response: httpx.Response, payload: object) -> LoiProviderAnh:
    detail = None
    if isinstance(payload, dict):
        for key in ("detail", "message", "error"):
            value = payload.get(key)
            if isinstance(value, str) and value.strip():
                detail = value.strip()[:500]
                break
    if response.status_code == 401:
        return LoiProviderAnh("PixelLab API key không hợp lệ")
    if response.status_code == 402:
        return LoiProviderAnh("PixelLab đã hết lượt miễn phí hoặc cần thêm credit")
    if response.status_code == 429:
        return LoiProviderAnh("PixelLab đang giới hạn số request, hãy thử lại sau")
    return LoiProviderAnh(detail or f"PixelLab trả HTTP {response.status_code}")


class PixelLabAnh:
    """Tạo nhân vật PixelLab rồi ghép 16 frame đi bộ thành sheet 4x4 thật.

    PixelLab trả frame qua các job nền. Adapter này chỉ nhận đủ 4 hướng x 4
    frame, không nhân bản một ảnh tĩnh thành animation.
    """

    generation_source: Literal["image_model"] = "image_model"
    supports_sprite_sheet = True
    supports_single_frame = False

    def __init__(
        self,
        *,
        api_key: str,
        model: str = "create-character-with-4-directions",
        base_url: str = "https://api.pixellab.ai/v2",
        timeout_seconds: float = 60,
        poll_interval_seconds: float = 3,
        max_polls: int = 60,
        client: httpx.Client | None = None,
    ):
        if not isinstance(api_key, str) or not 1 <= len(api_key.strip()) <= 4096:
            raise ValueError("PIXELLAB_API_TOKEN không hợp lệ")
        if not isinstance(model, str) or model.strip() != "create-character-with-4-directions":
            raise ValueError("PIXELLAB_IMAGE_MODEL phải là create-character-with-4-directions")
        try:
            endpoint = httpx.URL(base_url.rstrip("/"))
        except (httpx.InvalidURL, ValueError, TypeError):
            raise ValueError("PIXELLAB_BASE_URL không hợp lệ") from None
        if endpoint.scheme not in ("http", "https") or not endpoint.host:
            raise ValueError("PIXELLAB_BASE_URL cần HTTP(S)")
        for value, name, upper in (
            (timeout_seconds, "PIXELLAB_TIMEOUT_SECONDS", 300),
            (poll_interval_seconds, "PIXELLAB_POLL_INTERVAL_SECONDS", 60),
        ):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or value > upper:
                raise ValueError(f"{name} không hợp lệ")
        if type(max_polls) is not int or not 1 <= max_polls <= 120:
            raise ValueError("PIXELLAB_MAX_POLLS phải nằm trong 1..120")
        self.api_key = api_key.strip()
        self.model = model.strip()
        self.base_url = str(endpoint).rstrip("/")
        self.timeout_seconds = float(timeout_seconds)
        self.poll_interval_seconds = float(poll_interval_seconds)
        self.max_polls = max_polls
        self._client = client

    def _request(self, client: httpx.Client, path: str, *, method: str = "GET", json_body: object | None = None) -> object:
        try:
            response = client.request(
                method,
                f"{self.base_url}{path}",
                json=json_body,
                headers={
                    "Accept": "application/json, image/png",
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                timeout=self.timeout_seconds,
                follow_redirects=False,
            )
            if response.status_code < 200 or response.status_code >= 300:
                try:
                    payload = response.json()
                except (ValueError, TypeError):
                    payload = None
                raise _loi_api(response, payload)
            if len(response.content) > _GIOI_HAN_JSON:
                raise LoiProviderAnh("Phản hồi PixelLab vượt giới hạn dung lượng")
            try:
                return response.json()
            except (ValueError, TypeError):
                raise LoiProviderAnh("PixelLab trả JSON không hợp lệ") from None
        except (httpx.HTTPError, httpx.TimeoutException):
            raise LoiProviderAnh("Không kết nối được PixelLab") from None

    def _cho_job(self, client: httpx.Client, job_id: str, initial: object, label: str) -> dict:
        job = initial if isinstance(initial, dict) else {}
        for attempt in range(self.max_polls):
            status = job.get("status")
            if status == "completed":
                return job
            if status == "failed":
                detail = job.get("last_response", {}).get("detail") if isinstance(job.get("last_response"), dict) else None
                raise LoiProviderAnh(str(detail or f"{label} thất bại")[:500])
            if attempt + 1 >= self.max_polls:
                break
            if self.poll_interval_seconds:
                import time
                time.sleep(self.poll_interval_seconds)
            result = self._request(client, f"/background-jobs/{job_id}")
            job = result if isinstance(result, dict) else {}
        raise LoiProviderAnh(f"{label} quá lâu, hãy thử lại sau")

    @staticmethod
    def _description(user_prompt: str) -> str:
        try:
            payload = json.loads(user_prompt)
        except (TypeError, ValueError):
            raise LoiProviderAnh("Mô tả nhân vật không hợp lệ") from None
        description = payload.get("description") if isinstance(payload, dict) else None
        if not isinstance(description, str) or not description.strip() or len(description.encode("utf-8")) > 4096:
            raise LoiProviderAnh("Mô tả nhân vật không hợp lệ")
        return description.strip()

    @staticmethod
    def _frame_png(data: bytes) -> bytes:
        if not isinstance(data, bytes) or not data or len(data) > _GIOI_HAN_ANH:
            raise LoiProviderAnh("Frame PixelLab thiếu hoặc quá lớn")
        try:
            with Image.open(BytesIO(data), formats=("PNG",)) as image:
                if getattr(image, "is_animated", False) or image.width < 1 or image.height < 1:
                    raise LoiProviderAnh("Frame PixelLab không hợp lệ")
                image.load()
                with BytesIO() as output:
                    image.convert("RGBA").save(output, format="PNG", optimize=True)
                    return output.getvalue()
        except LoiProviderAnh:
            raise
        except (UnidentifiedImageError, OSError, ValueError):
            raise LoiProviderAnh("PixelLab trả về frame không phải PNG") from None

    def _tai_frame(self, client: httpx.Client, url: str) -> bytes:
        if not isinstance(url, str) or not url.startswith(("https://", "http://")):
            raise LoiProviderAnh("PixelLab trả URL frame không hợp lệ")
        try:
            response = client.get(url, headers={"Accept": "image/png"}, timeout=self.timeout_seconds, follow_redirects=False)
            if response.status_code != 200:
                raise LoiProviderAnh("Không tải được frame từ PixelLab")
            return self._frame_png(response.content)
        except (httpx.HTTPError, httpx.TimeoutException):
            raise LoiProviderAnh("Không tải được frame từ PixelLab") from None

    @staticmethod
    def _ghep(frames: list[list[bytes]]) -> bytes:
        if len(frames) != 4 or any(len(row) != 4 for row in frames):
            raise LoiProviderAnh("PixelLab không trả đủ 4 hướng x 4 frame")
        sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        try:
            for row, direction_frames in enumerate(frames):
                for col, data in enumerate(direction_frames):
                    with Image.open(BytesIO(data)) as source:
                        frame = source.convert("RGBA")
                        # Giữ đúng cách ghép của web test: ảnh 64x64 được đặt
                        # nguyên ô; chỉ thu nhỏ khi PixelLab trả ảnh lớn hơn ô.
                        ti_le = min(1.0, 64 / frame.width, 64 / frame.height)
                        if ti_le < 1.0:
                            kich_thuoc = (
                                max(1, int(frame.width * ti_le)),
                                max(1, int(frame.height * ti_le)),
                            )
                            resized = frame.resize(kich_thuoc, Image.Resampling.NEAREST)
                            frame.close()
                            frame = resized
                        x = col * 64 + (64 - frame.width) // 2
                        y = row * 64 + (64 - frame.height) // 2
                        sheet.alpha_composite(frame, (x, y))
                        frame.close()
            with BytesIO() as output:
                sheet.save(output, format="PNG", optimize=True)
                return output.getvalue()
        finally:
            sheet.close()

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        description = self._description(user_prompt)
        if not isinstance(system_prompt, str) or not system_prompt.strip():
            raise LoiProviderAnh("Prompt PixelLab không hợp lệ")
        final_prompt = (
            "Game-ready pixel art RPG character. "
            "Create one consistent full-body character for all four directions. "
            "Use crisp square pixels, simple limited colors, transparent background, "
            "and a natural walking pose with alternating legs. "
            f"Character appearance only: {description}."
        )
        manager = nullcontext(self._client) if self._client is not None else httpx.Client()
        with manager as client:
            created = self._request(client, "/create-character-with-4-directions", method="POST", json_body={
                "description": final_prompt,
                "image_size": {"width": 64, "height": 64},
                "async_mode": True,
                "view": "low top-down",
                "outline": "single color black outline",
                "shading": "basic shading",
                "detail": "medium detail",
                "proportions": {"type": "preset", "name": "heroic"},
            })
            if not isinstance(created, dict):
                raise LoiProviderAnh("PixelLab trả dữ liệu character không hợp lệ")
            job_id = created.get("background_job_id")
            character_id = created.get("character_id")
            if not isinstance(job_id, str) or not isinstance(character_id, str):
                raise LoiProviderAnh("PixelLab không trả job character hợp lệ")
            self._cho_job(client, job_id, created, "PixelLab tạo character")
            character_idle = self._request(client, f"/characters/{character_id}")
            if not isinstance(character_idle, dict):
                raise LoiProviderAnh("PixelLab trả character không hợp lệ")
            rotation_urls = character_idle.get("rotation_urls")
            if not isinstance(rotation_urls, dict) or any(
                not isinstance(rotation_urls.get(direction), str) for direction in _HUONG
            ):
                raise LoiProviderAnh("PixelLab không trả đủ ảnh hướng nhân vật")
            # Giữ đúng luồng của web test: một request tạo animation cho cả
            # bốn hướng, sau đó chờ bốn background job song song hoàn tất.
            animation = self._request(client, "/animate-character", method="POST", json_body={
                "character_id": character_id,
                "action_description": "walking forward with a natural alternating leg stride; feet move one after another while the body stays consistent",
                "mode": "v3",
                "frame_count": 4,
                "directions": list(_HUONG),
                "keep_first_frame": False,
                "async_mode": True,
            })
            if not isinstance(animation, dict):
                raise LoiProviderAnh("PixelLab trả animation không hợp lệ")
            jobs = animation.get("background_job_ids")
            group_id = animation.get("animation_group_id")
            if (not isinstance(jobs, list) or len(jobs) != len(_HUONG)
                    or not all(isinstance(job_id, str) for job_id in jobs)
                    or not isinstance(group_id, str)):
                raise LoiProviderAnh("PixelLab không trả đủ 4 job animation")
            # Web test dùng Promise.all; chờ song song để tổng thời gian gần
            # bằng một animation job thay vì cộng dồn cả bốn hướng.
            with ThreadPoolExecutor(max_workers=len(jobs)) as executor:
                futures = [
                    executor.submit(self._cho_job, client, job_id, {}, "PixelLab tạo animation")
                    for job_id in jobs
                ]
                for future in futures:
                    future.result()
            character = self._request(client, f"/characters/{character_id}")
            if not isinstance(character, dict):
                raise LoiProviderAnh("PixelLab trả character sau animation không hợp lệ")
            groups = character.get("animations")
            if not isinstance(groups, list):
                raise LoiProviderAnh("PixelLab không trả dữ liệu animation")
            group = next(
                (item for item in groups
                 if isinstance(item, dict) and item.get("animation_group_id") == group_id),
                groups[-1] if groups and isinstance(groups[-1], dict) else None,
            )
            if not isinstance(group, dict):
                raise LoiProviderAnh("PixelLab không trả nhóm animation hợp lệ")
            frame_urls: list[list[str]] = []
            for direction in _HUONG:
                entry = next((item for item in group.get("directions", [])
                              if isinstance(item, dict) and item.get("direction") == direction), None)
                urls = entry.get("frames") if isinstance(entry, dict) else None
                if not isinstance(urls, list) or len(urls) < 4 or not all(isinstance(url, str) for url in urls[:4]):
                    raise LoiProviderAnh(f"PixelLab không trả đủ frame đi bộ hướng {direction}")
                frame_urls.append(urls[:4])
            # Web test dùng Promise.all cho toàn bộ 16 frame. Tải song song
            # để thời gian không bị cộng dồn 4 hướng x 4 frame.
            with ThreadPoolExecutor(max_workers=16) as executor:
                futures = [
                    [executor.submit(self._tai_frame, client, url) for url in row]
                    for row in frame_urls
                ]
                rows = [[future.result() for future in row] for row in futures]
            return self._ghep(rows)


def pixellab_provider_tu_moi_truong(
    moi_truong: Mapping[str, str] | None = None, *, client: httpx.Client | None = None,
) -> NhaCungCapAnh:
    env = os.environ if moi_truong is None else moi_truong
    key = env.get("PIXELLAB_API_TOKEN", "").strip()
    if not key:
        raise ValueError("Cần cấu hình PIXELLAB_API_TOKEN")
    try:
        timeout = float(env.get("PIXELLAB_TIMEOUT_SECONDS", "60"))
        interval = float(env.get("PIXELLAB_POLL_INTERVAL_SECONDS", "3"))
        polls = int(env.get("PIXELLAB_MAX_POLLS", "60"))
    except ValueError:
        raise ValueError("Cấu hình thời gian PixelLab không hợp lệ") from None
    return PixelLabAnh(
        api_key=key,
        model=env.get("PIXELLAB_IMAGE_MODEL", "create-character-with-4-directions").strip(),
        base_url=env.get("PIXELLAB_BASE_URL", "https://api.pixellab.ai/v2").strip(),
        timeout_seconds=timeout,
        poll_interval_seconds=interval,
        max_polls=polls,
        client=client,
    )
