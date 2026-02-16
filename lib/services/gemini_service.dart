import '../models/chat_message.dart';
import 'llm_service.dart';

class GeminiService implements LlmService {
  final String apiKey;
  GeminiService({required this.apiKey});

  @override
  Future<String> summarize(List<ChatMessage> messages) async {
    // TODO: Gemini API 호출 구현
    throw UnimplementedError('Gemini 서비스 미구현');
  }
}
