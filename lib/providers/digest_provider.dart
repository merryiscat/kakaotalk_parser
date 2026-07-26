import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../models/daily_digest.dart';
import '../parser/kakaotalk_parser.dart';
import '../providers/settings_provider.dart';
import '../services/agent_api_service.dart';
import '../services/storage_service.dart';
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

  /// 현재 진행 중인 노드의 한글 표시명 (예: "대화 분석", "웹 검색")
  /// null이면 노드 정보 없음 (아직 시작 전이거나 날짜 단위 진행 중)
  final String? currentNodeName;

  /// 노드 단위 진행률: (완료된 노드 수, 전체 노드 수)
  /// 예: (3, 8)이면 8개 노드 중 3개 완료
  /// null이면 노드 진행률 없음
  final (int step, int totalSteps)? nodeProgress;

  /// 누적 토큰 사용량 (API 비용 계산용)
  final int totalInputTokens;
  final int totalOutputTokens;

  const DigestState({
    this.roomNames = const [],
    this.digests = const {},
    this.isProcessing = false,
    this.processingProgress,
    this.currentNodeName,
    this.nodeProgress,
    this.error,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
  });

  DigestState copyWith({
    List<String>? roomNames,
    Map<String, DailyDigest>? digests,
    bool? isProcessing,
    (int, int)? processingProgress,
    // null로 설정하려면 clearProgress: true 사용
    bool clearProgress = false,
    String? currentNodeName,
    (int, int)? nodeProgress,
    // null로 설정하려면 clearNodeInfo: true 사용 (노드 이름 + 노드 진행률 모두 초기화)
    bool clearNodeInfo = false,
    String? error,
    // null로 설정하려면 clearError: true 사용
    bool clearError = false,
    int? totalInputTokens,
    int? totalOutputTokens,
  }) {
    return DigestState(
      roomNames: roomNames ?? this.roomNames,
      digests: digests ?? this.digests,
      isProcessing: isProcessing ?? this.isProcessing,
      processingProgress:
          clearProgress ? null : (processingProgress ?? this.processingProgress),
      currentNodeName:
          clearNodeInfo ? null : (currentNodeName ?? this.currentNodeName),
      nodeProgress:
          clearNodeInfo ? null : (nodeProgress ?? this.nodeProgress),
      error: clearError ? null : (error ?? this.error),
      totalInputTokens: totalInputTokens ?? this.totalInputTokens,
      totalOutputTokens: totalOutputTokens ?? this.totalOutputTokens,
    );
  }
}

/// ──────────────────────────────────────────────
/// 파싱 결과 임시 객체
/// 파일 선택+파싱(1단계)과 요약(2단계) 사이에 데이터를 전달한다
/// ──────────────────────────────────────────────
class ParsedUpload {
  /// 날짜별로 분류된 메시지 (파서의 groupByDate 결과)
  final Map<DateTime, List<ChatMessage>> grouped;

  /// 요약 대상으로 선택 가능한 날짜 목록 (오늘 제외, 과거만, 오름차순 정렬)
  final List<DateTime> selectableDates;

  const ParsedUpload({
    required this.grouped,
    required this.selectableDates,
  });
}

/// ──────────────────────────────────────────────
/// DigestNotifier — 파일 업로드부터 AI 요약까지 원스톱 처리
/// ──────────────────────────────────────────────
class DigestNotifier extends Notifier<DigestState> {
  @override
  DigestState build() => const DigestState();

  /// ── 앱 시작 시 저장된 데이터 불러오기 ──
  /// main.dart에서 앱 초기화 직후 호출하여 이전 요약 복원
  Future<void> loadSavedData() async {
    final saved = await StorageService.load();
    if (saved != null) {
      state = DigestState(
        roomNames: saved.roomNames,
        digests: saved.digests,
        totalInputTokens: saved.totalInputTokens,
        totalOutputTokens: saved.totalOutputTokens,
      );
    }
  }

  /// ── 현재 상태를 JSON 파일로 저장 ──
  /// 상태가 변경될 때마다 호출하여 데이터 유실 방지
  Future<void> _saveState() async {
    await StorageService.save(
      roomNames: state.roomNames,
      digests: state.digests,
      totalInputTokens: state.totalInputTokens,
      totalOutputTokens: state.totalOutputTokens,
    );
  }

  /// ── 빈 방 추가: 리스트에 이름만 등록 ──
  void addRoom(String name) {
    // 이미 존재하는 이름이면 무시
    if (state.roomNames.contains(name)) return;
    state = state.copyWith(
      roomNames: [...state.roomNames, name],
    );
    _saveState(); // 방 추가 후 저장
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
    _saveState(); // 이름 변경 후 저장
  }

