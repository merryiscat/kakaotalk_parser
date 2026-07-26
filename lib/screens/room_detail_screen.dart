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
            : () => _pickDatesAndUpload(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('파일 업로드'),
      ),
    );
  }

  /// 파일을 먼저 선택·파싱한 뒤, 파일에 실제로 있는 날짜 목록을
  /// 체크박스 바텀시트로 보여주고 사용자가 고른 날짜만 요약한다.
  /// - 이미 요약된 날짜는 "요약됨" 표시 (다시 선택하면 재요약·덮어쓰기)
  /// - 기본 선택: 아직 요약되지 않은 날짜 전부
  Future<void> _pickDatesAndUpload(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(digestProvider.notifier);

    // 1단계: 파일 선택 + 파싱 (취소하거나 파싱 실패하면 null)
    final upload = await notifier.pickAndParse();
    if (upload == null || !context.mounted) return;

    // 요약 가능한 과거 날짜가 하나도 없는 경우 안내
    if (upload.selectableDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('요약할 과거 날짜가 없습니다. (오늘 대화는 내일 요약할 수 있어요)'),
        ),
      );
      return;
    }

    // 이미 요약된 날짜 집합 ("요약됨" 뱃지 표시용)
    final digestedDates = <DateTime>{
      for (final d in upload.selectableDates)
        if (notifier.isDigested(roomName, d)) d,
    };

    // 기본 선택: 아직 요약되지 않은 날짜 전부
    final selected = upload.selectableDates
        .where((d) => !digestedDates.contains(d))
        .toSet();

    // 2단계: 날짜 선택 바텀시트 (확정 시 선택된 날짜 Set 반환, 닫으면 null)
    final confirmed =
        await _showDateSelectSheet(context, upload, selected, digestedDates);
    if (confirmed == null || confirmed.isEmpty) return;

    // 3단계: 선택한 날짜만 요약 시작
    await notifier.digestDates(roomName, upload, confirmed.toList());
  }

  /// 날짜 선택 바텀시트 — 파일에 있는 날짜를 체크박스 리스트로 표시
  Future<Set<DateTime>?> _showDateSelectSheet(
    BuildContext context,
    ParsedUpload upload,
    Set<DateTime> initialSelected,
    Set<DateTime> digestedDates,
  ) {
    final dateFormat = DateFormat('M월 d일 (E)', 'ko');
    // 최신 날짜가 위로 오도록 내림차순 표시 (요약 자체는 오래된 날짜부터 진행)
    final dates = upload.selectableDates.reversed.toList();

    return showModalBottomSheet<Set<DateTime>>(
      context: context,
      showDragHandle: true,
      // 날짜가 많을 수 있으므로 화면 높이의 최대 70%까지 사용
      isScrollControlled: true,
      builder: (ctx) {
        final selected = Set<DateTime>.from(initialSelected);
        // 체크박스 상태 변경 시 바텀시트만 다시 그리기 위한 StatefulBuilder
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final allSelected = selected.length == dates.length;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 헤더: 제목 + 전체 선택/해제 버튼
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                      child: Row(
                        children: [
                          Text(
                            '요약할 날짜 선택',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setSheetState(() {
                              // 전부 선택돼 있으면 해제, 아니면 전체 선택
                              if (allSelected) {
                                selected.clear();
                              } else {
                                selected.addAll(dates);
                              }
                            }),
                            child: Text(allSelected ? '전체 해제' : '전체 선택'),
                          ),
                        ],
                      ),
                    ),
                    // 날짜 체크박스 리스트 (스크롤 가능)
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: dates.length,
                        itemBuilder: (_, i) {
                          final date = dates[i];
                          final messageCount = upload.grouped[date]!.length;
                          final digested = digestedDates.contains(date);
                          return CheckboxListTile(
                            value: selected.contains(date),
                            onChanged: (checked) => setSheetState(() {
                              if (checked == true) {
                                selected.add(date);
                              } else {
                                selected.remove(date);
                              }
                            }),
                            title: Row(
                              children: [
                                Text(dateFormat.format(date)),
                                // 이미 요약된 날짜 표시 (선택하면 재요약)
                                if (digested) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '요약됨',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text('$messageCount개 메시지'),
                            dense: true,
                          );
                        },
                      ),
                    ),
                    // 하단 확정 버튼 — 선택 개수 표시, 0개면 비활성화
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, selected),
                        child: Text(
                          selected.isEmpty
                              ? '날짜를 선택하세요'
                              : '${selected.length}개 날짜 요약 시작',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
