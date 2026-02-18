import 'package:http/http.dart' as http;

/// URL에서 페이지 제목(title)을 가져오는 서비스
///
/// 카카오톡 대화에 공유된 링크의 제목을 추출하여
/// LLM 프롬프트에 포함시키기 위해 사용
class UrlMetadataService {
  /// 개별 URL 요청 타임아웃 (느린 사이트 대비)
  static const _timeout = Duration(seconds: 5);

  /// URL 목록에서 각 URL의 페이지 제목을 가져옴
  ///
  /// 반환: { "https://example.com/article" : "기사 제목" }
  /// - 실패한 URL은 결과에서 제외 (에러 무시)
  /// - 병렬로 요청하여 속도 최적화
  static Future<Map<String, String>> fetchTitles(List<String> urls) async {
    final results = <String, String>{};
    if (urls.isEmpty) return results;

    // 중복 제거
    final uniqueUrls = urls.toSet().toList();

    // 병렬로 모든 URL의 제목을 가져옴
    final futures = uniqueUrls.map((url) async {
      try {
        final title = await _fetchTitle(url);
        if (title != null && title.isNotEmpty) {
          results[url] = title;
        }
      } catch (_) {
        // 개별 URL 실패는 무시 (네트워크 에러, 타임아웃 등)
      }
    });

    await Future.wait(futures);
    return results;
  }

  /// 단일 URL에서 HTML <title> 태그를 추출
  ///
  /// 우선순위: og:title > <title> 태그
  /// HEAD 요청이 아닌 GET을 사용 (HTML 본문이 필요하므로)
  static Future<String?> _fetchTitle(String url) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            // 봇 차단 방지를 위한 브라우저 User-Agent
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        )
        .timeout(_timeout);

    if (response.statusCode != 200) return null;

    final body = response.body;

    // 1순위: og:title 메타 태그
    final ogMatch = RegExp(
      r"""<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']""",
      caseSensitive: false,
    ).firstMatch(body);
    if (ogMatch != null) return _cleanTitle(ogMatch.group(1)!);

    // og:title이 content 먼저 오는 경우도 처리
    final ogMatch2 = RegExp(
      r"""<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']""",
      caseSensitive: false,
    ).firstMatch(body);
    if (ogMatch2 != null) return _cleanTitle(ogMatch2.group(1)!);

    // 2순위: <title> 태그
    final titleMatch = RegExp(
      r'<title[^>]*>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(body);
    if (titleMatch != null) return _cleanTitle(titleMatch.group(1)!);

    return null;
  }

  /// HTML 엔티티 디코딩 + 공백 정리
  static String _cleanTitle(String raw) {
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 메시지 텍스트에서 URL을 추출
  ///
  /// http:// 또는 https:// 로 시작하는 문자열을 모두 찾음
  static List<String> extractUrls(String text) {
    final regex = RegExp(r'https?://[^\s<>"]+');
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }
}
