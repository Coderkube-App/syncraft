// A SyncItem is one queued API request stored in SQLite.
// Every request (GET/POST/PUT/DELETE) that needs to be sent
// becomes a SyncItem. If offline, it waits until internet returns.

import 'dart:convert';

class SyncItem {
  final String id; // unique UUID for this request
  final String endpoint; // full API URL e.g. https://api.example.com/posts
  final String method; // GET, POST, PUT, PATCH, DELETE
  final Map<String, dynamic> data; // request body (empty map for GET)
  final Map<String, String> headers; // custom HTTP headers
  String status; // pending, syncing, success, failed
  int retryCount; // how many times we tried and failed
  final DateTime createdAt; // when this request was first created
  final String? requestHash; // MD5 hash used to detect duplicate requests

  SyncItem({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.data,
    this.headers = const {},
    this.status = 'pending',
    this.retryCount = 0,
    DateTime? createdAt,
    this.requestHash,
  }) : createdAt = createdAt ?? DateTime.now();

  // Convert SyncItem to a Map so we can save it to SQLite
  Map<String, dynamic> toMap() => {
        'id': id,
        'endpoint': endpoint,
        'method': method,
        'data': jsonEncode(data),
        'headers': jsonEncode(headers),
        'status': status,
        'retry_count': retryCount,
        'created_at': createdAt.toIso8601String(),
        'request_hash': requestHash ?? '',
      };

  // Create a SyncItem from a SQLite row (Map)
  factory SyncItem.fromMap(Map<String, dynamic> map) => SyncItem(
        id: map['id'] as String,
        endpoint: map['endpoint'] as String,
        method: map['method'] as String,
        data: Map<String, dynamic>.from(
          jsonDecode(map['data'] as String) as Map,
        ),
        headers: Map<String, String>.from(
          jsonDecode(map['headers'] as String? ?? '{}') as Map,
        ),
        status: map['status'] as String,
        retryCount: (map['retry_count'] as int?) ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String),
        requestHash: map['request_hash'] as String?,
      );

  @override
  String toString() =>
      'SyncItem($method $endpoint status=$status retries=$retryCount)';
}
