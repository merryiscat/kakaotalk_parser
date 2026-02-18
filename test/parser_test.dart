import 'package:flutter_test/flutter_test.dart';
import 'package:kakaotalk_parser/models/chat_message.dart';
import 'package:kakaotalk_parser/parser/kakaotalk_parser.dart';

void main() {
  group('헤더 파싱', () {
    test('방 이름과 내보내기 날짜를 올바르게 추출한다', () {
      const input = '인공지능 연구방 2025 (NLP, LLM, RAG) 2716 님과 카카오톡 대화\n'
          '저장한 날짜 : 2026년 2월 16일 오후 4:45\n';
      final room = KakaotalkParser.parse(input);

      expect(room.name, '인공지능 연구방 2025 (NLP, LLM, RAG)');
      expect(room.exportDate, DateTime(2026, 2, 16, 16, 45));
      expect(room.messages, isEmpty);
    });

    test('1:1 채팅방 헤더를 파싱한다', () {
      const input = '홍길동 1 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n';
      final room = KakaotalkParser.parse(input);

      expect(room.name, '홍길동');
      expect(room.exportDate, DateTime(2025, 1, 1, 9, 0));
    });
  });

  group('일반 메시지 파싱', () {
    test('기본 메시지를 파싱한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '\n'
          '2025년 12월 15일 오후 1:18\n'
          '2025년 12월 15일 오후 1:18, 신재솔 : 현대 AI 담론의 지도\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(room.messages[0].sender, '신재솔');
      expect(room.messages[0].content, '현대 AI 담론의 지도');
      expect(room.messages[0].dateTime, DateTime(2025, 12, 15, 13, 18));
      expect(room.messages[0].type, MessageType.text);
    });

    test('발신자 이름에 공백이 포함된 메시지를 파싱한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:36, 엄지척 어피치 : 아지트분들 집 가셨겠네요\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(room.messages[0].sender, '엄지척 어피치');
      expect(room.messages[0].content, '아지트분들 집 가셨겠네요');
    });

    test('메시지 내용에 콜론이 포함된 경우를 처리한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:36, 홍길동 : URL : https://example.com\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].sender, '홍길동');
      // 첫 번째 " : " 이후 전부가 content
      expect(room.messages[0].content, 'URL : https://example.com');
    });
  });

  group('멀티라인 메시지', () {
    test('여러 줄에 걸친 메시지를 하나로 합친다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:18, 신재솔 : 현대 AI 담론의 지도\n'
          'source - https://x.com/example\n'
          '참고하세요\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(
        room.messages[0].content,
        '현대 AI 담론의 지도\nsource - https://x.com/example\n참고하세요',
      );
    });

    test('멀티라인 후 새 메시지가 오면 분리된다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:18, 홍길동 : 첫 줄\n'
          '두 번째 줄\n'
          '2025년 12월 15일 오후 1:19, 김철수 : 다음 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 2);
      expect(room.messages[0].content, '첫 줄\n두 번째 줄');
      expect(room.messages[1].content, '다음 메시지');
    });
  });

  group('시스템 메시지 분류', () {
    test('입장 메시지를 system 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:14, merry님이 들어왔습니다.\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(room.messages[0].type, MessageType.system);
      expect(room.messages[0].sender, '');
      expect(room.messages[0].content, 'merry님이 들어왔습니다.');
    });

    test('퇴장 메시지를 system 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 4:46, 멋쩍은 튜브님이 나갔습니다.\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(room.messages[0].type, MessageType.system);
      expect(room.messages[0].content, '멋쩍은 튜브님이 나갔습니다.');
    });
  });

  group('미디어/이모티콘/삭제 메시지 분류', () {
    test('이모티콘 메시지를 emoticon 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 4:30, AI_열공 : 이모티콘\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].type, MessageType.emoticon);
    });

    test('사진 미디어 메시지를 media 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:17, 신재솔 : <사진 읽지 않음>\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].type, MessageType.media);
    });

    test('동영상 미디어 메시지를 media 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:17, 홍길동 : <동영상 읽지 않음>\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].type, MessageType.media);
    });

    test('삭제된 메시지를 deleted 타입으로 분류한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:17, 홍길동 : 삭제된 메시지입니다.\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].type, MessageType.deleted);
    });
  });

  group('오전/오후 12시간제 변환', () {
    test('오전 12:30 → 0시 30분 (자정)', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 16일 오전 12:30, 홍길동 : 자정 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].dateTime.hour, 0);
      expect(room.messages[0].dateTime.minute, 30);
    });

    test('오후 12:30 → 12시 30분 (정오)', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 16일 오후 12:30, 홍길동 : 점심 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].dateTime.hour, 12);
      expect(room.messages[0].dateTime.minute, 30);
    });

    test('오전 9:15 → 9시 15분', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 16일 오전 9:15, 홍길동 : 아침 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].dateTime.hour, 9);
      expect(room.messages[0].dateTime.minute, 15);
    });

    test('오후 11:45 → 23시 45분', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 16일 오후 11:45, 홍길동 : 밤 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages[0].dateTime.hour, 23);
      expect(room.messages[0].dateTime.minute, 45);
    });
  });

  group('BOM 및 빈 파일 처리', () {
    test('BOM이 포함된 파일을 정상적으로 파싱한다', () {
      const input = '\uFEFF테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '2025년 12월 15일 오후 1:18, 홍길동 : 안녕하세요\n';
      final room = KakaotalkParser.parse(input);

      expect(room.name, '테스트방');
      expect(room.messages.length, 1);
      expect(room.messages[0].content, '안녕하세요');
    });

    test('빈 파일은 빈 ChatRoom을 반환한다', () {
      final room = KakaotalkParser.parse('');

      expect(room.name, '');
      expect(room.exportDate, isNull);
      expect(room.messages, isEmpty);
    });

    test('헤더만 있는 파일을 처리한다', () {
      const input = '테스트방 5 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 6월 1일 오후 3:00\n';
      final room = KakaotalkParser.parse(input);

      expect(room.name, '테스트방');
      expect(room.messages, isEmpty);
    });
  });

  group('날짜 구분선 처리', () {
    test('날짜 구분선은 메시지에 포함되지 않는다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '\n'
          '2025년 12월 15일 오후 1:14\n'
          '2025년 12월 15일 오후 1:18, 홍길동 : 첫 메시지\n'
          '\n'
          '2025년 12월 16일 오전 12:01\n'
          '2025년 12월 16일 오전 12:01, 김철수 : 다음 날 메시지\n';
      final room = KakaotalkParser.parse(input);

      // 날짜 구분선은 제외되고 일반 메시지 2개만 남음
      expect(room.messages.length, 2);
      expect(room.messages[0].sender, '홍길동');
      expect(room.messages[1].sender, '김철수');
    });

    test('--- 형식 날짜 구분선도 무시한다', () {
      const input = '테스트방 2 님과 카카오톡 대화\n'
          '저장한 날짜 : 2025년 1월 1일 오전 9:00\n'
          '--- 2025년 12월 15일 월요일 ---\n'
          '2025년 12월 15일 오후 1:18, 홍길동 : 메시지\n';
      final room = KakaotalkParser.parse(input);

      expect(room.messages.length, 1);
      expect(room.messages[0].sender, '홍길동');
    });
  });

  group('실제 샘플 파싱 통합 테스트', () {
    test('여러 종류의 메시지가 섞인 대화를 올바르게 파싱한다', () {
      const input = '인공지능 연구방 2716 님과 카카오톡 대화\n'
          '저장한 날짜 : 2026년 2월 16일 오후 4:45\n'
          '\n'
          '2025년 12월 15일 오후 1:14\n'
          '2025년 12월 15일 오후 1:14, merry님이 들어왔습니다.\n'
          '2025년 12월 15일 오후 1:17, 신재솔 : <사진 읽지 않음>\n'
          '2025년 12월 15일 오후 1:18, 신재솔 : 현대 AI 담론의 지도\n'
          'source - https://x.com/example\n'
          '2025년 12월 15일 오후 4:30, AI_열공 : 이모티콘\n'
          '2025년 12월 15일 오후 4:46, 멋쩍은 튜브님이 나갔습니다.\n';
      final room = KakaotalkParser.parse(input);

      expect(room.name, '인공지능 연구방');
      expect(room.exportDate, DateTime(2026, 2, 16, 16, 45));

      // 메시지 5개: 시스템(입장), 미디어, 텍스트(멀티라인), 이모티콘, 시스템(퇴장)
      expect(room.messages.length, 5);

      // 시스템 메시지 (입장)
      expect(room.messages[0].type, MessageType.system);
      expect(room.messages[0].content, contains('들어왔습니다'));

      // 미디어 메시지
      expect(room.messages[1].type, MessageType.media);

      // 멀티라인 텍스트 메시지
      expect(room.messages[2].type, MessageType.text);
      expect(room.messages[2].content, contains('source'));

      // 이모티콘
      expect(room.messages[3].type, MessageType.emoticon);

      // 시스템 메시지 (퇴장)
      expect(room.messages[4].type, MessageType.system);
      expect(room.messages[4].content, contains('나갔습니다'));
    });
  });
}
