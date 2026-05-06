/// Represents the outcome of an operation performed by [SyncService].
///
/// Developers should check these fields to determine how to update the UI.
/// For example, checking [fromCache] to show a "Viewing offline data" banner,
/// or [queued] to show a "Saved offline" snackbar.
class SyncResult {
  /// Whether this result should be treated as successful by the application.
  final bool success;

  /// The JSON response body. Present when [success] is true and not [queued].
  final String? data;

  /// Error details. Present when [success] is false and [hasNoCache] is false.
  final String? error;

  /// True when the data was retrieved from the local SQLite cache.
  final bool fromCache;

  /// True when the request was saved to the sync queue for later processing.
  final bool queued;

  /// True when the device is offline and no cached data exists for the endpoint.
  ///
  /// This is not an error state; it indicates a "first-time offline" scenario.
  /// Developers should typically show an empty state rather than an error screen.
  final bool hasNoCache;

  /// A friendly human-readable message from [SyncCraftConfig].
  ///
  /// Can be used directly in snackbars, banners, or empty state widgets.
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

  /// Creates a result representing a successful online GET request.
  factory SyncResult.success(String data) =>
      SyncResult._(success: true, data: data);

  /// Creates a result representing data retrieved from the local cache.
  factory SyncResult.cached(String data, {String message = ''}) => SyncResult._(
      success: true, data: data, fromCache: true, message: message);

  /// Creates a result representing a request that has been queued for later sync.
  factory SyncResult.queued({String message = ''}) =>
      SyncResult._(success: true, queued: true, message: message);

  /// Creates a result representing an offline state where no cache is available.
  factory SyncResult.noCache({String message = ''}) => SyncResult._(
        success: false,
        queued: true,
        hasNoCache: true,
        message: message,
      );

  /// Creates a result representing a direct failure (e.g., server or network error).
  factory SyncResult.failure(String error) =>
      SyncResult._(success: false, error: error);
}
