// 리포트 마크다운을 섹션별로 파싱하는 유틸리티
//
// Writer가 생성한 마크다운 리포트를 앱에서 섹션별로 다른 위젯으로
// 렌더링하기 위해, `## ` 헤더와 `### ` 헤더 기준으로 분할합니다.
//
// 리포트 구조:
// - ## 주제 키워드 → 쉼표 구분 키워드 (Chip으로 렌더링)
// - ## 대화 주요 내용 → 마크다운 그대로 (MarkdownBody로 렌더링)
// - ## 핵심 정보 → ### 주제별 소섹션 (ExpansionTile로 렌더링)
// - ## 톡비서 제안 → ### 주제별 소섹션 (Card로 렌더링)

/// 주제별 소섹션 데이터 (핵심 정보, 톡비서 제안에서 사용)
/// `### 주제명` 아래의 마크다운 내용을 담습니다.
class TopicSection {
  /// `### ` 뒤의 주제명 (예: "LangGraph", "RAG 파이프라인 구축")
  final String title;

  /// 해당 소섹션의 마크다운 본문 (### 헤더 제외)
  final String markdown;

  const TopicSection({
    required this.title,
    required this.markdown,
  });
}

/// Writer가 생성한 리포트를 파싱한 결과
/// 각 섹션을 별도 위젯으로 렌더링하기 위한 구조체
class ReportData {
  /// 주제 키워드 목록 (쉼표로 분리된 키워드들)
  final List<String> keywords;

  /// 대화 주요 내용 마크다운 (그대로 MarkdownBody에 전달)
  final String mainContent;

  /// 핵심 정보 — 주제별 소섹션 리스트 (ExpansionTile로 렌더링)
  final List<TopicSection> keyInfoTopics;

  /// 톡비서 제안 — 주제별 소섹션 리스트 (Card로 렌더링)
  final List<TopicSection> suggestions;

  const ReportData({
    this.keywords = const [],
    this.mainContent = '',
    this.keyInfoTopics = const [],
    this.suggestions = const [],
  });
}

/// 마크다운 리포트를 파싱하여 ReportData로 변환
/// [markdown] — Writer가 생성한 전체 마크다운 텍스트
ReportData parseReport(String markdown) {
  // ## 헤더 기준으로 대섹션 분할
  // 정규식: 줄 시작에서 "## " 으로 시작하는 라인을 기준으로 split
  final sectionMap = _splitBySections(markdown);

  // 1. 주제 키워드 파싱: 쉼표로 구분된 키워드 추출
  final keywordsRaw = sectionMap['주제 키워드'] ?? '';
  final keywords = keywordsRaw
      .split(',')
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toList();

  // 2. 대화 주요 내용: 마크다운 그대로
  final mainContent = sectionMap['대화 주요 내용'] ?? '';

  // 3. 핵심 정보: ### 주제별 소섹션으로 분할
  final keyInfoRaw = sectionMap['핵심 정보'] ?? '';
  final keyInfoTopics = _splitBySubSections(keyInfoRaw);

  // 4. 톡비서 제안: ### 주제별 소섹션으로 분할
  final suggestionsRaw = sectionMap['톡비서 제안'] ?? '';
  final suggestions = _splitBySubSections(suggestionsRaw);

  return ReportData(
    keywords: keywords,
    mainContent: mainContent,
    keyInfoTopics: keyInfoTopics,
    suggestions: suggestions,
  );
}

/// `## 섹션이름` 기준으로 마크다운을 분할하여 Map으로 반환
/// 키: 섹션 이름 (예: "주제 키워드"), 값: 해당 섹션의 마크다운 본문
Map<String, String> _splitBySections(String markdown) {
  final result = <String, String>{};
  // `## ` 으로 시작하는 라인을 찾아서 분할 (### 은 제외)
  final pattern = RegExp(r'^## (.+)$', multiLine: true);
  final matches = pattern.allMatches(markdown).toList();

  for (var i = 0; i < matches.length; i++) {
    final sectionName = matches[i].group(1)!.trim();
    // 현재 섹션의 본문: 현재 매치 끝 ~ 다음 매치 시작 (또는 끝)
    final start = matches[i].end;
    final end = (i + 1 < matches.length) ? matches[i + 1].start : markdown.length;
    final body = markdown.substring(start, end).trim();
    result[sectionName] = body;
  }

  return result;
}

/// `### 주제명` 기준으로 섹션 본문을 소섹션 리스트로 분할
/// [sectionBody] — `## ` 헤더 아래의 본문 텍스트
List<TopicSection> _splitBySubSections(String sectionBody) {
  if (sectionBody.isEmpty) return [];

  final result = <TopicSection>[];
  final pattern = RegExp(r'^### (.+)$', multiLine: true);
  final matches = pattern.allMatches(sectionBody).toList();

  // ### 소섹션이 없으면 전체를 하나의 소섹션으로 처리
  if (matches.isEmpty) {
    final trimmed = sectionBody.trim();
    if (trimmed.isNotEmpty) {
      result.add(TopicSection(title: '정보', markdown: trimmed));
    }
    return result;
  }

  for (var i = 0; i < matches.length; i++) {
    final title = matches[i].group(1)!.trim();
    final start = matches[i].end;
    final end = (i + 1 < matches.length) ? matches[i + 1].start : sectionBody.length;
    final body = sectionBody.substring(start, end).trim();
    if (body.isNotEmpty) {
      result.add(TopicSection(title: title, markdown: body));
    }
  }

  return result;
}
