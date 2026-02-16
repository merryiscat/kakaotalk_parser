/// 메시지 타입
enum MessageType { text, system, media, deleted, emoticon }

/// 카카오톡 메시지 한 줄
class ChatMessage {
  final String sender;
  final DateTime dateTime;
  final String content;
  final MessageType type;

  const ChatMessage({
    required this.sender,
    required this.dateTime,
    required this.content,
    this.type = MessageType.text,
  });
}
