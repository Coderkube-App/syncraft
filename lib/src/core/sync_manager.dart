// SyncManager is the core engine that sends HTTP requests.
// It handles GET (with cache) and POST/PUT/DELETE (from queue).
// Every request has a timeout — the app NEVER hangs waiting for a response.
//
// Key behaviors:
//   - Every request times out after [timeoutSeconds] (default 10s)
//   - Successful GET responses are saved to CacheStorage
//   - Successful mutations are removed from the queue
//   - Failed requests stay in queue with incremented retry count
//   - All events are emitted on statusStream for the UI to listen

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/cached_response.dart';
import '../models/sync_item.dart';
import '../models/sync_result.dart';
import '../models/sync_status.dart';
import '../storage/cache_storage.dart';
import '../storage/local_storage.dart';
import 'sync_queue.dart';

class SyncManager {
  final SyncQueue _queue;
  final int timeoutSeconds;
  final int maxCacheRows;
  final int maxCacheSizeMB;

  // Internal HTTP client — can be replaced in tests with a mock client
  final http.Client _client;

  // Prevents multiple sync batches from running at the same time
  bool _isSyncing = false;

  // Stream that broadcasts sync events so the UI can react in real time
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncManager({
    SyncQueue? queue,
    http.Client? client,
    this.timeoutSeconds = 10,
    this.maxCacheRows = 200,
    this.maxCacheSizeMB = 10,
  })  : _queue = queue ?? SyncQueue(),
        _client = client ?? http.Client();

  // Send all pending items to the server.
  // Called automatically when internet returns, or manually via retryFailed().
  Future<void> syncPending() async {
    if (_isSyncing) return; // do not run two syncs at the same time
    _isSyncing = true;

    try {
      final items = await _queue.getPending();
      if (items.isEmpty) {
        debugPrint('syncraft: nothing to sync');
        return;
      }

      _statusController.add(SyncStatus.syncing(items.length));
      debugPrint('syncraft: syncing ${items.length} item(s)...');

      for (final item in items) {
        await _sendRequest(item);
      }
    } finally {
      _isSyncing = false;
    }
  }

  // Reset all failed items back to pending and sync them.
  // Call this from a "Retry" button or after reconnect.
  Future<void> retryFailed() async {
    final failed = await _queue.getFailed();
    if (failed.isEmpty) {
      debugPrint('syncraft: no failed items to retry');
      return;
    }

    debugPrint('syncraft: retrying ${failed.length} failed item(s)...');

    // Reset status back to pending so syncPending() can pick them up
    for (final item in failed) {
      await LocalStorage.updateStatus(item.id, 'pending');
    }

    await syncPending();
  }

  // Send a single HTTP request with timeout handling.
  // On success: saves cache (GET) or removes from queue (mutation).
  // On failure: marks as failed, emits failed event.
  Future<SyncResult> sendRequest(SyncItem item) async {
    try {
      final url = Uri.parse(item.endpoint);
      final headers = {
        'Content-Type': 'application/json',
        ...item.headers,
      };
      final body = item.data.isNotEmpty ? jsonEncode(item.data) : null;

      // Make the HTTP call — throws TimeoutException if it takes too long
      final response = await _makeRequest(
        method: item.method,
        url: url,
        headers: headers,
        body: body,
      ).timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => throw TimeoutException(
          'syncraft: request timed out after ${timeoutSeconds}s',
        ),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // SUCCESS — 2xx response
        if (item.method == 'GET') {
          // Cache the GET response so it can be returned when offline later
          await CacheStorage.saveResponse(
            CachedResponse(
              endpoint: item.endpoint,
              responseBody: response.body,
              cachedAt: DateTime.now(),
              statusCode: response.statusCode,
            ),
            maxRows: maxCacheRows,
            maxSizeMB: maxCacheSizeMB,
          );
        }

        await _queue.markSuccess(item.id);
        _statusController.add(SyncStatus.synced(item));
        debugPrint('syncraft: ✓ ${item.method} ${item.endpoint}');
        return SyncResult.success(response.body);
      } else {
        // Server returned a non-2xx error
        await _queue.markFailed(item.id);
        final errorMsg = 'HTTP ${response.statusCode}';
        _statusController.add(SyncStatus.failed(item, errorMsg));
        debugPrint('syncraft: ✗ $errorMsg ${item.endpoint}');
        return SyncResult.failure(errorMsg);
      }
    } on TimeoutException catch (e) {
      await _queue.markFailed(item.id);
      final msg = e.message ?? 'Request timed out';
      _statusController.add(SyncStatus.failed(item, msg));
      debugPrint('syncraft: timeout → ${item.endpoint}');
      return SyncResult.failure(msg);
    } catch (e) {
      await _queue.markFailed(item.id);
      final msg = e.toString();
      _statusController.add(SyncStatus.failed(item, msg));
      debugPrint('syncraft: error → ${item.endpoint} | $e');
      return SyncResult.failure(msg);
    }
  }

  // Internal: send a single request and update queue (used inside syncPending)
  Future<void> _sendRequest(SyncItem item) async {
    await sendRequest(item);
  }

  // Route the request to the correct HTTP method
  Future<http.Response> _makeRequest({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    String? body,
  }) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _client.get(url, headers: headers);
      case 'POST':
        return _client.post(url, headers: headers, body: body);
      case 'PUT':
        return _client.put(url, headers: headers, body: body);
      case 'PATCH':
        return _client.patch(url, headers: headers, body: body);
      case 'DELETE':
        return _client.delete(url, headers: headers);
      default:
        return _client.post(url, headers: headers, body: body);
    }
  }

  // Close the stream controller when the service is no longer needed
  void dispose() => _statusController.close();
}
