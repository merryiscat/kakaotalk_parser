import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';
import '../providers/settings_provider.dart';
import '../services/agent_api_service.dart';

/// 설정 화면 — 서버 URL + API 키 관리
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// OpenAI API 키 입력 컨트롤러
  late TextEditingController _apiKeyController;

  /// 멀티에이전트 서버 URL 입력 컨트롤러
  late TextEditingController _serverUrlController;

  /// Tavily API 키 입력 컨트롤러
  late TextEditingController _tavilyKeyController;

  /// YouTube API 키 입력 컨트롤러
  late TextEditingController _youtubeKeyController;

  /// 서버 연결 테스트 진행 중 여부
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    // 현재 저장된 값들로 초기화
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _serverUrlController = TextEditingController(text: settings.serverUrl);
    _tavilyKeyController = TextEditingController(text: settings.tavilyApiKey);
    _youtubeKeyController =
        TextEditingController(text: settings.youtubeApiKey);
  }

  @override
  void dispose() {
    // 화면을 떠날 때 입력 중이던 값들을 자동 저장
    _saveApiKey();
    _saveServerUrl();
    _saveTavilyKey();
    _saveYoutubeKey();
    _apiKeyController.dispose();
    _serverUrlController.dispose();
    _tavilyKeyController.dispose();
    _youtubeKeyController.dispose();
    super.dispose();
  }

  /// OpenAI API 키를 provider에 저장
  void _saveApiKey() {
    final currentText = _apiKeyController.text.trim();
    final savedKey = ref.read(settingsProvider).apiKey;
    if (currentText != savedKey) {
      ref.read(settingsProvider.notifier).setApiKey(currentText);
    }
  }

  /// Tavily API 키를 provider에 저장
  void _saveTavilyKey() {
    final currentText = _tavilyKeyController.text.trim();
    final savedKey = ref.read(settingsProvider).tavilyApiKey;
    if (currentText != savedKey) {
      ref.read(settingsProvider.notifier).setTavilyApiKey(currentText);
    }
  }

  /// YouTube API 키를 provider에 저장
  void _saveYoutubeKey() {
    final currentText = _youtubeKeyController.text.trim();
    final savedKey = ref.read(settingsProvider).youtubeApiKey;
    if (currentText != savedKey) {
      ref.read(settingsProvider.notifier).setYoutubeApiKey(currentText);
    }
  }

  /// 서버 URL을 provider에 저장
  void _saveServerUrl() {
    final currentText = _serverUrlController.text.trim();
    final savedUrl = ref.read(settingsProvider).serverUrl;
    if (currentText != savedUrl) {
      ref.read(settingsProvider.notifier).setServerUrl(currentText);
    }
  }

  /// 에러 메시지를 복사 가능한 다이얼로그로 표시
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 멀티에이전트 서버 연결 테스트
  Future<void> _testServerConnection() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 URL을 입력하세요')),
      );
      return;
    }

    setState(() => _isTesting = true);
    try {
      final service = AgentApiService(
        serverUrl: url,
        openaiApiKey: '',
        tavilyApiKey: '',
        youtubeApiKey: '',
      );
      // null이면 성공, 문자열이면 에러 메시지
      final error = await service.healthCheck();

      if (!mounted) return;
      if (error == null) {
        // 연결 성공 → URL 자동 저장
        _saveServerUrl();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('서버 연결 성공!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showErrorDialog('연결 실패', error);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('서버 연결 실패', '$e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // 외부에서 값이 변경되면 컨트롤러도 동기화
    if (_apiKeyController.text != settings.apiKey) {
      _apiKeyController.text = settings.apiKey;
    }
    if (_serverUrlController.text != settings.serverUrl) {
      _serverUrlController.text = settings.serverUrl;
    }
    if (_tavilyKeyController.text != settings.tavilyApiKey) {
      _tavilyKeyController.text = settings.tavilyApiKey;
    }
    if (_youtubeKeyController.text != settings.youtubeApiKey) {
      _youtubeKeyController.text = settings.youtubeApiKey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 서버 연결 ──
          _buildServerSection(context, settings),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // ── API 키 관리 ──
          _buildApiKeysSection(context, settings),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // ── API 사용량 ──
          _buildUsageCard(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // ── 앱 정보 ──
          _buildAppInfo(context),
        ],
      ),
    );
  }

  /// 서버 연결 섹션
  Widget _buildServerSection(BuildContext context, SettingsState settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.dns_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('서버 연결', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '멀티에이전트 서버에 연결하여 웹/유튜브 검색이 포함된 리포트를 생성합니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _serverUrlController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'http://192.168.0.10:3936',
                  labelText: '서버 URL',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save, size: 18),
                    tooltip: '저장',
                    onPressed: () {
                      _saveServerUrl();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('서버 URL 저장됨')),
                      );
                    },
                  ),
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _testServerConnection(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _testServerConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find, size: 18),
                label: Text(_isTesting ? '테스트 중' : '연결 테스트'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 서버 연결 상태 표시
        if (settings.serverUrl.isNotEmpty)
          Card(
            color: Colors.green.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '서버 연결됨 (${settings.serverUrl})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            color: Colors.orange.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '서버 URL을 설정해야 요약 기능을 사용할 수 있습니다',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// API 키 관리 섹션
  Widget _buildApiKeysSection(BuildContext context, SettingsState settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.key_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('API 키', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 12),
        // ── OpenAI API 키 ──
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'OpenAI API 키',
            hintText: 'sk-...',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save, size: 18),
              tooltip: '저장',
              onPressed: () {
                _saveApiKey();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('OpenAI API 키가 저장되었습니다')),
                );
              },
            ),
          ),
          onSubmitted: (_) {
            _saveApiKey();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OpenAI API 키가 저장되었습니다')),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'platform.openai.com 에서 발급',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        // ── Tavily API 키 ──
        TextField(
          controller: _tavilyKeyController,
          obscureText: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Tavily API 키 (웹 검색)',
            hintText: 'tvly-...',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save, size: 18),
              tooltip: '저장',
              onPressed: () {
                _saveTavilyKey();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tavily API 키가 저장되었습니다')),
                );
              },
            ),
          ),
          onSubmitted: (_) {
            _saveTavilyKey();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tavily API 키가 저장되었습니다')),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'tavily.com 에서 무료 발급 (월 1,000건)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        // ── YouTube API 키 ──
        TextField(
          controller: _youtubeKeyController,
          obscureText: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'YouTube API 키 (영상 검색)',
            hintText: 'AIza...',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save, size: 18),
              tooltip: '저장',
              onPressed: () {
                _saveYoutubeKey();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('YouTube API 키가 저장되었습니다')),
                );
              },
            ),
          ),
          onSubmitted: (_) {
            _saveYoutubeKey();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('YouTube API 키가 저장되었습니다')),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Google Cloud Console → YouTube Data API v3 사용 설정 후 발급',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  /// 토큰 사용량 카드
  Widget _buildUsageCard(BuildContext context) {
    final digestState = ref.watch(digestProvider);
    final inputTokens = digestState.totalInputTokens;
    final outputTokens = digestState.totalOutputTokens;

    // gpt-5.1 기준 1M 토큰당 가격 (USD) — 실제 가격은 추후 조정
    const model = 'gpt-5.1';
    const inputPrice = 2.0;
    const outputPrice = 8.0;

    // 비용 계산: 토큰 수 / 1,000,000 × 단가
    final inputCost = inputTokens / 1000000 * inputPrice;
    final outputCost = outputTokens / 1000000 * outputPrice;
    final totalCost = inputCost + outputCost;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.paid_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('API 사용량',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '모델: $model',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            if (inputTokens == 0 && outputTokens == 0)
              Text(
                '아직 사용 내역이 없습니다. 요약을 실행하면 여기에 표시됩니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else ...[
              Text(
                '입력: ${_formatTokens(inputTokens)} 토큰 (\$${inputCost.toStringAsFixed(4)})\n'
                '출력: ${_formatTokens(outputTokens)} 토큰 (\$${outputCost.toStringAsFixed(4)})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '예상 비용: \$${totalCost.toStringAsFixed(4)} (약 ₩${(totalCost * 1450).toStringAsFixed(0)})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '단가: 입력 \$$inputPrice / 출력 \$$outputPrice (1M 토큰)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 앱 정보 섹션
  Widget _buildAppInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('앱 정보', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('톡비서'),
          subtitle: Text(
            'v2.0.1',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('라이센스'),
          subtitle: Text(
            'MIT License © 2026 merryiscat',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          onTap: () => showLicensePage(
            context: context,
            applicationName: '톡비서',
            applicationVersion: 'v2.0.1',
            applicationLegalese: '© 2026 merryiscat\nMIT License',
          ),
        ),
      ],
    );
  }

  /// 토큰 수를 읽기 쉽게 포맷 (1234 → "1,234")
  String _formatTokens(int tokens) {
    if (tokens < 1000) return '$tokens';
    final str = tokens.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}
