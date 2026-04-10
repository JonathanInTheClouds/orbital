import 'package:flutter_test/flutter_test.dart';
import 'package:orbital/features/alerts/models/alert_model.dart';

void main() {
  group('AlertModel', () {
    final alert = AlertModel(
      id: 'a1',
      serverId: 's1',
      metric: 'cpu',
      value: 91,
      threshold: 90,
      timestamp: DateTime.parse('2026-01-01T00:00:00Z'),
    );

    test('copyWith updates read state only', () {
      final read = alert.copyWith(isRead: true);
      expect(read.isRead, isTrue);
      expect(read.id, alert.id);
      expect(read.metric, alert.metric);
    });

    test('serializes and deserializes lists', () {
      final raw = AlertModel.listToJson([alert]);
      final parsed = AlertModel.listFromJson(raw);

      expect(parsed, hasLength(1));
      expect(parsed.first.id, 'a1');
      expect(parsed.first.value, 91);
      expect(parsed.first.isRead, isFalse);
    });

    test('maps metric labels and structured details flag', () {
      expect(alert.metricLabel, 'CPU');
      expect(alert.hasStructuredDetails, isTrue);

      final generic = AlertModel(
        id: 'a2',
        serverId: 's1',
        metric: 'unknown',
        value: 0,
        threshold: 0,
        timestamp: DateTime.now(),
      );
      expect(generic.metricLabel, 'Server');
      expect(generic.hasStructuredDetails, isFalse);

      final custom = generic.copyWith().toJson();
      custom['metric'] = 'temp';
      final customAlert = AlertModel.fromJson(custom);
      expect(customAlert.metricLabel, 'TEMP');
    });
  });
}
