"""
Supervisor 노드 — 분석 결과를 기반으로 검색 워커에게 업무 분배

Analyst의 분석 결과(주제별 키워드)를 읽고,
웹 검색 워커와 유튜브 검색 워커에게 각각 키워드를 분배합니다.
LLM 호출 없이 JSON 파싱만 수행합니다 (비용 절약).
"""

import json
import logging
from .state import AgentState

logger = logging.getLogger("톡비서.supervisor")


def supervisor_node(state: AgentState) -> dict:
    """
    Analyst의 분석 결과에서 검색 키워드를 추출하여 워커에게 분배합니다.

    입력: state.analysis (Analyst가 생성한 JSON 문자열)
    출력: state.web_search_tasks, state.youtube_search_tasks (키워드 리스트)
    """
    analysis_text = state.get("analysis", "")

    web_keywords: list[str] = []
    youtube_keywords: list[str] = []

    try:
        # Analyst의 JSON 응답에서 코드블록 마커 제거
        clean_text = analysis_text.strip()
        if clean_text.startswith("```"):
            # ```json ... ``` 형식에서 JSON 부분만 추출
            lines = clean_text.split("\n")
            # 첫 줄(```json)과 마지막 줄(```) 제거
            json_lines = []
            started = False
            for line in lines:
                if line.strip().startswith("```") and not started:
                    started = True
                    continue
                if line.strip() == "```" and started:
                    break
                if started:
                    json_lines.append(line)
            clean_text = "\n".join(json_lines)

        analysis = json.loads(clean_text)

        # 각 주제에서 키워드 수집
        for topic in analysis.get("topics", []):
            web_keywords.extend(topic.get("web_keywords", []))
            youtube_keywords.extend(topic.get("youtube_keywords", []))

    except (json.JSONDecodeError, KeyError, TypeError) as e:
        logger.warning(f"분석 결과 파싱 실패: {e}")
        # 폴백: 분석 텍스트 자체를 하나의 검색 키워드로 사용
        # (이 경우 검색 품질은 떨어지지만 파이프라인은 계속 진행)
        web_keywords = ["카카오톡 대화 주요 주제"]
        youtube_keywords = ["카카오톡 대화 관련 영상"]

    # 중복 제거
    web_keywords = list(dict.fromkeys(web_keywords))
    youtube_keywords = list(dict.fromkeys(youtube_keywords))

    logger.info(f"[완료] 웹 키워드 {len(web_keywords)}개: {web_keywords}")
    logger.info(f"[완료] 유튜브 키워드 {len(youtube_keywords)}개: {youtube_keywords}")

    return {
        "web_search_tasks": web_keywords,
        "youtube_search_tasks": youtube_keywords,
    }
