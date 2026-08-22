import 'package:flutter/material.dart';
import 'screens/main_shell_screen.dart';
import 'theme.dart';

/// 앱 루트 위젯
///
/// 색·글꼴·모양 규칙은 전부 lib/theme.dart에 모여 있습니다.
/// (딥 잉크 그린 시드 + 허니 액센트 / BMJUA 제목 + Pretendard 본문)
class KakaoTalkParserApp extends StatelessWidget {
  const KakaoTalkParserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '톡비서',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // 라이트/다크는 기기 시스템 설정을 따라갑니다
      themeMode: ThemeMode.system,
      // 하단 네비게이션 바가 포함된 메인 shell 화면
      home: const MainShellScreen(),
    );
  }
}
