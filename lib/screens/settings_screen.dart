import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';
import '../providers/settings_provider.dart';

/// ConsumerStatefulWidget으로 변경:
/// TextEditingController를 위젯 수명 동안 유지하고,
/// 화면을 벗어날 때 자동으로 API 키를 저장하기 위함
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// API 키 입력 컨트롤러 (위젯 수명 동안 유지)
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    // 현재 저장된 API 키로 초기화
    _apiKeyController = TextEditingController(
      text: ref.read(settingsProvider).apiKey,
    );
  }

  @override
  void dispose() {
    // 화면을 떠날 때 입력 중이던 키를 자동 저장
    _saveApiKey();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// API 키를 provider에 저장
  void _saveApiKey() {
    final currentText = _apiKeyController.text.trim();
    final savedKey = ref.read(settingsProvider).apiKey;
    // 변경된 경우에만 저장 (불필요한 쓰기 방지)
    if (currentText != savedKey) {
      ref.read(settingsProvider.notifier).setApiKey(currentText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // provider 변경(예: 다른 LLM 선택)으로 키가 바뀌면 컨트롤러도 동기화
    if (_apiKeyController.text != settings.apiKey) {
      _apiKeyController.text = settings.apiKey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('LLM 제공자', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<LlmProvider>(
            segments: const [
              ButtonSegment(value: LlmProvider.claude, label: Text('Claude')),
              ButtonSegment(value: LlmProvider.openai, label: Text('OpenAI')),
              ButtonSegment(value: LlmProvider.gemini, label: Text('Gemini')),
            ],
            selected: {settings.provider},
            onSelectionChanged: (selected) {
              // provider 변경 전 현재 키 저장
              _saveApiKey();
              ref.read(settingsProvider.notifier).setProvider(selected.first);
            },
          ),
          const SizedBox(height: 24),
          Text('API 키', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: '${settings.provider.label} API 키를 입력하세요',
              // 저장 버튼을 필드 안에 배치
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'API 키 저장',
                onPressed: () {
                  _saveApiKey();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API 키가 저장되었습니다')),
                  );
                },
              ),
            ),
            // Enter 키로도 저장 가능
            onSubmitted: (value) {
              _saveApiKey();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API 키가 저장되었습니다')),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            _getApiKeyHint(settings.provider),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // ── 사용 모델 및 토큰 사용량 기반 비용 ──
          _buildUsageCard(context, settings.provider),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          // ── 앱 정보 & 라이센스 ──
          Text('앱 정보', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('톡비서'),
            subtitle: Text(
              'v1.0.4',
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
            // Flutter 기본 제공 라이센스 페이지 열기
            onTap: () => showLicensePage(
              context: context,
              applicationName: '톡비서',
              applicationVersion: 'v0.1.0',
              applicationLegalese: '© 2026 merryiscat\nMIT License',
            ),
          ),
        ],
      ),
    );
  }

  String _getApiKeyHint(LlmProvider provider) {
    return switch (provider) {
      LlmProvider.claude => 'Anthropic 콘솔에서 API 키를 발급받으세요',
      LlmProvider.openai => 'OpenAI 플랫폼에서 API 키를 발급받으세요',
      LlmProvider.gemini => 'Google AI Studio에서 API 키를 발급받으세요',
    };
  }

  /// 토큰 사용량 기반 비용 계산 카드
  Widget _buildUsageCard(BuildContext context, LlmProvider provider) {
    final digestState = ref.watch(digestProvider);
    final inputTokens = digestState.totalInputTokens;
    final outputTokens = digestState.totalOutputTokens;

    // 각 LLM별 1M 토큰당 가격 (USD)
    final (String model, double inputPrice, double outputPrice) =
        switch (provider) {
      LlmProvider.claude => ('claude-sonnet-4-5-20250929', 3.0, 15.0),
      LlmProvider.openai => ('gpt-4.1-mini', 0.4, 1.6),
      LlmProvider.gemini => ('gemini-2.0-flash', 0.1, 0.4),
    };

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
            // 토큰 사용량이 0이면 안내 메시지
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

  /// 토큰 수를 읽기 쉽게 포맷 (1,234 → "1,234")
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
