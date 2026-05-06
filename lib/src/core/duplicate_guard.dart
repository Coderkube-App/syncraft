// DuplicateGuard prevents the same POST/PUT from being queued twice.
// Common scenario: user taps Submit button twice quickly.
// We create an MD5 hash of endpoint + method + data.
// Before enqueuing, we check if a pending item with this hash exists.
// If yes — skip it silently. If no — allow it through.

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../storage/local_storage.dart';

class DuplicateGuard {
  // Generate a unique fingerprint for a request.
  // Same endpoint + method + data will always produce the same hash.
  static String generateHash(
    String endpoint,
    String method,
    Map<String, dynamic> data,
  ) {
    final input = '$method:$endpoint:${jsonEncode(data)}';
    final bytes = utf8.encode(input);
    return md5.convert(bytes).toString();
  }

  // Returns true if a pending item with this hash already exists in the queue.
  // Returns false if it is safe to enqueue this request.
  static Future<bool> isDuplicate(String hash) async {
    return LocalStorage.itemExistsByHash(hash);
  }
}
