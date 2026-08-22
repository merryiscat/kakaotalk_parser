import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';

/// 톡비서 브랜드 마크 — 초록 링 안에 허니 점
///
/// "비서" 캐릭터를 최소한의 도형으로 표현한 로고입니다.
/// 홈 앱바, 요약 상세의 "톡비서 제안" 헤더, 빈 상태 일러스트에서 재사용합니다.
class TokbiseoMark extends StatelessWidget {
  /// 전체 지름 (링 두께와 점 크기는 비율로 자동 계산)
  final double size;

  const TokbiseoMark({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.primary, width: size * 0.115),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.27,
        height: size * 0.27,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 허니 점 — 라이트/다크에서 tertiary가 알아서 반전됨
          color: scheme.tertiary,
        ),
      ),
    );
  }
}

/// 톡비서 공용 UI 위젯 모음
///
/// home_screen.dart와 room_detail_screen.dart에서 동일하게 사용되는
/// 진행률 표시, 에러 배너 등의 위젯을 여기에 모아둡니다.
/// 두 화면에서 중복 없이 재사용하기 위해 별도 파일로 분리했습니다.

/// 파이프라인 단계별 "비서 말투" 진행 문구
///
/// 서버가 노드 완료 이벤트(step 1~7)를 보낼 때마다,
/// "지금 무엇을 하고 있는지"를 딱딱한 노드 이름 대신 비서 말투로 보여줍니다.
/// 인덱스 = 완료된 노드 수 (0이면 아직 첫 노드 진행 중).
const List<String> _nodePhrases = [
  '잡담을 걸러내고 있어요', // filter 진행 중
  '대화를 분석하고 있어요', // analyst 진행 중
  '무엇을 조사할지 정하고 있어요', // supervisor 진행 중
  '웹을 뒤지고 있어요', // web_searcher 진행 중
  '유튜브를 뒤지고 있어요', // yt_searcher 진행 중
  '자료가 믿을 만한지 확인하고 있어요', // validator 진행 중
  '리포트를 쓰고 있어요', // writer 진행 중
];

/// 처리 중 진행 배너 — 비서 말풍선 스타일
///
/// 배경색 블록(컨테이너 규칙 ②) 안에:
/// - 브랜드 마크 + 현재 단계의 비서 말투 문구 + 단계 카운터
/// - 4px 얇은 진행률 바 (노드 진행률 기반, 없으면 무한 애니메이션)
/// - 여러 날짜 요약 중이면 "N일 중 M일째" 표시
class DigestProgressBar extends StatelessWidget {
  final DigestState digestState;

  const DigestProgressBar({super.key, required this.digestState});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final np = digestState.nodeProgress; // (완료 수, 전체 수)
    // 완료된 노드 수 → 지금 진행 중인 단계의 말투 문구
    final completed = np?.$1 ?? 0;
    final phrase = _nodePhrases[completed.clamp(0, _nodePhrases.length - 1)];

    // 날짜 단위 진행률 (예: 3일치 중 1일째)
    final dp = digestState.processingProgress;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TokbiseoMark(size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phrase,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 단계 카운터 (예: 5/7단계 · 2일째/3일)
              Text(
                [
                  if (np != null) '${np.$1}/${np.$2}단계',
                  if (dp != null && dp.$2 > 1) '${dp.$1}/${dp.$2}일',
                ].join(' · '),
                style: text.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 4px 얇은 진행률 바
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: np != null
                ? LinearProgressIndicator(value: np.$1 / np.$2)
                : const LinearProgressIndicator(),
          ),
        ],
      ),
    );
  }
}

/// 에러 메시지 배너 위젯
///
/// 요약 처리 중 에러가 발생하면 화면 상단에 빨간 배너로 표시합니다.
/// '닫기' 버튼을 누르면 에러 상태가 초기화됩니다.
class DigestErrorBanner extends ConsumerWidget {
  final String errorMessage;

  const DigestErrorBanner({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(digestProvider.notifier).clearError(),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}
