import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/chat_provider.dart';
import 'digest_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('카톡 다이제스트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: chatState.when(
        initial: () => _buildEmptyState(context, ref),
        loading: () => const Center(child: CircularProgressIndicator()),
        loaded: (roomName, dates) => _buildDateList(context, ref, roomName, dates),
        error: (message) => _buildErrorState(context, ref, message),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          const Text('카카오톡 대화 파일을 불러와주세요', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text('내보내기한 .txt 파일을 선택하세요', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => ref.read(chatProvider.notifier).pickAndParse(),
            icon: const Icon(Icons.file_open),
            label: const Text('파일 불러오기'),
          ),
        ],
      ),
    );
  }

  Widget _buildDateList(
    BuildContext context,
    WidgetRef ref,
    String roomName,
    List<DateTime> dates,
  ) {
    final dateFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(roomName, style: Theme.of(context).textTheme.titleMedium),
              Text('${dates.length}일간의 대화', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: dates.length,
            itemBuilder: (context, index) {
              final date = dates[index];
              return ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(dateFormat.format(date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DigestScreen(date: date, roomName: roomName),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(chatProvider.notifier).pickAndParse(),
            icon: const Icon(Icons.file_open),
            label: const Text('다른 파일 불러오기'),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('파싱 오류', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.read(chatProvider.notifier).pickAndParse(),
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
