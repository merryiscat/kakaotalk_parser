"""
Filter 노드 — 잡담 필터링 (gpt-4.1-mini)

파이프라인의 첫 번째 노드입니다.
오픈채팅방 대화에서 잡담, 인사, 이모티콘, 밈 등 비기술 메시지를 제거하고
기술적 내용이 담긴 메시지만 남깁니다.

비용 최적화:
  - 잡담 필터링은 단순 분류 작업이므로 gpt-4.1-mini 사용
  - 필터링 후 줄어든 텍스트가 Analyst(기본 gpt-5.4-mini)에게 전달되어
    고비용 모델의 입력 토큰을 절감합니다.
"""

import os
import logging
from langchain_openai import ChatOpenAI
from .state import AgentState, extract_token_usage

logger = logging.getLogger("톡비서.filter")

# 잡담 필터링 시스템 프롬프트
# gpt-4.1-mini가 처리하기 좋게 명확하고 간결하게 작성
_SYSTEM_PROMPT = """당신은 IT 오픈채팅방 대화에서 잡담을 걸러내는 필터입니다.

입력으로 "[HH:MM] 발신자: 내용" 형식의 대화가 주어집니다.
기술적 가치가 있는 메시지만 남기고, 나머지는 제거하세요.

## 제거 대상 (비기술 메시지)
- 인사, 안부 ("안녕하세요", "좋은 아침", "수고하세요", "ㅎㅇ")
- 감탄사, 리액션 ("ㅋㅋ", "ㅎㅎ", "ㄷㄷ", "오오", "와", "굿", "ㄱㅇㄷ")
- 잡담, 일상 대화 (날씨, 식사, 퇴근, 주말 계획 등)
- 밈, 유머, 드립
- 단순 동의/호응 ("맞아요", "그렇죠", "인정", "+1")
- 맥락 없는 짧은 메시지 (2단어 이하의 의미 없는 발화)
- 기술과 무관한 뉴스, 가십, 정치, 연예 이야기

## 보존 대상 (기술 메시지)
- 기술 관련 질문, 답변, 경험 공유
- 도구, 라이브러리, 프레임워크 언급
- 코드, 명령어, 설정값 공유
- URL 공유 및 그에 대한 논의
- 기술적 의견, 비교, 추천
- 에러, 트러블슈팅 관련 대화

## 출력 규칙
- 보존 대상 메시지를 원본 형식 그대로 출력 (수정하지 말 것)
- 메시지 순서 유지
- 추가 설명이나 주석 없이 필터링된 메시지만 출력
- 보존할 메시지가 없으면 "기술 관련 대화 없음"이라고만 출력"""


def filter_node(state: AgentState) -> dict:
    """
    대화에서 잡담을 제거하고 기술 관련 메시지만 남깁니다.

    gpt-4.1-mini를 사용하여 비용을 최소화합니다.
    필터링 결과는 filtered_messages에 저장되어 Analyst가 사용합니다.

    입력: state.messages (원본 대화 텍스트)
    출력: state.filtered_messages (잡담 제거된 기술 대화 텍스트)
    """
    logger.info("[시작] 잡담 필터링 중...")

    # 잡담 필터링은 단순 분류 작업 → gpt-4.1-mini로 충분
    filter_model = os.getenv("OPENAI_FILTER_MODEL", "gpt-4.1-mini")
    llm = ChatOpenAI(model=filter_model, temperature=0)

    response = llm.invoke([
        {"role": "system", "content": _SYSTEM_PROMPT},
        {"role": "user", "content": state["messages"]},
    ])

    # 토큰 사용량 추적
    input_tokens, output_tokens = extract_token_usage(response)

    filtered = response.content.strip()
    original_lines = len(state["messages"].strip().split("\n"))
    filtered_lines = len(filtered.strip().split("\n"))
    logger.info(
        f"[완료] 필터링: {original_lines}줄 → {filtered_lines}줄 "
        f"({100 - filtered_lines / max(original_lines, 1) * 100:.0f}% 제거, "
        f"토큰: 입력 {input_tokens}, 출력 {output_tokens})"
    )

    return {
        "filtered_messages": filtered,
        "total_input_tokens": input_tokens,
        "total_output_tokens": output_tokens,
    }
