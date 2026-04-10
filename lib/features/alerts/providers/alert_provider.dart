import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_model.dart';
import '../../../data/settings/settings_repository.dart';

const _kAlertsKey = 'orbital_alerts';
const _kMaxAlerts = 100;

class AlertNotifier extends Notifier<List<AlertModel>> {
  @override
  List<AlertModel> build() => _load();

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  List<AlertModel> _load() {
    final raw = _prefs.getString(_kAlertsKey);
    if (raw == null) return [];

    try {
      return AlertModel.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_kAlertsKey, AlertModel.listToJson(state));
  }

  /// Adds a new alert to the top of the list and persists it.
  Future<void> addAlert(AlertModel alert) async {
    // Prevent duplicate inserts when the same push is processed by
    // multiple message callbacks (for example onMessage + onMessageOpenedApp).
    if (state.any((a) => a.id == alert.id)) return;

    final updated = [alert, ...state];
    // Keep only the most recent alerts to avoid unbounded growth.
    state = updated.length > _kMaxAlerts
        ? updated.sublist(0, _kMaxAlerts)
        : updated;
    await _save();
  }

  /// Marks a single alert as read.
  Future<void> markAsRead(String alertId) async {
    state = state
        .map((a) => a.id == alertId ? a.copyWith(isRead: true) : a)
        .toList();
    await _save();
  }

  /// Marks every alert as read.
  Future<void> markAllAsRead() async {
    state = state.map((a) => a.copyWith(isRead: true)).toList();
    await _save();
  }

  /// Removes a single alert by ID (used by swipe-to-dismiss).
  Future<void> dismissAlert(String alertId) async {
    state = state.where((a) => a.id != alertId).toList();
    await _save();
  }

  /// Removes all alerts.
  Future<void> clearAll() async {
    state = [];
    await _prefs.remove(_kAlertsKey);
  }

  int get unreadCount => state.where((a) => !a.isRead).length;
}

final alertNotifierProvider = NotifierProvider<AlertNotifier, List<AlertModel>>(
  AlertNotifier.new,
);

/// Convenience provider for the unread count — used by the nav badge.
final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertNotifierProvider);
  return alerts.where((a) => !a.isRead).length;
});
