import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/daily_digest.dart';
import '../providers/digest_provider.dart';
import 'digest_screen.dart';

/// 달력 화면 (월간 달력)
/// 모든 채팅방의 요약 날짜를 합쳐서 표시합니다.
/// - 요약이 있는 날짜: 초록색 체크 마커
/// 날짜를 탭하면 해당 날짜의 AI 요약 화면으로 이동합니다.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // 현재 달력에서 선택된 날짜
  DateTime _selectedDay = DateTime.now();
  // 달력이 보여주는 기준 날짜 (월 이동용)
  DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    // 날짜 → 해당 날짜의 요약 리스트 (모든 방 합산)
    final calendarDigests = ref.watch(calendarDigestsProvider);

    // 달력 범위: 오늘 기준 ±2년
    final now = DateTime.now();
    final firstDay = DateTime(now.year - 2, 1, 1);
    final lastDay = DateTime(now.year + 1, 12, 31);

    return Scaffold(
      appBar: AppBar(title: const Text('달력')),
      body: Column(
        children: [
          // ── 달력 위젯 ──
          TableCalendar(
            locale: 'ko_KR',
            // 월요일부터 시작
            startingDayOfWeek: StartingDayOfWeek.monday,
            firstDay: firstDay,
            lastDay: lastDay,
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),

            // 날짜 선택 시
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });

              final normalizedDay = DateTime(
                selectedDay.year,
                selectedDay.month,
                selectedDay.day,
              );

              // 해당 날짜에 요약이 있는지 확인
              final digests = calendarDigests[normalizedDay];
              if (digests == null || digests.isEmpty) return;

              // 요약 상세 화면으로 이동 (해당 날짜의 모든 방 요약 전달)
              _openDigest(context, normalizedDay, digests);
            },

            // 달력 페이지(월) 변경 시
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },

            // 요약이 있는 날짜에 체크 마커 표시
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                final normalizedDate =
                    DateTime(date.year, date.month, date.day);
                if (!calendarDigests.containsKey(normalizedDate)) return null;

                // 보색 액센트: 골든 옐로우로 요약 완료 마커 표시
                return Positioned(
                  bottom: 1,
                  child: Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                );
              },
            ),

            // 달력 스타일
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),

            // 헤더 스타일
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
          ),

        ],
      ),
    );
  }

  /// 요약 화면으로 이동 — 해당 날짜의 모든 방 요약을 전달
  void _openDigest(
    BuildContext context,
    DateTime date,
    List<DailyDigest> digests,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DigestScreen(date: date, digests: digests),
      ),
    );
  }
}
