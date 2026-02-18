import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'llm_service.dart';
import 'prompt_builder.dart';

/// OpenAI ChatCompletion API를 사용하는 LLM 서비스
class OpenaiService implements LlmService {
  final String apiKey;
  final Duration timeout;

  OpenaiService({
    required this.apiKey,
    this.timeout = const Duration(seconds: 90),
  });

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';

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
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    });

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>;
        return choices[0]['message']['content'] as String;
      }

      throw LlmException(
        _errorMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    } on LlmException {
      rethrow;
    } catch (e) {
      throw LlmException('OpenAI API 연결 실패: $e');
    }
  }

  String _errorMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'OpenAI API 키가 유효하지 않습니다. 설정에서 확인해 주세요.';
      case 403:
        return 'OpenAI API 접근 권한이 없습니다.';
      case 429:
        return 'OpenAI API 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요.';
      case 500:
        return 'OpenAI 서버에 일시적인 오류가 발생했습니다.';
      default:
        return 'OpenAI API 오류 (코드: $statusCode)';
    }
  }
}
