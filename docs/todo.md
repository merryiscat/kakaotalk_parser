# 톡비서 TODO

## 대기 중

### 화면 UI 업데이트
- **파일**: `lib/screens/` 전체
- **현황**: 기본 Material 3 디자인으로 동작 중
- **할 일**: 구체적 개선 사항 미정 — 실사용 후 결정

### Notion 연동 개선
- **파일**: `tokbiseo-server/app/services/notion_service.py`, `app/main.py`의 `_save_to_notion()`
- **현황**: OAuth 콜백 + 리포트 저장 기본 구현 완료
- **할 일**: 구체적 개선 사항 미정 — 실사용 후 결정

## 완료

### v2.0.5 리팩토링 (2026-06-02)
- dead code 제거 (prompt_builder.dart)
- 중복 코드 헬퍼 추출 (서버: extract_token_usage, _apply_api_keys, _save_to_notion / 클라이언트: shared_widgets.dart)
- 학습용 주석 보강 (settings_screen, home_screen, web_searcher, __init__.py)

### v2.0.4 비용 최적화 2차 (2026-06-02)
- Validator 합병 (web_validator + yt_validator → validator.py, gpt-4.1-mini)
- Reviewer 제거 (REVISE 로직 포함)
- Writer가 filtered_messages 사용하도록 변경
- 9노드 → 7노드

### v2.0.3 비용 최적화 1차 (2026-06-02)
- Filter 노드 추가 (gpt-4.1-mini 잡담 필터링)
- Analyst를 잡담 필터링에서 분리하여 주제 추출에 집중
- 8노드 → 9노드
