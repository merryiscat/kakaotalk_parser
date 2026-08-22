import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/daily_digest.dart';
import '../theme.dart';
import '../utils/report_parser.dart';
import 'shared_widgets.dart';

/// AI 요약 상세 화면 — 앱의 핵심 화면
/// 특정 날짜의 이미 완료된 요약 목록을 표시합니다.
/// LLM 호출 없이 기존 데이터만 렌더링합니다.
///
/// ── 정보 위계 (디자인 리뉴얼 기준) ──
/// 위에서부터 "행동을 유발하는 순서"로 배치합니다:
/// 0. 헤더        → 앱바로 흡수 (Card 제거)
/// 1. 주제 키워드 → 스캔 진입점. 허니 칩, 섹션 아님
/// 2. 톡비서 제안 → 유일한 행동 유발 섹션. 맨 위 + Card(규칙 ④) + 좌측 마커
/// 3. 핵심 정보   → 깊게 파는 사람만. 1px 보더(규칙 ③) + 접힘 + 미리보기 1줄
/// 4. 대화 주요 내용 → 맥락. 컨테이너 없이 본문만(규칙 ①)
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
    final dateFormat = DateFormat('M월 d일 (E)', 'ko');
    // 방이 1개면 앱바 제목을 방 이름으로 (헤더 Card를 앱바로 흡수)
    final singleRoom = digests.length == 1 ? digests.first : null;

    return Scaffold(
      appBar: AppBar(
        title: singleRoom != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    singleRoom.roomName,
                    style: const TextStyle(fontSize: 19),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${dateFormat.format(date)} · ${singleRoom.messageCount}개 메시지 분석',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              )
            : Text(dateFormat.format(date)),
      ),
      body: digests.isEmpty
          ? const Center(child: Text('요약 데이터가 없습니다.'))
          : ListView.builder(
              // 하단에 시스템 네비게이션 바 높이만큼 여유 공간 확보
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 24 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: digests.length,
              itemBuilder: (context, index) {
                final digest = digests[index];
                return _buildDigestBody(
                  context,
                  digest,
                  // 방이 여러 개면(달력 진입) 방 이름 헤더를 본문에 표시
                  showRoomHeader: singleRoom == null,
                );
              },
            ),
    );
  }

  /// 리포트 본문 — 파싱한 4개 섹션을 위계 순서대로 렌더링
  Widget _buildDigestBody(
    BuildContext context,
    DailyDigest digest, {
    required bool showRoomHeader,
  }) {
    final report = parseReport(digest.summary);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 방 이름 헤더 (달력에서 여러 방을 볼 때만) — Card 없이 여백만
          if (showRoomHeader) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(digest.roomName, style: text.titleLarge),
                ),
                Text(
                  '${digest.messageCount}개 메시지',
                  style: text.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── 1. 주제 키워드: 허니 칩. 섹션 제목 없이 스캔 진입점 역할 ──
          if (report.keywords.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: report.keywords
                  .map((keyword) => Chip(label: Text(keyword)))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          // ── 2. 톡비서 제안: 유일한 행동 유발 섹션 → 맨 위 ──
          if (report.suggestions.isNotEmpty) ...[
            Row(
              children: [
                const TokbiseoMark(size: 22),
                const SizedBox(width: 8),
                Text('톡비서 제안', style: text.headlineSmall),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '오늘 이것만 보면 됩니다',
                    style: text.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...report.suggestions.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SuggestionCard(
                      rank: entry.key + 1,
                      topic: entry.value,
                      markdownBuilder: _buildMarkdownBody,
                    ),
                  ),
                ),
            const SizedBox(height: 16),
          ],

          // ── 3. 핵심 정보: 1px 보더 + 접힘 + 미리보기 1줄 ──
          if (report.keyInfoTopics.isNotEmpty) ...[
            Text('핵심 정보', style: text.titleLarge),
            const SizedBox(height: 12),
            ...report.keyInfoTopics.map(
              (topic) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _KeyInfoTile(
                  topic: topic,
                  markdownBuilder: _buildMarkdownBody,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── 4. 대화 주요 내용: 컨테이너 없이 본문만 (규칙 ①) ──
          if (report.mainContent.isNotEmpty) ...[
            Text('대화 주요 내용', style: text.titleLarge),
            const SizedBox(height: 10),
            _buildMarkdownBody(context, report.mainContent),
          ],
        ],
      ),
    );
  }

  /// 공통 MarkdownBody 위젯 빌더
  /// 앱 테마에 맞는 스타일시트 + URL 클릭 핸들러 포함
  Widget _buildMarkdownBody(BuildContext context, String data) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return MarkdownBody(
      data: data,
      selectable: true,
      // URL 클릭 시 브라우저에서 열기
      onTapLink: (linkText, href, title) {
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
        h3: text.titleSmall?.copyWith(height: 2.0),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
        // 본문 텍스트 — 긴 리포트를 읽는 스타일 (Pretendard 16/1.75)
        p: text.bodyLarge,
        // 리스트 항목
        listBullet: text.bodyLarge,
        listIndent: 18,
        // 링크 스타일
        a: TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary.withValues(alpha: 0.4),
        ),
        // 인용문 (> 학습 목표나 팁) — 배경색 블록(규칙 ②)
        // 주의: BoxDecoration에서 한쪽 보더 + borderRadius를 같이 쓰면
        // Flutter가 페인트 예외를 던지므로 배경색 + 라운딩만 사용합니다.
        blockquote: text.bodyMedium,
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        blockquotePadding: const EdgeInsets.all(12),
        // 코드 (인라인 백틱) — 배경색 구분
        code: text.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          fontSize: 13.5,
          backgroundColor: scheme.surfaceContainerHigh,
        ),
        // 굵은 텍스트
        strong: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 제안 카드 — Card(규칙 ④) + 좌측 4px 순위 마커
///
/// 1순위만 허니 마커 + 허니 배지로 강조, 나머지는 회색 마커.
/// "무엇부터 볼지"를 시각적 무게로 안내하는 장치입니다.
class _SuggestionCard extends StatelessWidget {
  final int rank;
  final TopicSection topic;
  final Widget Function(BuildContext, String) markdownBuilder;

  const _SuggestionCard({
    required this.rank,
    required this.topic,
    required this.markdownBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isTop = rank == 1;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        // 좌측 4px 마커 — 1순위는 허니, 나머지는 회색
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isTop ? scheme.tertiary : scheme.outlineVariant,
              width: 4,
            ),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 순위 배지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isTop ? scheme.tertiaryContainer : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$rank순위',
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isTop
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 주제명 — 주아체 제목
            Text(
              topic.title,
              style: text.titleLarge?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 8),
            // 학습 로드맵 마크다운 (URL, 영상 포함)
            markdownBuilder(context, topic.markdown),
          ],
        ),
      ),
    );
  }
}

