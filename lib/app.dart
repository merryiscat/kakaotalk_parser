import 'package:flutter/material.dart';
import 'screens/main_shell_screen.dart';

class KakaoTalkParserApp extends StatelessWidget {
  const KakaoTalkParserApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ── 색상 전략 ──
    // 톤온톤: 딥 블루(#1565C0)를 seed로 Material 3가
    //         밝은 파랑 ~ 진한 파랑까지 자동 팔레트 생성
    // 보색:   카카오 옐로우 계열을 tertiary(액센트)로 지정
    //         토픽 칩, 달력 마커 등 포인트 컬러로 사용

    return MaterialApp(
      title: '톡비서',
      theme: ThemeData(
        fontFamily: 'BMJUA',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0), // 딥 블루 (톤온톤 기준색)
          brightness: Brightness.light,
        ).copyWith(
          // 보색 액센트: 골든 옐로우 계열
          tertiary: const Color(0xFF996515),       // 진한 골드 (아이콘, 마커)
          tertiaryContainer: const Color(0xFFFFF3CD), // 연한 크림 옐로우 (칩 배경)
          onTertiary: Colors.white,
          onTertiaryContainer: const Color(0xFF533600), // 칩 텍스트
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        fontFamily: 'BMJUA',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ).copyWith(
          // 다크모드에서는 밝은 골드로 반전
          tertiary: const Color(0xFFFFD54F),        // 밝은 골드
          tertiaryContainer: const Color(0xFF6D4C00), // 어두운 골드 (칩 배경)
          onTertiary: const Color(0xFF3E2723),
          onTertiaryContainer: const Color(0xFFFFECB3), // 칩 텍스트
        ),
        useMaterial3: true,
      ),
      // 하단 네비게이션 바가 포함된 메인 shell 화면
      home: const MainShellScreen(),
    );
  }
}
