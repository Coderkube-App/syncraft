// This is the ONLY file developers import in their Flutter app:
//   import 'package:syncraft/syncraft.dart';
//
// All internal files (LocalStorage, SyncQueue, SyncManager, etc.)
// are in src/ and are NOT exported — developers never use them directly.

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
