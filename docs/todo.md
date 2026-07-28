# 톡비서 TODO

## 대기 중

### 화면 UI 업데이트 (디자인 리뉴얼)
- **파일**: `lib/screens/` 전체, `lib/app.dart`(테마)
- **현황**: Claude Design 입력 프롬프트 작성 완료 → `docs/design_renewal_prompt_v1.md`
- **할 일**: 프롬프트로 시안 확보 후 디자인 토큰(색·타이포·스페이싱) → 컴포넌트 → 화면 순으로 적용
- **정리된 문제점**: Card 남용/중첩, 5개 섹션 위계 평탄, BMJUA로 긴 본문 가독성 저하,
  7단계 파이프라인 대기 경험 부재

### 티스토리 발행
- **파일**: `tokbiseo-server/`(발행 엔드포인트 신규), `lib/screens/`(발행 화면 신규)
- **현황**: 실행 환경만 준비됨 (Playwright + Chromium, `shm_size` 1gb)
- **제약**: 티스토리 Open API가 2024년 2월 종료 — 글 작성 API 없음.
  에디터 브라우저 자동화가 유일한 경로. 에디터는 마크다운 모드를 지원하므로
  노션 마크다운을 그대로 투입 가능 (HTML 변환 불필요)
- **할 일**:
  1. `GET /api/notion/pending` — 발행상태="초안" 페이지 조회
  2. 노션 블록 → 마크다운 역변환
  3. 앱 발행 화면 (목록·미리보기·발행)
  4. `POST /api/publish/tistory` — Playwright 발행 후 발행상태를 "발행완료"로 PATCH
- **주의**: 카카오 로그인 `storage_state`를 볼륨으로 영속화해야 함(재로그인 시 캡차),
  티스토리 1일 발행 수 제한이 있어 큐를 한 번에 밀면 막힘

## 완료

### v2.0.9 Notion 메타데이터 + 티스토리 발행 준비 (2026-07-28)
- Notion 페이지 제목을 "방이름 — YYYY-MM-DD"로 생성
  (기존에는 전부 "톡비서 리포트"라는 동일 제목으로 쌓였음)
- 앱이 `room_name`/`chat_date`/`message_count`를 요약 요청에 포함
- 페이지 생성 전 DB 스키마를 조회해 존재하고 타입까지 맞는 속성만 전송
  (없는 속성을 보내면 Notion이 400 → 저장 자체가 실패하므로)
  지원 속성: 채팅방·대화일자·생성일·주제 키워드·메시지수·입력/출력토큰·발행상태
- **버그 수정**: 블록 100개 초과분을 버리던 `blocks[:100]` 제거,
  `PATCH /blocks/{id}/children`로 100개씩 이어붙임 (긴 리포트 뒷부분 유실)
- Playwright 실행 환경 구성 (Dockerfile bookworm 고정, 브라우저 설치, shm_size)

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
