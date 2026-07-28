"""
FastAPI 메인 앱 — 톡비서 멀티에이전트 서버

엔드포인트:
- POST /api/summarize : 카카오톡 대화를 받아 멀티에이전트 파이프라인으로 분석/요약
- POST /api/summarize-stream : SSE 스트리밍 버전 (진행률 실시간 전송)
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

from .schemas import SummarizeRequest, SummarizeResponse, HealthResponse
from .agents.graph import build_graph
from .services.notion_service import (
    save_report_to_notion,
    exchange_code_for_token,
    extract_keywords,
)

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
    yield
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
