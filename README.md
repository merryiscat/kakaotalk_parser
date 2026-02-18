# 톡비서 (TokBiseo) - 카카오톡 AI 요약 앱

카카오톡 대화 내보내기 파일(`.txt`)을 파싱하여 날짜별 AI 요약을 생성하는 Flutter 앱입니다.

스터디 단톡방, 업무 채팅 등에서 공유된 **링크, 기술 정보, 핵심 인사이트**를 놓치지 않고 정리해 줍니다.

## 주요 기능

- **카카오톡 TXT 파싱** — 내보내기 파일의 메시지, 날짜, 발신자를 정규식으로 정확히 추출
- **AI 요약 생성** — Claude / OpenAI / Gemini API 중 택 1 (설정에서 변경 가능)
- **URL 메타데이터** — 대화에 공유된 링크의 페이지 제목을 자동 수집하여 요약에 반영
- **마크다운 렌더링** — 요약 본문에서 링크 클릭, 볼드/리스트 등 마크다운 지원
- **날짜별 타임라인** — 채팅방 선택 → 날짜별 요약 카드 → 상세 보기
- **달력 뷰** — 요약이 있는 날짜를 달력에서 한눈에 확인
- **중복 감지** — 이미 요약한 날짜는 건너뛰어 API 토큰 절약

## 스크린샷

> 추후 추가 예정

## 시작하기

### 요구사항

- Flutter SDK 3.11.0 이상
- Dart SDK 3.11.0 이상
- Android / iOS / Windows 지원

### 설치 및 실행

```bash
# 의존성 설치
flutter pub get

# Android 실행
flutter run

# Windows 데스크톱 실행
flutter run -d windows

# APK 빌드
flutter build apk --release
```

### API 키 설정

앱 내 **설정** 화면에서 사용할 LLM 서비스를 선택하고 API 키를 입력합니다.

| 서비스 | 모델 | API 키 발급 |
|--------|------|------------|
| Claude | claude-sonnet-4-5-20250929 | [Anthropic Console](https://console.anthropic.com/) |
| OpenAI | gpt-4o-mini | [OpenAI Platform](https://platform.openai.com/) |
| Gemini | gemini-2.0-flash | [Google AI Studio](https://aistudio.google.com/) |

## 사용법

1. 카카오톡에서 대화 내보내기 (`.txt` 파일)
2. 앱 홈 화면에서 **+ 채팅방 추가**
3. 채팅방 선택 → **파일 업로드** 버튼 탭
4. 내보낸 `.txt` 파일 선택
5. 날짜별 AI 요약이 자동 생성됩니다

## 기술 스택

| 구분 | 기술 |
|------|------|
| Framework | Flutter 3.29+ |
| Language | Dart 3.11+ |
| 상태 관리 | Riverpod (Notifier 패턴) |
| LLM API | Claude / OpenAI / Gemini (추상화 인터페이스) |
| 저장소 | SharedPreferences (API 키), 메모리 (채팅 데이터) |
| 폰트 | Pretendard (SIL Open Font License) |
| 테마 | Material 3, KakaoTalk Yellow (#FEE500) |

## 프로젝트 구조

```
lib/
├── models/                 # 데이터 모델
│   ├── chat_message.dart       # 채팅 메시지 (발신자, 시간, 내용, 타입)
│   ├── chat_room.dart          # 채팅방 (메시지 리스트, 날짜별 그룹핑)
│   └── daily_digest.dart       # 일별 요약 결과
├── parser/
│   └── kakaotalk_parser.dart   # 카카오톡 TXT 정규식 파서
├── services/               # 외부 서비스 연동
│   ├── llm_service.dart        # LLM 추상 인터페이스 + LlmException
│   ├── claude_service.dart     # Anthropic Messages API
│   ├── openai_service.dart     # OpenAI Chat Completions API
│   ├── gemini_service.dart     # Google Gemini API
│   ├── prompt_builder.dart     # 공통 프롬프트 빌더 (스터디 특화)
│   └── url_metadata_service.dart  # URL 페이지 제목 추출
├── providers/              # Riverpod 상태 관리
│   ├── digest_provider.dart    # 핵심: 파싱 → 요약 파이프라인
│   ├── navigation_provider.dart # 하단 네비게이션 상태
│   └── settings_provider.dart  # API 키, LLM 선택 (SharedPreferences)
└── screens/                # UI 화면
    ├── home_screen.dart        # 채팅방 목록 + 방 추가/수정/삭제
    ├── room_detail_screen.dart # 방 상세: 날짜별 요약 타임라인
    ├── digest_screen.dart      # 요약 상세: 마크다운 렌더링
    ├── calendar_screen.dart    # 달력 뷰
    ├── settings_screen.dart    # API 키 입력 + LLM 선택
    └── main_shell_screen.dart  # 하단 탭 네비게이션 쉘
```

## 파서 지원 형식

카카오톡 내보내기 파일(UTF-8, BOM 포함)의 다음 패턴을 인식합니다:

```
인공지능 연구방 2025 님과 카카오톡 대화        ← 헤더 (방 이름)
저장한 날짜 : 2026년 2월 16일 오후 4:45       ← 내보내기 날짜
2025년 12월 15일 오후 1:18, 홍길동 : 안녕하세요  ← 일반 메시지
2025년 12월 15일 오후 1:20, 시스템 메시지       ← 시스템 메시지
```

- 오전/오후 12시간제 → 24시간제 자동 변환
- 멀티라인 메시지 자동 합치기
- 이모티콘, 사진, 삭제된 메시지 분류

## 테스트

```bash
# 파서 단위 테스트 (23개)
flutter test test/parser_test.dart

# 전체 테스트
flutter test
```

## 라이선스

MIT License - [LICENSE](LICENSE) 참조

## v1.0.0 변경 이력

초기 릴리스. 주요 구현 내용:

- 카카오톡 TXT 파서 (정규식 5종, 멀티라인 처리, 메시지 타입 분류)
- LLM 서비스 3종 (Claude, OpenAI, Gemini) API 연동
- 스터디 특화 프롬프트 (링크 추출, 기술 정보, 핵심 인사이트)
- URL 메타데이터 서비스 (og:title / HTML title 자동 추출)
- 마크다운 요약 렌더링 + URL 클릭 가능
- Riverpod 기반 상태 관리 파이프라인
- Material 3 테마 + Pretendard 폰트
- 하단 탭 네비게이션 (홈/달력/설정)
- 파서 단위 테스트 23개
