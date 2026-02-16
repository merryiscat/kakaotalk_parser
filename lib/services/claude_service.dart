import '../models/chat_message.dart';
import 'llm_service.dart';

class ClaudeService implements LlmService {
  final String apiKey;
  ClaudeService({required this.apiKey});

  @override
  Future<String> summarize(List<ChatMessage> messages) async {
    // TODO: Claude API 호출 구현
    throw UnimplementedError('Claude 서비스 미구현');
  }
}
