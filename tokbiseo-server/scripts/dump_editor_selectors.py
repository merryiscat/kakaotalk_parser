# -*- coding: utf-8 -*-
"""
티스토리 에디터 실제 셀렉터 확인용 진단 스크립트

티스토리 에디터가 개편되어 tistory_service.py의 SEL_* 상수가 실제와
달라졌을 때, 에디터 DOM에서 버튼·입력 요소들을 뽑아 확인합니다.
(발행 레이어까지 열어 보지만 최종 발행 버튼은 누르지 않습니다)

사용법:
  cd tokbiseo-server
  uv run python scripts/dump_editor_selectors.py
"""
import asyncio
import io
import sys
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

_ROOT = Path(__file__).resolve().parent.parent
STATE_PATH = _ROOT / "data" / "tistory_state.json"


def _blog_name_from_env() -> str:
    """.env에서 TISTORY_BLOG_NAME을 읽습니다."""
    env_path = _ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("TISTORY_BLOG_NAME="):
                return line.split("=", 1)[1].strip()
    return ""


EDITOR_URL = f"https://{_blog_name_from_env()}.tistory.com/manage/newpost/"


async def main():
    from playwright.async_api import async_playwright

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(storage_state=str(STATE_PATH))
        page = await context.new_page()
        page.on("dialog", lambda d: asyncio.ensure_future(d.accept()))
        await page.goto(EDITOR_URL, wait_until="networkidle", timeout=30000)

        # id가 있는 버튼/입력과, publish·btn이 들어간 요소를 모두 수집
        items = await page.evaluate(
            """() => {
                const out = [];
                for (const el of document.querySelectorAll('button, [id*=publish], [id*=btn], [id*=save], input[type=button], input[type=submit]')) {
                    out.push({
                        tag: el.tagName.toLowerCase(),
                        id: el.id || '',
                        cls: (el.className || '').toString().slice(0, 60),
                        text: (el.textContent || '').trim().slice(0, 30),
                        visible: el.offsetParent !== null,
                    });
                }
                return out;
            }"""
        )
        print(f"URL: {page.url}")
        print(f"{'tag':8s} {'visible':7s} {'id':35s} {'text':30s} class")
        for it in items:
            print(f"{it['tag']:8s} {str(it['visible']):7s} {it['id']:35s} {it['text']:30s} {it['cls']}")

        # ── 발행 레이어 열어서 내부 요소 확인 (최종 발행 버튼은 누르지 않음) ──
        print("\n===== '완료' 클릭 → 발행 레이어 내부 =====")
        await page.fill("#post-title-inp", "셀렉터 확인용 (발행 안 함)")
        await page.click("#publish-layer-btn")
        await page.wait_for_timeout(2000)
        layer_items = await page.evaluate(
            """() => {
                const out = [];
                for (const el of document.querySelectorAll('[id*=publish], [id*=open], input[type=radio], button')) {
                    if (el.offsetParent === null) continue;  // 보이는 것만
                    out.push({
                        tag: el.tagName.toLowerCase(),
                        id: el.id || '',
                        type: el.type || '',
                        text: (el.textContent || el.value || '').trim().slice(0, 30),
                    });
                }
                return out;
            }"""
        )
        for it in layer_items:
            print(f"{it['tag']:8s} {it['type']:8s} {it['id']:35s} {it['text']}")

        await browser.close()


asyncio.run(main())
