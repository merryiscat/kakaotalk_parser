import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/daily_digest.dart';

/// AI 요약 상세 화면
/// 특정 날짜의 이미 완료된 요약 목록을 표시합니다.
/// LLM 호출 없이 기존 데이터만 렌더링합니다.
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
              padding: const EdgeInsets.all(16),
              itemCount: digests.length,
              itemBuilder: (context, index) {
                final digest = digests[index];
                return _buildDigestCard(context, digest);
              },
            ),
    );
  }

  /// 개별 요약 카드 위젯
  Widget _buildDigestCard(BuildContext context, DailyDigest digest) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 채팅방 이름 + 메시지 수
              Row(
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

              // 주요 주제 칩
              if (digest.topics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('주요 주제',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: digest.topics
                      .map((t) => Chip(
                            label: Text(t,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onTertiaryContainer,
                              ),
                            ),
                            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
              ],

              // 요약 본문 — 마크다운 렌더링 + URL 클릭 가능
              const SizedBox(height: 12),
              MarkdownBody(
                data: digest.summary,
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
                  h2: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  p: Theme.of(context).textTheme.bodyLarge,
                  listBullet: Theme.of(context).textTheme.bodyLarge,
                  a: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
