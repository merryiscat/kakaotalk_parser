"""
FastAPI 메인 앱 — 톡비서 멀티에이전트 서버

엔드포인트:
- POST /api/summarize : 카카오톡 대화를 받아 멀티에이전트 파이프라인으로 분석/요약
- POST /api/summarize-stream : SSE 스트리밍 버전 (진행률 실시간 전송)
- GET /api/notion/pending : 발행 대기(초안) Notion 페이지 목록
- GET /api/notion/page/{page_id} : 페이지 본문 마크다운 (발행 미리보기)
- POST /api/publish/tistory : 티스토리 발행 (Playwright 자동화)
- GET /health : 서버 상태 확인
"""

import os
import json
import logging
import time
from contextlib import asynccontextmanager
from datetime import datetime

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sse_starlette.sse import EventSourceResponse

from .schemas import (
    SummarizeRequest,
    SummarizeResponse,
    HealthResponse,
    PendingPagesResponse,
    PageContentResponse,
    PublishRequest,
    PublishResponse,
)
from .agents.graph import build_graph
from .services.notion_service import (
    save_report_to_notion,
    exchange_code_for_token,
    extract_keywords,
    query_pending_pages,
    fetch_page_info,
    fetch_page_markdown,
    update_publish_status,
)
from .services import tistory_service

# .env 파일에서 환경 변수 로드 (API 키 등)
# 서버 루트 디렉토리의 .env를 명시적으로 지정 (실행 위치와 무관하게 동작)
from pathlib import Path
_env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(_env_path)

# ── 로깅 설정 ──
from logging.handlers import TimedRotatingFileHandler

_log_format = "%(asctime)s [%(name)s] %(levelname)s: %(message)s"
_log_datefmt = "%H:%M:%S"
_log_handlers: list[logging.Handler] = [logging.StreamHandler()]

try:
    _log_dir = Path(__file__).resolve().parent.parent / "logs"
    _log_dir.mkdir(exist_ok=True)
    _file_handler = TimedRotatingFileHandler(
        _log_dir / "tokbiseo.log",
        when="midnight",
        backupCount=7,
        encoding="utf-8",
    )
    _file_handler.suffix = "%Y-%m-%d"
    _file_handler.setFormatter(logging.Formatter(_log_format, datefmt=_log_datefmt))
    _log_handlers.append(_file_handler)
except (PermissionError, OSError):
    pass  # Docker 권한 문제 등 — stdout만 사용

logging.basicConfig(
    level=logging.INFO,
    format=_log_format,
    datefmt=_log_datefmt,
    handlers=_log_handlers,
)
logger = logging.getLogger("톡비서")

