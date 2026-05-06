// SQLite storage for GET response caching (cached_responses table).
// When a GET request succeeds, the response is saved here.
// When offline, syncraft reads from here instead of freezing.
//
// Cache management strategy (simple and performant):
//   1. TTL Expiry  — delete rows older than cacheDurationHours on app start
//   2. LRU Eviction — when row count or size limit is exceeded,
//                     delete least-recently-accessed rows first
//   3. Upsert      — when new data arrives, it REPLACES the old row
//                     for the same endpoint (no stale data accumulates)
//   4. VACUUM      — run weekly to shrink the .db file on disk
//
// There is NO compression — this keeps the code simple and readable.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/cache_stats.dart';
import '../models/cached_response.dart';

class CacheStorage {
  // Singleton database instance
  static Database? _database;

  static const String _tableName = 'cached_responses';
  // Key used in SharedPreferences to remember when we last ran VACUUM
  static const String _vacuumPrefKey = 'syncraft_last_vacuum';

  // Opens the database and creates the cached_responses table if needed
  static Future<Database> get database async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'syncraft_cache.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            endpoint         TEXT PRIMARY KEY,
            response_body    TEXT NOT NULL,
            cached_at        TEXT NOT NULL,
            status_code      INTEGER NOT NULL DEFAULT 200,
            last_accessed_at TEXT NOT NULL
          )
        ''');
      },
    );

    return _database!;
  }

  // Save (or replace) a cached GET response for an endpoint.
  // When new data arrives from the server, the old row is replaced.
  // After saving, enforce row and size limits (LRU eviction).
  static Future<void> saveResponse(
    CachedResponse response, {
    int maxRows = 200,
    int maxSizeMB = 10,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Upsert — replace the old row if this endpoint already has a cache
    await db.insert(
      _tableName,
      {
        'endpoint': response.endpoint,
        'response_body': response.responseBody,
        'cached_at': response.cachedAt.toIso8601String(),
        'status_code': response.statusCode,
        'last_accessed_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('syncraft: cached → ${response.endpoint}');

    // After saving new data, remove oldest rows if limits are exceeded
    await enforceCacheLimit(maxRows: maxRows, maxSizeMB: maxSizeMB);
  }

  // Read a cached response for an endpoint.
  // Returns null if this endpoint has never been cached.
  // Also updates last_accessed_at for LRU tracking.
  static Future<CachedResponse?> getResponse(String endpoint) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      where: 'endpoint = ?',
      whereArgs: [endpoint],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    // Update last_accessed_at so this row is protected from LRU eviction
    await db.update(
      _tableName,
      {'last_accessed_at': DateTime.now().toIso8601String()},
      where: 'endpoint = ?',
      whereArgs: [endpoint],
    );

    return CachedResponse.fromMap(rows.first);
  }

  // Delete the cache for one specific endpoint
  static Future<void> deleteResponse(String endpoint) async {
    final db = await database;
    await db.delete(_tableName, where: 'endpoint = ?', whereArgs: [endpoint]);
    debugPrint('syncraft: cache deleted for $endpoint');
  }

  // Delete ALL cached responses
  static Future<void> clearAll() async {
    final db = await database;
    final count = await db.delete(_tableName);
    debugPrint('syncraft: cache cleared — $count row(s) removed');
    await vacuum();
  }

  // Delete cache rows that are older than [maxAgeHours].
  // Called on every app start to keep the cache fresh.
  static Future<void> deleteExpiredCache(int maxAgeHours) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: maxAgeHours)).toIso8601String();

    final count = await db.delete(
      _tableName,
      where: 'cached_at < ?',
      whereArgs: [cutoff],
    );

    if (count > 0) {
      debugPrint('syncraft: TTL expired — deleted $count old cache row(s)');
    }
  }

  // Enforce row count and size limits using LRU (least recently accessed first).
  // Called after every saveResponse() to prevent unbounded growth.
  static Future<void> enforceCacheLimit({
    required int maxRows,
    required int maxSizeMB,
  }) async {
    final db = await database;

    // Step A — Row count check
    // If we have more rows than allowed, delete the oldest accessed ones first
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_tableName',
    );
    final currentCount = (countResult.first['cnt'] as int?) ?? 0;

    if (currentCount > maxRows) {
      final overflow = currentCount - maxRows;
      await db.rawDelete(
        'DELETE FROM $_tableName WHERE endpoint IN ('
        '  SELECT endpoint FROM $_tableName '
        '  ORDER BY last_accessed_at ASC LIMIT ?'
        ')',
        [overflow],
      );
      debugPrint(
          'syncraft: LRU eviction — removed $overflow row(s) (row limit)');
    }

    // Step B — Size check in MB
    // If total response body size exceeds limit, delete 20 oldest at a time
    bool tooBig = true;
    while (tooBig) {
      final sizeResult = await db.rawQuery(
        'SELECT SUM(LENGTH(response_body)) as total_bytes FROM $_tableName',
      );
      final totalBytes = (sizeResult.first['total_bytes'] as int?) ?? 0;
      final sizeMB = totalBytes / (1024 * 1024);

      if (sizeMB > maxSizeMB) {
        await db.rawDelete(
          'DELETE FROM $_tableName WHERE endpoint IN ('
          '  SELECT endpoint FROM $_tableName '
          '  ORDER BY last_accessed_at ASC LIMIT 20'
          ')',
        );
        debugPrint(
          'syncraft: LRU eviction — removed 20 row(s) '
          '(size ${sizeMB.toStringAsFixed(2)}MB > ${maxSizeMB}MB)',
        );
      } else {
        tooBig = false;
      }
    }
  }

  // Run SQLite VACUUM at most once per week.
  // VACUUM reclaims disk space that SQLite holds after row deletions.
  // Without VACUUM, the .db file never shrinks even after deleting rows.
  static Future<void> runVacuumIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastVacuumStr = prefs.getString(_vacuumPrefKey);

    bool shouldVacuum = true;

    if (lastVacuumStr != null) {
      final lastVacuum = DateTime.tryParse(lastVacuumStr);
      if (lastVacuum != null) {
        final daysSince = DateTime.now().difference(lastVacuum).inDays;
        shouldVacuum = daysSince >= 7; // only run once per week
      }
    }

    if (shouldVacuum) {
      await vacuum();
      await prefs.setString(
        _vacuumPrefKey,
        DateTime.now().toIso8601String(),
      );
    }
  }

  // Run VACUUM directly — shrinks the .db file on disk
  static Future<void> vacuum() async {
    final db = await database;
    await db.rawQuery('VACUUM');
    debugPrint('syncraft: VACUUM complete — cache file shrunk');
  }

  // Get cache statistics for the CacheStats model
  static Future<Map<String, dynamic>> getCacheStats() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT '
      '  COUNT(*) as row_count, '
      '  SUM(LENGTH(response_body)) as total_bytes, '
      '  MIN(cached_at) as oldest, '
      '  MAX(cached_at) as newest '
      'FROM $_tableName',
    );
    return result.first;
  }

  // Build the full CacheStats object combining cache + queue data
  static Future<CacheStats> buildCacheStats(
    Map<String, dynamic> queueStats,
  ) async {
    final cacheData = await getCacheStats();

    final cacheBytes = (cacheData['total_bytes'] as int?) ?? 0;
    final queueBytes = (queueStats['total_size'] as int?) ?? 0;
    final cacheMB = cacheBytes / (1024 * 1024);
    final queueMB = queueBytes / (1024 * 1024);

    return CacheStats(
      cacheRowCount: (cacheData['row_count'] as int?) ?? 0,
      queueRowCount: (queueStats['total'] as int?) ?? 0,
      cacheSizeMB: double.parse(cacheMB.toStringAsFixed(3)),
      queueSizeMB: double.parse(queueMB.toStringAsFixed(3)),
      totalSizeMB: double.parse((cacheMB + queueMB).toStringAsFixed(3)),
      oldestCache: cacheData['oldest'] != null
          ? DateTime.tryParse(cacheData['oldest'] as String)
          : null,
      newestCache: cacheData['newest'] != null
          ? DateTime.tryParse(cacheData['newest'] as String)
          : null,
      pendingCount: (queueStats['pending_count'] as int?) ?? 0,
      failedCount: (queueStats['failed_count'] as int?) ?? 0,
    );
  }
}
