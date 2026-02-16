import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../models/chat_room.dart';
import '../parser/kakaotalk_parser.dart';

/// 채팅 데이터 상태
sealed class ChatState {
  const ChatState();

  /// 상태별 분기 헬퍼
  T when<T>({
    required T Function() initial,
    required T Function() loading,
    required T Function(String roomName, List<DateTime> dates) loaded,
    required T Function(String message) error,
  }) {
    return switch (this) {
      ChatInitial() => initial(),
      ChatLoading() => loading(),
      ChatLoaded(roomName: final n, dates: final d) => loaded(n, d),
      ChatError(message: final m) => error(m),
    };
  }
}

class ChatInitial extends ChatState {
  const ChatInitial();
}

class ChatLoading extends ChatState {
  const ChatLoading();
}

class ChatLoaded extends ChatState {
  final String roomName;
  final List<DateTime> dates;
  final ChatRoom chatRoom;

  const ChatLoaded({
    required this.roomName,
    required this.dates,
    required this.chatRoom,
  });
}

class ChatError extends ChatState {
  final String message;
  const ChatError(this.message);
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatInitial();

  Future<void> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (result == null || result.files.single.path == null) return;

    state = const ChatLoading();

    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final chatRoom = KakaotalkParser.parse(content);
      final grouped = chatRoom.groupByDate();
      final dates = grouped.keys.toList()..sort();

      state = ChatLoaded(
        roomName: chatRoom.name,
        dates: dates,
        chatRoom: chatRoom,
      );
    } catch (e) {
      state = ChatError('파일을 파싱할 수 없습니다: $e');
    }
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
