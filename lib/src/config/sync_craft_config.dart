// SyncCraftConfig is the single place where developers customize
// every message, timeout, and behavior of the syncraft package.
// Every field has a sensible default so zero config is needed.
// Developer only overrides what they want to change.
//
// Usage — zero config (uses all defaults):
//   final sync = SyncService();
//
// Usage — custom messages:
//   final sync = SyncService(
//     config: SyncCraftConfig(
//       msgQueued: 'Order saved! Will place when online.',
//       msgSynced: 'Order placed!',
//     ),
//   );

/// Configuration class for [SyncService].
///
/// Use this class to customize user-facing messages, timeouts, retry counts,
/// and cache management behavior. All fields have sensible defaults.
class SyncCraftConfig {
  // --- User-facing messages ---

  /// Shown when a POST/PUT/DELETE request is saved offline.
  final String msgQueued;

  /// Shown when a queued request successfully syncs in background.
  final String msgSynced;

  /// Shown when a request fails even after retries.
  final String msgFailed;

  /// Shown when GET is called offline and no cache exists yet.
  ///
  /// This is not an error — it is a temporary "first launch offline" state.
  final String msgNoCache;

  /// Banner message shown when the app is offline.
  final String msgOfflineBanner;

  /// Banner message shown when displaying cached (saved) GET data.
  final String msgCachedBanner;

  /// Shown when network returns and auto-sync starts.
  final String msgNetworkRestored;

  /// Shown when a failed item is being retried.
  final String msgRetrying;

  // --- Behavior settings ---

  /// How many seconds before any HTTP request times out.
  final int timeoutSeconds;

  /// Maximum number of times to retry a failed request.
  final int maxRetryCount;

  /// If true, auto-sync all pending items when internet returns.
  ///
  /// Set false if you want to trigger sync manually using [SyncService.retryFailed].
  final bool autoSyncOnReconnect;

  /// How many hours to keep cached GET data before it is considered stale.
  ///
  /// Stale cache is deleted on app start.
  final int cacheDurationHours;

  /// Maximum number of cache rows to keep.
  ///
  /// Oldest rows are deleted first when this limit is reached.
  final int maxCacheRows;

  /// Maximum cache size in MB.
  ///
  /// Oldest rows are deleted when this size limit is exceeded.
  final int maxCacheSizeMB;

  /// Maximum number of items in the sync queue.
  final int maxQueueRows;

  /// If true, runs SQLite VACUUM weekly on startup to shrink the .db file.
  final bool vacuumOnStartup;

  /// Creates a new [SyncCraftConfig] with the given settings.
  const SyncCraftConfig({
    this.msgQueued =
        'Saved offline. Will sync automatically when internet returns.',
    this.msgSynced = 'Synced successfully in the background.',
    this.msgFailed = 'Sync failed. Will retry automatically.',
    this.msgNoCache = 'No data available yet. Will load when you go online.',
    this.msgOfflineBanner = 'You are offline.',
    this.msgCachedBanner = 'Showing saved data from your last visit.',
    this.msgNetworkRestored = 'Back online! Syncing your data...',
    this.msgRetrying = 'Retrying your request...',
    this.timeoutSeconds = 15,
    this.maxRetryCount = 3,
    this.autoSyncOnReconnect = true,
    this.cacheDurationHours = 24,
    this.maxCacheRows = 200,
    this.maxCacheSizeMB = 10,
    this.maxQueueRows = 500,
    this.vacuumOnStartup = true,
  });
}
