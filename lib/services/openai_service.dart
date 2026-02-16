import '../models/chat_message.dart';
import 'llm_service.dart';

class OpenaiService implements LlmService {
  final String apiKey;
  OpenaiService({required this.apiKey});

  @override
  Future<String> summarize(List<ChatMessage> messages) async {
    // TODO: OpenAI API 호출 구현
    throw UnimplementedError('OpenAI 서비스 미구현');
  }
}
