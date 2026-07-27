# 톡비서 멀티에이전트 서버 아키텍처

## 개요

톡비서 서버는 **FastAPI + LangGraph** 기반의 멀티에이전트 시스템입니다.
카카오톡 오픈채팅방 대화를 입력받아, 8개 에이전트 노드가 순차/병렬로 협업하여
**노이즈 필터링 → 주제 분석 → 자료 검색 → 검증 → 리포트 작성 → 품질 검증**까지
자동 수행합니다.

---

## 시스템 구성도

```
┌─────────────────────────────────────────────────────────┐
│  Flutter 앱 (클라이언트)                                  │
│  POST /api/summarize  ──────────────────────────────┐   │
└─────────────────────────────────────────────────────│───┘
                                                      │
┌─────────────────────────────────────────────────────▼───┐
│  FastAPI 서버 (포트 3936)                                │
│                                                         │
│  ┌───────────┐                                          │
│  │ Analyst   │ ── LLM 호출 (대화 분석)                    │
│  └─────┬─────┘                                          │
│        │                                                │
│  ┌─────▼──────┐                                         │
│  │ Supervisor │ ── 검색 키워드 분배 (LLM 없음)             │
│  └──┬─────┬───┘                                         │
│     │     │                                             │
│     │     │         ←── 병렬 실행 ──→                     │
│  ┌──▼──┐ ┌▼─────┐                                       │
│  │ Web │ │  YT  │ ── API 호출만 (LLM 없음)                │
│  │Sear.│ │Sear. │                                       │
│  └──┬──┘ └┬─────┘                                       │
│     │     │                                             │
│  ┌──▼──┐ ┌▼─────┐                                       │
│  │ Web │ │  YT  │ ── LLM 호출 (결과 검증)                 │
│  │Valid.│ │Valid. │                                       │
│  └──┬──┘ └┬─────┘                                       │
│     │     │                                             │
│     └──┬──┘                                             │
│  ┌─────▼─────┐                                          │
│  │  Writer   │ ── LLM 호출 (리포트 작성)                   │
│  └─────┬─────┘                                          │
│        │                                                │
│  ┌─────▼─────┐     ┌──── REVISE (최대 1회) ──→ Writer    │
│  │ Reviewer  │ ──┤                                      │
│  └───────────┘     └──── PASS ──→ 응답 반환              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 외부 서비스 의존성

| 서비스 | 용도 | API 키 |
|--------|------|--------|
| **OpenAI** (GPT) | Analyst, Validator, Writer, Reviewer의 LLM 추론 | `OPENAI_API_KEY` (필수) |
| **Tavily** | 웹 검색 (공식문서, 블로그, 튜토리얼 수집) | `TAVILY_API_KEY` |
| **YouTube Data API v3** | 유튜브 영상 검색 (교육 영상 수집) | `YOUTUBE_API_KEY` |
| **LangSmith** | LangGraph 실행 트레이싱/디버깅 (선택) | `LANGCHAIN_API_KEY` |

---

## 공유 상태 (AgentState)

모든 노드가 읽고 쓰는 공유 상태입니다. LangGraph가 자동으로 상태를 관리하며,
각 노드는 자기 담당 필드만 업데이트합니다.

```
AgentState (TypedDict)
│
├── 입력 (클라이언트 제공)
│   ├── messages: str              ← 파싱된 카카오톡 대화 텍스트
│   └── url_titles: dict[str,str]  ← 대화에서 발견된 URL → 페이지 제목 맵
│
├── Analyst 출력
│   └── analysis: str              ← 구조화된 분석 결과 (JSON 문자열)
│
├── Supervisor 출력
│   ├── web_search_tasks: list[str]     ← 웹 검색 키워드 리스트
│   └── youtube_search_tasks: list[str] ← 유튜브 검색 키워드 리스트
│
├── Searcher 출력
│   ├── raw_web_results: list[dict]     ← Tavily 웹 검색 원본 결과
│   └── raw_youtube_results: list[dict] ← YouTube 검색 원본 결과
│
├── Validator 출력
│   ├── validated_web_results: str      ← LLM이 검증/정리한 웹 자료
│   └── validated_youtube_results: str  ← LLM이 검증/정리한 영상 자료
│
├── Writer 출력
│   └── report: str                ← 최종 마크다운 리포트
│
├── Reviewer 출력
│   ├── review: str                ← "PASS" 또는 "REVISE:피드백"
│   └── revision_count: int        ← Writer 재호출 횟수 (최대 1회)
│
└── 토큰 추적 (자동 합산)
    ├── total_input_tokens: int    ← 전체 파이프라인 입력 토큰 합계
    └── total_output_tokens: int   ← 전체 파이프라인 출력 토큰 합계
