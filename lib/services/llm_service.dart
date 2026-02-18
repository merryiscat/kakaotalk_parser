import '../models/chat_message.dart';

/// LLM API 호출 시 발생하는 커스텀 예외
/// - 3개 서비스(Claude, OpenAI, Gemini)에서 공통으로 사용
class LlmException implements Exception {
  /// 사용자에게 보여줄 한국어 에러 메시지
  final String message;

  /// HTTP 상태 코드 (네트워크 에러 시 null)
  final int? statusCode;

  const LlmException(this.message, {this.statusCode});

  @override
  String toString() => 'LlmException: $message (statusCode: $statusCode)';
}

/// LLM 요약 추상 인터페이스
/// - 각 서비스(Claude, OpenAI, Gemini)가 이 인터페이스를 구현
abstract class LlmService {
  /// [urlTitles] : URL → 페이지 제목 맵 (프롬프트에 포함하여 링크 설명 정확도 향상)
  Future<String> summarize(
    List<ChatMessage> messages, {
    Map<String, String> urlTitles,
  });
}