  /// ── 요약 키 생성: "방이름_YYYY-MM-DD" (DailyDigest.key와 동일 형식) ──
  String _digestKey(String roomName, DateTime date) =>
      '${roomName}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// 해당 방·날짜의 요약이 이미 존재하는지 확인
  /// (날짜 선택 바텀시트에서 "요약됨" 표시와 기본 선택 제외에 사용)
  bool isDigested(String roomName, DateTime date) =>
      state.digests.containsKey(_digestKey(roomName, date));

  /// ── 1단계: 파일 선택 + 파싱 ──
  /// FilePicker로 txt 파일을 고르고 파싱하여, 날짜별 메시지와
  /// 선택 가능한 날짜 목록을 돌려준다. UI는 이 결과로 날짜 선택
  /// 바텀시트를 띄운 뒤 digestDates()를 호출한다.
  /// 오늘 날짜는 제외 — 아직 대화가 진행 중일 수 있어 불완전한 요약이 되므로,
  /// 내일이 되면 오늘 날짜가 완성되어 정상 요약 가능.
  /// 사용자가 파일 선택을 취소하거나 파싱에 실패하면 null 반환.
  Future<ParsedUpload?> pickAndParse() async {
    // 파일 선택 다이얼로그 (카카오톡 내보내기 기본 경로)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: '/storage/emulated/0/Documents/KakaoTalk/Chats',
    );

    // 사용자가 파일 선택을 취소한 경우
    if (result == null || result.files.single.path == null) return null;

