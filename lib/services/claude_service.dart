import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'llm_service.dart';
import 'prompt_builder.dart';

/// Anthropic Claude API를 사용하는 LLM 서비스
class ClaudeService implements LlmService {
  final String apiKey;
  final Duration timeout;

  ClaudeService({
    required this.apiKey,
    this.timeout = const Duration(seconds: 30),
  });

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-4-5-20250929';

  @override
  Future<String> summarize(
    List<ChatMessage> messages, {
    Map<String, String> urlTitles = const {},
  }) async {
    final userPrompt = PromptBuilder.buildUserPromptWithLimit(messages);
    final systemPrompt = PromptBuilder.buildSystemPrompt(urlTitles);

    final body = jsonEncode({
      'model': _model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    });

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>;
        return content[0]['text'] as String;
      }

      throw LlmException(
        _errorMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    } on LlmException {
      rethrow;
    } catch (e) {
      throw LlmException('Claude API 연결 실패: $e');
    }
  }

  String _errorMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Claude API 키가 유효하지 않습니다. 설정에서 확인해 주세요.';
      case 403:
        return 'Claude API 접근 권한이 없습니다.';
      case 429:
        return 'Claude API 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요.';
      case 500:
        return 'Claude 서버에 일시적인 오류가 발생했습니다.';
      case 529:
        return 'Claude 서버가 과부하 상태입니다. 잠시 후 다시 시도해 주세요.';
      default:
        return 'Claude API 오류 (코드: $statusCode)';
    }
  }
}
