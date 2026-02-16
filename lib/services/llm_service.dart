import '../models/chat_message.dart';

/// LLM 요약 추상 인터페이스
abstract class LlmService {
  Future<String> summarize(List<ChatMessage> messages);
}
