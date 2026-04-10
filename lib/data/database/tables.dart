import 'package:drift/drift.dart';
import '../../core/models/server_icon_catalog.dart';

// Enum for auth type stored as int in DB
enum AuthType { password, privateKey }

class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get host => text().withLength(min: 1, max: 255)();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text().withLength(min: 1, max: 100)();

  // 0 = password, 1 = privateKey
  IntColumn get authType => integer().withDefault(const Constant(0))();

  // Key into flutter_secure_storage where the credential is stored
  TextColumn get credentialStorageKey => text()();

  // Optional metadata
  TextColumn get label => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get tags => text().nullable()(); // comma-separated
  IntColumn get color => integer().nullable()(); // stored as ARGB int
  TextColumn get iconKey =>
      text().withDefault(const Constant(ServerIconCatalog.defaultKey))();

  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();

  // Alert thresholds (null = use app defaults)
  RealColumn get cpuAlertThreshold => real().nullable()();
  RealColumn get memoryAlertThreshold => real().nullable()();
  RealColumn get diskAlertThreshold => real().nullable()();
  BoolColumn get alertsEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get relayId => text().nullable()();
}

class Snippets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 100)();
  TextColumn get command => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Many-to-many: which snippets are pinned to which servers
class ServerSnippets extends Table {
  IntColumn get serverId => integer().references(Servers, #id)();
  IntColumn get snippetId => integer().references(Snippets, #id)();

  @override
  Set<Column> get primaryKey => {serverId, snippetId};
}
