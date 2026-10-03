import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/data/models/activity_models.dart';

void main() {
  ClientErrorReport report(int id, String message, int minute,
          {String? user}) =>
      ClientErrorReport(
        id: id,
        occurredAt: DateTime(2026, 10, 3, 12, minute),
        fingerprint: message.split('\n').first,
        message: message,
        userId: user,
      );

  test('groups reports by fingerprint, most recent group first', () {
    final groups = ClientErrorGroup.group([
      report(1, 'A\nstack', 1, user: 'u1'),
      report(2, 'B', 5),
      report(3, 'A\nother', 9, user: 'u2'),
      report(4, 'A', 3, user: 'u1'),
    ]);
    expect(groups.map((g) => g.latest.headline), ['A', 'B']);
    expect(groups.first.count, 3);
    expect(groups.first.latest.id, 3);
    expect(groups.first.affectedUsers, 2);
    expect(groups.last.affectedUsers, 0);
  });

  test('an audit row lists the fields it changed', () {
    final entry = AuditLogEntry.fromMap({
      'id': 7,
      'occurredAt': '2026-10-03T12:00:00',
      'actorRole': 'admin',
      'action': 'store.update',
      'entityType': 'store',
      'entityId': 'store-1',
      'details': {
        'changes': {
          'is_suspended': [false, true],
          'suspension_reason': [null, 'x'],
        },
      },
    });
    expect(entry.changedFields, ['is_suspended', 'suspension_reason']);
    expect(entry.actorId, isNull);
  });

  test('a client error row reads its context', () {
    final r = ClientErrorReport.fromMap({
      'id': 1,
      'occurredAt': '2026-10-03T12:00:00',
      'fingerprint': 'f',
      'message': 'TypeError\nat x',
      'context': {'route': '/s/amina'},
    });
    expect(r.headline, 'TypeError');
    expect(r.context['route'], '/s/amina');
  });
}
