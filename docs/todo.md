# 톡비서 TODO

## 대기 중

### 화면 UI 업데이트 (디자인 리뉴얼)
- **파일**: `lib/screens/` 전체, `lib/app.dart`(테마)
- **현황**: Claude Design 입력 프롬프트 작성 완료 → `docs/design_renewal_prompt_v1.md`
- **할 일**: 프롬프트로 시안 확보 후 디자인 토큰(색·타이포·스페이싱) → 컴포넌트 → 화면 순으로 적용
- **정리된 문제점**: Card 남용/중첩, 5개 섹션 위계 평탄, BMJUA로 긴 본문 가독성 저하,
  7단계 파이프라인 대기 경험 부재

### 티스토리 발행 — 후속 개선 (검증은 완료)
- **발행 URL 반환값**: 현재 발행 후 `page.url`을 반환하는데 실제로는 글 주소가 아니라
  관리 페이지(`/manage/posts/`)가 잡힘 → 발행된 글 실주소를 얻으려면 별도 처리 필요
- **카테고리 선택**: 현재 미구현이라 기본 카테고리로 들어감.
  발행 레이어에 카테고리 드롭다운 있음 (dump_editor_selectors.py로 확인 가능)
- **Dockerfile 레이어 최적화**: 코드 한 줄만 바뀌어도 Playwright Chromium(~300MB)을
  매번 재다운로드함 → 브라우저 설치 레이어를 코드 COPY 앞으로 이동
- **Notion 스키마 캐시**: 서버가 DB 스키마를 프로세스 수명 동안 캐시
  (`notion_service.py`의 `_schema_cache`) → DB 속성 변경 시 서버 재시작 필요

## 완료

### v2.0.12~13 티스토리 실서버 검증 완료 (2026-08-04)
- **첫 실발행 성공**: Notion "초안" → 티스토리 공개 발행 → "발행완료" 갱신 전 과정 확인
- 검증 중 발견한 버그 수정:
  - `tistory_login.py`: 리다이렉트 도중 세션을 저장해 TSSESSION 쿠키가 빠지던 버그
    → 쿠키 폴링 방식으로 변경 (v2.0.12)
  - `tistory_service.py`: CodeMirror 2개 중 숨겨진 것을 잡던 문제 → `:visible` 필터 (v2.0.12)
  - `tistory_service.py`: "완료" 버튼 실제 id는 `#publish-layer-btn` ("-open" 없음) (v2.0.13)
- Notion DB에 `발행상태` select 속성(초안/발행완료) 추가
- 진단 도구 추가: `scripts/test_session_local.py`(세션 유효성 검증),
  `scripts/dump_editor_selectors.py`(에디터 셀렉터 확인)
- 운영 배포 절차 확인: 서버(192.168.50.205)에서 `git pull` 후 반드시
  `docker compose up -d --build` (git pull만으로는 미반영). `.env`·`data/`는 scp로 별도 업로드

### v2.0.11 티스토리 발행 기능 (2026-07-29)
- 서버: `GET /api/notion/pending`(발행상태="초안" 조회), `GET /api/notion/page/{id}`(블록→마크다운 역변환),
  `POST /api/publish/tistory`(Playwright 발행 → 발행상태 "발행완료" PATCH)
- 서버: `tistory_service.py` — 마크다운 모드 에디터 자동화, 발행 직렬화 Lock,
  세션 만료 감지, 실패 시 스크린샷 저장. 셀렉터는 SEL_* 상수로 모아둠
- 서버: `scripts/tistory_login.py` — 로컬 헤드풀 로그인으로 storage_state 생성
- docker-compose에 `./data:/app/data` 볼륨 추가 (세션 영속화), data/는 gitignore
- 앱: 발행 탭 신규 (4탭) — 대기 목록·마크다운 미리보기·한 건씩 발행·완료 URL 표시

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
