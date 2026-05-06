/// Syncraft is a robust Flutter package for managing API request synchronization,
/// local caching, and offline data handling.
///
/// It provides a [SyncService] to handle requests, a sync queue for offline
/// operations, and cache management tools to monitor database health.
library syncraft;

// The one public class developers use
export 'src/service/sync_service.dart';

// Config — passed to SyncService to customize messages and behavior
export 'src/config/sync_craft_config.dart';

// Models — used in callbacks and return values
export 'src/models/sync_item.dart';
export 'src/models/sync_result.dart';
export 'src/models/sync_status.dart';
export 'src/models/cached_response.dart';
export 'src/models/cache_stats.dart';

// Utility — useful for UI to check connectivity
export 'src/network/network_checker.dart';
