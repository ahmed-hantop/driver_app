import 'package:driver_app/services/background_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('background reminder helpers', () {
    test('decodes reminder state and drops invalid values', () {
      final state = decodeReminderStateForTest(
        '{"pickup:41":171000,"delivery:42":"172000","bad-zero":0,"bad-negative":-1,"bad-text":"oops"}',
      );

      expect(state, {
        'pickup:41': 171000,
        'delivery:42': 172000,
      });
    });

    test('cooldown gate only allows reminders after one hour or when unseen', () {
      final now = DateTime(2026, 5, 10, 12);
      final reminderState = {
        'pickup:41': now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
        'delivery:42': now.subtract(const Duration(hours: 1, minutes: 1)).millisecondsSinceEpoch,
      };

      expect(canSendReminderForTest(reminderState, 'pickup:41', now), isFalse);
      expect(canSendReminderForTest(reminderState, 'delivery:42', now), isTrue);
      expect(canSendReminderForTest(reminderState, 'pickup:99', now), isTrue);
    });

    test('builds stable reminder keys from order ids', () {
      expect(reminderKeyForTest({'id': '41'}, 'pickup'), 'pickup:41');
      expect(reminderKeyForTest({'id': 42}, 'delivery'), 'delivery:42');
    });
  });
}