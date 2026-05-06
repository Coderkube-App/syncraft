// SyncResult is returned from getData() and sendData().
// The developer checks these fields to know what happened
// and decide what to show in the UI.
//
// Key flags:
//   success    — true if data was fetched or request was sent
//   fromCache  — true if the data came from local SQLite cache
//   queued     — true if the request was saved for later sync
//   hasNoCache — true if offline AND no cached data exists yet
//   message    — friendly message from SyncCraftConfig (show in UI)

class SyncResult {
  // Whether this result should be treated as successful by the app
  final bool success;

  // The JSON response body — present when success=true and not queued
  final String? data;

  // Error details — present when success=false and hasNoCache=false
  final String? error;

  // True when data came from the local SQLite cache (offline mode)
  final bool fromCache;

  // True when the request was saved to queue (offline mode)
  final bool queued;

  // True when offline AND no cache exists for this endpoint
  // This is NOT an error — it is a first-time-offline state
  // Show an empty state, NOT an error screen
  final bool hasNoCache;

  // A friendly human-readable message from SyncCraftConfig
  // Use this directly in snackbars, banners, or empty states
  final String message;

  const SyncResult._({
    required this.success,
    this.data,
    this.error,
    this.fromCache = false,
    this.queued = false,
    this.hasNoCache = false,
    this.message = '',
  });

  // Online GET succeeded — data is fresh from the server
  factory SyncResult.success(String data) =>
      SyncResult._(success: true, data: data);

  // Offline GET succeeded — data came from local cache
  factory SyncResult.cached(String data, {String message = ''}) =>
      SyncResult._(success: true, data: data, fromCache: true, message: message);

  // Request saved to queue — will sync when internet returns
  factory SyncResult.queued({String message = ''}) =>
      SyncResult._(success: true, queued: true, message: message);

  // Offline + no cache at all — first time user, no data yet
  // NOT an error — show empty state with helpful message
  factory SyncResult.noCache({String message = ''}) => SyncResult._(
        success: false,
        queued: true,
        hasNoCache: true,
        message: message,
      );

  // A real failure — network error or server error
  factory SyncResult.failure(String error) =>
      SyncResult._(success: false, error: error);
}
