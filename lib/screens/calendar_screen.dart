import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/daily_digest.dart';
import '../providers/digest_provider.dart';
import '../theme.dart';
import 'digest_screen.dart';

/// 달력 화면 (월간 달력)
/// 모든 채팅방의 요약 날짜를 합쳐서 표시합니다.
/// - 요약이 있는 날짜: 날짜 아래 작은 점(dot) 마커
/// - 날짜를 탭하면 아래에 그 날짜의 리포트 목록이 나오고,
///   목록의 방을 탭하면 요약 상세로 이동합니다.
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // 달력 범위: 오늘 기준 ±2년
    final now = DateTime.now();
    final firstDay = DateTime(now.year - 2, 1, 1);
    final lastDay = DateTime(now.year + 1, 12, 31);

    // 선택된 날짜의 요약 목록 (하단 리스트용)
    final selectedKey = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final selectedDigests = calendarDigests[selectedKey] ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('달력')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

            // 날짜 선택 시 — 하단 목록만 갱신 (바로 이동하지 않음)
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },

            // 달력 페이지(월) 변경 시
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },

            // 요약이 있는 날짜에 작은 점 마커
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                final normalizedDate =
                    DateTime(date.year, date.month, date.day);
                if (!calendarDigests.containsKey(normalizedDate)) return null;

                return Positioned(
                  bottom: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                  ),
                );
              },
            ),

            // 달력 스타일
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(color: scheme.onPrimaryContainer),
              selectedDecoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),

            // 헤더 스타일 — 월 제목은 주아체
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontFamily: 'BMJUA',
                fontSize: 20,
                color: scheme.onSurface,
              ),
            ),
          ),

          // ── 선택한 날짜의 리포트 목록 ──
          Expanded(
            child: selectedDigests.isEmpty
                ? Center(
                    child: Text(
                      '이 날짜에는 요약이 없어요',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      Text(
                        '${DateFormat('M월 d일', 'ko').format(_selectedDay)} · ${selectedDigests.length}개 리포트',
                        style: text.titleLarge?.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 10),
                      ...selectedDigests.map(
                        (digest) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildDigestRow(context, digest),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 선택 날짜의 방별 리포트 행 — 1px 보더(컨테이너 규칙 ③)
  Widget _buildDigestRow(BuildContext context, DailyDigest digest) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: outlinedBox(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DigestScreen(
              date: DateTime(
                digest.date.year,
                digest.date.month,
                digest.date.day,
              ),
              digests: [digest],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // 방 아이콘 (40px · radius 12 · primaryContainer)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: 22,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      digest.roomName,
                      style: text.titleSmall?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${digest.messageCount}개 메시지',
                        if (digest.topics.isNotEmpty)
                          '키워드 ${digest.topics.length}',
                      ].join(' · '),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
