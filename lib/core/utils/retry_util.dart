/// Retries [fn] up to [attempts] times with exponential backoff (1 s, 2 s, 4 s…).
/// If [shouldRetry] is provided, only retries when it returns true for the thrown error.
/// If [delayFor] is provided it chooses how long to wait after a failed
/// attempt (0-based) instead of the exponential default, for example to honour
/// a server's `Retry-After`.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int attempts = 3,
  bool Function(Object)? shouldRetry,
  Duration Function(Object error, int attempt)? delayFor,
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      final isLast = i == attempts - 1;
      if (isLast || (shouldRetry != null && !shouldRetry(e))) rethrow;
      await Future.delayed(delayFor?.call(e, i) ?? Duration(seconds: 1 << i));
    }
  }
  throw StateError('unreachable');
}
