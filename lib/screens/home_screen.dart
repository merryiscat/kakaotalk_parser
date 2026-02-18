import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';
import 'room_detail_screen.dart';

/// 홈 화면 — 단톡방 리스트
/// 방 이름을 먼저 만들고, 방 안에서 txt 파일을 업로드하는 2단계 플로우
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digestState = ref.watch(digestProvider);
    final roomNames = ref.watch(roomNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('톡비서'),
      ),
      body: _buildBody(context, ref, digestState, roomNames),
      // 단톡방 추가 FAB (방이 1개 이상일 때만 표시)
      floatingActionButton: roomNames.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddRoomDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('단톡방 추가'),
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    DigestState digestState,
    List<String> roomNames,
  ) {
    // 방이 없는 경우 → 빈 상태 + 방 만들기 버튼
    if (roomNames.isEmpty) {
      return _buildEmptyState(context, ref, digestState.error);
    }

    // 방이 있는 경우 → 단톡방 카드 리스트
    return _buildRoomList(context, ref, digestState, roomNames);
  }

  /// 방이 없을 때 보여주는 빈 화면
  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    String? error,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            '단톡방을 추가해보세요',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '방을 만든 뒤 카카오톡 대화 파일을 불러올 수 있어요',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          // 에러 메시지가 있으면 표시
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _showAddRoomDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('단톡방 추가'),
          ),
        ],
      ),
    );
  }

  /// 단톡방 카드 리스트
  Widget _buildRoomList(
    BuildContext context,
    WidgetRef ref,
    DigestState digestState,
    List<String> roomNames,
  ) {
    return Column(
      children: [
        // 에러 메시지 배너
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
        // 채팅방 카드 리스트
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: roomNames.length,
            itemBuilder: (context, index) {
              final roomName = roomNames[index];
              // 해당 방의 요약 목록에서 날짜 수, 총 메시지 수 계산
              final roomDigests = ref.watch(roomDigestsProvider(roomName));
              final dateCount = roomDigests.length;
              final totalMessages = roomDigests.fold<int>(
                0,
                (sum, d) => sum + d.messageCount,
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    // 탭 → 방 상세 화면으로 이동
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RoomDetailScreen(roomName: roomName),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          // 채팅방 아이콘
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.chat,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 채팅방 이름 + 요약 날짜 수 + 메시지 수
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roomName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dateCount > 0
                                      ? '$dateCount일 요약 완료 · $totalMessages개 메시지'
                                      : '아직 대화 파일이 없습니다',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          // 더보기 메뉴 (이름 수정 / 삭제)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'rename') {
                                _showRenameDialog(context, ref, roomName);
                              } else if (value == 'delete') {
                                _showDeleteDialog(context, ref, roomName);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text('이름 수정'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20),
                                    SizedBox(width: 8),
                                    Text('삭제'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 방 추가 다이얼로그 — 이름을 입력받아 빈 방 생성
  void _showAddRoomDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단톡방 추가'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '채팅방 이름을 입력하세요',
            border: OutlineInputBorder(),
          ),
          // 엔터키로 바로 추가
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              ref.read(digestProvider.notifier).addRoom(name);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(digestProvider.notifier).addRoom(name);
                Navigator.pop(context);
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  /// 방 이름 수정 다이얼로그
  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String oldName,
  ) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '새 이름을 입력하세요',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final newName = value.trim();
            if (newName.isNotEmpty && newName != oldName) {
              ref.read(digestProvider.notifier).renameRoom(oldName, newName);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                ref.read(digestProvider.notifier).renameRoom(oldName, newName);
                Navigator.pop(context);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  /// 채팅방 삭제 확인 다이얼로그
  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String roomName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단톡방 삭제'),
        content: Text('"$roomName"의 모든 요약을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(digestProvider.notifier).removeRoom(roomName);
              Navigator.pop(context);
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}
