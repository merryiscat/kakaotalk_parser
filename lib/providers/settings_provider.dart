import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LLM 제공자
enum LlmProvider {
  claude('Claude'),
  openai('OpenAI'),
  gemini('Gemini');

  final String label;
  const LlmProvider(this.label);
}

/// 설정 상태
class SettingsState {
  final LlmProvider provider;
  final String apiKey;

  const SettingsState({
    this.provider = LlmProvider.claude,
    this.apiKey = '',
  });

  SettingsState copyWith({LlmProvider? provider, String? apiKey}) {
    return SettingsState(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  /// SharedPreferences 로딩 완료를 보장하는 Future
  /// - 다른 provider에서 await ensureLoaded()로 호출
  late final Future<void> _initialized;

  @override
  SettingsState build() {
    _initialized = _loadFromPrefs();
    return const SettingsState();
  }

  /// SharedPreferences 로딩이 완료될 때까지 대기
  /// - uploadAndDigest 등에서 API 키를 읽기 전에 호출해야 함
  Future<void> ensureLoaded() => _initialized;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final providerIndex = prefs.getInt('llm_provider') ?? 0;
    final apiKey = prefs.getString('api_key') ?? '';
    state = SettingsState(
      provider: LlmProvider.values[providerIndex],
      apiKey: apiKey,
    );
  }

  Future<void> setProvider(LlmProvider provider) async {
    state = state.copyWith(provider: provider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('llm_provider', provider.index);
    // 제공자 변경 시 해당 제공자의 키를 로드
    final apiKey = prefs.getString('api_key_${provider.name}') ?? '';
    state = state.copyWith(apiKey: apiKey);
  }

  Future<void> setApiKey(String apiKey) async {
    state = state.copyWith(apiKey: apiKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', apiKey);
    await prefs.setString('api_key_${state.provider.name}', apiKey);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
