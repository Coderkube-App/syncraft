// A CachedResponse stores the last successful GET response.
// When offline, syncraft returns this instead of making a network call.
// This prevents the app from freezing when GET is called with no internet.

class CachedResponse {
  final String endpoint; // the API URL this cache belongs to
  final String responseBody; // the raw JSON response string from the server
  final DateTime cachedAt; // when this response was last saved
  final int statusCode; // HTTP status code e.g. 200
  final DateTime? lastAccessedAt; // when this cache was last read (for LRU)

  CachedResponse({
    required this.endpoint,
    required this.responseBody,
    required this.cachedAt,
    required this.statusCode,
    this.lastAccessedAt,
  });

  // Convert to Map for SQLite insert
  Map<String, dynamic> toMap() => {
        'endpoint': endpoint,
        'response_body': responseBody,
        'cached_at': cachedAt.toIso8601String(),
        'status_code': statusCode,
        'last_accessed_at': (lastAccessedAt ?? cachedAt).toIso8601String(),
      };

  // Create from SQLite row
  factory CachedResponse.fromMap(Map<String, dynamic> map) => CachedResponse(
        endpoint: map['endpoint'] as String,
        responseBody: map['response_body'] as String,
        cachedAt: DateTime.parse(map['cached_at'] as String),
        statusCode: (map['status_code'] as int?) ?? 200,
        lastAccessedAt: map['last_accessed_at'] != null
            ? DateTime.tryParse(map['last_accessed_at'] as String)
            : null,
      );
}
