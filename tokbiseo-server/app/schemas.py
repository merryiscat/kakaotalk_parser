"""
Pydantic 스키마 — FastAPI 요청/응답 모델

API 엔드포인트의 입출력 데이터 형식을 정의합니다.
Pydantic이 자동으로 타입 검증과 JSON 직렬화를 처리합니다.
"""

from pydantic import BaseModel, Field


class SummarizeRequest(BaseModel):
    """
    POST /api/summarize 요청 바디

    Flutter 앱에서 보내는 데이터:
    - messages: 파싱된 카카오톡 대화 텍스트 ("[14:30] 발신자: 내용" 형식)
    - url_titles: 대화에서 발견된 URL → 페이지 제목 맵 (선택)
    - API 키 3종: 앱 설정에서 관리, 서버로 전송
    """
    messages: str = Field(
        ...,
        description="파싱된 카카오톡 대화 텍스트",
        min_length=1,
    )
    url_titles: dict[str, str] = Field(
        default_factory=dict,
        description="URL → 페이지 제목 맵 (선택)",
    )
    # ── 리포트 메타데이터 ──
    # Notion 페이지 제목과 속성(채팅방/대화일자/메시지수)을 채우는 데 사용합니다.
    # 비어있으면 Notion에는 제목만 기본값으로 저장됩니다.
    room_name: str = Field(
        default="",
        description="채팅방 이름 (Notion 제목·속성에 사용)",
    )
    chat_date: str = Field(
        default="",
        description="요약 대상 대화 날짜 (YYYY-MM-DD)",
    )
    message_count: int = Field(
        default=0,
        description="해당 날짜의 원본 메시지 수",
    )
    # API 키 — 앱에서 전송, 서버의 .env 값보다 우선 적용
    openai_api_key: str = Field(
        default="",
        description="OpenAI API 키 (앱에서 전송)",
    )
    tavily_api_key: str = Field(
        default="",
        description="Tavily API 키 (앱에서 전송)",
    )
    youtube_api_key: str = Field(
        default="",
        description="YouTube API 키 (앱에서 전송)",
    )


class SummarizeResponse(BaseModel):
    """
    POST /api/summarize 응답 바디

    멀티에이전트 파이프라인이 생성한 결과:
    - summary: 5개 섹션으로 구성된 마크다운 리포트
    - input_tokens: 전체 파이프라인에서 사용한 입력 토큰 합계
    - output_tokens: 전체 파이프라인에서 사용한 출력 토큰 합계
    """
    summary: str = Field(
        ...,
        description="최종 마크다운 리포트",
    )
    input_tokens: int = Field(
        default=0,
        description="총 입력 토큰 수",
    )
    output_tokens: int = Field(
        default=0,
        description="총 출력 토큰 수",
    )


# ── 티스토리 발행 관련 스키마 ──


class PendingPage(BaseModel):
    """발행 대기(발행상태="초안") 상태인 Notion 페이지 요약 정보"""
    page_id: str = Field(..., description="Notion 페이지 ID")
    title: str = Field(default="", description="페이지 제목 (방이름 — 날짜)")
    chat_date: str = Field(default="", description="대화 날짜 (YYYY-MM-DD)")
    room_name: str = Field(default="", description="채팅방 이름")
    keywords: list[str] = Field(default_factory=list, description="주제 키워드")
    notion_url: str = Field(default="", description="Notion 페이지 URL")


class PendingPagesResponse(BaseModel):
    """GET /api/notion/pending 응답 — 발행 대기 목록"""
    pages: list[PendingPage] = Field(default_factory=list)


class PageContentResponse(BaseModel):
    """GET /api/notion/page/{page_id} 응답 — 미리보기용 본문"""
    markdown: str = Field(..., description="Notion 블록을 역변환한 마크다운")


class PublishRequest(BaseModel):
    """POST /api/publish/tistory 요청 바디"""
    page_id: str = Field(..., description="발행할 Notion 페이지 ID")
    tags: list[str] = Field(
        default_factory=list,
        description="티스토리 태그 (비우면 Notion 주제 키워드 사용)",
    )


class PublishResponse(BaseModel):
    """POST /api/publish/tistory 응답 바디"""
    url: str = Field(..., description="발행된 티스토리 글 URL")


class HealthResponse(BaseModel):
    """
    GET /health 응답 바디

    서버 상태 확인용 간단한 응답
    """
    status: str = "ok"
    version: str = "0.1.0"
