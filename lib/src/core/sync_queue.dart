// SyncQueue manages the request queue using LocalStorage.
// It supports both GET (background refresh) and POST/PUT/DELETE queues.
// For non-GET methods, it checks for duplicate requests before enqueuing.

import 'package:flutter/foundation.dart';

import '../models/sync_item.dart';
import '../storage/local_storage.dart';
import 'duplicate_guard.dart';

class SyncQueue {
  // Add a request to the queue.
  // For GET: always allowed (idempotent — safe to have duplicates).
  // For POST/PUT/DELETE: blocked if a pending item with the same hash exists.
  // Returns true if the item was enqueued, false if it was a duplicate.
  Future<bool> enqueue(SyncItem item) async {
    if (item.method != 'GET' &&
        item.requestHash != null &&
        item.requestHash!.isNotEmpty) {
      final duplicate = await DuplicateGuard.isDuplicate(item.requestHash!);
      if (duplicate) {
        debugPrint(
          'syncraft: duplicate blocked → ${item.method} ${item.endpoint}',
        );
        return false;
      }
    }
    await LocalStorage.insertItem(item);
    return true;
  }

  // Get all pending items (waiting to be sent)
  Future<List<SyncItem>> getPending() => LocalStorage.getPendingItems();

  // Get all failed items (tried but got an error)
  Future<List<SyncItem>> getFailed() => LocalStorage.getFailedItems();

  // Mark item as successfully sent and remove it from the queue
  Future<void> markSuccess(String id) async {
    await LocalStorage.updateStatus(id, 'success');
    await LocalStorage.deleteItem(id);
  }

  // Mark item as failed — stays in queue for retry
  Future<void> markFailed(String id) async {
    await LocalStorage.updateStatus(id, 'failed');
    await LocalStorage.incrementRetry(id);
  }
}
