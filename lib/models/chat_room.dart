import 'chat_message.dart';

/// 파싱된 채팅방 전체 데이터
class ChatRoom {
  final String name;
  final DateTime? exportDate;
  final List<ChatMessage> messages;

  const ChatRoom({
    required this.name,
    required this.messages,
    this.exportDate,
  });

  /// 날짜별로 메시지를 그룹핑
  Map<DateTime, List<ChatMessage>> groupByDate() {
    final map = <DateTime, List<ChatMessage>>{};
    for (final msg in messages) {
      final dateOnly = DateTime(msg.dateTime.year, msg.dateTime.month, msg.dateTime.day);
      map.putIfAbsent(dateOnly, () => []).add(msg);
    }
    return map;
  }
}
