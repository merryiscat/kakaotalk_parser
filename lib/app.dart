import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

class KakaoTalkParserApp extends StatelessWidget {
  const KakaoTalkParserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '카톡 다이제스트',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFEE500),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFFEE500),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routes: {
        '/': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
