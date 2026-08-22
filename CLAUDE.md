# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요
톡비서(TokBiseo) — 카카오톡 내보내기 파일(.txt)을 파싱하여 멀티에이전트 AI로 날짜별 요약 리포트를 생성하는 Flutter 앱.

## 개발 명령어
```bash
flutter pub get                  # 의존성 설치
flutter run -d windows           # Windows 데스크톱 실행
flutter run                      # 기본 디바이스 실행
flutter build apk --release      # 릴리스 APK 빌드
dart run flutter_launcher_icons  # 앱 아이콘 생성
```

### 멀티에이전트 서버 (tokbiseo-server/ — 본 저장소에서 직접 관리)
```bash
cd tokbiseo-server
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 3936
```

## 아키텍처

### 데이터 흐름
파일 선택 → `KakaotalkParser.parse()` → 날짜별 분류 → `AgentApiService.summarizeStream()` (SSE) → 노드별 진행률 콜백 → `DailyDigest` 생성 → `StorageService` 영구 저장

### 계층 구조
- **Models** (`chat_message`, `chat_room`, `daily_digest`) — 데이터 클래스
- **Services** — 외부 통신 및 저장
  - `agent_api_service.dart` — SSE 수동 파싱으로 서버 스트리밍 수신 (node_complete/result/error 이벤트)
  - `publish_api_service.dart` — Notion 발행 큐 조회 + 티스토리 발행 요청
  - `storage_service.dart` — `tokbiseo_data.json` 파일로 영구 저장 (path_provider)
- **Providers** (Riverpod Notifier) — 상태 관리
  - `digest_provider.dart` — 핵심 비즈니스 로직: 파싱 → 중복 감지 → 요약 요청 → 저장
  - `publish_provider.dart` — 발행 대기 목록·발행 진행 상태 (한 번에 한 건씩)
  - `settings_provider.dart` — API 키, 서버 URL 등 SharedPreferences 관리
- **Screens** — `MainShellScreen`이 IndexedStack + BottomNavigationBar로 4탭(달력/홈/발행/설정) 관리
- **Utils** — `report_parser.dart`가 마크다운 리포트를 `##` 섹션별로 파싱

### 서버 (LangGraph 파이프라인, 7노드)
Filter(gpt-4.1-mini) → Analyst(gpt-5.4-mini) → Supervisor → Web/YT Searcher (병렬) → Validator(gpt-4.1-mini) → Writer(gpt-5.4-mini)

### 티스토리 발행 (Notion 발행 큐 → Playwright 자동화)
요약 완료 시 Notion에 발행상태="초안"으로 저장 → 앱 발행 탭에서 목록 조회
→ `POST /api/publish/tistory` → Playwright가 에디터(마크다운 모드) 자동화 발행
→ 발행상태 "발행완료"로 갱신. 로그인 세션은 `scripts/tistory_login.py`로 생성
(티스토리 Open API 2024.2 종료로 브라우저 자동화가 유일한 경로)

## 주요 패턴
- **SSE 스트리밍**: `AgentApiService`가 raw HTTP 응답을 수동 파싱 (sse-starlette 프로토콜)
- **중간 저장**: 날짜별 요약 1건 완료 시 즉시 `StorageService.save()` (중단 시 데이터 보존)
- **서버 URL 폴백**: 설정에서 서버 URL이 비어있으면 기존 LLM 직접 호출 모드로 동작
- **DailyDigest 중복 감지**: key = "roomName_YYYY-MM-DD"

## 버전 관리
- 현재 버전: pubspec.yaml의 `version` 필드 확인
- 매 수정마다 patch + buildNumber 함께 올릴 것
- 커밋 메시지에 버전 포함: `v2.0.x: 변경 설명`

## docs 인덱스

| 파일 | 내용 | 참조 시점 |
|------|------|----------|
| `docs/design_renewal_prompt_v1.md` | Claude Design 입력 프롬프트 (현재 UI 문제점 정리 포함) | 디자인 리뉴얼 작업 시 |
| `docs/design_renewal_v1.dc.html` | Claude Design 산출물 — 토큰·컨테이너 규칙·화면 시안 (v2.1.0에서 코드 반영, 원본은 `lib/theme.dart`) | 디자인 후속 작업 시 |
| `docs/pending.md` | 보류 안건 + 재검토 조건 (OpenAI 프로젝트 분리 등) | 관련 조건 충족 시 |

## Tech Stack
- Dart SDK ^3.11.0, Flutter (iOS/Android/Windows)
- 상태 관리: flutter_riverpod ^2.6.1 (sealed class + Notifier 패턴)
- 테마: Material 3, 커스텀 폰트 BMJUA (배달의민족 주아체)
- 서버: FastAPI + LangGraph + Tavily + YouTube Data API (포트 3936)
