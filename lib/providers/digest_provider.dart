import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_digest.dart';
import '../parser/kakaotalk_parser.dart';
import '../providers/settings_provider.dart';
import '../services/llm_service.dart';
import '../services/claude_service.dart';
import '../services/openai_service.dart';
import '../services/gemini_service.dart';
import '../services/url_metadata_service.dart';

/// ──────────────────────────────────────────────
/// 통합 다이제스트 상태
/// 파싱 + 요약이 하나의 파이프라인으로 동작
/// ──────────────────────────────────────────────
class DigestState {
  /// 방 이름 목록 (빈 방도 포함, source of truth)
  final List<String> roomNames;

  /// "방이름_YYYY-MM-DD" → 요약 결과 (앱의 핵심 저장소)
  final Map<String, DailyDigest> digests;

  /// 업로드+요약이 진행 중인지 여부
  final bool isProcessing;

  /// 현재 진행률: (완료된 수, 전체 수) — null이면 진행 중 아님
  final (int done, int total)? processingProgress;

  /// 에러 메시지 (파일 파싱 실패, API 오류 등)
  final String? error;

  const DigestState({
    this.roomNames = const [],
    this.digests = const {},
    this.isProcessing = false,
    this.processingProgress,
    this.error,
  });

  DigestState copyWith({
    List<String>? roomNames,
    Map<String, DailyDigest>? digests,
    bool? isProcessing,
    (int, int)? processingProgress,
    // null로 설정하려면 clearProgress: true 사용
    bool clearProgress = false,
    String? error,
    // null로 설정하려면 clearError: true 사용
    bool clearError = false,
  }) {
    return DigestState(
      roomNames: roomNames ?? this.roomNames,
      digests: digests ?? this.digests,
      isProcessing: isProcessing ?? this.isProcessing,
      processingProgress:
          clearProgress ? null : (processingProgress ?? this.processingProgress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// ──────────────────────────────────────────────
/// DigestNotifier — 파일 업로드부터 AI 요약까지 원스톱 처리
/// ──────────────────────────────────────────────
class DigestNotifier extends Notifier<DigestState> {
  @override
  DigestState build() => const DigestState();

  /// ── 빈 방 추가: 리스트에 이름만 등록 ──
  void addRoom(String name) {
    // 이미 존재하는 이름이면 무시
    if (state.roomNames.contains(name)) return;
    state = state.copyWith(
      roomNames: [...state.roomNames, name],
    );
  }

  /// ── 방 이름 수정: roomNames + digests 키/roomName 모두 갱신 ──
  void renameRoom(String oldName, String newName) {
    // 같은 이름이거나 이미 존재하면 무시
    if (oldName == newName || state.roomNames.contains(newName)) return;

    // roomNames 리스트에서 교체
    final updatedNames = state.roomNames
        .map((n) => n == oldName ? newName : n)
        .toList();

    // digests에서 해당 방의 요약을 새 이름으로 재생성
    final updatedDigests = Map<String, DailyDigest>.from(state.digests);
    final keysToRemove = <String>[];
    final newEntries = <String, DailyDigest>{};

    for (final entry in updatedDigests.entries) {
      if (entry.value.roomName == oldName) {
        keysToRemove.add(entry.key);
        final newDigest = entry.value.copyWith(roomName: newName);
        newEntries[newDigest.key] = newDigest;
      }
    }

    for (final key in keysToRemove) {
      updatedDigests.remove(key);
    }
    updatedDigests.addAll(newEntries);

    state = state.copyWith(
      roomNames: updatedNames,
      digests: updatedDigests,
    );
  }

  /// ── 핵심 메서드: 파일 업로드 → 파싱 → 자동 요약 ──
  /// roomName: 미리 생성해둔 방 이름 (파싱 결과 대신 이 이름 사용)
  /// 1. FilePicker로 파일 선택
  /// 2. KakaotalkParser.parse() → ChatRoom (임시)
  /// 3. groupByDate() → 날짜별 메시지
  /// 4. 중복 감지: 이미 요약된 날짜는 스킵 (토큰 절약)
  /// 5. 새 날짜만 LLM 순차 호출 → DailyDigest 생성 → 즉시 state 반영
  /// 6. ChatRoom은 scope 벗어나면 GC 처리
  Future<void> uploadAndDigest(String roomName) async {
    // 파일 선택 다이얼로그 (카카오톡 내보내기 기본 경로)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: '/storage/emulated/0/Documents/KakaoTalk/Chats',
    );

    // 사용자가 파일 선택을 취소한 경우
    if (result == null || result.files.single.path == null) return;

    // 처리 시작
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearProgress: true,
    );

    try {
      // 1. 파일 읽기 + 파싱 → ChatRoom (임시 객체)
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final chatRoom = KakaotalkParser.parse(content);

      // 2. 날짜별 메시지 그룹핑
      final grouped = chatRoom.groupByDate();
      final dates = grouped.keys.toList()..sort();

      // 3. 중복 감지: 이미 요약된 날짜는 제외
      final newDates = <DateTime>[];
      for (final date in dates) {
        final key =
            '${roomName}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        if (!state.digests.containsKey(key)) {
          newDates.add(date);
        }
      }

      // 새로 요약할 날짜가 없으면 완료
      if (newDates.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          clearProgress: true,
        );
        return;
      }

      // 4. 설정에서 API 키 확인 (SharedPreferences 로딩 완료 보장)
      await ref.read(settingsProvider.notifier).ensureLoaded();
      final settings = ref.read(settingsProvider);
      if (settings.apiKey.isEmpty) {
        // API 키가 없으면 메시지 정보만 저장 (요약 없이)
        final updatedDigests = Map<String, DailyDigest>.from(state.digests);
        for (final date in newDates) {
          final messages = grouped[date]!;
          final digest = DailyDigest(
            date: date,
            summary: 'API 키를 설정하면 AI 요약이 생성됩니다.',
            roomName: roomName,
            messageCount: messages.length,
            createdAt: DateTime.now(),
          );
          updatedDigests[digest.key] = digest;
        }
        state = state.copyWith(
          digests: updatedDigests,
          isProcessing: false,
          clearProgress: true,
          error: 'API 키를 설정해주세요. (설정 화면에서 입력)',
        );
        return;
      }

      // 5. LLM 서비스로 순차 요약
      final llmService = _createLlmService(settings);
      final total = newDates.length;

      for (var i = 0; i < newDates.length; i++) {
        final date = newDates[i];
        final messages = grouped[date]!;

        // 진행률 업데이트
        state = state.copyWith(processingProgress: (i, total));

        try {
          // URL 메타데이터 가져오기 (대화에서 URL 추출 → 페이지 제목 수집)
          final allText = messages.map((m) => m.content).join('\n');
          final urls = UrlMetadataService.extractUrls(allText);
          final urlTitles = await UrlMetadataService.fetchTitles(urls);

          // AI 요약 호출 (URL 제목 정보 포함)
          final summary = await llmService.summarize(
            messages,
            urlTitles: urlTitles,
          );
          final topics = _extractTopics(summary);

          final digest = DailyDigest(
            date: date,
            summary: summary,
            roomName: roomName,
            messageCount: messages.length,
            topics: topics,
            createdAt: DateTime.now(),
          );

          // 즉시 state에 반영 (하나씩 완료될 때마다 UI 갱신)
          final updatedDigests = Map<String, DailyDigest>.from(state.digests);
          updatedDigests[digest.key] = digest;
          state = state.copyWith(digests: updatedDigests);
        } catch (e) {
          // 개별 날짜 요약 실패 시 에러만 기록하고 계속 진행
          state = state.copyWith(error: '${date.month}/${date.day} 요약 실패: $e');
        }
      }

      // 6. 처리 완료 (ChatRoom은 scope를 벗어나며 GC 처리)
      state = state.copyWith(
        isProcessing: false,
        processingProgress: (total, total),
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        clearProgress: true,
        error: '파일을 처리할 수 없습니다: $e',
      );
    }
  }

