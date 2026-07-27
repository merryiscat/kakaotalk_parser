"""
Analyst 노드 — 기술 주제 추출 + 학습 방향 설계

Filter 노드가 잡담을 제거한 뒤 실행되는 두 번째 노드입니다.
필터링된 기술 대화에서 주제를 분류하고, 확장 학습 경로를 설계합니다.
"""

import os
import logging
from langchain_openai import ChatOpenAI
from .state import AgentState, extract_token_usage

logger = logging.getLogger("톡비서.analyst")

# Analyst 시스템 프롬프트
# Filter가 잡담을 이미 제거했으므로, 노이즈 필터링 지시를 줄이고
# 주제 추출 + 학습 경로 설계에 집중
_SYSTEM_PROMPT = """당신은 IT 오픈채팅방의 기술 대화를 분석하는 전문가입니다.

입력으로 잡담이 제거된 기술 관련 대화만 주어집니다.
이 대화에서 학습 가치가 있는 주제를 추출하고, 확장 학습 경로를 설계하세요.

## 1단계: URL 선별 (Top 5)

대화에 등장한 URL 중 **기술적 학습 가치가 높은 것만 최대 5개** 선별하세요.

선별 기준:
- 포함: 공식 문서, 기술 블로그, 튜토리얼, GitHub 레포, API 문서, 기술 발표 영상
- 포함: 실무 도구/프레임워크/라이브러리 소개
- 제외: 뉴스 기사, 일반 뉴스, 쇼핑, 채용 공고
- 제외: 기술과 무관한 흥미 위주 콘텐츠
- 제외: 별도 설명 없이 그냥 던져진 URL (맥락 없는 링크 스팸)

각 URL에 대해 "왜 이 URL이 학습 가치가 있는지" 한 줄 근거를 작성하세요.

## 2단계: 기술 주제 분류 (최대 5건)

대화에서 **실무에 적용 가능한 기술 주제**만 추출하세요.

선별 기준:
- 포함: 프레임워크, 라이브러리, 아키텍처, DevOps, AI/ML 실무, 코딩 기법, 인프라
- 포함: 대화 참여자가 실제로 해보고 경험을 공유한 내용
- 제외: "~라카더라" 식의 소문, 근거 없는 추측
- 제외: 기술 뉴스 가십 (기업 인수, 주가, 인물 이야기)

각 주제에 대해:
- 대화에서 **실제로 언급된 구체적 기술/도구/명령어** 정리
- 대화 내용만으로는 부족한 부분 → "추가로 찾아봐야 할 것" 명시

## 3단계: 학습 방향 설계

각 기술 주제에 대해 **대화 내용을 넘어선 확장 학습 경로**를 설계하세요.

설계 원칙:
- 대화에서 "~한다더라"로 끝난 것 → "실제로 해보려면 이런 순서로" 단계 제시
- 초보자가 따라할 수 있는 구체적 순서 (1→2→3 단계)
- 각 단계에 "뭘 검색하면 되는지" 검색 키워드 포함
- 웹 검색 키워드: 공식 문서, 튜토리얼 블로그를 찾기 위한 구체적 키워드
- 유튜브 검색 키워드: 따라하기 영상을 찾기 위한 키워드 (한국어 우선, 영어 보조)

## 출력 형식

반드시 아래 JSON 형식으로만 응답하세요 (다른 텍스트 없이):
```json
{
  "filtered_urls": [
    {
      "url": "https://...",
      "title": "페이지 제목",
      "reason": "이 URL의 학습 가치 근거 한 줄"
    }
  ],
  "topics": [
    {
      "title": "주제 제목 (예: LangGraph 멀티에이전트 파이프라인)",
      "summary": "대화에서 논의된 핵심 내용 2~3줄",
      "mentioned_tech": ["실제 언급된 도구/기술/명령어 리스트"],
      "gaps": "대화에서 빠졌거나 더 알아봐야 할 부분",
      "learning_path": [
        "1단계: ~를 먼저 이해한다 (검색: '키워드')",
        "2단계: ~를 설치하고 실행해본다 (검색: '키워드')",
        "3단계: ~를 직접 구현해본다 (검색: '키워드')"
      ],
      "web_keywords": ["웹 검색 키워드1", "키워드2", "키워드3"],
      "youtube_keywords": ["유튜브 검색 키워드1", "키워드2"]
    }
  ],
  "noise_summary": "제외한 비기술 주제 간단 요약 (1~2줄)",
  "report_guide": {
    "shared_links": "공유 링크 섹션: 선별된 URL + 검색으로 찾은 추가 자료",
    "key_info": "핵심 정보 섹션: 대화에서 나온 구체적 사실/수치/팁/명령어",
    "main_content": "대화 주요 내용 섹션: 기술 주제별 논의 맥락",
    "study_guide": "톡비서 제안 섹션: 주제별 학습 경로 + 추천 자료 + 실습 방향",
    "recommended_videos": "추천 영상 섹션: 학습 경로에 맞는 유튜브 영상"
  }
}
```"""


def analyst_node(state: AgentState) -> dict:
    """
    필터링된 대화를 분석하여 기술 주제를 선별하고 학습 방향을 설계합니다.

    핵심 역할:
    - 기술적 학습 가치가 있는 URL만 Top 5 선별
    - 실무 기술 주제 추출 + 확장 학습 경로 설계
    - 검색 키워드 생성 (웹 + 유튜브)

    입력: state.filtered_messages (잡담 제거된 대화), state.url_titles (URL→제목 맵)
    출력: state.analysis (구조화된 분석 결과 JSON 문자열)
    """
    logger.info("[시작] 대화 분석 중...")
    model = os.getenv("OPENAI_MODEL", "gpt-5.4-mini")
    llm = ChatOpenAI(model=model, temperature=0)

    # URL 제목 정보를 프롬프트에 포함
    url_titles = state.get("url_titles", {})
    url_info = ""
    if url_titles:
        url_info = "\n\n[대화에 등장한 URL과 페이지 제목]\n"
        for url, title in url_titles.items():
            url_info += f"- {url} → \"{title}\"\n"
        url_info += f"\n총 {len(url_titles)}개 URL 중 기술 학습 가치가 높은 것만 최대 5개를 선별하세요."

    # Filter가 잡담을 제거한 텍스트를 사용 (입력 토큰 절감)
    filtered = state.get("filtered_messages", state["messages"])

    # LLM 호출: 대화 분석
    user_prompt = f"아래 카카오톡 IT 오픈채팅방 대화를 분석해주세요:{url_info}\n\n{filtered}"

    response = llm.invoke([
        {"role": "system", "content": _SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ])

    # 토큰 사용량 추적
    input_tokens, output_tokens = extract_token_usage(response)

    logger.info(f"[완료] 분석 결과: {len(response.content)}자 (토큰: 입력 {input_tokens}, 출력 {output_tokens})")

    return {
        "analysis": response.content,
        "total_input_tokens": input_tokens,
        "total_output_tokens": output_tokens,
    }
