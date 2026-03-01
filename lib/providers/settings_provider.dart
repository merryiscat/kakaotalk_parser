import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 상태 — 서버 URL + API 키 관리
class SettingsState {
  /// OpenAI API 키 (멀티에이전트 서버에서 LLM 호출에 사용)
  final String apiKey;

  /// 멀티에이전트 서버 URL (예: "http://192.168.0.10:3936")
  final String serverUrl;

  /// Tavily 웹 검색 API 키
  final String tavilyApiKey;

  /// YouTube Data API v3 키
  final String youtubeApiKey;

  const SettingsState({
    this.apiKey = '',
    this.serverUrl = '',
    this.tavilyApiKey = '',
    this.youtubeApiKey = '',
  });

  SettingsState copyWith({
    String? apiKey,
    String? serverUrl,
    String? tavilyApiKey,
    String? youtubeApiKey,
  }) {
    return SettingsState(
      apiKey: apiKey ?? this.apiKey,
      serverUrl: serverUrl ?? this.serverUrl,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      youtubeApiKey: youtubeApiKey ?? this.youtubeApiKey,
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
  Future<void> ensureLoaded() => _initialized;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key') ?? '';
    final serverUrl = prefs.getString('agent_server_url') ?? '';
    final tavilyApiKey = prefs.getString('tavily_api_key') ?? '';
    final youtubeApiKey = prefs.getString('youtube_api_key') ?? '';
    state = SettingsState(
      apiKey: apiKey,
      serverUrl: serverUrl,
      tavilyApiKey: tavilyApiKey,
      youtubeApiKey: youtubeApiKey,
    );
  }

  /// OpenAI API 키 저장
  Future<void> setApiKey(String apiKey) async {
    state = state.copyWith(apiKey: apiKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', apiKey);
  }

  /// 멀티에이전트 서버 URL 저장
  Future<void> setServerUrl(String url) async {
    state = state.copyWith(serverUrl: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('agent_server_url', url);
  }

  /// Tavily API 키 저장
  Future<void> setTavilyApiKey(String key) async {
    state = state.copyWith(tavilyApiKey: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tavily_api_key', key);
  }

  /// YouTube API 키 저장
  Future<void> setYoutubeApiKey(String key) async {
    state = state.copyWith(youtubeApiKey: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('youtube_api_key', key);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
