import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

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
              ref.read(settingsProvider.notifier).setProvider(selected.first);
            },
          ),
          const SizedBox(height: 24),
          Text('API 키', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: settings.apiKey),
            obscureText: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: '${settings.provider.label} API 키를 입력하세요',
            ),
            onSubmitted: (value) {
              ref.read(settingsProvider.notifier).setApiKey(value);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API 키가 저장되었습니다')),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            _getApiKeyHint(settings.provider),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
}
