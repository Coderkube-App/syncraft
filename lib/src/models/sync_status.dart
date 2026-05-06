// SyncStatus is emitted on the statusStream so the UI can react in real time.
// The developer listens to this stream to show live sync feedback.

import 'sync_item.dart';

class SyncStatus {
  final String event; // 'syncing', 'synced', 'failed', 'queued'
  final int? count; // number of items being synced (for 'syncing' event)
  final SyncItem? item; // the item that was processed
  final String? error; // error message (only for 'failed' event)

  const SyncStatus._({
    required this.event,
    this.count,
    this.item,
    this.error,
  });

  // Called when we start syncing a batch — count = number of items
  factory SyncStatus.syncing(int count) =>
      SyncStatus._(event: 'syncing', count: count);

  // Called when a single item was successfully sent to the server
  factory SyncStatus.synced(SyncItem item) =>
      SyncStatus._(event: 'synced', item: item);

  // Called when a single item failed to send
  factory SyncStatus.failed(SyncItem item, String error) =>
      SyncStatus._(event: 'failed', item: item, error: error);

  // Called when an item was saved offline (queued for later)
  factory SyncStatus.queued(SyncItem item) =>
      SyncStatus._(event: 'queued', item: item);
}
