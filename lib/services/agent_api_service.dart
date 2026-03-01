import 'dart:convert';

import 'package:http/http.dart' as http;

/// LLM 응답 결과 — 요약 텍스트 + 토큰 사용량
class LlmResult {
  final String text;
  final int inputTokens;
  final int outputTokens;

  const LlmResult({
    required this.text,
    this.inputTokens = 0,
    this.outputTokens = 0,
  });
}

/// 톡비서 멀티에이전트 서버와 HTTP 통신하는 서비스
///
/// FastAPI 서버의 /api/summarize 엔드포인트를 호출하여
/// 웹 검색 + 유튜브 검색이 포함된 고품질 리포트를 받아옵니다.
class AgentApiService {
  /// 멀티에이전트 서버 기본 URL (예: "http://192.168.0.10:3936")
  final String serverUrl;

  /// 서버에서 LLM 호출에 사용할 OpenAI API 키
  final String openaiApiKey;

  /// 서버에서 웹 검색에 사용할 Tavily API 키
  final String tavilyApiKey;

  /// 서버에서 유튜브 검색에 사용할 YouTube API 키
  final String youtubeApiKey;

  /// API 요청 타임아웃 — 멀티에이전트 파이프라인은 시간이 걸리므로 300초
  final Duration timeout;

  AgentApiService({
    required this.serverUrl,
    required this.openaiApiKey,
    required this.tavilyApiKey,
    required this.youtubeApiKey,
    this.timeout = const Duration(seconds: 300),
  });

  /// 서버 연결 상태를 확인합니다 (GET /health)
  ///
  /// 설정 화면에서 "연결 테스트" 버튼 누를 때 호출.
  /// 서버가 정상이면 null (성공), 아니면 에러 메시지 문자열 반환.
  Future<String?> healthCheck() async {
    try {
      // URL 끝의 슬래시 제거 (이중 슬래시 방지)
      final baseUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.contains('ok')) {
          return null; // 성공
        }
        return '응답 형식이 올바르지 않습니다: $body';
      }
      return 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      return '연결 실패: $e';
    }
  }

  /// 멀티에이전트 파이프라인으로 대화를 요약합니다.
  ///
  /// [messagesText] : 파싱된 대화 텍스트 ("[HH:MM] 발신자: 내용" 형식)
  /// [urlTitles] : URL → 페이지 제목 맵
  Future<LlmResult> summarize(
    String messagesText, {
    Map<String, String> urlTitles = const {},
  }) async {
    // 요청 바디 구성 (API 키를 서버로 전송)
    final body = jsonEncode({
      'messages': messagesText,
      'url_titles': urlTitles,
      'openai_api_key': openaiApiKey,
      'tavily_api_key': tavilyApiKey,
      'youtube_api_key': youtubeApiKey,
    });

    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/api/summarize'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return LlmResult(
          text: data['summary'] as String? ?? '',
          inputTokens: data['input_tokens'] as int? ?? 0,
          outputTokens: data['output_tokens'] as int? ?? 0,
        );
      }

      // 에러 응답 처리
      String errorMsg;
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMsg = errorData['detail'] as String? ?? '알 수 없는 오류';
      } catch (_) {
        errorMsg = '서버 오류 (코드: ${response.statusCode})';
      }
      throw Exception(errorMsg);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('멀티에이전트 서버 연결 실패: $e');
    }
  }
}