    try {
      // 파일 읽기 + 파싱 → 날짜별 메시지 그룹핑
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final chatRoom = KakaotalkParser.parse(content);
      final grouped = chatRoom.groupByDate();

      // 오늘 이전 날짜만 선택 가능 (오름차순 정렬)
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final dates =
          grouped.keys.where((d) => d.isBefore(todayOnly)).toList()..sort();

      return ParsedUpload(grouped: grouped, selectableDates: dates);
    } catch (e) {
      state = state.copyWith(error: '파일을 처리할 수 없습니다: $e');
      return null;
    }
  }

  /// ── 2단계: 선택한 날짜들 요약 ──
  /// [dates]에 담긴 날짜만 순서대로 LLM 호출 → DailyDigest 생성 → 즉시 저장.
  /// 이미 요약된 날짜를 다시 선택한 경우 새 결과로 덮어쓴다 (재요약).
  Future<void> digestDates(
    String roomName,
    ParsedUpload upload,
    List<DateTime> dates,
  ) async {
    if (dates.isEmpty) return;

    // 오래된 날짜부터 순서대로 처리
    final newDates = [...dates]..sort();
    final grouped = upload.grouped;

    // 처리 시작 (노드 정보도 초기화)
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearProgress: true,
      clearNodeInfo: true,
    );

    // Android에서만 Foreground Service 시작 (백그라운드 전환 시에도 API 호출 유지)
    if (!kIsWeb && Platform.isAndroid) {
      await _startForegroundService();
    }

    try {
      // 설정에서 서버 URL 확인 (SharedPreferences 로딩 완료 보장)
      await ref.read(settingsProvider.notifier).ensureLoaded();
      final settings = ref.read(settingsProvider);

      // 서버 URL이 없으면 요약 불가
      if (settings.serverUrl.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          clearProgress: true,
          error: '서버 URL을 설정해주세요. (설정 화면에서 입력)',
        );
        return;
      }

      // 멀티에이전트 서버 서비스 생성
      final agentService = AgentApiService(
        serverUrl: settings.serverUrl,
        openaiApiKey: settings.apiKey,
        tavilyApiKey: settings.tavilyApiKey,
        youtubeApiKey: settings.youtubeApiKey,
      );
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

          // 멀티에이전트 서버로 요약 요청 (SSE 스트리밍 우선, 실패 시 기존 방식 폴백)
          final messagesText = _buildMessagesText(messages);

          // 노드 진행률 초기화 (새 날짜 시작)
          state = state.copyWith(clearNodeInfo: true);

          LlmResult result;
          try {
            // SSE 스트리밍: 노드 완료마다 진행률 콜백으로 UI 갱신
            result = await agentService.summarizeStream(
              messagesText,
              urlTitles: urlTitles,
              onNodeComplete: (event) {
                // 각 노드 완료 시 상태 업데이트 → UI에 "대화 분석 완료 (3/8)" 표시
                state = state.copyWith(
                  currentNodeName: event.displayName,
                  nodeProgress: (event.step, event.totalSteps),
                );
              },
            );
          } catch (sseError) {
            // SSE 실패 시 기존 summarize()로 폴백 (서버가 구버전일 수 있음)
            debugPrint('SSE 스트리밍 실패, 기존 방식으로 폴백: $sseError');
            state = state.copyWith(clearNodeInfo: true);
            result = await agentService.summarize(
              messagesText,
              urlTitles: urlTitles,
            );
          }

          final summary = result.text;
          final topics = _extractTopics(summary);

          // 토큰 사용량 누적
          state = state.copyWith(
            totalInputTokens: state.totalInputTokens + result.inputTokens,
            totalOutputTokens: state.totalOutputTokens + result.outputTokens,
          );

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

          // 날짜 하나 완료될 때마다 저장 (중간에 앱이 죽어도 데이터 보존)
          await _saveState();
        } catch (e) {
          // 개별 날짜 요약 실패 시 에러만 기록하고 계속 진행
          state = state.copyWith(error: '${date.month}/${date.day} 요약 실패: $e');
        }
      }

      // 처리 완료 (파싱 결과는 scope를 벗어나며 GC 처리)
      state = state.copyWith(
        isProcessing: false,
        processingProgress: (total, total),
        clearNodeInfo: true,
      );
      await _saveState(); // 최종 상태 저장
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        clearProgress: true,
        clearNodeInfo: true,
        error: '요약 처리 중 오류가 발생했습니다: $e',
      );
    } finally {
      // Foreground Service 종료 (처리 완료 또는 에러 모두)
      if (!kIsWeb && Platform.isAndroid) {
        await _stopForegroundService();
      }
    }
  }

  /// ── Foreground Service 시작 ──
  /// 알림바에 "요약 진행 중" 표시 → 화면 꺼도 OS가 앱을 중단하지 않음
  Future<void> _startForegroundService() async {
    try {
      await FlutterForegroundTask.startService(
        serviceId: 100,
        notificationTitle: '톡비서 - 요약 진행 중',
        notificationText: '대화 요약을 처리하고 있습니다. 잠시만 기다려주세요.',
        callback: _foregroundTaskCallback,
      );
    } catch (e) {
      // Foreground Service 시작 실패해도 요약은 계속 진행 (포그라운드에서라도)
      debugPrint('Foreground Service 시작 실패: $e');
    }
  }

  /// ── Foreground Service 종료 ──
  Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('Foreground Service 종료 실패: $e');
    }
  }

  /// 특정 채팅방의 모든 요약을 삭제 + roomNames에서도 제거
  void removeRoom(String roomName) {
    final updatedNames = state.roomNames.where((n) => n != roomName).toList();
    final updatedDigests = Map<String, DailyDigest>.from(state.digests)
      ..removeWhere((key, digest) => digest.roomName == roomName);
    state = state.copyWith(roomNames: updatedNames, digests: updatedDigests);
    _saveState(); // 방 삭제 후 저장
  }

  /// 개별 요약 1건 삭제 (키 형식: "방이름_YYYY-MM-DD")
  void deleteDigest(String key) {
    final updatedDigests = Map<String, DailyDigest>.from(state.digests)
      ..remove(key);
    state = state.copyWith(digests: updatedDigests);
    _saveState(); // 삭제 후 저장
  }

  /// 에러 메시지 초기화
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// ChatMessage 리스트를 멀티에이전트 서버에 보낼 텍스트로 변환
  /// 형식: "[HH:MM] 발신자: 내용" (PromptBuilder와 동일한 형식)
  String _buildMessagesText(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      if (msg.type == MessageType.system ||
          msg.type == MessageType.media ||
          msg.type == MessageType.emoticon ||
          msg.type == MessageType.deleted) {
        continue;
      }
      final hour = msg.dateTime.hour.toString().padLeft(2, '0');
      final minute = msg.dateTime.minute.toString().padLeft(2, '0');
      buffer.writeln('[$hour:$minute] ${msg.sender}: ${msg.content}');
    }
    return buffer.toString();
  }

  /// 요약 텍스트에서 주요 주제 추출
  /// "## 주제 키워드" 섹션의 쉼표 구분 키워드를 파싱
  /// 해당 섹션이 없으면 "- " 또는 "* "로 시작하는 짧은 줄로 폴백
  List<String> _extractTopics(String summary) {
    // 새 형식: "## 주제 키워드" 섹션에서 쉼표 구분 키워드 추출
    final keywordMatch = RegExp(
      r'^## 주제 키워드\s*\n(.+)',
      multiLine: true,
    ).firstMatch(summary);

    if (keywordMatch != null) {
      return keywordMatch
          .group(1)!
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .take(5)
          .toList();
    }

    // 폴백: 이전 형식 호환 (리스트 항목에서 추출)
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

/// ── Foreground Service 콜백 ──
/// 별도 isolate에서 실행되는 최소한의 TaskHandler
/// 실제 요약 작업은 메인 isolate에서 진행되므로 여기서는 아무것도 하지 않음
/// 이 콜백의 역할은 단지 OS가 앱을 백그라운드에서 중단시키지 않도록 하는 것
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MinimalTaskHandler());
}

/// 최소한의 TaskHandler — Foreground Service 유지만 담당
class _MinimalTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
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
