// Tests for the syncraft package.
// These tests cover all models, utilities, and basic service behavior.
// Tests do not require a real device — all SQLite calls are avoided
// in unit tests (SQLite platform channel is not available in test runner).

import 'package:flutter_test/flutter_test.dart';
import 'package:syncraft/syncraft.dart';
// ignore: implementation_imports
import 'package:syncraft/src/core/duplicate_guard.dart';

void main() {
  group('SyncItem', () {
    test('1. default status is pending', () {
      final item = SyncItem(
        id: 'abc-123',
        endpoint: 'https://example.com/posts',
        method: 'POST',
        data: {},
      );
      expect(item.status, 'pending');
    });

    test('2. default retryCount is 0', () {
      final item = SyncItem(
        id: 'abc-123',
        endpoint: 'https://example.com/posts',
        method: 'POST',
        data: {},
      );
      expect(item.retryCount, 0);
    });

    test('3. toMap / fromMap round-trip preserves all fields', () {
      final original = SyncItem(
        id: 'test-id-001',
        endpoint: 'https://api.example.com/orders',
        method: 'POST',
        data: {'name': 'Alice', 'amount': 99},
        headers: {'Authorization': 'Bearer token123'},
        status: 'pending',
        retryCount: 2,
        requestHash: 'abc123hash',
      );

      final roundTrip = SyncItem.fromMap(original.toMap());

      expect(roundTrip.id, original.id);
      expect(roundTrip.endpoint, original.endpoint);
      expect(roundTrip.method, original.method);
      expect(roundTrip.data['name'], original.data['name']);
      expect(roundTrip.data['amount'], original.data['amount']);
      expect(roundTrip.headers['Authorization'],
          original.headers['Authorization']);
      expect(roundTrip.status, original.status);
      expect(roundTrip.retryCount, original.retryCount);
      expect(roundTrip.requestHash, original.requestHash);
      expect(
        roundTrip.createdAt.toIso8601String(),
        original.createdAt.toIso8601String(),
      );
    });

    test('4. toString contains method and endpoint', () {
      final item = SyncItem(
        id: 'x',
        endpoint: 'https://example.com/submit',
        method: 'DELETE',
        data: {},
      );
      expect(item.toString(), contains('DELETE'));
      expect(item.toString(), contains('https://example.com/submit'));
    });
  });

  group('SyncResult', () {
    test('5. SyncResult.queued() has queued=true and success=true', () {
      final result = SyncResult.queued();
      expect(result.queued, isTrue);
      expect(result.success, isTrue);
      expect(result.hasNoCache, isFalse);
    });

    test('6. SyncResult.cached() has fromCache=true and success=true', () {
      final result = SyncResult.cached('{"data": "test"}');
      expect(result.fromCache, isTrue);
      expect(result.success, isTrue);
      expect(result.data, '{"data": "test"}');
    });

    test('7. SyncResult.noCache() has hasNoCache=true and queued=true', () {
      final result = SyncResult.noCache(message: 'No data yet');
      expect(result.hasNoCache, isTrue);
      expect(result.queued, isTrue);
      expect(result.success, isFalse);
      expect(result.message, 'No data yet');
    });

    test('8. SyncResult.success() has success=true and data set', () {
      final result = SyncResult.success('{"id": 1}');
      expect(result.success, isTrue);
      expect(result.data, '{"id": 1}');
      expect(result.fromCache, isFalse);
      expect(result.queued, isFalse);
    });

    test('9. SyncResult.failure() has success=false and error set', () {
      final result = SyncResult.failure('HTTP 500');
      expect(result.success, isFalse);
      expect(result.error, 'HTTP 500');
    });

    test('10. SyncResult.cached() carries message from config', () {
      const config = SyncCraftConfig(msgCachedBanner: 'Using local data');
      final result = SyncResult.cached(
        '{}',
        message: config.msgCachedBanner,
      );
      expect(result.message, 'Using local data');
    });
  });

  group('DuplicateGuard', () {
    test('11. same inputs produce same hash', () {
      final hash1 = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'POST',
        {'item': 'shoes', 'qty': 2},
      );
      final hash2 = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'POST',
        {'item': 'shoes', 'qty': 2},
      );
      expect(hash1, hash2);
    });

    test('12. different data produces different hash', () {
      final hash1 = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'POST',
        {'item': 'shoes', 'qty': 2},
      );
      final hash2 = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'POST',
        {'item': 'boots', 'qty': 1},
      );
      expect(hash1, isNot(hash2));
    });

    test('13. different method produces different hash', () {
      final hashPost = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'POST',
        {'item': 'shoes'},
      );
      final hashPut = DuplicateGuard.generateHash(
        'https://example.com/orders',
        'PUT',
        {'item': 'shoes'},
      );
      expect(hashPost, isNot(hashPut));
    });
  });

  group('SyncCraftConfig', () {
    test('14. default config has correct defaults', () {
      const config = SyncCraftConfig();
      expect(config.timeoutSeconds, 10);
      expect(config.maxRetryCount, 3);
      expect(config.autoSyncOnReconnect, isTrue);
      expect(config.cacheDurationHours, 24);
      expect(config.maxCacheRows, 200);
      expect(config.maxCacheSizeMB, 10);
      expect(config.vacuumOnStartup, isTrue);
    });

    test('15. custom config overrides defaults', () {
      const config = SyncCraftConfig(
        msgQueued: 'Order queued',
        timeoutSeconds: 30,
        maxRetryCount: 999,
        autoSyncOnReconnect: false,
      );
      expect(config.msgQueued, 'Order queued');
      expect(config.timeoutSeconds, 30);
      expect(config.maxRetryCount, 999);
      expect(config.autoSyncOnReconnect, isFalse);
    });
  });

  group('SyncService', () {
    test('16. SyncService initializes without throwing', () {
      expect(
        () => SyncService(),
        returnsNormally,
      );
    });

    test('17. SyncService accepts custom config without throwing', () {
      expect(
        () => SyncService(
          config: const SyncCraftConfig(
            msgQueued: 'Custom queued message',
            timeoutSeconds: 15,
          ),
        ),
        returnsNormally,
      );
    });

    test('18. SyncService callbacks can be null (no crash)', () {
      final service = SyncService(
        onQueued: null,
        onSynced: null,
        onFailed: null,
      );
      expect(service, isNotNull);
      service.dispose();
    });

    test('19. SyncService callbacks are accepted without crash', () {
      final service = SyncService(
        onQueued: (item, msg) {},
        onSynced: (item, msg) {},
        onFailed: (item, err, msg) {},
      );
      expect(service, isNotNull);
      service.dispose();
    });
  });

  group('CachedResponse', () {
    test('20. toMap / fromMap round-trip preserves all fields', () {
      final original = CachedResponse(
        endpoint: 'https://api.example.com/posts',
        responseBody: '[{"id":1,"title":"Test"}]',
        cachedAt: DateTime(2024, 1, 15, 10, 30),
        statusCode: 200,
      );

      final roundTrip = CachedResponse.fromMap(original.toMap());

      expect(roundTrip.endpoint, original.endpoint);
      expect(roundTrip.responseBody, original.responseBody);
      expect(roundTrip.statusCode, original.statusCode);
      expect(
        roundTrip.cachedAt.toIso8601String(),
        original.cachedAt.toIso8601String(),
      );
    });
  });
}
