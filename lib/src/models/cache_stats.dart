// CacheStats gives the developer a snapshot of the database health.
// Use getCacheStats() from SyncService to get this data.
// Display it in a debug/admin screen to monitor app performance.

class CacheStats {
  // Total number of cached GET responses in the database
  final int cacheRowCount;

  // Total number of items in the sync queue
  final int queueRowCount;

  // Size of all cached response bodies in MB
  final double cacheSizeMB;

  // Size of all queued request bodies in MB
  final double queueSizeMB;

  // Combined total size of cache + queue in MB
  final double totalSizeMB;

  // When the oldest cache entry was saved (null if cache is empty)
  final DateTime? oldestCache;

  // When the newest cache entry was saved (null if cache is empty)
  final DateTime? newestCache;

  // Number of queue items with status = 'pending'
  final int pendingCount;

  // Number of queue items with status = 'failed'
  final int failedCount;

  const CacheStats({
    required this.cacheRowCount,
    required this.queueRowCount,
    required this.cacheSizeMB,
    required this.queueSizeMB,
    required this.totalSizeMB,
    this.oldestCache,
    this.newestCache,
    required this.pendingCount,
    required this.failedCount,
  });

  @override
  String toString() =>
      'CacheStats(rows=$cacheRowCount, cacheMB=$cacheSizeMB, '
      'pending=$pendingCount, failed=$failedCount)';
}
