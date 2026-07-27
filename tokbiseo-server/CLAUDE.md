# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

톡비서(TokBiseo) 서버 — 카카오톡 오픈채팅방 대화를 분석하여 기술 학습 리포트를 자동 생성하는 FastAPI + LangGraph 멀티에이전트 시스템. Flutter 앱이 클라이언트.

## Commands

```bash
# 로컬 개발 서버 실행
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 3936

# Docker 빌드 & 실행
docker compose up -d --build

# 헬스체크
curl http://localhost:3936/health

# 의존성 추가
uv add <package-name>
```

테스트 프레임워크, 린터 미설정. Swagger UI: `http://localhost:3936/docs`

## Architecture

7-node LangGraph StateGraph 파이프라인. 그래프는 서버 시작 시 한 번 컴파일되어 `app.state`에 저장, 요청마다 재사용.

```
Filter → Analyst → Supervisor → [Web Searcher ∥ YT Searcher] → Validator → Writer → END
```

- **LLM 사용 노드**: Filter (gpt-4.1-mini), Analyst (gpt-5.1), Validator (gpt-4.1-mini), Writer (gpt-5.1, temp=0.3)
- **LLM 미사용 노드**: Supervisor (JSON 파싱), Web Searcher (Tavily API), YT Searcher (YouTube API)
- **병렬 실행**: Supervisor 이후 Web/YT Searcher 병렬

### Key Files

| 파일 | 역할 |
|------|------|
| `app/main.py` | FastAPI 앱, 엔드포인트 (`/api/summarize`, `/api/summarize-stream`, `/auth/notion/callback`), lifespan |
| `app/agents/state.py` | `AgentState` TypedDict — 노드 간 공유 상태. 토큰 카운트는 `Annotated[int, operator.add]`로 병렬 자동 합산 |
| `app/agents/graph.py` | `build_graph()` — StateGraph 조립 및 컴파일 |
| `app/agents/*.py` | 각 에이전트 노드 (`filter`, `analyst`, `supervisor`, `web_searcher`, `yt_searcher`, `validator`, `writer`) |
| `app/schemas.py` | Pydantic 요청/응답 모델 (`SummarizeRequest`, `SummarizeResponse`) |
| `app/tools/` | 외부 API 래퍼 (`tavily_tool.py`, `youtube_tool.py`) |
| `app/services/notion_service.py` | Notion OAuth 토큰 교환 + 리포트 저장 |

### API Endpoints

- `POST /api/summarize` — 동기 분석 (blocking)
- `POST /api/summarize-stream` — SSE 스트리밍 (노드 완료마다 이벤트 전송, 30초 keep-alive ping)
- `GET /auth/notion/callback` — Notion OAuth 콜백
- `GET /health` — 헬스체크

### Agent Node Pattern

각 에이전트 노드는 동일 패턴: `AgentState`를 받아 자기 담당 필드만 업데이트한 dict를 반환. LLM 사용 노드는 `ChatOpenAI`를 노드 내에서 인스턴스화하고, 토큰 사용량을 `total_input_tokens`/`total_output_tokens`에 누적.

## Environment Variables

필수: `OPENAI_API_KEY`. 선택: `TAVILY_API_KEY`, `YOUTUBE_API_KEY`, Notion OAuth 관련 키, `LANGCHAIN_API_KEY` (LangSmith 트레이싱). `.env.example` 참조.

## Tech Stack

Python 3.13, FastAPI, LangGraph, LangChain (ChatOpenAI), Tavily, YouTube Data API v3, uv (패키지 매니저), Docker
