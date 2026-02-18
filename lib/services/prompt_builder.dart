import '../models/chat_message.dart';

/// LLM에 보낼 프롬프트를 생성하는 유틸리티 클래스
///
/// 3개 LLM 서비스(Claude, OpenAI, Gemini)가 공통으로 사용
class PromptBuilder {
  /// LLM 시스템 프롬프트
  /// 용도: 스터디 단톡방에서 나중에 다시 볼 핵심 정보를 추출
  static const systemPrompt = '''
당신은 카카오톡 스터디 그룹채팅에서 핵심 정보를 추출하는 전문가입니다.

사용자는 여러 스터디 단톡방의 대화를 나중에 다시 확인하기 위해 정리합니다.
전반적인 대화 요약이 아니라, **나중에 찾아볼 가치가 있는 정보**만 뽑아주세요.

추출 규칙:
1. **공유된 링크**: 마크다운 링크 형식으로 정리. URL과 대화 맥락으로 내용을 유추하여 설명 추가.
   - 형식: `- [제목 또는 설명](URL)` — 어떤 맥락에서 공유되었는지 한 줄 설명
2. **기술 정보 / 팁**: 대화에서 나온 실용적인 기술 지식, 도구 사용법, 추천 등
3. **주요 인사이트**: 토론에서 나온 의미 있는 의견이나 결론

응답 형식 (마크다운):
## 공유 링크
- [제목](URL) — 설명
- ...

## 기술 정보
- ...

## 주요 인사이트
- ...

주의사항:
- 잡담, 인사, 감탄사 등은 무시
- 정보가 없는 섹션은 생략
- 링크가 제공된 경우 반드시 마크다운 링크로 출력
''';

  /// URL 메타데이터가 포함된 시스템 프롬프트 생성
  ///
  /// [urlTitles] : { URL → 페이지 제목 } 맵
  /// URL 제목 정보를 프롬프트에 포함하여 LLM이 더 정확한 링크 설명 생성
  static String buildSystemPrompt(Map<String, String> urlTitles) {
    if (urlTitles.isEmpty) return systemPrompt;

    final urlInfo = StringBuffer();
    urlInfo.writeln('\n참고: 대화에 등장하는 URL의 실제 페이지 제목 정보입니다.');
    urlInfo.writeln('링크 정리 시 이 제목을 활용하세요:');
    for (final entry in urlTitles.entries) {
      urlInfo.writeln('- ${entry.key} → "${entry.value}"');
    }

    return '$systemPrompt$urlInfo';
  }

  /// ChatMessage 리스트 → LLM에 보낼 텍스트로 변환
  ///
  /// system, media, emoticon, deleted 메시지는 제외 (토큰 절약)
  /// 출력 형식: "[HH:MM] 발신자: 내용"
  static String buildUserPrompt(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('아래 카카오톡 대화에서 핵심 정보를 추출해 주세요:\n');

    for (final msg in messages) {
      if (msg.type == MessageType.system ||
          msg.type == MessageType.media ||
          msg.type == MessageType.emoticon ||
          msg.type == MessageType.deleted) {
        continue;
      }

      final hour = msg.dateTime.hour.toString().padLeft(2, '0');
      final minute = msg.dateTime.minute.toString().padLeft(2, '0');
      buffer.writeln('[$hour:$minute] ${msg.sender}: ${msg.content}');
    }

    return buffer.toString();
  }

  /// 글자 수 제한이 있는 프롬프트 생성
  ///
  /// [maxChars] 초과 시 앞부분(오래된 메시지)부터 잘라냄
  static String buildUserPromptWithLimit(
    List<ChatMessage> messages, {
    int maxChars = 30000,
  }) {
    final fullPrompt = buildUserPrompt(messages);

    if (fullPrompt.length <= maxChars) return fullPrompt;

    final truncated = fullPrompt.substring(fullPrompt.length - maxChars);
    final firstNewline = truncated.indexOf('\n');
    final clean =
        firstNewline >= 0 ? truncated.substring(firstNewline + 1) : truncated;

    return '(이전 대화 생략)\n$clean';
  }
}
