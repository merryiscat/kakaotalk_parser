# 톡비서 TODO

## 대기 중

### Cloudflare Tunnel 전환 검토 — 라우터 포트포워딩(3936) 닫기 (2026-08-10, 외부 인계)
- **파일**: `docs/handoff-2026-08-10-tokbiseo-exposure.md` (project_odin 세션에서 인계)
- **요지**: 미니PC에 이미 돌고 있는 cloudflared 터널에 호스트네임 추가 → 앱 serverUrl을
  HTTPS 주소로 교체 → 라우터 포워딩 삭제. v2.0.18 API 키 인증이 있어 긴급 아님(심층 방어).
  선행 확인 사항·미니PC 실측 정보는 인계 문서 참조.

### 화면 UI 업데이트 (디자인 리뉴얼)
- **파일**: `lib/screens/` 전체, `lib/app.dart`(테마)
- **현황**: Claude Design 입력 프롬프트 작성 완료 → `docs/design_renewal_prompt_v1.md`
- **할 일**: 프롬프트로 시안 확보 후 디자인 토큰(색·타이포·스페이싱) → 컴포넌트 → 화면 순으로 적용
- **정리된 문제점**: Card 남용/중첩, 5개 섹션 위계 평탄, BMJUA로 긴 본문 가독성 저하,
  7단계 파이프라인 대기 경험 부재

### 티스토리 발행 — 후속 개선 (기능 검증은 완료)
- **배치 실패 알림**: 배치 실패가 서버 로그에만 남아 발견이 늦음
  (2026-08-05 세션 만료 실패를 다음날에야 인지) → 텔레그램 등 알림 수단 필요
- **발행 URL 반환값**: 현재 발행 후 `page.url`을 반환하는데 실제로는 글 주소가 아니라
  관리 페이지(`/manage/posts/`)가 잡힘 → 발행된 글 실주소를 얻으려면 별도 처리 필요
- **Dockerfile 레이어 최적화**: 코드 한 줄만 바뀌어도 Playwright Chromium(~300MB)을
  매번 재다운로드함 → 브라우저 설치 레이어를 코드 COPY 앞으로 이동
- **Notion 스키마 캐시**: 서버가 DB 스키마를 프로세스 수명 동안 캐시
  (`notion_service.py`의 `_schema_cache`) → DB 속성 변경 시 서버 재시작 필요

## 완료

### v2.0.18 서버 API 인증 (X-API-Key) — 인터넷 노출 대응 (2026-08-07)
- **배경**: 공유기 포트포워딩(3936)으로 서버가 인터넷에 노출 → 무인증 상태였음
- **서버** (`app/main.py`, 별도 세션에서 작업):
  - `/docs`·`/redoc`·`/openapi.json` 비활성화 (구조 노출 방지)
  - `/api/*` 전체(7개 라우트)에 `X-API-Key` 헤더 인증 — `secrets.compare_digest` 비교,
    서버에 `TALKBISEO_API_KEY` 미설정이면 fail-closed(503)
  - `/health`·`/auth/notion/callback`만 공개 유지
- **앱** (이 세션에서 작업):
  - 설정 화면에 "서버 접근 토큰" 입력란 추가 (`settings_provider`에 `serverApiKey` 저장)
  - `AgentApiService`·`PublishApiService`의 모든 `/api/*` 호출에 `X-API-Key` 헤더 전송
  - `/health` 연결 테스트는 토큰 불필요 (공개 엔드포인트)
- **주의**: 서버 배포 + 앱 재빌드 + 앱 설정에 토큰 입력, 3가지가 모두 돼야 요약/발행 동작.
  토큰이 다르면 401, 서버 .env에 토큰이 없으면 503
- ~~후속 TODO: CORS `allow_origins=["*"]` → 필요 출처만 허용으로 축소~~
  → v2.0.22(2026-08-10)에서 CORS 미들웨어 자체를 제거. 클라이언트가 Flutter 네이티브
  앱뿐이라 브라우저 CORS가 적용될 일이 없음 (웹 클라이언트 추가 시 명시 출처로 재도입)

### v2.0.17 티스토리 세션 3단 방어 — keep-alive + 자동 재로그인 (2026-08-06)
- **문제**: 8/6 00시에 새로 만든 세션이 반나절도 안 돼 만료 (로컬 원본도 동반 사망 확인
  → 업로드 문제 아님). 세션 수명이 배치 간격(24h)보다 짧아 v2.0.16 되쓰기 방식은
  연장 기회 자체를 못 잡음. 핵심 쿠키(TSSESSION, _kawlt)는 만료 시각 없는 세션 쿠키
  = 수명을 카카오/티스토리 서버가 결정 (실측 반나절~하루)
