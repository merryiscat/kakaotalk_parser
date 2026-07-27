"""
YouTube Searcher 노드 — YouTube Data API로 영상 검색 수행

Supervisor가 분배한 키워드 리스트를 받아
각 키워드로 YouTube 영상 검색을 실행합니다.
LLM 호출 없이 API 호출만 수행합니다 (비용 절약).
"""

import logging
from .state import AgentState
from ..tools.youtube_tool import search_youtube

logger = logging.getLogger("톡비서.yt_searcher")


def yt_searcher_node(state: AgentState) -> dict:
    """
    유튜브 검색 키워드로 YouTube Data API를 호출하여 관련 영상을 수집합니다.

    입력: state.youtube_search_tasks (검색 키워드 리스트)
    출력: state.raw_youtube_results (검색 결과 리스트)
    """
    keywords = state.get("youtube_search_tasks", [])

    if not keywords:
        logger.warning("검색 키워드 없음 — 건너뜀")
        return {"raw_youtube_results": []}

    logger.info(f"[시작] 유튜브 검색 {len(keywords)}개 키워드...")
    try:
        results = search_youtube(keywords, max_results_per_keyword=3)
        logger.info(f"[완료] 유튜브 검색 결과 {len(results)}건")
        for r in results:
            logger.info(f"  - {r.get('title', '?')} ({r.get('url', '?')})")
    except Exception as e:
        logger.error(f"[실패] 유튜브 검색 에러: {e}", exc_info=True)
        results = []

    return {"raw_youtube_results": results}
