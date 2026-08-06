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
- TISTORY_CATEGORY: 글을 넣을 카테고리 이름 (선택, 없으면 기본 카테고리)
- TISTORY_KEEPALIVE_HOURS: 세션 keep-alive 주기(시간, 기본 3, 0=끔)
- KAKAO_EMAIL / KAKAO_PASSWORD: 세션이 완전히 죽었을 때 자동 재로그인용 (선택)

로그인 세션 준비 (최초 1회):
  카카오 로그인은 캡차 때문에 자동화할 수 없습니다.
  로컬 PC에서 `uv run python scripts/tistory_login.py`를 실행해 직접 로그인하면
  세션이 storage_state 파일로 저장됩니다. 이 파일을 운영 서버의
  tokbiseo-server/data/ 에 올려두면 (docker-compose가 /app/data로 마운트)
  재로그인 없이 발행이 동작합니다.
  이후에는 발행할 때마다 갱신된 쿠키를 파일에 되써서 세션을 자동 연장합니다
  (그래도 카카오 쪽 절대 만료 등으로 세션이 죽으면 위 절차로 재로그인).

세션 유지 3단 방어 (v2.0.17):
1. keep-alive — 서버가 몇 시간마다 관리 페이지에 접속해 쿠키를 갱신
   → 세션이 "미사용으로 인한 만료"에 이르지 않게 유지
2. 카카오 SSO 재로그인 — 티스토리 세션(TSSESSION)이 죽어도 카카오 쿠키가
   살아있으면 "카카오계정으로 로그인" 버튼 클릭만으로 재로그인 (비밀번호 불필요)
3. 비밀번호 폼 로그인 — 카카오 쿠키까지 죽었으면 .env의 KAKAO_EMAIL/
   KAKAO_PASSWORD로 로그인 폼을 자동 입력. 캡차·2단계 인증이 뜨면 여기서
   실패하고 로그를 남김 → 그때만 수동 재로그인 필요

주의:
- 티스토리는 1일 발행 수 제한이 있습니다. 큐를 한 번에 밀지 말고
  앱에서 한 건씩 발행하세요.
- 세션이 만료되면 로그인 페이지로 리다이렉트됩니다 → 위 2·3단계로
  자동 복구를 시도하고, 그래도 안 되면 수동 재로그인을 안내합니다.
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
# 마크다운 편집기 (CodeMirror)
# 주의: 에디터 페이지에는 CodeMirror가 2개 있음 (HTML 모드용 숨김 + 마크다운용).
# ":visible"로 화면에 보이는 쪽만 잡아야 함 — 첫 번째는 숨겨진 HTML용이라
# 그냥 ".CodeMirror"로 기다리면 타임아웃 남 (실발행 테스트에서 확인)
SEL_CODEMIRROR = ".CodeMirror"
SEL_CODEMIRROR_VISIBLE = ".CodeMirror:visible"
SEL_TAG_INPUT = "#tagText"                       # 태그 입력창
SEL_CATEGORY_BTN = "#category-btn"               # 카테고리 드롭다운 버튼 (에디터 상단)
SEL_CATEGORY_ITEM = "div.mce-menu-item"          # 드롭다운의 카테고리 항목
# "완료" 버튼 (발행 레이어 열기) — 실제 id는 "-open" 접미사가 없음 (실발행 테스트에서 확인)
SEL_PUBLISH_LAYER_BTN = "#publish-layer-btn"
SEL_PUBLIC_RADIO = "#open20"                     # 발행 레이어의 "공개" 라디오
SEL_PUBLISH_BTN = "#publish-btn"                 # 최종 "공개 발행" 버튼

# ── 재로그인 관련 ──
TISTORY_LOGIN_URL = "https://www.tistory.com/auth/login"
# 티스토리 로그인 페이지의 "카카오계정으로 로그인" 버튼
# (클래스가 바뀌어도 잡히도록 텍스트 기반 폴백을 함께 사용)
SEL_KAKAO_LOGIN_BTN = "a.btn_login.link_kakao_id"
# 카카오 로그인 폼 (accounts.kakao.com) — name 속성 기반이 가장 안정적
SEL_KAKAO_ID_INPUT = 'input[name="loginId"]'
SEL_KAKAO_PW_INPUT = 'input[name="password"]'
SEL_KAKAO_SUBMIT = 'button[type="submit"]'


def _get_config() -> tuple[str, Path]:
    """블로그 이름과 세션 파일 경로를 환경변수에서 읽습니다."""
    blog_name = os.getenv("TISTORY_BLOG_NAME", "").strip()
    state_path = Path(
        os.getenv("TISTORY_STORAGE_STATE", "") or _DEFAULT_STATE_PATH
    )
    return blog_name, state_path


