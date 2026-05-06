// All SQLite operations for the request queue (sync_items table).
// This is the only file that touches sqflite for the queue.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/sync_item.dart';

class LocalStorage {
  // Singleton database instance
  static Database? _database;

  static const String _tableName = 'sync_items';

  // Opens the database.
  // We use version 2 to ensure migration logic runs for early testers.
  static Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'syncraft.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id           TEXT PRIMARY KEY,
            endpoint     TEXT NOT NULL,
            method       TEXT NOT NULL,
            data         TEXT NOT NULL,
            headers      TEXT NOT NULL DEFAULT '{}',
            status       TEXT NOT NULL,
            retry_count  INTEGER NOT NULL DEFAULT 0,
            created_at   TEXT NOT NULL,
            request_hash TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        // Safe migration: Add columns if they were missing from v1
        if (oldVersion < 2) {
          final tableInfo = await db.rawQuery('PRAGMA table_info($_tableName)');
          final columns = tableInfo.map((c) => c['name'] as String).toList();

          if (!columns.contains('headers')) {
            await db.execute(
                "ALTER TABLE $_tableName ADD COLUMN headers TEXT NOT NULL DEFAULT '{}'");
          }
          if (!columns.contains('retry_count')) {
            await db.execute(
                "ALTER TABLE $_tableName ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0");
          }
          if (!columns.contains('request_hash')) {
            await db.execute(
                "ALTER TABLE $_tableName ADD COLUMN request_hash TEXT NOT NULL DEFAULT ''");
          }
          debugPrint(
              'syncraft: Database migrated to v2 — missing columns added.');
        }
      },
    );

    return _database!;
  }

  // ... rest of the file remains the same ...
  static Future<void> insertItem(SyncItem item) async {
    final db = await database;
    await db.insert(
      _tableName,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<SyncItem>> getPendingItems() async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) => SyncItem.fromMap(row)).toList();
  }

  static Future<List<SyncItem>> getFailedItems() async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: ['failed'],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) => SyncItem.fromMap(row)).toList();
  }

  static Future<void> updateStatus(String id, String status) async {
    final db = await database;
    await db.update(
      _tableName,
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> incrementRetry(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $_tableName SET retry_count = retry_count + 1 WHERE id = ?',
      [id],
    );
  }

  static Future<void> deleteItem(String id) async {
    final db = await database;
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> itemExistsByHash(String hash) async {
    if (hash.isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'request_hash = ? AND status = ?',
      whereArgs: [hash, 'pending'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableName);
  }

  static Future<void> clearSuccessful() async {
    final db = await database;
    await db.delete(_tableName, where: 'status = ?', whereArgs: ['success']);
  }

  static Future<Map<String, dynamic>> getQueueStats() async {
    final db = await database;
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as total, '
      'SUM(LENGTH(data)) as total_size, '
      'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as pending_count, '
      'SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as failed_count '
      'FROM $_tableName',
      ['pending', 'failed'],
    );
    return countResult.first;
  }

  static Future<void> vacuum() async {
    final db = await database;
    await db.rawQuery('VACUUM');
  }
}
