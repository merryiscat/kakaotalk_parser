import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/digest_provider.dart';

class DigestScreen extends ConsumerStatefulWidget {
  final DateTime date;
  final String roomName;

  const DigestScreen({super.key, required this.date, required this.roomName});

  @override
  ConsumerState<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends ConsumerState<DigestScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(digestProvider.notifier).generateDigest(widget.date);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy년 M월 d일 (E)', 'ko');
    final state = ref.watch(digestProvider);
    final digest = state.digests[widget.date];
    final isLoading = state.loadingDates.contains(widget.date);
    final error = state.errors[widget.date];

    return Scaffold(
      appBar: AppBar(title: Text(dateFormat.format(widget.date))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(context, digest?.summary, digest?.topics, isLoading, error),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String? summary,
    List<String>? topics,
    bool isLoading,
    String? error,
  ) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('AI가 대화를 요약하고 있습니다...'),
          ],
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(digestProvider.notifier).generateDigest(widget.date),
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (summary == null) {
      return const Center(child: Text('요약을 생성할 수 없습니다.'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topics != null && topics.isNotEmpty) ...[
            Text('주요 주제', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: topics.map((t) => Chip(label: Text(t))).toList(),
            ),
            const SizedBox(height: 24),
          ],
          Text('요약', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                summary,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
