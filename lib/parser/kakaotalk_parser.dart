import '../models/chat_message.dart';
import '../models/chat_room.dart';

/// 카카오톡 내보내기 txt 파일을 파싱하는 클래스
///
/// 지원 형식 예시:
/// ```
/// 방이름 2716 님과 카카오톡 대화
/// 저장한 날짜 : 2026년 2월 16일 오후 4:45
///
/// 2025년 12월 15일 오후 1:14
/// 2025년 12월 15일 오후 1:14, merry님이 들어왔습니다.
/// 2025년 12월 15일 오후 1:18, 신재솔 : 현대 AI 담론의 지도
/// ```
class KakaotalkParser {
  // ─── 정규식 패턴들 ───

  /// 날짜+시간 부분 (캡처 그룹 6개: 년/월/일/오전오후/시/분)
  static const _dtPrefix =
      r'(\d{4})년 (\d{1,2})월 (\d{1,2})일 (오전|오후) (\d{1,2}):(\d{2})';

  /// 일반 메시지: "2025년 12월 15일 오후 1:18, 신재솔 : 내용"
  /// - 그룹 7: 발신자 (첫 번째 ` : ` 앞까지, 비탐욕적)
  /// - 그룹 8: 메시지 내용
  static final _messageRegex = RegExp('^$_dtPrefix, (.+?) : (.*)\$');

  /// 시스템 메시지: "2025년 12월 15일 오후 1:14, merry님이 들어왔습니다."
  /// - _messageRegex에 매칭 안 되는 "날짜, 내용" 형태를 잡음
  /// - 그룹 7: 시스템 메시지 전체 내용
  static final _systemRegex = RegExp('^$_dtPrefix, (.+)\$');

  /// 헤더: "방이름 N 님과 카카오톡 대화" (첫 번째 줄)
  /// - 그룹 1: 방 이름 (끝에 참여자 수 제외)
  static final _headerRegex = RegExp(r'^(.+)\s+\d+\s*님과 카카오톡 대화$');

  /// 내보내기 날짜: "저장한 날짜 : 2026년 2월 16일 오후 4:45" (두 번째 줄)
  static final _exportDateRegex = RegExp('^저장한 날짜 : $_dtPrefix\$');

  /// 날짜 구분선: "2025년 12월 15일 오후 1:14" (쉼표 없이 날짜+시간만)
  /// - 날짜가 바뀔 때 카카오톡이 삽입하는 구분선
  static final _dateSeparatorRegex = RegExp('^$_dtPrefix\$');

  /// --- 구분선 --- 형식 (일부 내보내기 형식에서 사용)
  static final _dashedSeparatorRegex = RegExp(r'^-{3,}\s.+\s-{3,}$');

  // ─── 메인 파싱 메서드 ───

