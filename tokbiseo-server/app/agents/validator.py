"""
Validator 노드 — 웹 + 유튜브 검색 결과를 한꺼번에 검증 (gpt-4.1-mini)

두 Searcher의 결과를 하나의 LLM 호출로 검증합니다.
기존 Web Validator + YT Validator를 합병하여 LLM 호출 2회 → 1회로 절감.
단순 분류/필터링 작업이므로 gpt-4.1-mini로 충분합니다.
"""

import os
import logging
from langchain_openai import ChatOpenAI
from .state import AgentState, extract_token_usage

logger = logging.getLogger("톡비서.validator")

# 웹 + 유튜브 검색 결과 통합 검증 프롬프트
_SYSTEM_PROMPT = """당신은 검색 결과를 검증하는 큐레이터입니다.

웹 검색 결과와 유튜브 검색 결과가 함께 주어집니다.
아래 규칙에 따라 각각 필터링하고 정리하세요.

## 웹 자료 검증 규칙

1. **관련성 검증**: 대화의 기술 주제와 직접 관련 있는 결과만 남기기
   - 스팸, 광고성 페이지, 대화 주제와 무관한 결과 제거
2. **품질 평가**: 공식 문서, 잘 알려진 블로그, 기술 커뮤니티 우선
   - 오래된 정보(2년 이상)는 낮은 우선순위
3. **출력 형식**:
```
- [제목](URL) — 한 줄 설명 [주제태그]
```

## 유튜브 영상 검증 규칙

1. **관련성 검증**: 주제와 직접 관련 있는 교육 영상만 남기기
   - 광고/프로모션 위주 영상, 너무 오래된 영상 제거
2. **난이도 태깅**: [기초] / [중급] / [심화]
3. **출력 형식** (난이도순 정렬):
```
- [기초] [영상 제목](URL) — 채널명
  추천 이유 한 줄
```

## 최종 출력 형식

반드시 아래 두 섹션으로 나누어 출력하세요:

```
### 검증된 웹 자료
- [제목](URL) — 설명 [태그]
...

### 검증된 유튜브 자료
- [난이도] [제목](URL) — 채널명
  추천 이유
...
```

해당 자료가 없으면 "없음"이라고 적으세요."""


def validator_node(state: AgentState) -> dict:
    """
    웹 + 유튜브 검색 결과를 한 번의 LLM 호출로 검증합니다.

    입력:
    - state.raw_web_results (웹 검색 원본)
    - state.raw_youtube_results (유튜브 검색 원본)
    - state.analysis (Analyst 분석 컨텍스트)
    출력: state.validated_results (검증된 웹+유튜브 자료 통합 마크다운)
    """
    raw_web = state.get("raw_web_results", [])
    raw_yt = state.get("raw_youtube_results", [])

    if not raw_web and not raw_yt:
        logger.warning("검색 결과 없음 — 건너뜀")
        return {"validated_results": "검증된 자료 없음"}

    logger.info(f"[시작] 검색 결과 검증 중... (웹 {len(raw_web)}건, 유튜브 {len(raw_yt)}건)")

    # 단순 분류/필터링 작업 → gpt-4.1-mini로 충분
    validator_model = os.getenv("OPENAI_VALIDATOR_MODEL", "gpt-4.1-mini")
    llm = ChatOpenAI(model=validator_model, temperature=0)

    # 웹 검색 결과를 텍스트로 변환
    web_text = ""
    if raw_web:
        for i, r in enumerate(raw_web, 1):
            web_text += f"\n{i}. [{r.get('title', '제목 없음')}]({r.get('url', '')})\n"
            web_text += f"   키워드: {r.get('keyword', '')}\n"
            web_text += f"   내용: {r.get('content', '')[:300]}\n"
    else:
        web_text = "없음"

    # 유튜브 검색 결과를 텍스트로 변환
    yt_text = ""
    if raw_yt:
        for i, r in enumerate(raw_yt, 1):
            yt_text += f"\n{i}. [{r.get('title', '제목 없음')}]({r.get('url', '')})\n"
            yt_text += f"   채널: {r.get('channel', '')}\n"
            yt_text += f"   키워드: {r.get('keyword', '')}\n"
            yt_text += f"   설명: {r.get('description', '')}\n"
    else:
        yt_text = "없음"

    # 분석 컨텍스트 포함
    analysis = state.get("analysis", "")

    user_prompt = f"""[대화 분석 결과]
{analysis}

[웹 검색 결과 ({len(raw_web)}건)]
{web_text}

[유튜브 검색 결과 ({len(raw_yt)}건)]
{yt_text}

위 검색 결과를 분석 결과와 대조하여 관련성 높은 자료만 골라 정리해주세요."""

    response = llm.invoke([
        {"role": "system", "content": _SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ])

    # 토큰 사용량 추적
    input_tokens, output_tokens = extract_token_usage(response)

    logger.info(f"[완료] 검증 결과: {len(response.content)}자 (토큰: 입력 {input_tokens}, 출력 {output_tokens})")

    return {
        "validated_results": response.content,
        "total_input_tokens": input_tokens,
        "total_output_tokens": output_tokens,
    }
