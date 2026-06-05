import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/daily_digest.dart';
import '../providers/digest_provider.dart';
import 'digest_screen.dart';
import 'shared_widgets.dart';

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
            : () => _pickRangeAndUpload(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('파일 업로드'),
      ),
    );
  }

  /// 파일 업로드 전, 요약할 기간을 먼저 고르는 바텀시트를 띄운다.
  /// 사용자가 기간을 선택하면 그 범위(sinceDays)로 업로드·요약을 시작.
  /// (전체 선택 시 sinceDays = null → 파일에 있는 모든 과거 날짜 요약)
  Future<void> _pickRangeAndUpload(BuildContext context, WidgetRef ref) async {
    // 선택지: 라벨 + sinceDays(요약할 최근 일수). 전체는 null.
    const options = <(String, int?)>[
      ('최근 3일', 3),
      ('최근 일주일', 7),
      ('최근 2주일', 14),
      ('최근 한 달', 30),
      ('전체 (없는 날짜 모두)', null),
    ];

    // 사용자가 고른 sinceDays를 돌려받음. 바텀시트를 그냥 닫으면 null이 아닌
    // "미선택"이므로, 선택 여부를 구분하기 위해 별도 플래그 대신 결과 객체로 처리.
    final selected = await showModalBottomSheet<(bool, int?)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  '요약할 기간 선택',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              // 각 기간 옵션을 ListTile로 나열 (탭하면 그 값으로 닫힘)
              for (final (label, days) in options)
                ListTile(
                  leading: Icon(
                    days == null ? Icons.all_inclusive : Icons.calendar_today,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  title: Text(label),
                  // (선택됨=true, 고른 일수) 형태로 반환
                  onTap: () => Navigator.pop(ctx, (true, days)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    // 사용자가 바깥을 탭해 닫은 경우(미선택)엔 아무 것도 하지 않음
    if (selected == null || !selected.$1) return;

    // 선택한 기간으로 업로드 + 요약 시작
    await ref
        .read(digestProvider.notifier)
        .uploadAndDigest(roomName, sinceDays: selected.$2);
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
        if (digestState.isProcessing)
          DigestProgressBar(digestState: digestState),
        // 에러 메시지
        if (digestState.error != null)
          DigestErrorBanner(errorMessage: digestState.error!),
        // 요약이 없으면 빈 상태, 있으면 리스트
        Expanded(
          child: digests.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  // FAB과 시스템 네비게이션 바에 가려지지 않도록 하단 여유 확보
                  padding: const EdgeInsets.only(
                    left: 16, right: 16, top: 16, bottom: 80,
                  ),
                  itemCount: digests.length,
                  itemBuilder: (context, index) {
                    final digest = digests[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDateCard(context, ref, dateFormat, digest),
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

  /// 개별 요약 삭제 확인 다이얼로그
  void _confirmDeleteDigest(BuildContext context, WidgetRef ref, DailyDigest digest, DateFormat dateFormat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('요약 삭제'),
        content: Text('${dateFormat.format(digest.date)} 요약을 삭제할까요?\n삭제하면 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              // digest.key = "방이름_YYYY-MM-DD" 형태의 고유 키
              ref.read(digestProvider.notifier).deleteDigest(digest.key);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  /// 날짜별 카드 위젯
  Widget _buildDateCard(
    BuildContext context,
    WidgetRef ref,
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
        // 길게 누르면 삭제 확인 다이얼로그
        onLongPress: () => _confirmDeleteDigest(context, ref, digest, dateFormat),
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