```

> `total_input_tokens`와 `total_output_tokens`는 `Annotated[int, operator.add]`로 선언되어,
> 병렬 노드(Web Validator + YT Validator)가 동시에 값을 보내도 자동으로 합산됩니다.

---

## 에이전트 노드 상세

### 1. Analyst (분석가)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/analyst.py` |
| **역할** | 대화 노이즈 필터링 + 기술 주제 선별 + 학습 방향 설계 |
| **LLM 사용** | O (GPT) |
| **입력** | `messages`, `url_titles` |
| **출력** | `analysis` (JSON) |

**시스템 프롬프트 핵심:**

파이프라인의 첫 번째 노드. 오픈채팅방의 잡담/밈/가십을 걸러내고 실무 가치가 있는 기술 정보만 추출합니다.

3단계 분석을 수행합니다:
- **1단계 — URL 선별 (Top 5)**: 대화에 등장한 URL 중 기술 학습 가치가 높은 것만 최대 5개 선별. 공식 문서, 기술 블로그, 튜토리얼, GitHub 레포 등을 포함하고, 뉴스 기사, 밈, 맥락 없는 링크 스팸은 제외합니다.
- **2단계 — 기술 주제 분류 (최대 5건)**: 프레임워크, 라이브러리, 아키텍처, DevOps, AI/ML 등 실무 적용 가능한 주제만 추출합니다. 각 주제에서 실제 언급된 기술/도구/명령어를 정리하고, 추가로 찾아봐야 할 부분을 명시합니다.
- **3단계 — 학습 방향 설계**: 각 주제에 대해 초보자도 따라할 수 있는 구체적 학습 경로(1→2→3 단계)를 설계합니다. 각 단계에 웹/유튜브 검색 키워드를 포함합니다.

**출력 형식:** JSON
```json
{
  "filtered_urls": [
    {"url": "...", "title": "...", "reason": "학습 가치 근거"}
  ],
  "topics": [
    {
      "title": "주제명",
      "summary": "핵심 내용 2~3줄",
      "mentioned_tech": ["기술/도구 리스트"],
      "gaps": "더 알아봐야 할 부분",
      "learning_path": ["1단계: ...", "2단계: ...", "3단계: ..."],
      "web_keywords": ["웹 검색 키워드"],
      "youtube_keywords": ["유튜브 검색 키워드"]
    }
  ],
  "noise_summary": "제외한 비기술 잡담 요약"
}
```

---

### 2. Supervisor (관리자)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/supervisor.py` |
| **역할** | Analyst의 분석 결과에서 검색 키워드를 추출하여 검색 워커에 분배 |
| **LLM 사용** | X (JSON 파싱만, 비용 절약) |
| **입력** | `analysis` |
| **출력** | `web_search_tasks`, `youtube_search_tasks` |

**동작 방식:**
- Analyst가 출력한 JSON에서 각 topic의 `web_keywords`와 `youtube_keywords`를 추출
- 중복 키워드 제거 후 각 Searcher에게 전달
- JSON 파싱 실패 시 폴백 키워드 자동 생성

---

### 3. Web Searcher (웹 검색)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/web_searcher.py` |
| **역할** | Tavily API로 웹 검색 수행 |
| **LLM 사용** | X (API 호출만, 비용 절약) |
| **입력** | `web_search_tasks` |
| **출력** | `raw_web_results` |

**동작 방식:**
- 각 키워드로 Tavily API 호출 (키워드당 최대 3건)
- URL 기준 중복 제거
- 검색 결과: 제목, URL, 요약 내용, 검색 키워드

---

