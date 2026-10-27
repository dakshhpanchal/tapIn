/// Open Food Facts answered, but not with a product: it is overloaded, rate
/// limiting this address (429), or down (500/502/503/504). Unlike "no such
/// product" this is worth trying again shortly, and the user can be told so.
class OffUnavailableException implements Exception {
  final int statusCode;

  /// How long the server asked clients to wait (`Retry-After`), if it said.
  final Duration? retryAfter;

  const OffUnavailableException(this.statusCode, {this.retryAfter});

  /// The statuses that mean "busy or down" rather than "not found".
  static bool isUnavailable(int statusCode) =>
      statusCode == 429 || (statusCode >= 500 && statusCode <= 504);

  /// The `Retry-After` header as a duration, for the seconds form servers
  /// send. The HTTP-date form is ignored (null).
  static Duration? parseRetryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  @override
  String toString() => 'OffUnavailableException(HTTP $statusCode)';
}
