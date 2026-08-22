import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';
import '../providers/settings_provider.dart';
import '../services/agent_api_service.dart';
import '../theme.dart';

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

  /// 서버 접근 토큰(X-API-Key) 입력 컨트롤러
  late TextEditingController _serverApiKeyController;

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
    _serverApiKeyController =
        TextEditingController(text: settings.serverApiKey);
    _tavilyKeyController = TextEditingController(text: settings.tavilyApiKey);
    _youtubeKeyController =
        TextEditingController(text: settings.youtubeApiKey);
  }

  /// dispose()는 Flutter가 이 화면(Widget)을 메모리에서 제거할 때 자동으로 호출하는 메서드입니다.
  ///
  /// 왜 여기서 저장(save)을 하나요?
  /// - 사용자가 API 키를 입력하고 "저장" 버튼을 누르지 않은 채 뒤로 가기를 눌러
  ///   화면을 나갈 수 있습니다. 이때 입력한 값이 사라지면 사용자 경험이 나빠집니다.
  /// - 그래서 화면이 닫힐 때(dispose) 자동으로 현재 입력값을 저장해두는 패턴입니다.
  /// - "저장 버튼 안 눌러도 알아서 저장되네?" 라는 편리한 UX를 만들어줍니다.
  ///
  /// dispose()에서 컨트롤러도 함께 .dispose()하는 이유:
  /// - TextEditingController는 메모리를 차지하는 리소스이므로,
  ///   화면이 사라질 때 반드시 해제(dispose)해야 메모리 누수가 발생하지 않습니다.
  @override
  void dispose() {
    // 화면을 떠날 때 입력 중이던 값들을 자동 저장
    _saveApiKey();
    _saveServerUrl();
    _saveServerApiKey();
    _saveTavilyKey();
    _saveYoutubeKey();
    _apiKeyController.dispose();
    _serverUrlController.dispose();
    _serverApiKeyController.dispose();
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

  /// 서버 접근 토큰(X-API-Key)을 provider에 저장
  void _saveServerApiKey() {
    final currentText = _serverApiKeyController.text.trim();
    final savedKey = ref.read(settingsProvider).serverApiKey;
    if (currentText != savedKey) {
      ref.read(settingsProvider.notifier).setServerApiKey(currentText);
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
  ///
  /// 이 메서드가 async(비동기)인 이유:
  /// - 서버에 HTTP 요청을 보내고 응답을 기다리는 작업은 시간이 걸립니다 (네트워크 통신).
  /// - 만약 동기(sync)로 실행하면 응답이 올 때까지 앱 전체가 멈춰버립니다 (버튼도 안 눌림).
  /// - async/await를 쓰면 "서버 응답을 기다리는 동안 앱은 정상 작동"합니다.
  ///
  /// _isTesting 상태가 필요한 이유:
  /// - 네트워크 요청 중에 사용자가 버튼을 또 누르면 중복 요청이 발생합니다.
  /// - _isTesting이 true인 동안: 버튼을 비활성화(회색)하고, 로딩 스피너를 표시합니다.
  /// - 요청이 끝나면(성공이든 실패든) finally 블록에서 _isTesting을 false로 되돌립니다.
  ///
  /// mounted 체크가 필요한 이유:
  /// - 서버 응답을 기다리는 동안 사용자가 뒤로 가기로 이 화면을 나갈 수 있습니다.
  /// - 이미 사라진 화면에 SnackBar를 띄우면 에러가 나므로,
  ///   mounted(화면이 아직 살아있는지)를 확인한 후에만 UI를 업데이트합니다.
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
    // ref.watch()는 settingsProvider의 값이 바뀔 때마다 이 build()를 다시 실행합니다.
    // 즉, 다른 화면에서 설정값을 바꿔도 여기에 즉시 반영됩니다.
    final settings = ref.watch(settingsProvider);

    // ── 컨트롤러 동기화 (중요한 Flutter 패턴) ──
    // 문제 상황: TextField는 TextEditingController가 관리하는 "자기만의 텍스트"를 보여줍니다.
    // 그런데 settings(앱의 전역 상태)가 외부에서 변경되면, Provider 값은 바뀌었는데
    // TextField에 표시되는 텍스트는 그대로인 "불일치" 상태가 됩니다.
    //
    // 해결: build()가 다시 실행될 때마다 Provider 값과 컨트롤러 값을 비교해서,
    // 다르면 컨트롤러를 업데이트합니다. 이렇게 하면 어디서 값이 바뀌든 화면에 항상
    // 최신 값이 표시됩니다.
    //
    // "왜 if 체크를 하나요?" → 같은 값으로 다시 설정하면 커서 위치가 초기화되는
    // 부작용이 있어서, 실제로 다를 때만 업데이트합니다.
    if (_apiKeyController.text != settings.apiKey) {
      _apiKeyController.text = settings.apiKey;
    }
    if (_serverUrlController.text != settings.serverUrl) {
      _serverUrlController.text = settings.serverUrl;
    }
    if (_serverApiKeyController.text != settings.serverApiKey) {
      _serverApiKeyController.text = settings.serverApiKey;
    }
    if (_tavilyKeyController.text != settings.tavilyApiKey) {
      _tavilyKeyController.text = settings.tavilyApiKey;
    }
    if (_youtubeKeyController.text != settings.youtubeApiKey) {
      _youtubeKeyController.text = settings.youtubeApiKey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      // 구분선 대신 "섹션 라벨 + 보더 그룹" 구조 (컨테이너 규칙 ③)
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 서버 연결 ──
          _buildServerSection(context, settings),
          const SizedBox(height: 22),
          // ── API 키 관리 ──
          _buildApiKeysSection(context, settings),
          const SizedBox(height: 22),
          // ── API 사용량 ──
          _buildUsageCard(context),
          const SizedBox(height: 22),
          // ── 앱 정보 ──
          _buildAppInfo(context),
        ],
      ),
    );
  }

  /// 섹션 라벨 — 작은 대문자 스타일의 그룹 제목 (시안의 "연결 상태" 라벨)
  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  /// 섹션 내용을 감싸는 1px 보더 그룹 컨테이너
  Widget _sectionGroup(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: outlinedBox(context),
      child: child,
    );
  }

  /// 서버 연결 섹션
  ///
  /// 이 섹션의 UX 설계 의도:
  /// - TextField(URL 입력창) + "연결 테스트" 버튼을 나란히 배치하여,
  ///   URL을 입력하고 바로 옆 버튼을 눌러 서버가 살아있는지 확인할 수 있습니다.
  /// - 입력 후 Enter 키를 누르면 자동으로 연결 테스트가 실행됩니다 (onSubmitted).
  /// - URL 오른쪽 끝 저장 아이콘을 눌러 수동 저장도 가능합니다.
  /// - 아래쪽에는 현재 연결 상태를 초록/주황 카드로 시각적으로 표시하여,
  ///   서버가 설정되어 있는지 한눈에 알 수 있게 합니다.
  Widget _buildServerSection(BuildContext context, SettingsState settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, '서버 연결'),
        _sectionGroup(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
        const SizedBox(height: 12),
        // ── 서버 접근 토큰 (X-API-Key) ──
        // 서버가 인터넷에 노출돼 있어 모든 /api/* 요청에 이 토큰이 필요합니다.
        // 서버 .env의 TALKBISEO_API_KEY와 같은 값을 입력해야 합니다.
        TextField(
          controller: _serverApiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: '서버 접근 토큰 (X-API-Key)',
            hintText: '서버 .env의 TALKBISEO_API_KEY 값',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.save, size: 18),
              tooltip: '저장',
              onPressed: () {
                _saveServerApiKey();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('서버 접근 토큰이 저장되었습니다')),
                );
              },
            ),
          ),
          onSubmitted: (_) {
            _saveServerApiKey();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('서버 접근 토큰이 저장되었습니다')),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          '요약·발행 요청이 401로 거부되면 이 토큰이 서버와 다른 것입니다',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        // 서버 연결 상태 표시 — 배경색 블록(규칙 ②) + 상태 배지
        if (settings.serverUrl.isNotEmpty)
          _buildStatusRow(
            context,
            icon: Icons.check_circle_outline,
            badge: '정상',
            badgeColor: Theme.of(context).colorScheme.primaryContainer,
            badgeTextColor: Theme.of(context).colorScheme.onPrimaryContainer,
            message: settings.serverUrl,
          )
        else
          _buildStatusRow(
            context,
            icon: Icons.link_off,
            badge: '미설정',
            badgeColor: Theme.of(context).colorScheme.tertiaryContainer,
            badgeTextColor: Theme.of(context).colorScheme.onTertiaryContainer,
            message: '서버 URL을 설정해야 요약 기능을 사용할 수 있습니다',
          ),
            ],
          ),
        ),
      ],
    );
  }

  /// 연결 상태 한 줄 표시 — 아이콘 + 메시지 + 우측 상태 배지
  Widget _buildStatusRow(
    BuildContext context, {
    required IconData icon,
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: badgeTextColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// API 키 관리 섹션
  ///
  /// 이 앱은 3가지 외부 API를 사용하며, 각각 별도의 키가 필요합니다:
  ///
  /// 1. **OpenAI API 키** (sk-...로 시작)
  ///    - 역할: 대화 내용을 읽고 요약하는 AI(GPT 모델)를 호출하는 데 사용
  ///    - 발급처: https://platform.openai.com → API Keys 메뉴
  ///    - 비용: 사용한 토큰(글자 수) 만큼 과금
  ///
  /// 2. **Tavily API 키** (tvly-...로 시작)
  ///    - 역할: 대화에 언급된 주제에 대해 "웹 검색"을 수행하여 최신 정보를 수집
  ///    - 발급처: https://tavily.com → 회원가입 후 Dashboard에서 발급
  ///    - 비용: 월 1,000건 무료
  ///
  /// 3. **YouTube API 키** (AIza...로 시작)
  ///    - 역할: 대화에 언급된 주제 관련 유튜브 영상을 검색
  ///    - 발급처: Google Cloud Console → YouTube Data API v3 활성화 후 발급
  ///    - 비용: 일 10,000 쿼터 무료
  ///
  /// 모든 키는 obscureText: true로 비밀번호처럼 ●●●●로 표시됩니다 (보안).
  Widget _buildApiKeysSection(BuildContext context, SettingsState settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, 'API 키'),
        _sectionGroup(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          ),
        ),
      ],
    );
  }

  /// 토큰 사용량 카드
  ///
  /// "토큰"이란? AI에게 보내는 텍스트의 단위입니다.
  /// 대략 한글 1글자 ≈ 2~3토큰, 영어 1단어 ≈ 1토큰 정도입니다.
  ///
  /// 비용 계산 방식:
  /// - OpenAI는 "100만(1M) 토큰당 몇 달러"로 요금을 매깁니다.
  /// - 입력(input): 사용자가 AI에게 보내는 텍스트 → 상대적으로 저렴
  /// - 출력(output): AI가 생성한 응답 텍스트 → 입력보다 비쌈
  /// - 예: 입력 10,000토큰이면 → 10,000 / 1,000,000 × 단가 = 비용(USD)
  ///
  /// 환율 상수 1450은 원/달러 환율 근사값입니다.
  /// 실제 환율은 매일 변하지만, 대략적인 비용 감각을 주기 위해 고정값을 사용합니다.
  Widget _buildUsageCard(BuildContext context) {
    final digestState = ref.watch(digestProvider);
    final inputTokens = digestState.totalInputTokens;
    final outputTokens = digestState.totalOutputTokens;

    // gpt-5.4-mini 기준 1M 토큰당 가격 (USD) — 실제 가격은 추후 조정
    const model = 'gpt-5.4-mini';
    const inputPrice = 0.75; // 입력 100만 토큰당 0.75달러
    const outputPrice = 4.5; // 출력 100만 토큰당 4.5달러 (입력의 6배)

    // 비용 계산: 토큰 수 / 1,000,000 × 단가
    final inputCost = inputTokens / 1000000 * inputPrice;
    final outputCost = outputTokens / 1000000 * outputPrice;
    final totalCost = inputCost + outputCost;

    // 정보 표시 전용이므로 배경색 블록(컨테이너 규칙 ②) — 보더·그림자 없음
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, 'API 사용량'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kRadiusContainer),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
      ],
    );
  }

  /// 앱 정보 섹션
  Widget _buildAppInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, '앱 정보'),
        _sectionGroup(
          context,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('톡비서'),
                subtitle: Text(
                  'v2.1.0',
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
                  applicationVersion: 'v2.1.0',
                  applicationLegalese: '© 2026 merryiscat\nMIT License',
                ),
              ),
            ],
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
