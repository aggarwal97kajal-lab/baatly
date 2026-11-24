import 'package:baatly/data/app_state.dart';
import 'package:baatly/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Splash shows brand and moves to Welcome', (tester) async {
    await tester.pumpWidget(const BaatlyApp());
    expect(find.text('BAATLY'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
  });

  test('Sending a message adds it to the chat', () {
    final s = AppState.instance;
    final chat = s.chats.firstWhere((c) => c.isGroup);
    final before = chat.messages.length;
    s.send(chat, 'Hello test');
    expect(chat.messages.length, before + 1);
    expect(chat.messages.last.text, 'Hello test');
    expect(chat.messages.last.fromMe, isTrue);
  });
}
