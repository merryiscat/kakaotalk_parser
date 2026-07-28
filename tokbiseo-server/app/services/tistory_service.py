"""
티스토리 발행 서비스 — Playwright 브라우저 자동화

티스토리 Open API가 2024년 2월 종료되어 글 작성 API가 없습니다.
그래서 실제 브라우저(Chromium)로 티스토리 에디터를 열어 사람이 쓰듯이
제목·본문을 입력하고 발행 버튼을 누르는 방식을 사용합니다.

에디터는 마크다운 모드를 지원하므로, Notion에서 역변환한 마크다운을
그대로 투입합니다 (HTML 변환 불필요).

.env 필요 항목:
- TISTORY_BLOG_NAME: 블로그 이름 (예: "myblog" → myblog.tistory.com)
- TISTORY_STORAGE_STATE: 로그인 세션 파일 경로 (기본 data/tistory_state.json)

로그인 세션 준비 (최초 1회):
  카카오 로그인은 캡차 때문에 자동화할 수 없습니다.
  로컬 PC에서 `uv run python scripts/tistory_login.py`를 실행해 직접 로그인하면
  세션이 storage_state 파일로 저장됩니다. 이 파일을 운영 서버의
  tokbiseo-server/data/ 에 올려두면 (docker-compose가 /app/data로 마운트)
  재로그인 없이 발행이 동작합니다.

주의:
- 티스토리는 1일 발행 수 제한이 있습니다. 큐를 한 번에 밀지 말고
  앱에서 한 건씩 발행하세요.
- 세션이 만료되면 로그인 페이지로 리다이렉트됩니다 → 에러로 감지하고
  storage_state 재생성을 안내합니다.
"""

import os
import asyncio
import logging
from datetime import datetime
from pathlib import Path

logger = logging.getLogger("톡비서.tistory")

# 세션 파일 기본 경로 (docker-compose가 ./data를 /app/data로 마운트)
_DEFAULT_STATE_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "tistory_state.json"

# 실패 시 스크린샷 저장 위치 (원인 파악용 — logs 볼륨에 남김)
_SCREENSHOT_DIR = Path(__file__).resolve().parent.parent.parent / "logs"

# 발행은 한 번에 하나씩만 (동시에 두 브라우저가 에디터를 열면 충돌)
_publish_lock = asyncio.Lock()

# ── 티스토리 에디터 셀렉터 ──
# 에디터 개편 시 여기만 고치면 되도록 상수로 모아둡니다.
SEL_TITLE = "#post-title-inp"                    # 제목 입력창
SEL_MODE_BTN = "#editor-mode-layer-btn-open"     # 에디터 모드 드롭다운 버튼
SEL_MODE_MARKDOWN = "#editor-mode-markdown"      # 드롭다운의 "마크다운" 항목
SEL_CODEMIRROR = ".CodeMirror"                   # 마크다운 편집기 (CodeMirror)
SEL_TAG_INPUT = "#tagText"                       # 태그 입력창
SEL_PUBLISH_LAYER_BTN = "#publish-layer-btn-open"  # "완료" 버튼 (발행 레이어 열기)
SEL_PUBLIC_RADIO = "#open20"                     # 발행 레이어의 "공개" 라디오
SEL_PUBLISH_BTN = "#publish-btn"                 # 최종 "공개 발행" 버튼


def _get_config() -> tuple[str, Path]:
    """블로그 이름과 세션 파일 경로를 환경변수에서 읽습니다."""
    blog_name = os.getenv("TISTORY_BLOG_NAME", "").strip()
    state_path = Path(
        os.getenv("TISTORY_STORAGE_STATE", "") or _DEFAULT_STATE_PATH
    )
    return blog_name, state_path


def is_configured() -> str | None:
    """
    발행 가능한 설정 상태인지 확인합니다.

    Returns:
        문제가 있으면 안내 메시지, 정상이면 None
    """
    blog_name, state_path = _get_config()
    if not blog_name:
        return "TISTORY_BLOG_NAME이 .env에 설정되지 않았습니다."
    if not state_path.exists():
        return (
            f"로그인 세션 파일이 없습니다: {state_path} — "
            "로컬에서 scripts/tistory_login.py 실행 후 파일을 서버에 올려주세요."
        )
    return None


