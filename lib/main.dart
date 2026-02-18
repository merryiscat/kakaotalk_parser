import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 달력에서 한국어 요일/월 이름을 표시하기 위한 locale 초기화
  await initializeDateFormatting('ko_KR');
  runApp(const ProviderScope(child: KakaoTalkParserApp()));
}
