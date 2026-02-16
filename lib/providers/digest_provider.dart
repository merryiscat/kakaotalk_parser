import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_digest.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/llm_service.dart';
import '../services/claude_service.dart';
import '../services/openai_service.dart';
import '../services/gemini_service.dart';

/// 다이제스트 상태
class DigestState {
  final Map<DateTime, DailyDigest> digests;
  final Set<DateTime> loadingDates;
  final Map<DateTime, String> errors;

  const DigestState({
    this.digests = const {},
    this.loadingDates = const {},
    this.errors = const {},
  });

  DigestState copyWith({
    Map<DateTime, DailyDigest>? digests,
    Set<DateTime>? loadingDates,
    Map<DateTime, String>? errors,
  }) {
    return DigestState(
      digests: digests ?? this.digests,
      loadingDates: loadingDates ?? this.loadingDates,
      errors: errors ?? this.errors,
    );
  }
}

class DigestNotifier extends Notifier<DigestState> {
  @override
  DigestState build() => const DigestState();

  Future<void> generateDigest(DateTime date) async {
    // 이미 캐시에 있으면 스킵
    if (state.digests.containsKey(date)) return;

    // 설정에서 API 키 확인
    final settings = ref.read(settingsProvider);
    if (settings.apiKey.isEmpty) {
      state = state.copyWith(
        errors: {...state.errors, date: 'API 키를 설정해주세요. (설정 화면에서 입력)'},
      );
      return;
    }

    // 채팅 데이터에서 해당 날짜 메시지 가져오기
    final chatState = ref.read(chatProvider);
    if (chatState is! ChatLoaded) return;

    final dateOnly = DateTime(date.year, date.month, date.day);
    final grouped = chatState.chatRoom.groupByDate();
    final messages = grouped[dateOnly];
    if (messages == null || messages.isEmpty) return;

    // 로딩 시작
    state = state.copyWith(
      loadingDates: {...state.loadingDates, date},
      errors: Map.from(state.errors)..remove(date),
    );

    try {
      // LLM 서비스 생성
      final llmService = _createLlmService(settings);
      final summary = await llmService.summarize(messages);

      // 요약에서 주제 추출 (간단히 첫 줄이나 - 로 시작하는 줄)
      final topics = _extractTopics(summary);

      final digest = DailyDigest(
        date: date,
        summary: summary,
        topics: topics,
      );

      state = state.copyWith(
        digests: {...state.digests, date: digest},
        loadingDates: Set.from(state.loadingDates)..remove(date),
      );
    } catch (e) {
      state = state.copyWith(
        loadingDates: Set.from(state.loadingDates)..remove(date),
        errors: {...state.errors, date: 'AI 요약 생성 실패: $e'},
      );
    }
  }

  LlmService _createLlmService(SettingsState settings) {
    return switch (settings.provider) {
      LlmProvider.claude => ClaudeService(apiKey: settings.apiKey),
      LlmProvider.openai => OpenaiService(apiKey: settings.apiKey),
      LlmProvider.gemini => GeminiService(apiKey: settings.apiKey),
    };
  }

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

final digestProvider = NotifierProvider<DigestNotifier, DigestState>(
  DigestNotifier.new,
);
