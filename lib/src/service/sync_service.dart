// SyncService is the ONLY class developers import and use.
// Everything else (SyncManager, SyncQueue, LocalStorage, CacheStorage)
// is internal — developers never touch those directly.
//
// Two main methods:
//   getData()  — GET requests. Returns cache instantly if offline.
//   sendData() — POST/PUT/DELETE. Queues silently if offline.
//
// Three optional callbacks:
//   onQueued(item, message) — called when a request is saved offline
//   onSynced(item, message) — called when a queued request is sent
//   onFailed(item, err, message) — called when a request fails
//
// Call init() once in main() or initState() to start background sync.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/sync_craft_config.dart';
import '../core/duplicate_guard.dart';
import '../core/sync_manager.dart';
import '../core/sync_queue.dart';
import '../models/cache_stats.dart';
import '../models/sync_item.dart';
import '../models/sync_result.dart';
import '../models/sync_status.dart';
import '../network/network_checker.dart';
import '../storage/cache_storage.dart';
import '../storage/local_storage.dart';

/// SyncService is the primary interface for developers using the Syncraft package.
///
/// It handles GET requests (with local caching) via [getData] and
/// POST/PUT/PATCH/DELETE requests (with offline queuing) via [sendData].
///
/// It also manages the background synchronization process and provides
/// hooks for UI feedback through callbacks like [onQueued], [onSynced],
/// and [onFailed].
class SyncService {
  /// All configuration — messages, timeouts, limits — lives here.
  final SyncCraftConfig config;

  /// Optional callbacks so the UI can react to sync events.
  /// Each callback receives the item AND the message from [SyncCraftConfig].

  /// Called when a request is saved offline due to lack of connectivity.
  final void Function(SyncItem item, String message)? onQueued;

  /// Called when a queued request is successfully sent to the server.
  final void Function(SyncItem item, String message)? onSynced;

  /// Called when a request fails due to a server or network error.
  final void Function(SyncItem item, String error, String message)? onFailed;

  final SyncManager _manager;
  final SyncQueue _queue;

  /// The sync status stream — listen to this in your UI for live updates.
  Stream<SyncStatus> get statusStream => _manager.statusStream;

  /// Creates a new [SyncService] with optional configuration and callbacks.
  SyncService({
    SyncCraftConfig? config,
    this.onQueued,
    this.onSynced,
    this.onFailed,
  })  : config = config ?? const SyncCraftConfig(),
        _queue = SyncQueue(),
        _manager = SyncManager(
          timeoutSeconds: (config ?? const SyncCraftConfig()).timeoutSeconds,
          maxCacheRows: (config ?? const SyncCraftConfig()).maxCacheRows,
          maxCacheSizeMB: (config ?? const SyncCraftConfig()).maxCacheSizeMB,
        );

  /// Initializes the service. Call this ONCE in main() or initState().
  ///
  /// This performs database maintenance:
  /// 1. Deletes expired cache entries based on TTL.
  /// 2. Enforces row/size limits (LRU).
  /// 3. Runs VACUUM if configured.
  /// 4. Subscribes to the status stream for callbacks.
  /// 5. Starts the connectivity listener for auto-sync.
  Future<void> init() async {
    // Step 1 — delete cache rows older than cacheDurationHours
    await CacheStorage.deleteExpiredCache(config.cacheDurationHours);

    // Step 2 — remove oldest rows if limits are exceeded
    await CacheStorage.enforceCacheLimit(
      maxRows: config.maxCacheRows,
      maxSizeMB: config.maxCacheSizeMB,
    );

    // Step 3 — shrink the .db file on disk once per week
    if (config.vacuumOnStartup) {
      await CacheStorage.runVacuumIfNeeded();
    }

    // Step 4 — wire up callbacks from the status stream
    _manager.statusStream.listen((status) {
      if (status.event == 'synced' && status.item != null) {
        onSynced?.call(status.item!, config.msgSynced);
      }
      if (status.event == 'failed' && status.item != null) {
        onFailed?.call(
          status.item!,
          status.error ?? 'Unknown error',
          config.msgFailed,
        );
      }
    });

    // Step 5 — listen for network changes and auto-sync when internet returns
    NetworkChecker.onConnectivityChanged.listen((bool hasInterface) async {
      if (hasInterface) {
        // Network interface is up, but internet data might take a moment to flow.
        // We check up to 3 times before giving up.
        bool isTrulyOnline = false;
        for (int i = 0; i < 3; i++) {
          isTrulyOnline = await NetworkChecker.isConnected();
          if (isTrulyOnline) break;
          await Future.delayed(const Duration(seconds: 1));
        }

        if (!isTrulyOnline) return;

        debugPrint('syncraft: ${config.msgNetworkRestored}');
        if (config.autoSyncOnReconnect) {
          // Small delay ensures DNS/routing is ready before we fire requests
          Future.delayed(const Duration(seconds: 2), () {
            _manager.retryFailed().whenComplete(_manager.syncPending);
          });
        }
      } else {
        debugPrint('syncraft: ${config.msgOfflineBanner}');
      }
    });

    debugPrint('syncraft: initialized — DB optimized ✓');
  }