### 4. YouTube Searcher (영상 검색)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/yt_searcher.py` |
| **역할** | YouTube Data API v3로 교육 영상 검색 |
| **LLM 사용** | X (API 호출만, 비용 절약) |
| **입력** | `youtube_search_tasks` |
| **출력** | `raw_youtube_results` |

**동작 방식:**
- 각 키워드로 YouTube Data API 호출 (키워드당 최대 3건)
- 한국어 결과 우선 (`relevanceLanguage: "ko"`)
- Video ID 기준 중복 제거
- 검색 결과: 제목, URL, 채널명, 설명(200자 제한), 검색 키워드

> Web Searcher와 YouTube Searcher는 **병렬로 동시 실행**됩니다.

---

### 5. Web Validator (웹 검증)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/web_validator.py` |
| **역할** | 웹 검색 결과를 LLM으로 검증/필터링/정리 |
| **LLM 사용** | O (GPT) |
| **입력** | `raw_web_results`, `analysis` |
| **출력** | `validated_web_results` |

**시스템 프롬프트 핵심:**

웹 검색 결과를 검증하는 큐레이터 역할. 다음 기준으로 필터링합니다:
- **관련성 검증**: 대화 주제와 직접 관련 있는 결과만 남기고, 스팸/광고 제거
- **품질 평가**: 공식 문서, 잘 알려진 블로그 등 신뢰 출처 우선. 2년 이상 오래된 정보 낮은 우선순위
- **출력**: `[제목](URL) — 한 줄 설명 [주제태그]` 형식의 마크다운 리스트

---

### 6. YouTube Validator (영상 검증)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/yt_validator.py` |
| **역할** | 유튜브 검색 결과를 LLM으로 검증/필터링 + 난이도 태깅 |
| **LLM 사용** | O (GPT) |
| **입력** | `raw_youtube_results`, `analysis` |
| **출력** | `validated_youtube_results` |

**시스템 프롬프트 핵심:**

유튜브 교육 영상 큐레이션 전문가 역할. 다음 기준으로 필터링합니다:
- **관련성 검증**: 대화 주제와 관련 없는 영상, 광고/프로모션 영상 제거
- **난이도 태깅**: 각 영상에 `[기초]` / `[중급]` / `[심화]` 태그 부여
- **출력**: 난이도별 그룹핑된 마크다운 리스트 (기초 → 중급 → 심화 순)

> Web Validator와 YouTube Validator도 **병렬로 동시 실행**됩니다.

---

### 7. Writer (작성자)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/writer.py` |
| **역할** | 모든 자료를 종합하여 최종 마크다운 리포트 작성 |
| **LLM 사용** | O (GPT, temperature=0.3) |
| **입력** | `messages`, `analysis`, `validated_web_results`, `validated_youtube_results`, `review` (재작성 시) |
| **출력** | `report` |

**시스템 프롬프트 핵심:**

IT 30년 시니어 개발자 페르소나. 4개 섹션 구조의 리포트를 작성합니다:

| 섹션 | 마크다운 헤더 | 설명 |
|------|------------|------|
| 주제 키워드 | `## 주제 키워드` | 핵심 기술 주제를 쉼표로 나열 (한 줄) |
| 대화 주요 내용 | `## 대화 주요 내용` | 주제별 `**제목**` + 2~3줄 서술 |
| 핵심 정보 | `## 핵심 정보` | `### 주제명` 소섹션별로 구체적 팁/명령어/수치 리스트 |
| 톡비서 제안 | `## 톡비서 제안` | `### 주제명` 소섹션별 학습 로드맵 + URL + 영상 포함 |

**마크다운 작성 규칙:**
- `## ` (대섹션)과 `### ` (소섹션)만 사용, `# ` (h1)은 사용 금지
- 이모지 절대 금지
- URL은 `[제목](URL)` 형식만 사용 (날것 노출 금지)
- URL과 영상을 별도 섹션에 모으지 않고 톡비서 제안의 각 주제 안에 포함
- Reviewer가 REVISE 판정 시 피드백을 반영하여 재작성

---

### 8. Reviewer (검증자)

| 항목 | 내용 |
|------|------|
| **파일** | `app/agents/reviewer.py` |
| **역할** | Writer의 리포트 품질 최종 검증 |
| **LLM 사용** | O (GPT, temperature=0) |
| **입력** | `report`, `validated_web_results`, `validated_youtube_results` |
| **출력** | `review`, `revision_count` |

