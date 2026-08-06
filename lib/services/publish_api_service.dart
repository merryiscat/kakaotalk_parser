import 'dart:convert';

import 'package:http/http.dart' as http;

/// 발행 대기 중인 Notion 페이지 한 건의 요약 정보
///
/// 서버의 GET /api/notion/pending 응답 항목과 1:1 대응합니다.
/// (서버가 Notion DB에서 발행상태="초안"인 페이지만 골라 내려줌)
class PendingPage {
  /// Notion 페이지 ID — 발행 요청 시 이 값을 서버에 전달
  final String pageId;

  /// 페이지 제목 (예: "방이름 — 2026-07-28")
  final String title;

  /// 대화 날짜 (YYYY-MM-DD, 없으면 빈 문자열)
  final String chatDate;

  /// 채팅방 이름
  final String roomName;

  /// 주제 키워드 — 발행 시 티스토리 태그로 사용됨
  final List<String> keywords;

  /// Notion 페이지 URL (브라우저에서 원본 확인용)
  final String notionUrl;

  const PendingPage({
    required this.pageId,
    required this.title,
    required this.chatDate,
    required this.roomName,
    required this.keywords,
    required this.notionUrl,
  });

  factory PendingPage.fromJson(Map<String, dynamic> json) {
    return PendingPage(
      pageId: json['page_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      chatDate: json['chat_date'] as String? ?? '',
      roomName: json['room_name'] as String? ?? '',
      keywords: (json['keywords'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      notionUrl: json['notion_url'] as String? ?? '',
    );
  }
}

/// 티스토리 발행 관련 서버 API를 호출하는 서비스
///
/// 요약(AgentApiService)과 별개로, Notion 발행 큐 조회와
/// 티스토리 발행 요청만 담당합니다.
class PublishApiService {
  /// 멀티에이전트 서버 기본 URL (예: "http://192.168.0.10:3936")
  final String serverUrl;

  /// 서버 접근 토큰 — /api/* 요청의 X-API-Key 헤더로 전송
  /// (서버가 인터넷에 노출돼 있어 이 토큰이 없으면 401로 거부됨)
  final String serverApiKey;

  PublishApiService({required this.serverUrl, this.serverApiKey = ''});

  /// URL 끝의 슬래시 제거 (이중 슬래시 방지 — AgentApiService와 동일 패턴)
  String get _baseUrl => serverUrl.endsWith('/')
      ? serverUrl.substring(0, serverUrl.length - 1)
      : serverUrl;

  /// /api/* 요청 공통 헤더 (서버 접근 토큰)
  Map<String, String> get _apiHeaders =>
      {if (serverApiKey.isNotEmpty) 'X-API-Key': serverApiKey};

  /// 에러 응답에서 detail 메시지를 추출합니다 (FastAPI 표준 형식)
  String _errorDetail(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['detail'] as String? ?? '알 수 없는 오류';
    } catch (_) {
      return '서버 오류 (코드: ${response.statusCode})';
    }
  }

  /// 발행 대기(발행상태="초안") 페이지 목록을 조회합니다.
  Future<List<PendingPage>> fetchPending() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/api/notion/pending'), headers: _apiHeaders)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response));
    }

    // 한글 제목이 깨지지 않도록 UTF-8로 명시적 디코딩
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['pages'] as List<dynamic>? ?? [])
        .map((e) => PendingPage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 페이지 본문을 마크다운으로 조회합니다 (발행 전 미리보기용).
  Future<String> fetchPageMarkdown(String pageId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/api/notion/page/$pageId'),
            headers: _apiHeaders)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response));
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['markdown'] as String? ?? '';
  }

  /// 페이지 한 건을 티스토리에 발행합니다.
  ///
  /// 서버가 Playwright로 브라우저를 띄워 발행하므로 시간이 걸립니다
  /// (타임아웃 180초). 성공 시 발행된 글 URL을 반환합니다.
  Future<String> publish(String pageId) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/publish/tistory'),
          headers: {'Content-Type': 'application/json', ..._apiHeaders},
          body: jsonEncode({'page_id': pageId}),
        )
        .timeout(const Duration(seconds: 180));

    if (response.statusCode != 200) {
      throw Exception(_errorDetail(response));
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return data['url'] as String? ?? '';
  }
}
