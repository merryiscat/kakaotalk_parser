# KakaoTalk Parser - 카톡 대화 AI 요약

카카오톡 내보내기 파일(.txt)을 파싱하여 날짜별 AI 요약을 생성하는 Flutter 앱.

## Tech Stack
- **Language**: Dart (SDK ^3.11.0)
- **Framework**: Flutter (iOS, Android, Windows)
- **State**: Riverpod (flutter_riverpod ^2.6.1)
- **LLM**: Claude / OpenAI / Gemini API (선택)
- **Storage**: SharedPreferences (API 키), 메모리 (채팅 데이터)

## Project Structure
```
lib/
  models/           chat_message, chat_room, daily_digest
  parser/           kakaotalk_parser (TODO: 정규식 파싱)
  services/         llm_service (추상), claude/openai/gemini (TODO: API 구현)
  providers/        chat_provider, digest_provider, settings_provider
  screens/          home, digest, settings
```

## Development Commands
```bash
cd kakaotalk_parser
flutter pub get         # 의존성 설치
flutter run             # 앱 실행
flutter run -d windows  # Windows 데스크톱
```

## Architecture
- Riverpod sealed class + Notifier 패턴
- Models → Services (LLM 추상화) → Providers (상태) → Screens (UI)

## TODO
1. `kakaotalk_parser.dart` - TXT 파싱 정규식 구현
2. LLM 서비스 3종 API 연동 구현
3. 테스트 코드 작성

## Theme
Material 3, KakaoTalk 옐로우 (#FEE500)
