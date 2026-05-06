import 'dart:convert';

/// Represents a single API request that is queued for synchronization.
///
/// Every request (GET/POST/PUT/DELETE) that needs to be sent becomes a [SyncItem].
/// If the device is offline, the item is stored in the local database until
/// internet connectivity is restored.
class SyncItem {
  /// Unique UUID for this request.
  final String id;

  /// Full API URL (e.g., https://api.example.com/posts).
  final String endpoint;

  /// HTTP method (GET, POST, PUT, PATCH, DELETE).
  final String method;

  /// Request body data. Empty map for GET requests.
  final Map<String, dynamic> data;

  /// Custom HTTP headers for this request.
  final Map<String, String> headers;

  /// Current status of the request (pending, syncing, success, failed).
  String status;

  /// Number of times this request has been attempted and failed.
  int retryCount;

  /// Timestamp when this request was first created.
  final DateTime createdAt;

  /// MD5 hash used to detect duplicate requests.
  final String? requestHash;

  /// Creates a new [SyncItem].
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
