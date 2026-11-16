from io import BytesIO
import json

import httpx
from PIL import Image

from core.providers.pixellab_anh import PixelLabAnh


def png_frame(color: tuple[int, int, int], shift: int) -> bytes:
    with Image.new("RGBA", (32, 48), (0, 0, 0, 0)) as image:
        for x in range(8 + shift, 24 + shift):
            for y in range(4, 44):
                if 0 <= x < image.width:
                    image.putpixel((x, y), (*color, 255))
        output = BytesIO()
        image.save(output, format="PNG")
        return output.getvalue()


def test_pixellab_ghep_giu_nguyen_frame_64x64_nhu_web_test():
    with Image.new("RGBA", (64, 64), (0, 0, 0, 0)) as image:
        for x in range(20, 44):
            for y in range(8, 56):
                image.putpixel((x, y), (255, 200, 40, 255))
        source = BytesIO()
        image.save(source, format="PNG")
        frame = source.getvalue()

    sheet_bytes = PixelLabAnh._ghep([[frame] * 4 for _ in range(4)])
    with Image.open(BytesIO(sheet_bytes)) as sheet:
        assert sheet.crop((0, 0, 64, 64)).getchannel("A").getbbox() == (20, 8, 44, 56)


def test_pixellab_ghep_du_16_frame_di_bo_thanh_sheet_256():
    frames = {}
    directions = ["south", "west", "east", "north"]
    for row, direction in enumerate(directions):
        for col in range(4):
            url = f"https://cdn.example/{direction}-{col}.png"
            frames[url] = png_frame((40 + row * 40, 80 + col * 20, 120), col % 3)

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path == "/v2/create-character-with-4-directions":
            return httpx.Response(200, json={
                "background_job_id": "job-character",
                "character_id": "character-1",
                "status": "completed",
            })
        if path == "/v2/animate-character":
            body = json.loads(request.content)
            assert body["directions"] == directions
            return httpx.Response(200, json={
                "background_job_ids": [f"job-{direction}" for direction in directions],
                "animation_group_id": "walk-all",
            })
        if path.startswith("/v2/background-jobs/"):
            return httpx.Response(200, json={"status": "completed"})
        if path == "/v2/characters/character-1":
            return httpx.Response(200, json={
                "rotation_urls": {
                    direction: f"https://cdn.example/{direction}-idle.png"
                    for direction in directions
                },
                "animations": [
                    {
                    "animation_group_id": "walk-all",
                    "directions": [
                        {
                            "direction": direction,
                            "frames": [f"https://cdn.example/{direction}-{col}.png" for col in range(4)],
                        }
                        for direction in directions
                    ],
                }
                ],
            })
        if request.url.host == "cdn.example":
            return httpx.Response(200, content=frames[f"https://cdn.example{path}"])
        return httpx.Response(404)

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        provider = PixelLabAnh(
            api_key="test-token",
            poll_interval_seconds=0,
            client=client,
        )
        result = provider.sinh(
            system_prompt="fixed sprite rules",
            user_prompt=json.dumps({"description": "Một nông dân áo xanh"}),
        )

    with Image.open(BytesIO(result)) as sheet:
        assert sheet.size == (256, 256)
        assert sheet.mode == "RGBA"
        assert sheet.getchannel("A").getbbox() is not None
        # Hướng/hàng khác nhau và frame đi bộ không bị nhân bản một ảnh tĩnh.
        assert sheet.crop((0, 0, 64, 64)).tobytes() != sheet.crop((0, 64, 64, 128)).tobytes()
        assert sheet.crop((0, 0, 64, 64)).tobytes() != sheet.crop((64, 0, 128, 64)).tobytes()
