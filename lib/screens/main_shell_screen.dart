import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// 앱의 메인 shell 화면
/// 하단 NavigationBar로 3개 탭(달력 / 홈 / 설정)을 전환합니다.
/// IndexedStack을 사용해 탭 전환 시 각 화면의 상태를 유지합니다.
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 현재 선택된 탭 인덱스 (0=달력, 1=홈, 2=설정)
    final selectedTab = ref.watch(selectedTabProvider);

    return Scaffold(
      // IndexedStack: 모든 탭 화면을 미리 생성하되,
      // 선택된 탭만 보여줌 (나머지는 숨겨진 상태로 상태 유지)
      body: IndexedStack(
        index: selectedTab,
        children: const [
          CalendarScreen(), // 인덱스 0: 달력
          HomeScreen(),     // 인덱스 1: 홈
          SettingsScreen(), // 인덱스 2: 설정
        ],
      ),
      // Material 3 하단 네비게이션 바
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          ref.read(selectedTabProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '달력',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
