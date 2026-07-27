"""
AgentState — 멀티에이전트 파이프라인의 공유 상태

모든 노드(Filter → Analyst → Supervisor → Searcher → Validator → Writer)가
이 상태를 읽고 쓰며, LangGraph가 자동으로 상태를 관리합니다.
"""

import operator
from typing import Annotated, TypedDict


class AgentState(TypedDict, total=False):
    """
    멀티에이전트 워크플로우에서 노드 간 공유되는 상태입니다.

    각 노드는 자기 담당 필드만 업데이트하고,
    다른 노드가 쓴 필드를 입력으로 읽습니다.

    Annotated[int, operator.add] 필드:
      병렬 노드(web_searcher + yt_searcher)가 동시에 값을 보내도
      자동으로 합산되어 충돌 없이 처리됩니다.

    필드 설명:
    - messages: 원본 카카오톡 대화 텍스트 (파싱된 형태)
    - url_titles: 대화에서 발견된 URL → 페이지 제목 맵
    - filtered_messages: Filter가 잡담을 제거한 기술 대화 텍스트
    - analysis: Analyst가 생성한 구조화된 분석 결과 (JSON 문자열)
    - web_search_tasks: Supervisor가 분배한 웹 검색 키워드 리스트
    - youtube_search_tasks: Supervisor가 분배한 유튜브 검색 키워드 리스트
    - raw_web_results: Tavily 웹 검색 원본 결과 리스트
    - raw_youtube_results: YouTube 검색 원본 결과 리스트
    - validated_results: Validator가 검증/정리한 웹+유튜브 자료 통합 텍스트
    - report: Writer가 작성한 최종 리포트 마크다운
    - total_input_tokens: 전체 파이프라인에서 사용한 입력 토큰 합계
    - total_output_tokens: 전체 파이프라인에서 사용한 출력 토큰 합계
    """

    # ── 입력 (클라이언트가 제공) ──
    messages: str
    url_titles: dict[str, str]

    # ── Filter 출력 ──
    filtered_messages: str

    # ── Analyst 출력 ──
    analysis: str

    # ── Supervisor 출력 ──
    web_search_tasks: list[str]
    youtube_search_tasks: list[str]

    # ── Searcher 출력 ──
    raw_web_results: list[dict]
    raw_youtube_results: list[dict]

    # ── Validator 출력 (웹+유튜브 통합) ──
    validated_results: str

    # ── Writer 출력 ──
    report: str

    # ── 토큰 사용량 추적 ──
    # Annotated + operator.add: 병렬 노드가 동시에 값을 보내면 자동 합산
    total_input_tokens: Annotated[int, operator.add]
    total_output_tokens: Annotated[int, operator.add]


def extract_token_usage(response) -> tuple[int, int]:
    """
    LLM 응답에서 토큰 사용량을 추출합니다.

    ChatOpenAI의 응답 객체에서 input_tokens, output_tokens를 안전하게 꺼냅니다.
    usage_metadata가 없는 경우(스트리밍 등) 0을 반환합니다.

    Returns:
        (input_tokens, output_tokens) 튜플
    """
    if not response.usage_metadata:
        return 0, 0
    return (
        response.usage_metadata.get("input_tokens", 0),
        response.usage_metadata.get("output_tokens", 0),
    )
