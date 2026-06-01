import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// SSE 노드 진행 이벤트 — 파이프라인 내 각 에이전트 노드가 완료될 때마다 발생
///
/// 예: "잡담 필터링 완료 (1/9)" → node="filter", displayName="잡담 필터링", step=1, totalSteps=9
class NodeProgressEvent {
  /// 서버 내부 노드 ID (예: "analyst", "web_searcher")
  final String node;

  /// 사용자에게 보여줄 한글 이름 (예: "대화 분석", "웹 검색")
  final String displayName;

  /// 현재까지 완료된 노드 수 (1부터 시작)
  final int step;

  /// 파이프라인 전체 노드 수 (보통 8, REVISE 시 10)
  final int totalSteps;

  const NodeProgressEvent({
    required this.node,
    required this.displayName,
    required this.step,
    required this.totalSteps,
  });
}

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

  /// SSE 스트리밍으로 멀티에이전트 파이프라인 요약을 실행합니다.
  ///
  /// 기존 [summarize]와 동일한 요청을 보내지만, 응답을 SSE 스트림으로 받아
  /// 각 노드 완료 시마다 [onNodeComplete] 콜백으로 진행률을 전달합니다.
  ///
  /// SSE 연결이므로 HTTP 타임아웃 없이 서버의 30초 ping으로 연결을 유지합니다.
  /// 반환값은 기존과 동일한 [LlmResult] (요약 텍스트 + 토큰 사용량).
  Future<LlmResult> summarizeStream(
    String messagesText, {
    Map<String, String> urlTitles = const {},
    void Function(NodeProgressEvent)? onNodeComplete,
  }) async {
    // HTTP 클라이언트를 직접 생성하여 스트림 종료 시 반드시 해제
    final client = http.Client();

    try {
      // URL 끝의 슬래시 제거
      final baseUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;

      // POST 요청 구성 (바디는 기존 summarize와 동일)
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/summarize-stream'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'messages': messagesText,
        'url_titles': urlTitles,
        'openai_api_key': openaiApiKey,
        'tavily_api_key': tavilyApiKey,
        'youtube_api_key': youtubeApiKey,
      });

      // StreamedResponse로 SSE 스트림 수신
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMsg;
        try {
          final errorData = jsonDecode(body) as Map<String, dynamic>;
          errorMsg = errorData['detail'] as String? ?? '알 수 없는 오류';
        } catch (_) {
          errorMsg = '서버 오류 (코드: ${response.statusCode})';
        }
        throw Exception(errorMsg);
      }

      // SSE 텍스트 프로토콜 수동 파싱
      // 형식: "event: 이벤트명\ndata: JSON데이터\n\n"
      String buffer = '';
      String? currentEvent;
      LlmResult? finalResult;

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        // SSE 서버(sse-starlette)가 \r\n 줄바꿈을 사용하므로
        // \r을 제거하여 \n으로 통일 (이벤트 구분자 \n\n 매칭용)
        buffer += chunk.replaceAll('\r', '');

        // SSE 이벤트는 빈 줄(\n\n)로 구분됨
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final block = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);

          // 이벤트 블록 내 각 줄 파싱
          for (final line in block.split('\n')) {
            if (line.startsWith('event: ')) {
              // 이벤트 타입 저장 (node_complete, result, error)
              currentEvent = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              // JSON 데이터 파싱
              final jsonStr = line.substring(6);
              Map<String, dynamic> data;
              try {
                data = jsonDecode(jsonStr) as Map<String, dynamic>;
              } catch (_) {
                continue; // 파싱 실패한 줄은 무시
              }

              switch (currentEvent) {
                case 'node_complete':
                  // 노드 완료 이벤트 → 콜백으로 진행률 전달
                  onNodeComplete?.call(NodeProgressEvent(
                    node: data['node'] as String? ?? '',
                    displayName: data['display_name'] as String? ?? '',
                    step: data['step'] as int? ?? 0,
                    totalSteps: data['total_steps'] as int? ?? 9,
                  ));
                  break;

                case 'result':
                  // 최종 결과 이벤트 → LlmResult 생성
                  finalResult = LlmResult(
                    text: data['summary'] as String? ?? '',
                    inputTokens: data['input_tokens'] as int? ?? 0,
                    outputTokens: data['output_tokens'] as int? ?? 0,
                  );
                  break;

                case 'error':
                  // 서버 에러 이벤트 → 예외 발생
                  throw Exception(
                    data['detail'] as String? ?? '파이프라인 오류',
                  );
              }
              currentEvent = null;
            }
            // ': ping' 등 주석 줄은 자동 무시
          }
        }
      }

      // 스트림 종료 후 버퍼에 남은 데이터 처리
      // (서버가 마지막 이벤트 직후 연결을 닫으면 \n\n 없이 버퍼에 남을 수 있음)
      if (buffer.trim().isNotEmpty && finalResult == null) {
        for (final line in buffer.split('\n')) {
          if (line.startsWith('event: ')) {
            currentEvent = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6);
            Map<String, dynamic> data;
            try {
              data = jsonDecode(jsonStr) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }

            if (currentEvent == 'result') {
              finalResult = LlmResult(
                text: data['summary'] as String? ?? '',
                inputTokens: data['input_tokens'] as int? ?? 0,
                outputTokens: data['output_tokens'] as int? ?? 0,
              );
            } else if (currentEvent == 'error') {
              throw Exception(
                data['detail'] as String? ?? '파이프라인 오류',
              );
            }
            currentEvent = null;
          }
        }
      }

      // 스트림 종료 후 결과 확인
      if (finalResult != null) {
        return finalResult;
      }
      throw Exception('SSE 스트림이 결과 없이 종료되었습니다.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('SSE 스트리밍 연결 실패: $e');
    } finally {
      // 스트림 완료/에러 모두에서 클라이언트 해제 (리소스 누수 방지)
      client.close();
      debugPrint('[AgentApiService] SSE 클라이언트 해제 완료');
    }
  }
}