  /// 카카오톡 내보내기 txt 전체 내용을 파싱하여 ChatRoom 반환
  ///
  /// [content] : txt 파일의 전체 문자열
  /// 반환값 : 방 이름, 내보내기 날짜, 메시지 목록이 담긴 ChatRoom
  static ChatRoom parse(String content) {
    // 1단계: BOM(Byte Order Mark) 제거 — 윈도우 메모장 등에서 생기는 특수 문자
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    // 2단계: 줄 단위로 분리 (Windows \r\n 과 Unix \n 모두 처리)
    final lines = content.split(RegExp(r'\r?\n'));

    // 파싱 결과를 담을 변수들
    String roomName = '';
    DateTime? exportDate;
    final messages = <ChatMessage>[];

    // 3단계: 각 줄을 순서대로 처리
    for (final line in lines) {
      // 빈 줄은 건너뜀
      if (line.trim().isEmpty) continue;

      // (1) 헤더: "방이름 N 님과 카카오톡 대화"
      final headerMatch = _headerRegex.firstMatch(line);
      if (headerMatch != null) {
        roomName = headerMatch.group(1)!.trim();
        continue;
      }

      // (2) 내보내기 날짜: "저장한 날짜 : 2026년 2월 16일 오후 4:45"
      final exportMatch = _exportDateRegex.firstMatch(line);
      if (exportMatch != null) {
        exportDate = _parseDateTime(exportMatch);
        continue;
      }

      // (3) 날짜 구분선: 날짜만 있는 줄 또는 --- 구분선 → 무시
      if (_dateSeparatorRegex.hasMatch(line) ||
          _dashedSeparatorRegex.hasMatch(line)) {
        continue;
      }

      // (4) 일반 메시지: "날짜, 발신자 : 내용"
      //     ` : ` (공백-콜론-공백) 으로 발신자와 내용을 구분
      final msgMatch = _messageRegex.firstMatch(line);
      if (msgMatch != null) {
        final dt = _parseDateTime(msgMatch);
        final sender = msgMatch.group(7)!;
        final msgContent = msgMatch.group(8) ?? '';
        messages.add(ChatMessage(
          sender: sender,
          dateTime: dt,
          content: msgContent,
          type: _classifyContent(msgContent),
        ));
        continue;
      }

      // (5) 시스템 메시지: "날짜, 내용" (` : `가 없는 경우)
      //     예: "merry님이 들어왔습니다.", "튜브님이 나갔습니다."
      final sysMatch = _systemRegex.firstMatch(line);
      if (sysMatch != null) {
        final dt = _parseDateTime(sysMatch);
        final sysContent = sysMatch.group(7)!;
        messages.add(ChatMessage(
          sender: '',
          dateTime: dt,
          content: sysContent,
          type: MessageType.system,
        ));
        continue;
      }

      // (6) 어떤 패턴에도 매칭되지 않음 → 직전 메시지의 멀티라인 이어붙이기
      //     예: URL이나 긴 문장이 여러 줄에 걸쳐 있는 경우
      if (messages.isNotEmpty) {
        final last = messages.removeLast();
        messages.add(ChatMessage(
          sender: last.sender,
          dateTime: last.dateTime,
          content: '${last.content}\n$line',
          type: last.type,
        ));
      }
      // 메시지가 하나도 없는 상태에서 매칭 안 되는 줄은 무시
    }

    return ChatRoom(
      name: roomName,
      exportDate: exportDate,
      messages: messages,
    );
  }

  // ─── 보조 함수들 ───

  /// 정규식 매치에서 날짜+시간 추출 → DateTime 변환
  ///
  /// 12시간제(오전/오후)를 24시간제로 변환하는 규칙:
  /// - 오전 12:30 → 0:30 (자정)
  /// - 오전 1:00 ~ 오전 11:59 → 그대로
  /// - 오후 12:00 → 12:00 (정오)
  /// - 오후 1:00 ~ 오후 11:59 → +12시간
  static DateTime _parseDateTime(RegExpMatch match) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final ampm = match.group(4)!; // "오전" 또는 "오후"
    var hour = int.parse(match.group(5)!);
    final minute = int.parse(match.group(6)!);

    // 12시간제 → 24시간제 변환
    if (ampm == '오전') {
      // 오전 12시 = 자정(0시), 오전 1~11시 = 그대로
      if (hour == 12) hour = 0;
    } else {
      // 오후 12시 = 정오(12시), 오후 1~11시 = +12
      if (hour != 12) hour += 12;
    }

    return DateTime(year, month, day, hour, minute);
  }

  /// 메시지 내용을 분석하여 타입(text/emoticon/media/deleted) 분류
  ///
  /// 카카오톡 특수 메시지 패턴:
  /// - "이모티콘" → emoticon
  /// - "<사진 읽지 않음>" 등 → media
  /// - "삭제된 메시지입니다." → deleted
  /// - 그 외 → text
  static MessageType _classifyContent(String content) {
    final trimmed = content.trim();

    // 삭제된 메시지
    if (trimmed == '삭제된 메시지입니다.' || trimmed == '삭제된 메시지입니다') {
      return MessageType.deleted;
    }

    // 이모티콘 (카카오톡은 이모티콘을 "이모티콘"이라는 텍스트로 내보냄)
    if (trimmed == '이모티콘') {
      return MessageType.emoticon;
    }

    // 미디어: <사진 읽지 않음>, <동영상 읽지 않음>, <파일 읽지 않음> 등
    if (_mediaPattern.hasMatch(trimmed)) {
      return MessageType.media;
    }

    return MessageType.text;
  }

  /// 미디어 메시지 패턴: <...읽지 않음> 형태
  static final _mediaPattern = RegExp(r'^<.+읽지 않음>$');
}
