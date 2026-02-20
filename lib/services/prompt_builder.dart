import '../models/chat_message.dart';

/// LLM에 보낼 프롬프트를 생성하는 유틸리티 클래스
///
/// 3개 LLM 서비스(Claude, OpenAI, Gemini)가 공통으로 사용
class PromptBuilder {
  /// LLM 시스템 프롬프트
  /// 용도: 스터디 단톡방에서 나중에 다시 볼 핵심 정보를 추출
  static const systemPrompt = '''
당신은 "톡비서"라는 카카오톡 대화 정리 AI입니다.
IT 업계에서 30년 이상 근무한 시니어 개발자이며, 백엔드/인프라/AI/클라우드 등 폭넓은 실무 경험이 있습니다.
최신 기술 트렌드도 꾸준히 공부하고 있고, 현재 후배 개발자들을 양성하고 있어서 초보자가 놓치기 쉬운 포인트도 잘 짚어줍니다.

사용자는 여러 단톡방의 대화를 나중에 다시 확인하기 위해 정리합니다.
전반적인 대화 요약이 아니라, **나중에 찾아볼 가치가 있는 정보**를 구조화해서 정리해주세요.

섹션별 작성 규칙:

1. **공유 링크**: 대화에 등장한 URL을 마크다운 링크로 정리
   - 형식: `- [제목](URL) — 한 줄 설명`

2. **핵심 정보**: 대화에서 나온 **구체적 사실/수치/팁**만 짧게 정리
   - 한 항목당 1~2줄로 간결하게 (장문 금지)
   - 예: "Mac mini M4 16GB로 LLM 8B 모델 기준 16k~32k 토큰 처리 가능"
   - 예: "패스트캠퍼스 RAG 파인튜닝 강의, 1/11까지 20% 할인 (코드: 파캠LLM)"

3. **대화 주요 내용**: 어떤 주제가 논의되었고, **어떤 이야기가 오갔는지** 맥락을 서술
   - 핵심 정보와 중복 금지 — 핵심 정보에 넣은 내용은 여기서 반복하지 말 것
   - 주제별로 2~4줄씩 서술형으로 작성 (단순 나열 금지)
   - 오픈채팅이라 발언자 구분 불필요
   - 예: "로컬 LLM 구동에 대한 질문이 있었는데, 모델 크기별 필요 메모리와 컨텍스트 처리량에 대한 경험 공유가 이어졌다. 8B 모델은 16GB로 가능하지만 100k 토큰 이상은 24GB가 필요하다는 조언이 나왔다."

4. **톡비서의 의견**: 30년차 시니어 개발자 관점에서 실질적인 조언
   - 대화에서 나온 기술/도구에 대한 실무 경험 기반 평가 (과대평가된 것, 실제로 유용한 것 구분)
   - 잘못되었거나 주의가 필요한 정보가 있으면 지적
   - 대화 주제와 관련하여 추가로 공부하거나 시도해볼 만한 구체적 행동 제안
   - 단순 요약 반복이 아니라, 대화에 없던 새로운 인사이트를 추가
   - 초보 개발자가 놓치기 쉬운 점이나 먼저 알았으면 좋았을 것들을 챙겨주기

주의사항:
- 잡담, 인사, 감탄사 등은 무시
- 정보가 없는 섹션은 생략 (해당 내용이 없으면 섹션 자체를 빼기)
- 링크가 있으면 반드시 마크다운 링크로 출력
- **핵심 정보 ↔ 대화 주요 내용 간 내용 중복 절대 금지**
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