async def publish_post(
    title: str,
    markdown: str,
    tags: list[str] | None = None,
) -> dict:
    """
    티스토리에 마크다운 글을 발행합니다.

    Args:
        title: 글 제목
        markdown: 본문 마크다운
        tags: 태그 목록 (선택, 최대 10개)

    Returns:
        {"url": "발행된 글 주소"} 또는 {"error": "에러 메시지"}
    """
    config_error = is_configured()
    if config_error:
        return {"error": config_error}

    blog_name, state_path = _get_config()

    # 발행 직렬화 — 동시 요청이 와도 한 건씩 처리
    async with _publish_lock:
        try:
            return await _publish_with_browser(
                blog_name, state_path, title, markdown, tags or []
            )
        except Exception as e:
            logger.error(f"티스토리 발행 중 오류: {e}", exc_info=True)
            return {"error": f"티스토리 발행 중 오류: {e}"}


async def _publish_with_browser(
    blog_name: str,
    state_path: Path,
    title: str,
    markdown: str,
    tags: list[str],
) -> dict:
    """실제 브라우저를 띄워 에디터를 조작하는 내부 구현."""
    # playwright import를 함수 안에서 하는 이유:
    # 미설치 환경(로컬 개발 등)에서도 서버의 다른 기능은 정상 동작해야 함
    from playwright.async_api import async_playwright

    editor_url = f"https://{blog_name}.tistory.com/manage/newpost/"

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(storage_state=str(state_path))
        page = await context.new_page()

        # 에디터의 confirm 대화상자(모드 전환 경고, 임시저장 글 알림 등)는
        # 모두 "확인"으로 처리 — 새 글 작성 흐름을 막지 않기 위함
        page.on("dialog", lambda dialog: asyncio.ensure_future(dialog.accept()))

        try:
            await page.goto(editor_url, wait_until="networkidle", timeout=30000)

            # 로그인 세션 만료 감지 — 로그인 페이지로 리다이렉트됨
            if "accounts.kakao.com" in page.url or "/login" in page.url:
                return {
                    "error": "티스토리 로그인 세션이 만료되었습니다. "
                    "로컬에서 scripts/tistory_login.py로 세션을 다시 만들어 주세요."
                }

            # ── 1. 마크다운 모드로 전환 ──
            await page.click(SEL_MODE_BTN, timeout=10000)
            await page.click(SEL_MODE_MARKDOWN, timeout=5000)
            # 모드 전환 확인 대화상자는 위의 dialog 핸들러가 자동 승인
            await page.wait_for_selector(SEL_CODEMIRROR, timeout=10000)

            # ── 2. 제목 입력 ──
            await page.fill(SEL_TITLE, title)

            # ── 3. 본문 입력 ──
            # CodeMirror는 일반 textarea가 아니라 fill()이 통하지 않음
            # → CodeMirror 인스턴스의 setValue()를 직접 호출
            await page.evaluate(
                """([selector, content]) => {
                    const cm = document.querySelector(selector).CodeMirror;
                    cm.setValue(content);
                }""",
                [SEL_CODEMIRROR, markdown],
            )

            # ── 4. 태그 입력 (있을 때만, 실패해도 발행은 계속) ──
            for tag in tags[:10]:
                try:
                    await page.fill(SEL_TAG_INPUT, tag)
                    await page.press(SEL_TAG_INPUT, "Enter")
                except Exception:
                    logger.warning(f"태그 입력 실패 (건너뜀): {tag}")
                    break

            # ── 5. 발행 ──
            await page.click(SEL_PUBLISH_LAYER_BTN, timeout=10000)
            await page.wait_for_selector(SEL_PUBLISH_BTN, timeout=10000)
            # 공개 범위: 공개 (라디오가 없거나 이미 선택돼 있으면 무시)
            try:
                await page.click(SEL_PUBLIC_RADIO, timeout=3000)
            except Exception:
                pass
            await page.click(SEL_PUBLISH_BTN, timeout=10000)

            # 발행 완료 시 글 목록 또는 발행된 글로 이동함
            await page.wait_for_url(
                lambda url: "/manage/newpost" not in url,
                timeout=20000,
            )

            published_url = page.url
            logger.info(f"티스토리 발행 완료: {title} → {published_url}")
            return {"url": published_url}

        except Exception as e:
            # 실패 원인 파악용 스크린샷 (셀렉터가 바뀌었는지 등 확인)
            screenshot_path = ""
            try:
                _SCREENSHOT_DIR.mkdir(exist_ok=True)
                stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                screenshot_path = str(_SCREENSHOT_DIR / f"tistory_fail_{stamp}.png")
                await page.screenshot(path=screenshot_path, full_page=True)
            except Exception:
                pass

            hint = f" (스크린샷: {screenshot_path})" if screenshot_path else ""
            return {"error": f"발행 실패: {e}{hint}"}
        finally:
            await context.close()
            await browser.close()
