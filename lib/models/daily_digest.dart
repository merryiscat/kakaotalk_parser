/// LLM이 생성한 일별 요약 — 앱의 핵심 데이터 단위
/// 파싱 + 요약이 완료된 결과를 저장하며, 원본 메시지는 보관하지 않음
class DailyDigest {
  /// 요약 대상 날짜
  final DateTime date;

  /// AI가 생성한 요약 텍스트
  final String summary;

  /// 요약에서 추출한 주요 주제 (최대 5개)
  final List<String> topics;

  /// 어떤 채팅방인지 식별하는 이름
  final String roomName;

  /// 해당 날짜의 원본 메시지 수 (메시지 자체는 저장하지 않음)
  final int messageCount;

  /// 요약이 생성된 시각
  final DateTime createdAt;

  const DailyDigest({
    required this.date,
    required this.summary,
    required this.roomName,
    this.topics = const [],
    this.messageCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? date;

  /// 일부 필드만 변경한 새 인스턴스 생성 (방 이름 수정 등에 사용)
  DailyDigest copyWith({String? roomName}) {
    return DailyDigest(
      date: date,
      summary: summary,
      roomName: roomName ?? this.roomName,
      topics: topics,
      messageCount: messageCount,
      createdAt: createdAt,
    );
  }

  /// 중복 감지용 고유 키: "방이름_YYYY-MM-DD"
  /// 같은 방 + 같은 날짜의 요약이 이미 존재하면 API를 다시 호출하지 않음
  String get key {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '${roomName}_$dateStr';
  }
}
