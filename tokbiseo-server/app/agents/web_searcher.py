"""
Web Searcher 노드 — Tavily API로 웹 검색 수행

Supervisor가 분배한 키워드 리스트를 받아
각 키워드로 Tavily 웹 검색을 실행합니다.

이 노드는 LLM을 호출하지 않습니다 (비용 0).
Tavily API가 자체적으로 검색 결과 요약을 제공하므로
별도의 LLM 처리 없이 raw 결과만 수집합니다.
검색 결과의 필터링/검증은 다음 단계인 Validator 노드가 담당합니다.
"""

import logging
from .state import AgentState
from ..tools.tavily_tool import search_web

logger = logging.getLogger("톡비서.web_searcher")


def web_searcher_node(state: AgentState) -> dict:
    """
    웹 검색 키워드로 Tavily API를 호출하여 관련 웹페이지를 수집합니다.

    입력: state.web_search_tasks (검색 키워드 리스트)
    출력: state.raw_web_results (검색 결과 리스트)
    """
    keywords = state.get("web_search_tasks", [])

    # 키워드가 비어있으면 빈 리스트 반환 (Validator가 "없음" 처리)
    if not keywords:
        logger.warning("검색 키워드 없음 — 건너뜀")
        return {"raw_web_results": []}

    logger.info(f"[시작] 웹 검색 {len(keywords)}개 키워드...")

    # 키워드당 최대 3개 결과 수집 (비용 제어 + 충분한 자료 확보 균형)
    results = search_web(keywords, max_results_per_keyword=3)

    logger.info(f"[완료] 웹 검색 결과 {len(results)}건")

    return {"raw_web_results": results}
