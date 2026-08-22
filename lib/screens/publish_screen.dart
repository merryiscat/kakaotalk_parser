import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/publish_provider.dart';
import '../services/publish_api_service.dart';
import '../theme.dart';

/// 티스토리 발행 화면 (하단 네비게이션 "발행" 탭)
///
/// 흐름:
/// 1. Notion에 저장된 리포트 중 발행상태="초안"인 목록을 서버에서 조회
/// 2. 카드 탭 → 본문 마크다운 미리보기 (바텀 시트)
/// 3. [발행] 버튼 → 확인 다이얼로그 → 서버가 Playwright로 티스토리 발행
/// 4. 성공 시 목록에서 제거 + 발행 URL 스낵바 표시
///
/// 티스토리 1일 발행 수 제한이 있어 한 번에 한 건씩만 발행합니다.
class PublishScreen extends ConsumerStatefulWidget {
  const PublishScreen({super.key});

  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  @override
  void initState() {
    super.initState();
    // 화면 최초 진입 시 발행 대기 목록 자동 로드
    // (build 중 상태 변경 금지 → 프레임 이후로 미룸)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(publishProvider.notifier).loadPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final publishState = ref.watch(publishProvider);

    // 발행 성공 시 스낵바로 URL 알림 (상태 변화를 감지해서 한 번만 표시)
    ref.listen(publishProvider, (previous, next) {
      final becamePublished = next.lastPublishedUrl != null &&
          previous?.lastPublishedUrl != next.lastPublishedUrl;
      if (becamePublished && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('발행 완료!\n${next.lastPublishedUrl}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('발행'),
            Text(
              '매일 09:00 자동 발행 · 수동은 보조',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          // 수동 새로고침 (발행 대기 목록 다시 조회)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: publishState.isLoading
                ? null
                : () => ref.read(publishProvider.notifier).loadPending(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 에러 배너 (조회/발행 실패 시) — errorContainer 라운드 배너
          if (publishState.error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      publishState.error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(publishProvider.notifier).clearError(),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onErrorContainer,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            ),

          // 발행 진행 중 안내 (Playwright 발행은 수십 초 걸림)
          // primaryContainer 블록 + 얇은 진행바 — 시안의 "발행 중" 배너
          if (publishState.publishingPageId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_upload_outlined,
                          size: 20,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '발행 중… 최대 3분 걸려요',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(),
                  ),
                ],
              ),
            ),

          Expanded(child: _buildBody(publishState)),
        ],
      ),
    );
  }

  /// 본문: 로딩 / 빈 목록 / 페이지 리스트 3가지 상태 표시
  Widget _buildBody(PublishState publishState) {
    if (publishState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (publishState.pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.drafts_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              '발행 대기 중인 리포트가 없어요',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 8),
            Text(
              '요약을 실행하면 "초안"으로 쌓이고,\n매일 09:00에 한 건씩 자동으로 발행됩니다',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    // 당겨서 새로고침 지원
    return RefreshIndicator(
      onRefresh: () => ref.read(publishProvider.notifier).loadPending(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: publishState.pages.length,
        itemBuilder: (context, index) {
          final page = publishState.pages[index];
          return _PendingPageCard(
            page: page,
            // 다른 발행이 진행 중이면 모든 발행 버튼 비활성화 (한 건씩만)
            isPublishing: publishState.publishingPageId == page.pageId,
            publishDisabled: publishState.publishingPageId != null,
            onPreview: () => _showPreview(page),
            onPublish: () => _confirmAndPublish(page),
          );
        },
      ),
    );
  }

  /// 본문 마크다운 미리보기 바텀 시트
  Future<void> _showPreview(PendingPage page) async {
    // 시트를 먼저 띄우고 내용은 비동기 로드 (FutureBuilder)
    final markdownFuture =
        ref.read(publishProvider.notifier).fetchPreview(page.pageId);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                page.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<String>(
                  future: markdownFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('미리보기 로드 실패: ${snapshot.error}'),
                      );
                    }
                    // 마크다운 원문을 그대로 표시 (발행될 내용 확인용)
                    return SingleChildScrollView(
                      controller: scrollController,
                      child: Text(
                        snapshot.data ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 발행 확인 다이얼로그 → 발행 실행
  Future<void> _confirmAndPublish(PendingPage page) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('티스토리 발행'),
        content: Text(
          '"${page.title}"\n\n'
          '이 리포트를 티스토리 블로그에 공개 글로 발행할까요?\n'
          '${page.keywords.isNotEmpty ? "태그: ${page.keywords.join(", ")}" : ""}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('발행'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(publishProvider.notifier).publish(page.pageId);
  }
}

/// 발행 대기 페이지 카드 한 장
///
/// 제목·날짜·키워드 표시 + 미리보기/발행 버튼
class _PendingPageCard extends StatelessWidget {
  final PendingPage page;

  /// 이 카드의 페이지가 지금 발행 중인지 (버튼을 스피너로 교체)
  final bool isPublishing;

  /// 발행 버튼 비활성화 여부 (다른 카드가 발행 중일 때)
  final bool publishDisabled;

  final VoidCallback onPreview;
  final VoidCallback onPublish;

  const _PendingPageCard({
    required this.page,
    required this.isPublishing,
    required this.publishDisabled,
    required this.onPreview,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // 발행 대기 카드 — 탭 가능한 목록이므로 1px 보더(컨테이너 규칙 ③)
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: outlinedBox(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 배지("초안") + 날짜·키워드 메타 한 줄
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '초안',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (page.chatDate.isNotEmpty) page.chatDate,
                    if (page.keywords.isNotEmpty)
                      page.keywords.take(3).join(' · '),
                  ].join(' · '),
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 제목 — 주아체 17
          Text(
            page.title.isEmpty ? '(제목 없음)' : page.title,
            style: const TextStyle(
                fontFamily: 'BMJUA', fontSize: 17, height: 1.35),
          ),
          const SizedBox(height: 12),

          // 하단 버튼 줄: 발행(주 버튼, 넓게) / 미리보기(보조)
          Row(
            children: [
              Expanded(
                child: isPublishing
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FilledButton(
                        onPressed: publishDisabled ? null : onPublish,
                        child: const Text('발행'),
                      ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onPreview,
                child: const Text('미리보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
