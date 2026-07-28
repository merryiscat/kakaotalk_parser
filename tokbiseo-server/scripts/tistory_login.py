"""
티스토리 로그인 세션 생성 스크립트 (로컬 PC에서 최초 1회 실행)

카카오 로그인은 캡차가 있어 서버에서 자동화할 수 없습니다.
이 스크립트는 화면이 보이는 브라우저를 띄워 사용자가 직접 로그인하게 하고,
로그인 세션(쿠키 등)을 storage_state 파일로 저장합니다.

사용법:
  1. 로컬 PC에서 실행:
     cd tokbiseo-server
     uv run python scripts/tistory_login.py
  2. 브라우저가 열리면 카카오 계정으로 티스토리에 로그인
  3. 로그인이 감지되면 자동으로 data/tistory_state.json 에 세션 저장
  4. 운영 서버에 파일 업로드:
     scp data/tistory_state.json 서버:.../tokbiseo-server/data/
     (docker-compose가 ./data를 /app/data로 마운트하므로 재시작 불필요)

세션이 만료되면 (발행 시 "세션 만료" 에러) 이 스크립트를 다시 실행하세요.
"""

import asyncio
from pathlib import Path

# 저장 경로: tokbiseo-server/data/tistory_state.json
STATE_PATH = Path(__file__).resolve().parent.parent / "data" / "tistory_state.json"

# 티스토리 로그인 시작 페이지
LOGIN_URL = "https://www.tistory.com/auth/login"


async def main():
    from playwright.async_api import async_playwright

    print("=" * 60)
    print("티스토리 로그인 세션 생성")
    print("=" * 60)
    print("브라우저가 열리면 카카오 계정으로 로그인해 주세요.")
    print("로그인이 완료되면 자동으로 세션을 저장하고 종료합니다.\n")

    async with async_playwright() as p:
        # headless=False: 사용자가 직접 로그인해야 하므로 화면 표시
        browser = await p.chromium.launch(headless=False)
        context = await browser.new_context()
        page = await context.new_page()

        await page.goto(LOGIN_URL)

        # 로그인 완료 감지: 티스토리 메인/관리 페이지 도착까지 대기 (최대 5분)
        # 로그인하면 tistory.com으로 리다이렉트되고 로그인 쿠키가 생김
        try:
            await page.wait_for_url(
                lambda url: (
                    "tistory.com" in url
                    and "auth/login" not in url
                    and "accounts.kakao.com" not in url
                ),
                timeout=300_000,
            )
        except Exception:
            print("\n[실패] 5분 안에 로그인이 감지되지 않았습니다. 다시 실행해 주세요.")
            await browser.close()
            return

        # 리다이렉트 직후 쿠키가 모두 심어질 때까지 잠깐 대기
        await page.wait_for_load_state("networkidle")

        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        await context.storage_state(path=str(STATE_PATH))
        await browser.close()

    print(f"\n[완료] 세션 저장: {STATE_PATH}")
    print("이 파일을 운영 서버의 tokbiseo-server/data/ 에 올려주세요.")


if __name__ == "__main__":
    asyncio.run(main())
