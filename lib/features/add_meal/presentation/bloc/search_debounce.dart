import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

/// Shared tuning for search-as-you-type across the product and food blocs.
///
/// Local matches (your foods, recipes, cache) are shown after this short pause;
/// the network search waits a further [remoteSearchDelay], so the remote source
/// still sees roughly one request per typing pause (the two add up to the old
/// 500 ms).
const searchDebounceDuration = Duration(milliseconds: 200);
const remoteSearchDelay = Duration(milliseconds: 300);

/// Minimum trimmed query length before a search runs at all. Shorter (or
/// blank) input doesn't query any source — local or remote — and resets
/// the search blocs to their initial state.
const minQueryLength = 2;

/// Debounce keystrokes, then run the latest one as a restartable handler so an
/// in-flight search is cancelled the moment a newer query arrives. Keeps the
/// remote source to roughly one request per typing pause.
EventTransformer<E> debounceRestartable<E>(Duration duration) {
  return (events, mapper) =>
      restartable<E>().call(events.debounce(duration), mapper);
}