**시스템 프롬프트 핵심:**

5가지 기준으로 리포트를 검증합니다:

1. **URL 진위 확인**: 리포트의 모든 URL이 검증된 자료나 원본 대화에 실제 존재하는지 확인. 환각 URL 발견 시 즉시 REVISE.
2. **섹션 구조 확인**: 4개 섹션(주제 키워드, 대화 주요 내용, 핵심 정보, 톡비서 제안)이 적절한지. "공유 링크"나 "추천 영상" 별도 섹션이 있으면 REVISE. 핵심 정보 ↔ 대화 주요 내용 간 중복 시 REVISE.
3. **톡비서 제안 품질** (가장 중요): 학습 목표 명확성, 단계별 구체성, 참고 자료 URL 포함 여부, 영상 포함 여부, 실습 과제 유무.
4. **노이즈 필터링**: 비기술 잡담이 포함되지 않았는지.
5. **이모지 확인**: 이모지가 포함되어 있으면 REVISE.

**판정 결과:**
- `PASS` — 품질 통과, 리포트 최종 확정
- `REVISE: [수정 사항]` — Writer에게 구체적 피드백과 함께 재작성 요청

> REVISE 판정 시 Writer를 최대 **1회만 재호출**합니다 (무한 루프 방지).

---

## 워크플로우 흐름 요약

```
[1] Analyst       ─── LLM ──→ 대화 분석 + 주제 선별 + 학습 방향 설계
         │
[2] Supervisor    ─── JSON ──→ 검색 키워드 분배 (LLM 없이 비용 절약)
         │
    ┌────┴────┐
    │         │             ←── 병렬 실행 (비용 절약) ──→
[3] Web       [4] YT
    Searcher      Searcher  ─── API ──→ Tavily / YouTube 검색 (LLM 없음)
    │              │
[5] Web       [6] YT
    Validator     Validator ─── LLM ──→ 검색 결과 검증 + 필터링
    │              │
    └────┬────┘
         │
[7] Writer        ─── LLM ──→ 4개 섹션 리포트 작성
         │
[8] Reviewer      ─── LLM ──→ 품질 검증
         │
    PASS → 응답 반환
    REVISE → Writer 재호출 (최대 1회)
```

**LLM 호출 횟수:** 최소 5회 (Analyst + Web Validator + YT Validator + Writer + Reviewer)
재작성 시 최대 7회 (Writer + Reviewer 추가 1회씩)

---

## API 엔드포인트

### `POST /api/summarize`

카카오톡 대화를 멀티에이전트 파이프라인으로 분석합니다.

**요청 (SummarizeRequest)**
```json
{
  "messages": "[14:30] 홍길동: LangGraph 써봤는데...",
  "url_titles": {
    "https://example.com": "페이지 제목"
  },
  "openai_api_key": "sk-...",
  "tavily_api_key": "tvly-...",
  "youtube_api_key": "AIza..."
}
```

**응답 (SummarizeResponse)**
```json
{
  "summary": "## 주제 키워드\n\nLangGraph, RAG...",
  "input_tokens": 15000,
  "output_tokens": 3000
}
```

### `GET /health`

서버 상태 확인 (연결 테스트용)

**응답 (HealthResponse)**
```json
{
  "status": "ok",
  "version": "0.1.0"
}
```

---

## 기술 스택

| 구분 | 기술 |
|------|------|
| 런타임 | Python 3.13 |
| 웹 프레임워크 | FastAPI |
| 에이전트 오케스트레이션 | LangGraph (StateGraph) |
| LLM 연동 | LangChain (ChatOpenAI) |
| 웹 검색 | Tavily API |
| 영상 검색 | YouTube Data API v3 |
| 패키지 관리 | uv |
| 트레이싱 | LangSmith (선택) |

---

## 실행 방법

```bash
# 환경 변수 설정 (.env 파일)
OPENAI_API_KEY=sk-...
TAVILY_API_KEY=tvly-...
YOUTUBE_API_KEY=AIza...

# 서버 실행
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 3936
```

API 문서: `http://localhost:3936/docs` (Swagger UI)
