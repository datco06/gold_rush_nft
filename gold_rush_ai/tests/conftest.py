import pytest


@pytest.fixture(autouse=True)
def quota_ai_cach_ly(tmp_path, monkeypatch):
    monkeypatch.setenv("AI_QUOTA_DB", str(tmp_path / "quota.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_DAILY_LIMIT", "5")
    monkeypatch.setenv("AI_QUEST_DAILY_LIMIT", "20")
