import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens the local database.
///
/// sqflite rather than Drift on purpose: Drift's `sqlite3_flutter_libs`
/// compiles SQLite from source and so requires the Android NDK, while sqflite
/// uses the SQLite already in Android. Same SQL, no native toolchain.
class AppDatabase {
  static const _fileName = 'who_pays.db';
  static const _version = 1;

  Database? _db;

  Future<Database> get instance async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(
      p.join(dir.path, _fileName),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in _schema) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static const _schema = <String>[
    '''
    CREATE TABLE rounds(
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      played_at    INTEGER NOT NULL,
      stake        TEXT    NOT NULL,
      custom_stake TEXT,
      target_ms    INTEGER,
      lasted_ms    INTEGER NOT NULL,
      outcome      TEXT    NOT NULL,
      reason       TEXT,
      room_code    TEXT
    )
    ''',
    'CREATE INDEX idx_rounds_played_at ON rounds(played_at DESC)',
    '''
    CREATE TABLE round_players(
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      round_id      INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
      name          TEXT    NOT NULL,
      lasted_ms     INTEGER NOT NULL,
      cracked_first INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_round_players_round ON round_players(round_id)',
    'CREATE INDEX idx_round_players_name ON round_players(name)',
  ];
}
