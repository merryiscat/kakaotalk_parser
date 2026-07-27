"""
Tavily 웹 검색 래퍼

Tavily API를 사용하여 키워드로 웹 검색을 수행하고,
관련 문서/블로그/공식사이트를 수집합니다.
"""

import os
import logging
from tavily import TavilyClient

logger = logging.getLogger("톡비서.tavily")


def search_web(keywords: list[str], max_results_per_keyword: int = 3) -> list[dict]:
    """
    키워드 리스트로 웹 검색을 수행합니다.

    각 키워드마다 Tavily API를 호출하여 관련 웹페이지를 수집합니다.
    결과는 중복 URL을 제거한 뒤 반환됩니다.

    Args:
        keywords: 검색할 키워드 리스트 (예: ["LangGraph 튜토리얼", "RAG 구축 방법"])
        max_results_per_keyword: 키워드당 최대 검색 결과 수 (기본 3개)

    Returns:
        검색 결과 리스트. 각 항목은:
        - title: 페이지 제목
        - url: 페이지 URL
        - content: 페이지 요약 (Tavily가 추출한 핵심 내용)
        - keyword: 이 결과를 찾은 검색 키워드
    """
    api_key = os.getenv("TAVILY_API_KEY")
    if not api_key:
        raise ValueError("TAVILY_API_KEY 환경 변수가 설정되지 않았습니다.")

    client = TavilyClient(api_key=api_key)
    results = []
    # 중복 URL 방지용 집합
    seen_urls: set[str] = set()

    for keyword in keywords:
        try:
            logger.info(f"  검색: '{keyword}'")
            response = client.search(
                query=keyword,
                max_results=max_results_per_keyword,
                search_depth="basic",
            )

            found = 0
            for item in response.get("results", []):
                url = item.get("url", "")
                if url in seen_urls:
                    continue
                seen_urls.add(url)
                found += 1

                results.append({
                    "title": item.get("title", ""),
                    "url": url,
                    "content": item.get("content", ""),
                    "keyword": keyword,
                })
            logger.info(f"    → {found}건 수집")
        except Exception as e:
            logger.error(f"  '{keyword}' 검색 실패: {e}", exc_info=True)

    return results
