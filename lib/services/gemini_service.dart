import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import 'llm_service.dart';
import 'prompt_builder.dart';

/// Google Gemini API를 사용하는 LLM 서비스
class GeminiService implements LlmService {
  final String apiKey;
  final Duration timeout;

  GeminiService({
    required this.apiKey,
    this.timeout = const Duration(seconds: 90),
  });

  static const _model = 'gemini-2.0-flash';

  static String _endpoint(String apiKey) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$apiKey';

  @override
  Future<String> summarize(
    List<ChatMessage> messages, {
    Map<String, String> urlTitles = const {},
  }) async {
    final userPrompt = PromptBuilder.buildUserPromptWithLimit(messages);
    final systemPrompt = PromptBuilder.buildSystemPrompt(urlTitles);

    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'parts': [
            {'text': userPrompt},
          ],
        },
      ],
      'generationConfig': {
        'maxOutputTokens': 1024,
      },
    });

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint(apiKey)),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>;
        final parts = candidates[0]['content']['parts'] as List<dynamic>;
        return parts[0]['text'] as String;
      }

      throw LlmException(
        _errorMessage(response.statusCode),
        statusCode: response.statusCode,
      );
    } on LlmException {
      rethrow;
    } catch (e) {
      throw LlmException('Gemini API 연결 실패: $e');
    }
  }

  String _errorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Gemini API 요청 형식이 올바르지 않습니다.';
      case 403:
        return 'Gemini API 키가 유효하지 않습니다. 설정에서 확인해 주세요.';
      case 429:
        return 'Gemini API 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요.';
      case 500:
        return 'Gemini 서버에 일시적인 오류가 발생했습니다.';
      default:
        return 'Gemini API 오류 (코드: $statusCode)';
    }
  }
}
