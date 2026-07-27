"""
YouTube Data API v3 검색 래퍼

키워드로 YouTube 영상을 검색하여
제목, URL, 채널, 설명 등 메타데이터를 수집합니다.
"""

import os
import logging
from googleapiclient.discovery import build

logger = logging.getLogger("톡비서.youtube")


def search_youtube(keywords: list[str], max_results_per_keyword: int = 3) -> list[dict]:
    """
    키워드 리스트로 YouTube 영상을 검색합니다.

    각 키워드마다 YouTube Data API를 호출하여 관련 영상을 수집합니다.
    결과는 중복 영상을 제거한 뒤 반환됩니다.

    Args:
        keywords: 검색할 키워드 리스트 (예: ["LangGraph 튜토리얼 한국어", "RAG 구축"])
        max_results_per_keyword: 키워드당 최대 검색 결과 수 (기본 3개)

    Returns:
        검색 결과 리스트. 각 항목은:
        - title: 영상 제목
        - url: 영상 URL (https://www.youtube.com/watch?v=...)
        - channel: 채널 이름
        - description: 영상 설명 (최대 200자)
        - keyword: 이 결과를 찾은 검색 키워드
    """
    api_key = os.getenv("YOUTUBE_API_KEY")
    if not api_key:
        logger.error("YOUTUBE_API_KEY 환경 변수가 설정되지 않았습니다!")
        raise ValueError("YOUTUBE_API_KEY 환경 변수가 설정되지 않았습니다.")

    # YouTube Data API v3 클라이언트 생성
    youtube = build("youtube", "v3", developerKey=api_key)
    results = []
    # 중복 영상 방지용 집합 (video ID 기준)
    seen_ids: set[str] = set()

    for keyword in keywords:
        try:
            logger.info(f"  검색: '{keyword}'")
            response = youtube.search().list(
                q=keyword,
                part="snippet",
                type="video",
                maxResults=max_results_per_keyword,
                # 관련성 순으로 정렬
                order="relevance",
                # 한국어 결과 우선
                relevanceLanguage="ko",
            ).execute()

            for item in response.get("items", []):
                video_id = item["id"]["videoId"]
                # 이미 수집한 영상이면 건너뜀
                if video_id in seen_ids:
                    continue
                seen_ids.add(video_id)

                snippet = item["snippet"]
                # 영상 설명은 200자로 제한 (너무 길면 토큰 낭비)
                description = snippet.get("description", "")
                if len(description) > 200:
                    description = description[:200] + "..."

                url = f"https://www.youtube.com/watch?v={video_id}"
                logger.info(f"    → {snippet.get('title', '?')} ({url})")
                results.append({
                    "title": snippet.get("title", ""),
                    "url": url,
                    "channel": snippet.get("channelTitle", ""),
                    "description": description,
                    "keyword": keyword,
                })
        except Exception as e:
            logger.error(f"  '{keyword}' 검색 실패: {e}", exc_info=True)

    return results