  /// 특정 채팅방의 모든 요약을 삭제 + roomNames에서도 제거
  void removeRoom(String roomName) {
    final updatedNames = state.roomNames.where((n) => n != roomName).toList();
    final updatedDigests = Map<String, DailyDigest>.from(state.digests)
      ..removeWhere((key, digest) => digest.roomName == roomName);
    state = state.copyWith(roomNames: updatedNames, digests: updatedDigests);
  }

  /// 에러 메시지 초기화
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// LLM 서비스 생성 (설정에 따라 Claude/OpenAI/Gemini)
  LlmService _createLlmService(SettingsState settings) {
    return switch (settings.provider) {
      LlmProvider.claude => ClaudeService(apiKey: settings.apiKey),
      LlmProvider.openai => OpenaiService(apiKey: settings.apiKey),
      LlmProvider.gemini => GeminiService(apiKey: settings.apiKey),
    };
  }

  /// 요약 텍스트에서 주요 주제 추출
  /// "- " 또는 "* "로 시작하는 짧은 줄을 주제로 인식
  List<String> _extractTopics(String summary) {
    final lines = summary.split('\n');
    final topics = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final topic = trimmed.substring(2).trim();
        if (topic.length < 40) topics.add(topic);
      }
    }
    return topics.take(5).toList();
  }
}

/// ── 메인 provider ──
final digestProvider = NotifierProvider<DigestNotifier, DigestState>(
  DigestNotifier.new,
);

/// ── 파생 provider: 달력용 ──
/// 모든 방의 요약을 날짜별로 그룹핑 (달력 마커 표시에 사용)
final calendarDigestsProvider =
    Provider<Map<DateTime, List<DailyDigest>>>((ref) {
  final digestState = ref.watch(digestProvider);
  final map = <DateTime, List<DailyDigest>>{};

  for (final digest in digestState.digests.values) {
    // 시간 제거, 날짜만 키로 사용
    final normalized =
        DateTime(digest.date.year, digest.date.month, digest.date.day);
    map.putIfAbsent(normalized, () => []).add(digest);
  }

  return map;
});

/// ── 파생 provider: 방 이름 리스트 ──
/// 홈 화면에서 채팅방 카드를 표시할 때 사용 (빈 방도 포함)
final roomNamesProvider = Provider<List<String>>((ref) {
  final digestState = ref.watch(digestProvider);
  return digestState.roomNames;
});

/// ── 파생 provider: 특정 방의 요약 리스트 ──
/// roomName을 family 파라미터로 받아 해당 방의 요약만 필터링
final roomDigestsProvider =
    Provider.family<List<DailyDigest>, String>((ref, roomName) {
  final digestState = ref.watch(digestProvider);
  final digests = digestState.digests.values
      .where((d) => d.roomName == roomName)
      .toList()
    // 최신 날짜가 위로
    ..sort((a, b) => b.date.compareTo(a.date));
  return digests;
});