/// 핵심 정보 접힘 카드 — 1px 보더(규칙 ③) + 접힘 상태 미리보기 1줄
///
/// 접힌 상태에서도 무슨 내용인지 1줄로 보여줘서,
/// 스크롤하며 훑어볼 때 "펼칠 가치가 있는지" 판단할 수 있게 합니다.
class _KeyInfoTile extends StatelessWidget {
  final TopicSection topic;
  final Widget Function(BuildContext, String) markdownBuilder;

  const _KeyInfoTile({
    required this.topic,
    required this.markdownBuilder,
  });

  /// 마크다운 문법을 걷어낸 미리보기 1줄
  String get _preview => topic.markdown
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\*{1,2}([^*]+)\*{1,2}'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^[-*>]\s+', multiLine: true), '')
      .replaceAll('\n', ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: outlinedBox(context),
      clipBehavior: Clip.antiAlias,
      // Card 사용 금지 (중첩 방지) — 보더 컨테이너 + ExpansionTile 조합
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          topic.title,
          style: text.titleSmall?.copyWith(fontSize: 15.5),
        ),
        // 접힘 상태 미리보기 1줄
        subtitle: Text(
          _preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          // 펼침 영역 — 배경색으로 살짝 구분 (규칙 ②)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.all(16),
            child: markdownBuilder(context, topic.markdown),
          ),
        ],
      ),
    );
  }
}
