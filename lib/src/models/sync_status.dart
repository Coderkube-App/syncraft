import 'package:syncraft/syncraft.dart';

/// Represents a synchronization event emitted on the [SyncService.statusStream].
///
/// Developers can listen to this stream to provide real-time feedback in the UI,
/// such as showing a progress bar or a success snackbar.
class SyncStatus {
  /// The type of event ('syncing', 'synced', 'failed', 'queued').
  final String event;

  /// The number of items being processed. Typically present for 'syncing' events.
  final int? count;

  /// The specific [SyncItem] that was processed.
  final SyncItem? item;

  /// An error message. Present only for 'failed' events.
  final String? error;

  const SyncStatus._({
    required this.event,
    this.count,
    this.item,
    this.error,
  });

  /// Creates a status indicating that a batch of items has started syncing.
  factory SyncStatus.syncing(int count) =>
      SyncStatus._(event: 'syncing', count: count);

  /// Creates a status indicating that an item has been successfully synced.
  factory SyncStatus.synced(SyncItem item) =>
      SyncStatus._(event: 'synced', item: item);

  /// Creates a status indicating that an item failed to sync.
  factory SyncStatus.failed(SyncItem item, String error) =>
      SyncStatus._(event: 'failed', item: item, error: error);

  /// Creates a status indicating that an item was saved offline (queued).
  factory SyncStatus.queued(SyncItem item) =>
      SyncStatus._(event: 'queued', item: item);
}
