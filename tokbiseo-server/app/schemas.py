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


class HealthResponse(BaseModel):
    """
    GET /health 응답 바디

    서버 상태 확인용 간단한 응답
    """
    status: str = "ok"
    version: str = "0.1.0"
