import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbital/data/settings/settings_repository.dart';
import 'package:orbital/features/alerts/models/alert_model.dart';
import 'package:orbital/features/alerts/providers/alert_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> buildContainer([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  }

  AlertModel alert(String id, {bool isRead = false}) => AlertModel(
        id: id,
        serverId: 's1',
        metric: 'cpu',
        value: 92,
        threshold: 90,
        timestamp: DateTime.parse('2026-01-01T00:00:00Z'),
        isRead: isRead,
      );

  group('AlertNotifier', () {
    test('loads existing alerts from SharedPreferences', () async {
      final raw = AlertModel.listToJson([alert('a1')]);
      final container = await buildContainer({'orbital_alerts': raw});
      addTearDown(container.dispose);

      final alerts = container.read(alertNotifierProvider);
      expect(alerts, hasLength(1));
      expect(alerts.first.id, 'a1');
    });

    test('addAlert de-duplicates by id and prepends new item', () async {
      final container = await buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(alertNotifierProvider.notifier);

      await notifier.addAlert(alert('a1'));
      await notifier.addAlert(alert('a2'));
      await notifier.addAlert(alert('a2'));

      final alerts = container.read(alertNotifierProvider);
      expect(alerts.map((a) => a.id).toList(), ['a2', 'a1']);
    });

    test('markAsRead, markAllAsRead, dismissAlert and clearAll update state', () async {
      final container = await buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(alertNotifierProvider.notifier);

      await notifier.addAlert(alert('a1'));
      await notifier.addAlert(alert('a2'));

      await notifier.markAsRead('a2');
      expect(container.read(unreadAlertCountProvider), 1);

      await notifier.markAllAsRead();
      expect(container.read(unreadAlertCountProvider), 0);

      await notifier.dismissAlert('a1');
      expect(container.read(alertNotifierProvider).map((a) => a.id), ['a2']);

      await notifier.clearAll();
      expect(container.read(alertNotifierProvider), isEmpty);
    });

    test('caps alerts list at 100 entries', () async {
      final container = await buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(alertNotifierProvider.notifier);

      for (var i = 0; i < 105; i++) {
        await notifier.addAlert(alert('id-$i'));
      }

      final alerts = container.read(alertNotifierProvider);
      expect(alerts, hasLength(100));
      expect(alerts.first.id, 'id-104');
      expect(alerts.last.id, 'id-5');
    });
  });
}
