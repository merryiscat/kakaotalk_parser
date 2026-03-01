import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/daily_digest.dart';
import '../utils/report_parser.dart';

/// AI 요약 상세 화면
/// 특정 날짜의 이미 완료된 요약 목록을 표시합니다.
/// LLM 호출 없이 기존 데이터만 렌더링합니다.
///
/// 리포트를 4개 섹션으로 파싱하여 각각 다른 위젯으로 표시:
/// - 주제 키워드 → Chip 가로 나열
/// - 대화 주요 내용 → MarkdownBody
/// - 핵심 정보 → 주제별 ExpansionTile (기본 접힘)
/// - 톡비서 제안 → 주제별 Card
class DigestScreen extends StatelessWidget {
  final DateTime date;
  final List<DailyDigest> digests;

  const DigestScreen({
    super.key,
    required this.date,
    required this.digests,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko');

    return Scaffold(
      appBar: AppBar(title: Text(dateFormat.format(date))),
      body: digests.isEmpty
          ? const Center(child: Text('요약 데이터가 없습니다.'))
          : ListView.builder(
              // 하단에 시스템 네비게이션 바 높이만큼 여유 공간 확보
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: digests.length,
              itemBuilder: (context, index) {
                final digest = digests[index];
                return _buildDigestCard(context, digest);
              },
            ),
    );
  }

  /// 개별 요약 카드 위젯
  /// 리포트를 파싱하여 4개 섹션을 각각 다른 위젯으로 렌더링
  Widget _buildDigestCard(BuildContext context, DailyDigest digest) {
    // 마크다운 리포트를 섹션별로 파싱
    final report = parseReport(digest.summary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 채팅방 이름 + 메시지 수 헤더
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.chat,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      digest.roomName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  Text(
                    '${digest.messageCount}개 메시지',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // 섹션 1: 주제 키워드 — Chip으로 가로 나열
          if (report.keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: report.keywords
                    .map((keyword) => Chip(
                          label: Text(
                            keyword,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer,
                            ),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          side: BorderSide.none,
                        ))
                    .toList(),
              ),
            ),
          ],

          // 섹션 2: 대화 주요 내용 — MarkdownBody 렌더링
          if (report.mainContent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '대화 주요 내용',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    _buildMarkdownBody(context, report.mainContent),
                  ],
                ),
              ),
            ),
          ],

          // 섹션 3: 핵심 정보 — 주제별 ExpansionTile (기본 접힘)
          if (report.keyInfoTopics.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, top: 16, bottom: 4),
                    child: Text(
                      '핵심 정보',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                  // 주제별 ExpansionTile — 탭하면 펼침
                  ...report.keyInfoTopics.map(
                    (topic) => ExpansionTile(
                      // 기본 접힘 상태
                      initiallyExpanded: false,
                      title: Text(
                        topic.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      // 펼쳤을 때 표시할 마크다운 내용
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 16, bottom: 16),
                          child:
                              _buildMarkdownBody(context, topic.markdown),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 섹션 4: 톡비서 제안 — 주제별 Card
          if (report.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '톡비서 제안',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            // 주제별 Card — 큰 제목 + 마크다운 본문
            ...report.suggestions.map(
              (topic) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  // 약간의 강조 효과를 위해 elevation 높임
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 주제명 — 큰 글씨 + 볼드
                        Text(
                          topic.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        // 학습 로드맵 마크다운 (URL, 영상 포함)
                        _buildMarkdownBody(context, topic.markdown),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 공통 MarkdownBody 위젯 빌더
  /// 앱 테마에 맞는 스타일시트 + URL 클릭 핸들러 포함
  Widget _buildMarkdownBody(BuildContext context, String data) {
    return MarkdownBody(
      data: data,
      selectable: true,
      // URL 클릭 시 브라우저에서 열기
      onTapLink: (text, href, title) {
        if (href != null) {
          launchUrl(
            Uri.parse(href),
            mode: LaunchMode.externalApplication,
          );
        }
      },
      // 마크다운 스타일을 앱 테마에 맞춤
      styleSheet: MarkdownStyleSheet(
        // ### 소섹션 제목 (파싱 후 남아있는 경우)
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              height: 2.0,
            ),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
        // 본문 텍스트
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
        // 리스트 항목
        listBullet: Theme.of(context).textTheme.bodyMedium,
        listIndent: 16,
        // 링크 스타일
        a: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        // 인용문 (> 학습 목표나 팁)
        blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        blockquotePadding:
            const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        // 코드 (인라인 백틱)
        code: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
        // 굵은 텍스트
        strong: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
