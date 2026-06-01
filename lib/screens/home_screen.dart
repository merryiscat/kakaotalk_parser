import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';
import 'room_detail_screen.dart';
import 'shared_widgets.dart';

/// 홈 화면 — 단톡방 리스트
///
/// 방 이름을 먼저 만들고, 방 안에서 txt 파일을 업로드하는 2단계 플로우.
/// (파일 업로드 기능은 [RoomDetailScreen]에 있습니다.
///  file_picker 패키지를 사용해서 기기의 파일을 선택합니다.)
///
/// [ConsumerWidget]은 Riverpod의 위젯으로, 일반 StatelessWidget과 비슷하지만
/// ref.watch()로 상태를 구독할 수 있습니다.
/// 상태가 바뀌면 Flutter가 이 위젯의 build()를 자동으로 다시 호출해서 화면을 갱신합니다.
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
  ///
  /// [ListView.builder]를 사용해서 방 목록을 카드 형태로 보여줍니다.
  /// ListView.builder는 화면에 보이는 항목만 그리기 때문에,
  /// 방이 아무리 많아도 성능 문제가 없습니다. (일반 Column + for문과의 차이)
  ///
  /// [roomDigestsProvider(roomName)]은 "family" 패턴입니다.
  /// 하나의 Provider가 roomName이라는 인자를 받아서
  /// 방마다 서로 다른 데이터를 제공합니다.
  /// 예: roomDigestsProvider("가족방") → 가족방 요약 목록
  ///     roomDigestsProvider("회사방") → 회사방 요약 목록
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
          DigestErrorBanner(errorMessage: digestState.error!),
        // 처리 중 진행률 표시
        if (digestState.isProcessing)
          DigestProgressBar(digestState: digestState),
        // 채팅방 카드 리스트
        // Expanded: 남은 공간을 전부 차지하라는 의미.
        // Column 안에서 ListView를 쓸 때 반드시 Expanded로 감싸야 합니다.
        // (안 그러면 "무한 높이" 오류 발생)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: roomNames.length,
            // itemBuilder: 각 항목을 어떻게 그릴지 정의하는 콜백 함수.
            // index는 0부터 시작하는 순번입니다.
            itemBuilder: (context, index) {
              final roomName = roomNames[index];
              // 해당 방의 요약 목록에서 날짜 수, 총 메시지 수 계산
              // ref.watch()로 구독하면, 요약 데이터가 바뀔 때 이 카드가 자동으로 다시 그려집니다.
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
                          // ──────────────────────────────────────────
                          // 더보기 메뉴 (이름 수정 / 삭제)
                          //
                          // PopupMenuButton: 점 세 개(⋮) 아이콘을 누르면
                          // 아래로 펼쳐지는 드롭다운 메뉴를 만듭니다.
                          //
                          // "길게 누르기(long press)"로 메뉴를 여는 방법도 있지만,
                          // 길게 누르기는 사용자가 기능이 있는지 모를 수 있습니다.
                          // 눈에 보이는 아이콘 버튼이 더 직관적이라 이 방식을 선택했습니다.
                          //
                          // <String> 제네릭: 각 메뉴 항목의 value 타입을 String으로 지정.
                          // onSelected에서 어떤 메뉴가 선택됐는지 value로 구분합니다.
                          // ──────────────────────────────────────────
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'rename') {
                                _showRenameDialog(context, ref, roomName);
                              } else if (value == 'delete') {
                                _showDeleteDialog(context, ref, roomName);
                              }
                            },
                            // itemBuilder: 메뉴에 들어갈 항목 목록을 정의합니다.
                            // 각 PopupMenuItem의 value가 onSelected로 전달됩니다.
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
  ///
  /// [showDialog]는 화면 위에 팝업(다이얼로그)을 띄우는 Flutter 내장 함수입니다.
  /// [AlertDialog]는 그 팝업의 모양(제목, 내용, 버튼)을 정의합니다.
  void _showAddRoomDialog(BuildContext context, WidgetRef ref) {
    // TextEditingController: 텍스트 입력칸의 값을 읽고 쓸 수 있는 컨트롤러.
    // 버튼 클릭 시 controller.text로 현재 입력값을 가져옵니다.
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
          // ──────────────────────────────────────────────
          // onSubmitted: 키보드에서 "엔터(완료)" 키를 눌렀을 때 호출됩니다.
          // 아래 FilledButton의 onPressed와 같은 로직을 씁니다.
          //
          // 왜 같은 코드가 두 곳에 있을까?
          // → 사용자에 따라 "엔터키로 바로 추가"하는 사람도 있고,
          //   "추가 버튼을 탭"하는 사람도 있기 때문입니다.
          //   두 방식 모두 지원해야 편리한 UX가 됩니다.
          // ──────────────────────────────────────────────
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) {
              ref.read(digestProvider.notifier).addRoom(name);
              Navigator.pop(context); // 다이얼로그 닫기
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          // FilledButton: Material 3 스타일의 채워진 버튼.
          // onPressed 안의 로직은 위 onSubmitted와 동일합니다.
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(digestProvider.notifier).addRoom(name);
                Navigator.pop(context); // 다이얼로그 닫기
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  /// 방 이름 수정 다이얼로그
  ///
  /// _showAddRoomDialog와 구조가 거의 같지만 두 가지가 다릅니다:
  /// 1. TextEditingController에 기존 이름(oldName)을 미리 넣어둡니다.
  ///    → 사용자가 처음부터 다시 입력할 필요 없이 일부만 수정 가능.
  /// 2. 저장 시 addRoom 대신 renameRoom을 호출합니다.
  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String oldName,
  ) {
    // text: oldName → 입력칸에 기존 방 이름이 미리 채워져 있습니다.
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
  ///
  /// 삭제는 되돌릴 수 없는 위험한 작업이므로,
  /// 바로 삭제하지 않고 "정말 삭제하시겠습니까?" 확인 단계를 거칩니다.
  /// 이것은 UX 설계에서 매우 중요한 패턴입니다.
  /// (실수로 삭제 버튼을 눌렀을 때 데이터를 잃지 않도록 보호)
  ///
  /// 참고: _showAddRoomDialog나 _showRenameDialog와 달리
  /// 여기에는 TextField가 없습니다. 단순히 "예/아니오"만 묻는 구조입니다.
  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    String roomName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단톡방 삭제'),
        // 어떤 방을 삭제하는지 이름을 보여줘야 사용자가 확인할 수 있습니다.
        content: Text('"$roomName"의 모든 요약을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              // removeRoom: 해당 방과 모든 요약 데이터를 삭제합니다.
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
