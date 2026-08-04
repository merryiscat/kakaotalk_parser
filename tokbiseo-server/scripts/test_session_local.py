# -*- coding: utf-8 -*-
"""
티스토리 세션 파일 검증 스크립트 (로컬 진단용)

서버에 올리기 전에 data/tistory_state.json이 실제로 유효한지 확인합니다.
tistory_login.py로 세션을 만든 직후, 또는 발행 시 "세션 만료" 에러가
났을 때 실행해 보세요.

사용법:
  cd tokbiseo-server
  uv run python scripts/test_session_local.py
"""
import asyncio
import io
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

_ROOT = Path(__file__).resolve().parent.parent
STATE_PATH = _ROOT / "data" / "tistory_state.json"


def _blog_name_from_env() -> str:
    """.env에서 TISTORY_BLOG_NAME을 읽습니다 (셸 인코딩을 타지 않도록 직접 파싱)."""
    env_path = _ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("TISTORY_BLOG_NAME="):
                return line.split("=", 1)[1].strip()
    return ""


async def main():
    from playwright.async_api import async_playwright

    blog_name = _blog_name_from_env()
    if not blog_name:
        print("[실패] .env에 TISTORY_BLOG_NAME이 없습니다.")
        return
    if not STATE_PATH.exists():
        print(f"[실패] 세션 파일이 없습니다: {STATE_PATH}")
        print("먼저 scripts/tistory_login.py로 로그인해 주세요.")
        return

    editor_url = f"https://{blog_name}.tistory.com/manage/newpost/"

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(storage_state=str(STATE_PATH))
        page = await context.new_page()
        await page.goto(editor_url, wait_until="networkidle", timeout=30000)
        final_url = page.url
        await browser.close()

    print(f"최종 URL: {final_url}")
    if "accounts.kakao.com" in final_url or "/login" in final_url:
        print("[실패] 로그인 페이지로 튕김 — 세션이 유효하지 않습니다.")
        print("scripts/tistory_login.py로 세션을 다시 만들어 주세요.")
    elif "/manage/newpost" in final_url:
        print("[성공] 에디터 접속 확인 — 세션이 유효합니다. 서버에 올려도 됩니다.")
    else:
        print("[불확실] 예상 밖 URL — 직접 확인이 필요합니다.")


asyncio.run(main())