def _get_credentials() -> tuple[str, str]:
    """자동 재로그인용 카카오 계정을 .env에서 읽습니다 (없으면 빈 문자열)."""
    return (
        os.getenv("KAKAO_EMAIL", "").strip(),
        os.getenv("KAKAO_PASSWORD", "").strip(),
    )


def is_configured() -> str | None:
    """
    발행 가능한 설정 상태인지 확인합니다.

    세션 파일이 없어도 KAKAO_EMAIL/KAKAO_PASSWORD가 있으면
    자동 로그인으로 세션을 새로 만들 수 있으므로 통과시킵니다.

    Returns:
        문제가 있으면 안내 메시지, 정상이면 None
    """
    blog_name, state_path = _get_config()
    if not blog_name:
        return "TISTORY_BLOG_NAME이 .env에 설정되지 않았습니다."
    email, password = _get_credentials()
    if not state_path.exists() and not (email and password):
        return (
            f"로그인 세션 파일이 없습니다: {state_path} — "
            "로컬에서 scripts/tistory_login.py 실행 후 파일을 서버에 올리거나, "
            ".env에 KAKAO_EMAIL/KAKAO_PASSWORD를 설정해 주세요."
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


async def _has_tistory_session(context) -> bool:
    """티스토리 로그인 쿠키(TSSESSION)가 브라우저에 있는지 확인합니다."""
    cookies = await context.cookies()
    return any(
        c["name"].startswith("TSSESSION") and "tistory.com" in c["domain"]
        for c in cookies
    )


async def _save_fail_screenshot(page, prefix: str) -> str:
    """실패 원인 파악용 스크린샷을 logs/에 남깁니다 (실패해도 무시)."""
    try:
        _SCREENSHOT_DIR.mkdir(exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = str(_SCREENSHOT_DIR / f"{prefix}_{stamp}.png")
        await page.screenshot(path=path, full_page=True)
        return path
    except Exception:
        return ""


async def _try_auto_relogin(page, context, state_path: Path) -> str | None:
    """
    티스토리 세션이 죽었을 때 자동 재로그인을 시도합니다.

    시도 순서:
    1. 티스토리 로그인 페이지 → "카카오계정으로 로그인" 클릭
       (카카오 쿠키가 살아있으면 이것만으로 재로그인 완료 — 비밀번호 불필요)
    2. 카카오 로그인 폼이 뜨면 .env의 KAKAO_EMAIL/KAKAO_PASSWORD로 자동 입력
    3. 동의/계속 페이지가 끼어들면 "계속하기" 류 버튼을 눌러 진행
    4. TSSESSION 쿠키가 생기면 세션 파일에 저장하고 성공

    캡차나 2단계 인증(카카오톡 확인)이 뜨면 자동화가 불가능하므로
    스크린샷을 남기고 실패를 반환합니다 → 이때만 수동 재로그인 필요.

    Returns:
        성공하면 None, 실패하면 에러 메시지
    """
    import asyncio as _asyncio

    logger.info("티스토리 세션 만료 → 자동 재로그인 시도")

    # 1. 티스토리 로그인 페이지에서 카카오 로그인 버튼 클릭
    try:
        await page.goto(TISTORY_LOGIN_URL, wait_until="networkidle", timeout=30000)
        kakao_btn = page.locator(SEL_KAKAO_LOGIN_BTN)
        if await kakao_btn.count() == 0:
            # 클래스가 개편됐을 때를 대비한 텍스트 기반 폴백
            kakao_btn = page.locator("a", has_text="카카오계정으로 로그인")
        await kakao_btn.first.click(timeout=10000)
    except Exception as e:
        shot = await _save_fail_screenshot(page, "tistory_relogin_fail")
        return f"카카오 로그인 버튼 클릭 실패: {e} (스크린샷: {shot})"

    # 2~4. 리다이렉트 체인을 따라가며 최대 45초 동안 로그인 완료를 기다림
    #      (카카오 쿠키 생존 시: 바로 티스토리 복귀 / 사망 시: 로그인 폼 경유)
    form_submitted = False
    for _ in range(45):
        await _asyncio.sleep(1)

        # 성공 판정: 티스토리 세션 쿠키가 생겼는가
        if await _has_tistory_session(context):
            try:
                await context.storage_state(path=str(state_path))
                logger.info("자동 재로그인 성공 — 세션 파일 갱신 완료")
            except Exception as e:
                logger.warning(f"재로그인은 성공했으나 세션 파일 저장 실패: {e}")
            return None

        url = page.url

        # 카카오 로그인 폼 단계 (한 번만 제출)
        if "accounts.kakao.com" in url and not form_submitted:
            email, password = _get_credentials()
            if not (email and password):
                return (
                    "카카오 쿠키까지 만료되어 비밀번호 로그인이 필요하지만 "
                    ".env에 KAKAO_EMAIL/KAKAO_PASSWORD가 없습니다. "
                    "설정하거나 로컬에서 scripts/tistory_login.py로 재로그인해 주세요."
                )

            try:
                # 폼이 아직 렌더링 중일 수 있으므로 입력창을 기다림
                await page.wait_for_selector(SEL_KAKAO_ID_INPUT, timeout=10000)

                # 캡차가 이미 떠 있으면 자동화 불가 → 바로 포기
                captcha_count = await page.locator(
                    "img[src*='captcha'], [class*='captcha'], iframe[src*='recaptcha']"
                ).count()
                if captcha_count > 0:
                    shot = await _save_fail_screenshot(page, "tistory_relogin_captcha")
                    return f"카카오 로그인 캡차 감지 — 수동 로그인 필요 (스크린샷: {shot})"

                await page.fill(SEL_KAKAO_ID_INPUT, email)
                await page.fill(SEL_KAKAO_PW_INPUT, password)

                # "로그인 상태 유지" 체크 (셀렉터가 자주 바뀌어 실패해도 계속)
                try:
                    stay = page.locator("input[type='checkbox']").first
                    if await stay.count() > 0 and not await stay.is_checked():
                        # 체크박스가 숨겨져 있고 라벨 클릭만 되는 UI 대비
                        await stay.check(timeout=3000, force=True)
                except Exception:
                    pass

                await page.click(SEL_KAKAO_SUBMIT, timeout=5000)
                form_submitted = True
                logger.info("카카오 로그인 폼 제출 완료 — 결과 대기")
            except Exception as e:
                shot = await _save_fail_screenshot(page, "tistory_relogin_fail")
                return f"카카오 로그인 폼 입력 실패: {e} (스크린샷: {shot})"
            continue

        # 동의/계속 페이지 (kauth.kakao.com) — "계속하기" 류 버튼을 눌러 진행
        if "kauth.kakao.com" in url or ("accounts.kakao.com" in url and form_submitted):
            for text in ("동의하고 계속하기", "계속하기", "확인"):
                try:
                    btn = page.locator(
                        f"button:has-text('{text}'), a:has-text('{text}')"
                    )
                    if await btn.count() > 0:
                        await btn.first.click(timeout=3000)
                        break
                except Exception:
                    continue

    # 45초 안에 세션이 안 생김 → 캡차/2단계 인증에 막혔을 가능성이 높음
    shot = await _save_fail_screenshot(page, "tistory_relogin_timeout")
    return (
        f"자동 재로그인 시간 초과 (현재 페이지: {page.url}) — "
        f"캡차 또는 카카오톡 2단계 인증에 막혔을 수 있습니다. "
        f"로컬에서 scripts/tistory_login.py로 수동 로그인해 주세요. (스크린샷: {shot})"
    )


async def keepalive_session() -> dict:
    """
    세션 keep-alive — 관리 페이지에 접속해 갱신된 쿠키를 세션 파일에 되씁니다.

    티스토리/카카오 세션은 "마지막 사용 후 일정 시간"이 지나면 서버 쪽에서
    만료시키는 것으로 보이므로(실측 반나절~하루), 몇 시간마다 이 함수를 돌려
    세션을 계속 사용 상태로 유지합니다. 이미 죽어 있으면 자동 재로그인을 시도합니다.

    Returns:
        {"status": "extended"|"relogin", "detail": 설명} 또는 {"error": 메시지}
    """
    config_error = is_configured()
    if config_error:
        return {"error": config_error}

    blog_name, state_path = _get_config()

    # 발행과 동시에 돌지 않도록 같은 잠금 사용 (브라우저 세션 충돌 방지)
    async with _publish_lock:
        from playwright.async_api import async_playwright

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            # 세션 파일이 아예 없으면 빈 브라우저로 시작해 곧장 재로그인 경로로
            context = await browser.new_context(
                storage_state=str(state_path) if state_path.exists() else None
            )
            page = await context.new_page()
            try:
                await page.goto(
                    f"https://{blog_name}.tistory.com/manage/",
                    wait_until="networkidle",
                    timeout=30000,
                )

                # 로그인 페이지로 튕김 = 세션 사망 → 자동 재로그인
                if "accounts.kakao.com" in page.url or "/login" in page.url:
                    error = await _try_auto_relogin(page, context, state_path)
                    if error:
                        return {"error": error}
                    return {
                        "status": "relogin",
                        "detail": "세션이 만료되어 자동 재로그인으로 복구했습니다.",
                    }

                # 살아있음 → 갱신된 쿠키를 되써서 만료 시점을 뒤로 밀기
                await context.storage_state(path=str(state_path))
                return {"status": "extended", "detail": "세션 쿠키를 갱신했습니다."}

            except Exception as e:
                logger.error(f"세션 keep-alive 중 오류: {e}", exc_info=True)
                return {"error": f"세션 keep-alive 중 오류: {e}"}
            finally:
                await context.close()
                await browser.close()


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
        # 세션 파일이 없으면 빈 브라우저로 시작 → 아래에서 자동 재로그인 시도
        context = await browser.new_context(
            storage_state=str(state_path) if state_path.exists() else None
        )
        page = await context.new_page()

        # 에디터의 confirm 대화상자(모드 전환 경고, 임시저장 글 알림 등)는
        # 모두 "확인"으로 처리 — 새 글 작성 흐름을 막지 않기 위함
        page.on("dialog", lambda dialog: asyncio.ensure_future(dialog.accept()))

        try:
            await page.goto(editor_url, wait_until="networkidle", timeout=30000)

            # 로그인 세션 만료 감지 — 로그인 페이지로 리다이렉트됨
            # → 자동 재로그인(카카오 SSO/비밀번호)을 시도한 뒤 에디터 재진입
            if "accounts.kakao.com" in page.url or "/login" in page.url:
                relogin_error = await _try_auto_relogin(page, context, state_path)
                if relogin_error:
                    return {
                        "error": f"티스토리 세션 만료 + 자동 재로그인 실패: {relogin_error}"
                    }
                await page.goto(editor_url, wait_until="networkidle", timeout=30000)
                if "accounts.kakao.com" in page.url or "/login" in page.url:
                    return {
                        "error": "자동 재로그인 후에도 에디터 접근 불가 — "
                        "로컬에서 scripts/tistory_login.py로 수동 로그인해 주세요."
                    }

            # ── 세션 자동 연장 ──
            # 에디터 접속에 성공했다는 건 방금 서버가 갱신된 쿠키를 내려줬다는 뜻.
            # 이 시점의 쿠키를 세션 파일에 되써두면 매일 배치가 돌 때마다
            # 만료 시점이 뒤로 밀려서, 수동 재로그인 빈도가 크게 줄어든다.
            # (로그인 페이지로 튕긴 경우는 위에서 이미 반환했으므로,
            #  로그아웃 상태로 파일을 덮어쓸 위험은 없음)
            try:
                await context.storage_state(path=str(state_path))
                logger.info("티스토리 세션 쿠키 갱신 저장 완료")
            except Exception as e:
                logger.warning(f"세션 쿠키 갱신 저장 실패 (발행은 계속): {e}")

            # ── 0. 카테고리 선택 (설정돼 있을 때만, 실패해도 발행은 계속) ──
            category = os.getenv("TISTORY_CATEGORY", "").strip()
            if category:
                try:
                    await page.click(SEL_CATEGORY_BTN, timeout=5000)
                    # 하위 카테고리는 "- 이름" 형태로 표시되므로 부분 일치로 찾음
                    await page.locator(
                        SEL_CATEGORY_ITEM, has_text=category
                    ).first.click(timeout=5000)
                    logger.info(f"카테고리 선택: {category}")
                except Exception as e:
                    logger.warning(
                        f"카테고리 선택 실패 (기본 카테고리로 발행 계속): {category} — {e}"
                    )

            # ── 1. 마크다운 모드로 전환 ──
            await page.click(SEL_MODE_BTN, timeout=10000)
            await page.click(SEL_MODE_MARKDOWN, timeout=5000)
            # 모드 전환 확인 대화상자는 위의 dialog 핸들러가 자동 승인
            await page.wait_for_selector(SEL_CODEMIRROR_VISIBLE, timeout=10000)

            # ── 2. 제목 입력 ──
            await page.fill(SEL_TITLE, title)

            # ── 3. 본문 입력 ──
            # CodeMirror는 일반 textarea가 아니라 fill()이 통하지 않음.
            # 주의: CodeMirror.setValue()로 넣으면 화면에는 보이지만 티스토리
            # 앱 내부 상태에 반영되지 않아 "빈 본문"으로 발행됨 (실발행에서 확인).
            # → 에디터를 클릭해 포커스한 뒤, 실제 타이핑과 동일한 입력 이벤트를
            #   만드는 keyboard.insert_text()로 본문을 주입한다.
            await page.click(SEL_CODEMIRROR_VISIBLE)
            await page.keyboard.insert_text(markdown)

            # 주입 결과 검증 — 에디터가 실제로 본문을 들고 있는지 확인
            injected_len = await page.evaluate(
                """(selector) => {
                    const editors = [...document.querySelectorAll(selector)];
                    const visible = editors.find(el => el.offsetParent !== null);
                    return (visible || editors[0]).CodeMirror.getValue().length;
                }""",
                SEL_CODEMIRROR,
            )
            if injected_len < len(markdown) * 0.9:
                return {
                    "error": f"본문 주입 실패: 에디터에 {injected_len}자만 들어감 "
                    f"(기대 {len(markdown)}자)"
                }

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