# LangGraph 워크플로우 (앱 시작 시 한 번만 빌드)
_graph = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작 시 그래프 빌드, 종료 시 정리"""
    global _graph

    # LangSmith 트레이싱 설정 상태 확인
    tracing_v2 = os.getenv("LANGCHAIN_TRACING_V2", "")
    langchain_key = os.getenv("LANGCHAIN_API_KEY", "")
    langchain_project = os.getenv("LANGCHAIN_PROJECT", "")
    logger.info(f"LangSmith 설정: LANGCHAIN_TRACING_V2={tracing_v2}")
    logger.info(f"  LANGCHAIN_API_KEY={'설정됨 (' + langchain_key[:10] + '...)' if langchain_key else '없음'}")
    logger.info(f"  LANGCHAIN_PROJECT={langchain_project or '없음'}")
    logger.info(f"  .env 경로: {_env_path} (존재: {_env_path.exists()})")

    _graph = build_graph()
    logger.info("멀티에이전트 그래프 빌드 완료")

    # 티스토리 일일 자동 발행 배치 시작 (매일 오전 9시, KST)
    import asyncio

    batch_task = asyncio.create_task(_tistory_batch_loop())
    # 티스토리 세션 keep-alive — 몇 시간마다 쿠키를 갱신해 세션 만료 방지
    keepalive_task = asyncio.create_task(_tistory_keepalive_loop())

    yield

    batch_task.cancel()
    keepalive_task.cancel()
    logger.info("서버 종료")


app = FastAPI(
    title="톡비서 멀티에이전트 서버",
    description="카카오톡 대화를 멀티에이전트 파이프라인으로 분석하여 구체적 리포트를 생성합니다.",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS 설정 — Flutter 앱에서 접근 가능하도록
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 모든 출처 허용 (로컬 서버용)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """서버 상태 확인 — 앱에서 연결 테스트 시 사용"""
    return HealthResponse()


@app.get("/auth/notion/callback")
async def notion_oauth_callback(code: str = "", error: str = ""):
    """
    Notion OAuth 콜백 — 인증 코드를 access token으로 교환 후 .env에 저장.

    브라우저에서 Notion 인증 후 리다이렉트되는 엔드포인트.
    한 번만 실행하면 이후 자동으로 Notion 저장이 동작합니다.
    """
    from fastapi.responses import HTMLResponse

    if error:
        return HTMLResponse(f"<h2>Notion 인증 거부</h2><p>{error}</p>")
    if not code:
        return HTMLResponse("<h2>인증 코드가 없습니다</h2>")

    result = await exchange_code_for_token(code)

    if "access_token" in result:
        workspace = result.get("workspace_name", "")
        return HTMLResponse(
            f"<h2>Notion 연결 완료!</h2>"
            f"<p>워크스페이스: {workspace}</p>"
            f"<p>access token이 .env에 저장되었습니다. 이 창을 닫아도 됩니다.</p>"
        )
    else:
        return HTMLResponse(f"<h2>토큰 교환 실패</h2><p>{result.get('error', '')}</p>")


def _apply_api_keys(request: SummarizeRequest) -> None:
    """
    요청에 포함된 API 키를 환경 변수에 설정합니다.

    Flutter 앱에서 사용자가 입력한 API 키를 서버 환경 변수로 전달합니다.
    키가 비어있으면 기존 .env 값이 유지됩니다.
    """
    if request.openai_api_key:
        os.environ["OPENAI_API_KEY"] = request.openai_api_key
    if request.tavily_api_key:
        os.environ["TAVILY_API_KEY"] = request.tavily_api_key
    if request.youtube_api_key:
        os.environ["YOUTUBE_API_KEY"] = request.youtube_api_key


def _build_notion_title(request: SummarizeRequest) -> str:
    """
    Notion 페이지 제목을 만듭니다.

    "방이름 — 2026-03-10" 형식이 기본이고, 앱이 메타데이터를 보내지 않는
    구버전이면 사용 가능한 정보만으로 조합합니다.
    """
    room = request.room_name.strip()
    date = request.chat_date.strip()
    if room and date:
        return f"{room} — {date}"
    if room:
        return room
    if date:
        return f"톡비서 리포트 — {date}"
    return "톡비서 리포트"


async def _save_to_notion(
    report: str,
    request: SummarizeRequest,
    input_tokens: int = 0,
    output_tokens: int = 0,
) -> None:
    """
    리포트를 Notion 데이터베이스에 저장합니다 (설정되어 있을 때만).

    .env에 NOTION_ACCESS_TOKEN과 NOTION_DATABASE_ID가 모두 있을 때만 동작합니다.
    저장 실패해도 예외를 발생시키지 않고 경고 로그만 남깁니다.

    메타데이터는 DB에 해당 속성이 있을 때만 채워집니다
    (매핑 규칙은 notion_service._PROPERTY_CANDIDATES 참조).
    """
    notion_token = os.getenv("NOTION_ACCESS_TOKEN", "")
    notion_db = os.getenv("NOTION_DATABASE_ID", "")
    if not (notion_token and notion_db):
        return

    meta = {
        "room_name": request.room_name.strip(),
        "chat_date": request.chat_date.strip(),
        "message_count": request.message_count,
        # 로컬 타임존 오프셋 포함 ISO 8601 (Notion date 속성이 요구하는 형식)
        "created_at": datetime.now().astimezone().isoformat(),
        "keywords": extract_keywords(report),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        # 티스토리 발행 큐의 시작 상태
        "publish_status": "초안",
    }

    result = await save_report_to_notion(
        access_token=notion_token,
        database_id=notion_db,
        title=_build_notion_title(request),
        report_markdown=report,
        meta=meta,
    )
    if "error" in result:
        logger.warning(f"Notion 저장 실패 (리포트는 정상 반환): {result['error']}")
    else:
        logger.info(f"Notion 저장 완료: {result.get('url', '')}")


@app.post("/api/summarize", response_model=SummarizeResponse)
async def summarize(request: SummarizeRequest):
    """
    카카오톡 대화를 멀티에이전트 파이프라인으로 분석합니다.
    """
    if _graph is None:
        raise HTTPException(
            status_code=500,
            detail="멀티에이전트 그래프가 초기화되지 않았습니다.",
        )

    _apply_api_keys(request)

    # API 키 상태 로그
    logger.info("=== 요약 요청 수신 ===")
    logger.info(f"  대화 길이: {len(request.messages)}자")
    logger.info(f"  URL 제목 수: {len(request.url_titles)}개")
    logger.info(f"  OpenAI 키: {'설정됨' if os.getenv('OPENAI_API_KEY') else '없음'}")
    logger.info(f"  Tavily 키: {'설정됨' if os.getenv('TAVILY_API_KEY') else '없음'}")
    logger.info(f"  YouTube 키: {'설정됨' if os.getenv('YOUTUBE_API_KEY') else '없음'}")

    # OpenAI 키는 필수
    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(
            status_code=400,
            detail="OpenAI API 키가 설정되지 않았습니다. 앱 설정에서 입력하세요.",
        )

    try:
        # 초기 상태 구성
        initial_state = {
            "messages": request.messages,
            "url_titles": request.url_titles,
            "total_input_tokens": 0,
            "total_output_tokens": 0,
        }

        start_time = time.time()
        result = await _graph.ainvoke(initial_state)
        elapsed = time.time() - start_time

        # 최종 결과 로그
        report = result.get("report", "")
        logger.info("=== 파이프라인 완료 ===")
        logger.info(f"  총 소요시간: {elapsed:.1f}초")
        logger.info(f"  리포트 길이: {len(report)}자")
        logger.info(f"  총 입력 토큰: {result.get('total_input_tokens', 0)}")
        logger.info(f"  총 출력 토큰: {result.get('total_output_tokens', 0)}")

        if not report:
            raise HTTPException(
                status_code=500,
                detail="리포트 생성에 실패했습니다. 파이프라인 결과가 비어있습니다.",
            )

        await _save_to_notion(
            report,
            request,
            input_tokens=result.get("total_input_tokens", 0),
            output_tokens=result.get("total_output_tokens", 0),
        )

        return SummarizeResponse(
            summary=report,
            input_tokens=result.get("total_input_tokens", 0),
            output_tokens=result.get("total_output_tokens", 0),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"파이프라인 실행 중 오류: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"파이프라인 실행 중 오류: {str(e)}",
        )


# ── SSE 스트리밍 관련 상수 ──

# 노드별 한글 표시명 (앱 UI에 표시)
NODE_DISPLAY_NAMES = {
    "filter": "잡담 필터링",
    "analyst": "대화 분석",
    "supervisor": "조사 계획",
    "web_searcher": "웹 검색",
    "yt_searcher": "유튜브 검색",
    "validator": "자료 검증",
    "writer": "리포트 작성",
}

# 파이프라인 총 노드 수
TOTAL_STEPS = 7


@app.post("/api/summarize-stream")
async def summarize_stream(request: SummarizeRequest):
    """
    SSE 스트리밍 버전 — 노드 완료마다 진행 이벤트 전송.

    이벤트 종류:
    - node_complete: 각 노드 완료 시 진행률
    - result: 파이프라인 완료, 최종 리포트
    - error: 오류 발생
    - (자동) : ping — 30초마다 keep-alive
    """
    if _graph is None:
        raise HTTPException(
            status_code=500,
            detail="멀티에이전트 그래프가 초기화되지 않았습니다.",
        )

    _apply_api_keys(request)

    logger.info("=== SSE 스트리밍 요약 요청 수신 ===")
    logger.info(f"  대화 길이: {len(request.messages)}자")
    logger.info(f"  URL 제목 수: {len(request.url_titles)}개")

    if not os.getenv("OPENAI_API_KEY"):
        raise HTTPException(
            status_code=400,
            detail="OpenAI API 키가 설정되지 않았습니다.",
        )

    async def event_generator():
        try:
            initial_state = {
                "messages": request.messages,
                "url_titles": request.url_titles,
                "total_input_tokens": 0,
                "total_output_tokens": 0,
            }

            step = 0
            start_time = time.time()

            # ── 누적 추적 변수 ──
            # astream()의 각 chunk는 해당 노드의 출력(증가분)만 포함하므로
            # 토큰과 리포트를 별도로 누적 관리해야 한다
            accumulated_input_tokens = 0
            accumulated_output_tokens = 0
            last_report = ""

            async for chunk in _graph.astream(initial_state):
                # chunk는 {노드이름: 상태업데이트} 형태
                # 병렬 노드는 하나의 chunk에 여러 키로 동시에 올 수 있음
                for node_name, node_state in chunk.items():
                    if node_name == "__end__":
                        continue

                    step += 1
                    display_name = NODE_DISPLAY_NAMES.get(node_name, node_name)

                    # 토큰 누적 (Annotated[int, operator.add] 필드라서
                    # 각 chunk에는 해당 노드의 증가분만 포함됨)
                    node_input = node_state.get("total_input_tokens", 0)
                    node_output = node_state.get("total_output_tokens", 0)
                    accumulated_input_tokens += node_input
                    accumulated_output_tokens += node_output

                    # writer 노드가 report를 출력하면 저장
                    if "report" in node_state:
                        last_report = node_state["report"]

                    event_data = {
                        "node": node_name,
                        "display_name": display_name,
                        "status": "completed",
                        "step": step,
                        "total_steps": TOTAL_STEPS,
                        "input_tokens": accumulated_input_tokens,
                        "output_tokens": accumulated_output_tokens,
                    }

                    yield {
                        "event": "node_complete",
                        "data": json.dumps(event_data, ensure_ascii=False),
                    }

            # 파이프라인 완료
            elapsed = time.time() - start_time
            logger.info(f"=== SSE 파이프라인 완료 ({elapsed:.1f}초) ===")

            if not last_report:
                yield {
                    "event": "error",
                    "data": json.dumps(
                        {"detail": "리포트 생성 실패: 결과가 비어있습니다."},
                        ensure_ascii=False,
                    ),
                }
                return

            yield {
                "event": "result",
                "data": json.dumps(
                    {
                        "summary": last_report,
                        "input_tokens": accumulated_input_tokens,
                        "output_tokens": accumulated_output_tokens,
                    },
                    ensure_ascii=False,
                ),
            }

            await _save_to_notion(
                last_report,
                request,
                input_tokens=accumulated_input_tokens,
                output_tokens=accumulated_output_tokens,
            )

        except Exception as e:
            logger.error(f"SSE 파이프라인 오류: {e}", exc_info=True)
            yield {
                "event": "error",
                "data": json.dumps(
                    {"detail": f"파이프라인 실행 중 오류: {str(e)}"},
                    ensure_ascii=False,
                ),
            }

    return EventSourceResponse(event_generator(), ping=30)


# ── 티스토리 발행 (Notion 발행 큐 → 블로그 글) ──


def _notion_credentials() -> tuple[str, str]:
    """
    Notion 토큰과 DB ID를 읽습니다. 없으면 400 에러.

    발행 관련 엔드포인트는 모두 Notion 연동이 선행돼야 동작합니다.
    """
    token = os.getenv("NOTION_ACCESS_TOKEN", "")
    db = os.getenv("NOTION_DATABASE_ID", "")
    if not (token and db):
        raise HTTPException(
            status_code=400,
            detail="Notion 연동이 설정되지 않았습니다 (NOTION_ACCESS_TOKEN/NOTION_DATABASE_ID).",
        )
    return token, db


@app.get("/api/notion/pending", response_model=PendingPagesResponse)
async def notion_pending():
    """
    발행상태가 "초안"인 Notion 페이지 목록 — 티스토리 발행 대기 큐.

    앱의 발행 화면이 이 목록을 보여줍니다.
    """
    token, db = _notion_credentials()
    result = await query_pending_pages(token, db)
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    return PendingPagesResponse(pages=result["pages"])


@app.get("/api/notion/page/{page_id}", response_model=PageContentResponse)
async def notion_page_content(page_id: str):
    """
    페이지 본문을 마크다운으로 역변환해 반환 — 발행 전 미리보기용.
    """
    token, _ = _notion_credentials()
    result = await fetch_page_markdown(token, page_id)
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    return PageContentResponse(markdown=result["markdown"])


async def _publish_notion_page(page_id: str, tags: list[str] | None = None) -> dict:
    """
    Notion 페이지 한 건을 티스토리에 발행하는 공통 로직.

    앱의 수동 발행 엔드포인트와 일일 자동 배치가 함께 사용합니다.

    흐름: 페이지 정보·본문 조회 → Playwright로 에디터 자동화 발행
          → 성공 시 Notion 발행상태를 "발행완료"로 갱신

    Returns:
        {"url": "발행된 주소"} 또는 {"error": "에러 메시지"}
    """
    token, db = _notion_credentials()

    # 발행 설정(블로그 이름·로그인 세션)이 안 돼 있으면 바로 안내
    config_error = tistory_service.is_configured()
    if config_error:
        return {"error": config_error}

    # 1. 페이지 제목·키워드 조회
    info = await fetch_page_info(token, page_id)
    if "error" in info:
        return {"error": info["error"]}

    # 2. 본문 마크다운 역변환
    content = await fetch_page_markdown(token, page_id)
    if "error" in content:
        return {"error": content["error"]}

    markdown = content["markdown"].strip()
    if not markdown:
        return {"error": "페이지 본문이 비어있습니다."}

    # 3. Playwright 발행 (태그를 안 보냈으면 Notion 키워드 사용)
    title = info.get("title") or "톡비서 리포트"
    tags = tags or info.get("keywords", [])
    logger.info(f"티스토리 발행 시작: {title} (태그 {len(tags)}개)")

    result = await tistory_service.publish_post(title, markdown, tags)
    if "error" in result:
        return {"error": result["error"]}

    # 4. 발행상태 갱신 — 실패해도 발행 자체는 성공이므로 경고만 남김
    status_result = await update_publish_status(token, db, page_id, "발행완료")
    if "error" in status_result:
        logger.warning(f"발행상태 갱신 실패 (글은 발행됨): {status_result['error']}")

    return {"url": result["url"], "title": title}


@app.post("/api/publish/tistory", response_model=PublishResponse)
async def publish_tistory(request: PublishRequest):
    """
    Notion 페이지 한 건을 티스토리에 발행합니다 (앱 발행 탭에서 호출).

    주의: 티스토리 1일 발행 수 제한이 있으므로 앱에서 한 건씩 호출하세요.
    """
    result = await _publish_notion_page(request.page_id, request.tags)
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    return PublishResponse(url=result["url"])


# ── 일일 자동 발행 배치 ──


async def _run_tistory_batch() -> dict:
    """
    발행 대기(발행상태="초안") 중 가장 최신 리포트 1건을 티스토리에 발행합니다.

    티스토리 1일 발행 수 제한 때문에 한 번에 1건만 발행합니다.
    발행할 글이 없으면 조용히 넘어갑니다.

    Returns:
        {"url", "title"} (발행 성공) / {"skipped": 사유} / {"error": 메시지}
    """
    try:
        token, db = _notion_credentials()
    except HTTPException as e:
        return {"skipped": f"Notion 미설정 — {e.detail}"}

    config_error = tistory_service.is_configured()
    if config_error:
        return {"skipped": f"티스토리 미설정 — {config_error}"}

    pending = await query_pending_pages(token, db)
    if "error" in pending:
        return {"error": pending["error"]}

    pages = pending["pages"]
    if not pages:
        return {"skipped": "발행 대기 글 없음"}

    # 목록이 최신 생성 순이므로 첫 번째가 가장 최근 리포트
    target = pages[0]
    logger.info(f"[배치] 발행 대상: {target['title']} ({target['page_id']})")
    return await _publish_notion_page(target["page_id"])


@app.post("/api/publish/tistory/batch")
async def publish_tistory_batch():
    """
    일일 배치를 수동으로 1회 실행 — 배치 동작 테스트용.
    """
    result = await _run_tistory_batch()
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    return result


@app.post("/api/publish/tistory/keepalive")
async def tistory_keepalive():
    """
    세션 keep-alive를 수동으로 1회 실행 — 배포 직후 세션 상태 점검용.

    세션이 살아있으면 쿠키만 갱신하고, 죽어있으면 자동 재로그인을 시도합니다.
    """
    result = await tistory_service.keepalive_session()
    if "error" in result:
        raise HTTPException(status_code=502, detail=result["error"])
    return result


async def _tistory_keepalive_loop():
    """
    몇 시간마다(기본 3시간, TISTORY_KEEPALIVE_HOURS로 변경) 세션 keep-alive를
    실행하는 백그라운드 루프.

    티스토리/카카오 세션은 안 쓰면 반나절~하루 만에 서버 쪽에서 만료되는 것으로
    실측됐습니다. 하루 1회 발행 배치만으로는 만료를 못 막으므로, 더 짧은 주기로
    세션을 "사용 중" 상태로 유지합니다. 죽어 있으면 자동 재로그인까지 시도합니다.
    """
    import asyncio

    hours = float(os.getenv("TISTORY_KEEPALIVE_HOURS", "3"))
    if hours <= 0:
        logger.info("[keep-alive] 비활성화됨 (TISTORY_KEEPALIVE_HOURS=0)")
        return

    # 서버 기동 직후 안정화를 위해 1분 뒤 첫 실행
    # (배포 직후 세션 상태를 바로 로그에서 확인할 수 있는 효과도 있음)
    await asyncio.sleep(60)

    while True:
        try:
            result = await tistory_service.keepalive_session()
            if "error" in result:
                logger.warning(f"[keep-alive] 실패: {result['error']}")
            else:
                logger.info(f"[keep-alive] {result['detail']}")
        except Exception as e:
            # keep-alive 1회 실패가 루프 자체를 죽이지 않도록 방어
            logger.error(f"[keep-alive] 실행 중 예외: {e}", exc_info=True)
        await asyncio.sleep(hours * 3600)


async def _tistory_batch_loop():
    """
    매일 지정 시각(기본 오전 9시, TISTORY_BATCH_HOUR로 변경 가능)에
    발행 배치를 실행하는 백그라운드 루프.

    컨테이너 타임존이 Asia/Seoul로 고정돼 있어 로컬 시각 기준 9시 = KST 9시.
    """
    import asyncio

    hour = int(os.getenv("TISTORY_BATCH_HOUR", "9"))

    while True:
        # 다음 실행 시각까지 남은 시간 계산
        now = datetime.now()
        next_run = now.replace(hour=hour, minute=0, second=0, microsecond=0)
        if next_run <= now:
            from datetime import timedelta

            next_run += timedelta(days=1)
        wait_seconds = (next_run - now).total_seconds()
        logger.info(
            f"[배치] 다음 티스토리 자동 발행: {next_run:%Y-%m-%d %H:%M} "
            f"({wait_seconds / 3600:.1f}시간 후)"
        )
        await asyncio.sleep(wait_seconds)

        try:
            result = await _run_tistory_batch()
            if "url" in result:
                logger.info(f"[배치] 발행 완료: {result.get('title')} → {result['url']}")
            elif "skipped" in result:
                logger.info(f"[배치] 건너뜀: {result['skipped']}")
            else:
                logger.error(f"[배치] 발행 실패: {result.get('error')}")
        except Exception as e:
            # 배치 1회 실패가 루프 자체를 죽이지 않도록 방어
            logger.error(f"[배치] 실행 중 예외: {e}", exc_info=True)