  /// Use this for GET requests.
  ///
  /// If ONLINE  → makes live HTTP call, saves response to cache, returns data.
  /// If OFFLINE → returns cached data instantly ([SyncResult.cached]) and
  ///              queues a background refresh for when internet returns.
  /// If OFFLINE and NO CACHE → queues the request, returns [SyncResult.noCache].
  ///
  /// The app NEVER freezes. This method always returns immediately if cache exists.
  Future<SyncResult> getData({
    required String endpoint,
    Map<String, String> headers = const {},
  }) async {
    final online = await NetworkChecker.isConnected();

    if (online) {
      // Online — make live request, cache will be updated on success
      final item = SyncItem(
        id: const Uuid().v4(),
        endpoint: endpoint,
        method: 'GET',
        data: {},
        headers: headers,
      );
      return _manager.sendRequest(item);
    } else {
      // Offline — try to return cached data first
      final cached = await CacheStorage.getResponse(endpoint);

      if (cached != null) {
        // Cache exists — return it instantly, queue a background refresh
        debugPrint('syncraft: offline — returning cache for $endpoint');

        // Queue a background GET so we get fresh data when internet returns
        final refreshItem = SyncItem(
          id: const Uuid().v4(),
          endpoint: endpoint,
          method: 'GET',
          data: {},
          headers: headers,
        );
        await _queue.enqueue(refreshItem);

        return SyncResult.cached(
          cached.responseBody,
          message: config.msgCachedBanner,
        );
      } else {
        // No cache at all — first time offline, nothing to show yet
        // Queue the GET so it fires automatically when internet returns
        debugPrint('syncraft: offline — no cache for $endpoint, queued');

        final item = SyncItem(
          id: const Uuid().v4(),
          endpoint: endpoint,
          method: 'GET',
          data: {},
          headers: headers,
        );
        await _queue.enqueue(item);

        // Return noCache — developer shows empty state, NOT an error screen
        return SyncResult.noCache(message: config.msgNoCache);
      }
    }
  }

  /// Use this for POST, PUT, PATCH, DELETE requests.
  ///
  /// If ONLINE  → saves to queue, sends immediately, removes on success.
  /// If OFFLINE → saves to queue, fires [onQueued] callback, auto-sends on reconnect.
  ///
  /// Duplicate protection — if same endpoint+method+data is already pending,
  /// it is silently ignored.
  Future<SyncResult> sendData({
    required String endpoint,
    required Map<String, dynamic> data,
    String method = 'POST',
    Map<String, String> headers = const {},
  }) async {
    // Generate a hash to detect duplicates (POST/PUT only)
    final hash = DuplicateGuard.generateHash(endpoint, method, data);

    final item = SyncItem(
      id: const Uuid().v4(),
      endpoint: endpoint,
      method: method,
      data: data,
      headers: headers,
      requestHash: hash,
    );

    // Always save locally FIRST — data is never lost even if app crashes
    final enqueued = await _queue.enqueue(item);
    if (!enqueued) {
      // Was a duplicate — silently return as if queued
      debugPrint('syncraft: duplicate blocked — $method $endpoint');
      return SyncResult.queued(message: config.msgQueued);
    }

    final online = await NetworkChecker.isConnected();

    if (online) {
      // Online — send it now
      return _manager.sendRequest(item);
    } else {
      // Offline — notify the developer's UI via callback
      debugPrint('syncraft: offline — queued → $method $endpoint');
      onQueued?.call(item, config.msgQueued);
      _manager.statusStream; // allow stream listeners to react
      return SyncResult.queued(message: config.msgQueued);
    }
  }

  /// Manually retry all failed items.
  ///
  /// Call this from a "Retry" button in your UI.
  /// Does nothing if offline.
  Future<void> retryFailed() async {
    final online = await NetworkChecker.isConnected();
    if (!online) {
      debugPrint('syncraft: retryFailed skipped — no internet');
      return;
    }
    await _manager.retryFailed();
  }

  /// Get all pending items (useful for showing a queue badge count).
  Future<List<SyncItem>> getPendingItems() => _queue.getPending();

  /// Get all failed items (useful for showing error states in UI).
  Future<List<SyncItem>> getFailedItems() => _queue.getFailed();

  /// Get a full snapshot of the database health.
  ///
  /// Use this in a debug/admin screen to monitor cache and queue size.
  Future<CacheStats> getCacheStats() async {
    final queueStats = await LocalStorage.getQueueStats();
    return CacheStorage.buildCacheStats(queueStats);
  }

  /// Delete all cached GET responses and run VACUUM.
  ///
  /// Does NOT affect the pending/failed queue.
  Future<void> clearCache() async {
    await CacheStorage.clearAll();
    debugPrint('syncraft: cache cleared');
  }

  /// Delete only successfully synced items from the queue.
  ///
  /// Keeps pending and failed items so they are not lost.
  Future<void> clearQueue() async {
    await LocalStorage.clearSuccessful();
    await LocalStorage.vacuum();
    debugPrint('syncraft: queue cleaned');
  }

  /// Clean up resources. Call in dispose() of your widget/service.
  void dispose() => _manager.dispose();
}