- **수정** (`tistory_service.py`, `main.py`):
  1. **keep-alive 루프**: `TISTORY_KEEPALIVE_HOURS`(기본 3시간)마다 관리 페이지 접속
     → 쿠키 되쓰기로 세션을 "사용 중" 상태 유지. 수동 실행: `POST /api/publish/tistory/keepalive`
  2. **카카오 SSO 재로그인**: 세션 사망 시 로그인 페이지에서 "카카오계정으로 로그인"
     자동 클릭 (카카오 쿠키 생존 시 비밀번호 없이 복구)
  3. **비밀번호 폼 로그인**: 카카오 쿠키까지 죽었으면 `.env`의 `KAKAO_EMAIL`/`KAKAO_PASSWORD`로
     폼 자동 입력. 캡차·2단계 인증 감지 시 스크린샷 남기고 실패 → 이때만 수동 로그인
- 발행 흐름에도 동일 적용: 에디터 진입 시 세션 만료면 자동 재로그인 후 재시도
- 로컬 검증: 죽은 세션으로 keep-alive 실행 → SSO 클릭 → 카카오 로그인 폼 도달
  → 계정정보 없음 감지까지 정상 동작 확인 (실제 로그인은 서버 .env 설정 후 검증)

### v2.0.16 티스토리 세션 자동 연장 (2026-08-06)
- **문제**: 8/5 오전 9시 첫 정기 배치가 세션 만료로 발행 실패 (8/4 로그인 후 하루 만에 만료).
  배치 루프·스케줄 자체는 정상 동작 확인 — 9시 정기 배치 가동 확인 항목은 이것으로 완료
- **원인**: 서버가 세션 파일(storage_state)을 읽기만 하고 갱신된 쿠키를 되쓰지 않아
  로그인 시점 쿠키 수명이 다하면 그대로 만료
- **수정**: `tistory_service.py` — 에디터 접속(=세션 유효 확인) 직후
  `context.storage_state(path=...)`로 쿠키를 파일에 되써서 세션 자동 연장.
  매일 배치가 돌면 만료 시점이 계속 뒤로 밀림 (카카오 절대 만료 시에만 재로그인)
- 세션 재발급·업로드 완료 (2026-08-06 00시, `tistory_login.py` → 검증 → scp)
- 추가 확인: 요약 요청의 방이름·날짜가 빈 값으로 들어옴 → 폰 APK가 v2.0.9 이전 구버전이라
  메타데이터 미전송이 원인. v2.0.16 APK로 업데이트하면 해결.
  Notion DB에 `주제 키워드`(다중 선택)·`입력토큰`/`출력토큰`(숫자) 속성은 없어서 건너뛰는 중
  — 원하면 Notion에서 속성 추가 후 컨테이너 재시작(스키마 캐시)

### v2.0.15 티스토리 카테고리 선택 + 일일 자동 발행 배치 (2026-08-04~05)
- 카테고리 자동 선택: `.env`의 `TISTORY_CATEGORY`에 지정한 카테고리로 발행
  (현재 "인공지능_연구방 (NLP, LLM, Agent)", 못 찾으면 기본 카테고리로 발행 계속)
- 일일 배치: 매일 오전 9시(KST, `TISTORY_BATCH_HOUR`로 변경 가능)에
  발행상태="초안" 중 **가장 최신 1건**을 자동 발행 → "발행완료" 갱신
  (티스토리 1일 발행 제한 때문에 하루 1건씩)
- `POST /api/publish/tistory/batch`: 배치 수동 실행 (테스트용)
- 발행 대기 목록을 최신 생성 순으로 정렬
- 상태값 흐름은 기존 그대로: 요약 저장 시 "초안"(=업로드 미완료) 기본
  → 발행 후 "발행완료"
- **서버 검증 완료 (08-05)**: 미발행 8/3 리포트를 초안으로 만들어 배치 실행
  → 본문·태그·카테고리·상태 갱신 전부 정상 (visionitse.tistory.com/40)
- 서버 `.env` 갱신 절차 주의: 한글 값(TISTORY_CATEGORY)이 있어 ssh echo 추가 금지,
  로컬 `.env`를 scp로 통째 업로드할 것

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
