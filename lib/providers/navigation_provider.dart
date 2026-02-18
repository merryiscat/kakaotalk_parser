import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 하단 네비게이션 바에서 현재 선택된 탭 인덱스
/// 0 = 달력, 1 = 홈, 2 = 설정
final selectedTabProvider = StateProvider<int>((ref) => 1);
