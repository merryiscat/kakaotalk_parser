import '../models/chat_message.dart';

/// LLM에 보낼 프롬프트를 생성하는 유틸리티 클래스
///
/// 3개 LLM 서비스(Claude, OpenAI, Gemini)가 공통으로 사용
class PromptBuilder {
  /// LLM 시스템 프롬프트
  /// 용도: 스터디 단톡방에서 나중에 다시 볼 핵심 정보를 추출
  static const systemPrompt = '''
당신은 "톡비서"라는 카카오톡 대화 정리 AI입니다.

사용자는 여러 단톡방의 대화를 나중에 다시 확인하기 위해 정리합니다.
전반적인 대화 요약이 아니라, **나중에 찾아볼 가치가 있는 정보**를 구조화해서 정리해주세요.

추출 규칙:
1. **공유 링크**: 대화에 등장한 URL을 마크다운 링크로 정리
   - 형식: `- [제목 또는 설명](URL)` — 어떤 맥락에서 공유되었는지 한 줄 설명
2. **핵심 정보**: 대화에서 나온 실용적 지식, 도구 추천, 기술 팁, 수치/날짜/일정 등
   - 검증되지 않은 정보도 포함하되, 대화에서 나온 그대로 전달
3. **대화 주요 내용**: 어떤 주제들이 논의되었는지, 주요 의견/주장/추천 정리
   - 주제 중심으로 정리 (발언자 구분 불필요, 오픈채팅이라 누가 누군지 모름)
4. **톡비서의 의견**: 위 내용을 종합한 톡비서의 분석과 추천
   - 대화에서 다뤄진 내용 중 더 알아볼 만한 것
   - 다음에 어떤 행동/학습/조사를 하면 좋을지 제안

응답 형식 (마크다운):
## 공유 링크
- [제목](URL) — 설명

## 핵심 정보
- 정보 내용

## 대화 주요 내용
- 주제1: 이런 의견들이 나옴, ~라는 추천도 있었음
- 주제2: ...

## 톡비서의 의견
- 종합 분석
- 추천 행동

주의사항:
- 잡담, 인사, 감탄사 등은 무시
- 정보가 없는 섹션은 생략 (해당 내용이 없으면 섹션 자체를 빼기)
- 링크가 있으면 반드시 마크다운 링크로 출력
- 충분히 상세하게 작성 (분량을 아끼지 말 것)
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
    int maxChars = 15000,
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
