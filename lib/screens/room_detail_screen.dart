import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/daily_digest.dart';
import '../providers/digest_provider.dart';
import 'digest_screen.dart';

/// 방 상세 화면 — 특정 채팅방의 날짜별 요약을 세로 타임라인으로 표시
/// 요약이 없으면 파일 업로드 안내, FAB로 txt 파일 업로드 가능
class RoomDetailScreen extends ConsumerWidget {
  final String roomName;

  const RoomDetailScreen({super.key, required this.roomName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 해당 방의 요약 리스트 (최신순 정렬됨)
    final digests = ref.watch(roomDigestsProvider(roomName));
    final digestState = ref.watch(digestProvider);
    final dateFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko');

    return Scaffold(
      appBar: AppBar(
        title: Text(roomName),
      ),
      body: _buildBody(context, ref, digests, digestState, dateFormat),
      // txt 파일 업로드 FAB
      floatingActionButton: FloatingActionButton.extended(
        // 처리 중이면 비활성화
        onPressed: digestState.isProcessing
            ? null
            : () => ref.read(digestProvider.notifier).uploadAndDigest(roomName),
        icon: const Icon(Icons.upload_file),
        label: const Text('파일 업로드'),
      ),
    );
  }

  /// 본문 영역: 빈 상태 / 처리 중 / 요약 리스트
  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<DailyDigest> digests,
    DigestState digestState,
    DateFormat dateFormat,
  ) {
    return Column(
      children: [
        // 처리 중 진행률 표시
        if (digestState.isProcessing) ...[
          const LinearProgressIndicator(),
          if (digestState.processingProgress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '요약 중... ${digestState.processingProgress!.$1}/${digestState.processingProgress!.$2}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
        // 에러 메시지
        if (digestState.error != null)
          MaterialBanner(
            content: Text(digestState.error!),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(digestProvider.notifier).clearError(),
                child: const Text('닫기'),
              ),
            ],
          ),
        // 요약이 없으면 빈 상태, 있으면 리스트
        Expanded(
          child: digests.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: digests.length,
                  itemBuilder: (context, index) {
                    final digest = digests[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDateCard(context, dateFormat, digest),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 요약이 없을 때 보여주는 빈 화면
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.upload_file,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '아직 대화 파일이 없습니다',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '하단 버튼으로 카카오톡 내보내기 .txt 파일을\n업로드하면 AI 요약이 생성됩니다',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 마크다운 문법을 제거하여 미리보기용 플레인 텍스트로 변환
  static String _stripMarkdown(String md) {
    return md
        // 헤더 제거: ## 제목 → 제목
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        // 마크다운 링크: [텍스트](url) → 텍스트
        .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
        // 볼드/이탤릭 제거: **텍스트** → 텍스트
        .replaceAllMapped(
            RegExp(r'\*{1,2}([^*]+)\*{1,2}'), (m) => m.group(1)!)
        // 리스트 마커 제거: - 항목 → 항목
        .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '')
        // 연속 빈 줄 정리
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  /// 날짜별 카드 위젯
  Widget _buildDateCard(
    BuildContext context,
    DateFormat dateFormat,
    DailyDigest digest,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 탭하면 상세 요약 화면으로 이동 (해당 날짜의 이 방 요약 1개를 리스트로)
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DigestScreen(
              date: digest.date,
              digests: [digest],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 날짜 헤더 + 메시지 수
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateFormat.format(digest.date),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${digest.messageCount}개 메시지',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 주제 칩
              if (digest.topics.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  // 보색 액센트: 골든 옐로우 배경의 토픽 칩
                  children: digest.topics
                      .take(3)
                      .map((t) => Chip(
                            label: Text(t,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onTertiaryContainer,
                              ),
                            ),
                            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
              ],
              // 요약 미리보기 (마크다운 문법 제거, 최대 3줄)
              Text(
                _stripMarkdown(digest.summary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
