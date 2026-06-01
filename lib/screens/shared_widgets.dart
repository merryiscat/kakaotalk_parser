import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/digest_provider.dart';

/// 톡비서 공용 UI 위젯 모음
///
/// home_screen.dart와 room_detail_screen.dart에서 동일하게 사용되는
/// 진행률 표시, 에러 배너 등의 위젯을 여기에 모아둡니다.
/// 두 화면에서 중복 없이 재사용하기 위해 별도 파일로 분리했습니다.

/// 진행률 텍스트를 조합하는 함수
///
/// 날짜 단위 + 노드 단위 정보를 합쳐서
/// "요약 중... 1/3 — 대화 분석 완료 (3/7)" 형태로 표시합니다.
///
/// - 날짜 단위: 전체 날짜 중 몇 번째 요약 중인지 (예: 3일치 중 1일째)
/// - 노드 단위: 현재 날짜의 파이프라인 7개 노드 중 몇 번째 완료인지
String buildProgressText(DigestState digestState) {
  final parts = <String>['요약 중...'];

  // 날짜 단위 진행률 (예: "1/3")
  if (digestState.processingProgress != null) {
    parts.add(
      '${digestState.processingProgress!.$1}/${digestState.processingProgress!.$2}',
    );
  }

  // 노드 단위 진행률 (예: "— 대화 분석 완료 (3/7)")
  if (digestState.currentNodeName != null &&
      digestState.nodeProgress != null) {
    final np = digestState.nodeProgress!;
    parts.add('— ${digestState.currentNodeName!} 완료 (${np.$1}/${np.$2})');
  }

  return parts.join(' ');
}

/// 처리 중 진행률 표시 위젯
///
/// 상단에 LinearProgressIndicator를 보여주고, 그 아래에 진행 텍스트를 표시합니다.
/// - nodeProgress가 있으면: 확정 프로그레스바 (몇 % 완료인지 표시)
/// - nodeProgress가 없으면: 무한 애니메이션 프로그레스바 (로딩 중)
class DigestProgressBar extends StatelessWidget {
  final DigestState digestState;

  const DigestProgressBar({super.key, required this.digestState});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 노드 진행률이 있으면 확정 프로그레스바, 없으면 무한 애니메이션
        if (digestState.nodeProgress != null)
          LinearProgressIndicator(
            value: digestState.nodeProgress!.$1 / digestState.nodeProgress!.$2,
          )
        else
          const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            buildProgressText(digestState),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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
    return MaterialBanner(
      content: Text(errorMessage),
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      actions: [
        TextButton(
          onPressed: () => ref.read(digestProvider.notifier).clearError(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}
