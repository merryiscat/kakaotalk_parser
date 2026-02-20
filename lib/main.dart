import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'providers/digest_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 달력에서 한국어 요일/월 이름을 표시하기 위한 locale 초기화
  await initializeDateFormatting('ko_KR');

  // Foreground Task 초기화 — 요약 처리 중 화면 꺼도 백그라운드에서 계속 실행
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'tokbiseo_digest',
      channelName: '톡비서 요약 처리',
      channelDescription: '대화 요약이 진행되는 동안 표시되는 알림입니다.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
      showWhen: false,
      enableVibration: false,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // 반복 실행은 필요 없음 (요약은 메인 isolate에서 처리)
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  // ProviderScope를 미리 생성하여 저장된 데이터를 로딩
  final container = ProviderContainer();
  // 이전 세션에서 저장한 요약 데이터 복원 (방 이름, 요약, 토큰 사용량)
  await container.read(digestProvider.notifier).loadSavedData();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KakaoTalkParserApp(),
    ),
  );
}
