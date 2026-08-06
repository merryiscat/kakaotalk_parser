import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/publish_api_service.dart';
import 'settings_provider.dart';

/// 발행 화면 상태
///
/// - 목록 로딩 / 발행 진행 / 에러를 모두 하나의 상태로 관리합니다.
/// - 발행은 티스토리 1일 발행 수 제한 때문에 한 번에 한 건씩만 진행합니다
///   (publishingPageId가 null이 아니면 다른 발행 버튼은 비활성화).
class PublishState {
  /// 발행 대기 목록을 불러오는 중인지
  final bool isLoading;

  /// 발행 대기(발행상태="초안") 페이지 목록
  final List<PendingPage> pages;

  /// 현재 발행 진행 중인 페이지 ID (없으면 null)
  final String? publishingPageId;

  /// 마지막으로 발행 성공한 글 URL (스낵바 표시용)
  final String? lastPublishedUrl;

  /// 에러 메시지 (없으면 null)
  final String? error;

  const PublishState({
    this.isLoading = false,
    this.pages = const [],
    this.publishingPageId,
    this.lastPublishedUrl,
    this.error,
  });

  PublishState copyWith({
    bool? isLoading,
    List<PendingPage>? pages,
    // null로 되돌릴 수 있어야 하는 필드는 별도 플래그로 처리
    String? publishingPageId,
    bool clearPublishing = false,
    String? lastPublishedUrl,
    String? error,
    bool clearError = false,
  }) {
    return PublishState(
      isLoading: isLoading ?? this.isLoading,
      pages: pages ?? this.pages,
      publishingPageId: clearPublishing
          ? null
          : (publishingPageId ?? this.publishingPageId),
      lastPublishedUrl: lastPublishedUrl ?? this.lastPublishedUrl,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PublishNotifier extends Notifier<PublishState> {
  @override
  PublishState build() => const PublishState();

  /// 설정의 서버 URL로 API 서비스를 만듭니다.
  ///
  /// 서버 URL이 비어있으면 null — 발행 기능은 멀티에이전트 서버 필수.
  Future<PublishApiService?> _service() async {
    // SharedPreferences 로딩이 끝나기 전에 접근하는 race condition 방지
    await ref.read(settingsProvider.notifier).ensureLoaded();
    final settings = ref.read(settingsProvider);
    final serverUrl = settings.serverUrl.trim();
    if (serverUrl.isEmpty) return null;
    return PublishApiService(
      serverUrl: serverUrl,
      serverApiKey: settings.serverApiKey.trim(),
    );
  }

  /// 발행 대기 목록을 새로 불러옵니다 (화면 진입·새로고침 시).
  Future<void> loadPending() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = await _service();
      if (service == null) {
        state = state.copyWith(
          isLoading: false,
          error: '설정에서 멀티에이전트 서버 URL을 먼저 입력해 주세요.',
        );
        return;
      }
      final pages = await service.fetchPending();
      state = state.copyWith(isLoading: false, pages: pages);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '목록 조회 실패: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  /// 페이지 본문 마크다운을 가져옵니다 (미리보기 시트용).
  ///
  /// 상태를 바꾸지 않고 결과만 반환 — 실패하면 예외를 던집니다.
  Future<String> fetchPreview(String pageId) async {
    final service = await _service();
    if (service == null) {
      throw Exception('서버 URL이 설정되지 않았습니다.');
    }
    return service.fetchPageMarkdown(pageId);
  }

  /// 페이지 한 건을 티스토리에 발행합니다.
  ///
  /// 성공하면 목록에서 해당 페이지를 제거하고 발행 URL을 상태에 남깁니다.
  /// (서버가 Notion 발행상태를 "발행완료"로 바꾸므로 다시 조회해도 안 나타남)
  Future<bool> publish(String pageId) async {
    // 이미 다른 발행이 진행 중이면 무시 (버튼이 비활성화되지만 이중 방어)
    if (state.publishingPageId != null) return false;

    state = state.copyWith(publishingPageId: pageId, clearError: true);
    try {
      final service = await _service();
      if (service == null) {
        throw Exception('서버 URL이 설정되지 않았습니다.');
      }
      final url = await service.publish(pageId);

      // 발행된 페이지를 목록에서 제거
      state = state.copyWith(
        pages: state.pages.where((p) => p.pageId != pageId).toList(),
        clearPublishing: true,
        lastPublishedUrl: url,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        clearPublishing: true,
        error: '발행 실패: ${e.toString().replaceFirst('Exception: ', '')}',
      );
      return false;
    }
  }

  /// 에러 배너 닫기
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final publishProvider = NotifierProvider<PublishNotifier, PublishState>(
  PublishNotifier.new,
);
