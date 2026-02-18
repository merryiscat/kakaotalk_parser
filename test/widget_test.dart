import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakaotalk_parser/app.dart';

void main() {
  testWidgets('앱 기본 렌더링 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KakaoTalkParserApp()),
    );
    expect(find.text('톡비서'), findsOneWidget);
    expect(find.text('파일 불러오기'), findsOneWidget);
  });
}
