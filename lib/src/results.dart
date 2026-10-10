/// The closed value sets from RFC 7489 appendix C, plus a lenient wrapper
/// that keeps unknown values as their raw string instead of throwing.
library;

import 'package:logging/logging.dart';

final _logger = Logger('dmarc_results');

/// DKIM authentication results, RFC 7489 section 6.3 / appendix C.
enum DkimAuthResult { none, pass, fail, policy, neutral, temperror, permerror }

/// SPF authentication results, RFC 7489 section 6.3 / appendix C.
/// Unlike DKIM this set includes `softfail`.
enum SpfAuthResult { none, neutral, pass, fail, softfail, temperror, permerror }

/// The receiver's DMARC verdict per mechanism in `policy_evaluated`.
enum PolicyResult { pass, fail }

/// What the receiver did with the message, and the values the published
/// policy `p`/`sp` tags can take. One enum serves both: the wire sets are
/// identical.
enum Disposition { none, quarantine, reject }

/// Alignment modes for the `adkim`/`aspf` policy tags. The wire names are
/// `r` and `s`; [wireName] maps them.
enum AlignmentMode { relaxed, strict }

/// The scope a SPF result was evaluated against: the `mfrom` (envelope from)
/// identity or the `helo` identity.
enum SpfScope { mfrom, helo }

/// A value from a closed set that may carry an out-of-set raw string.
///
/// Reporters occasionally send values the RFC does not list. Throwing on them
/// used to lose the whole report; keeping the raw string keeps the row and
/// still shows the odd value in the CSV. Decide on this type with exhaustive
/// `switch`es, never with `==`.
sealed class Lenient<T extends Enum> {
  const Lenient();

  const factory Lenient.known(T value) = Known<T>;

  const factory Lenient.unknown(String raw) = Unknown<T>;
}

final class Known<T extends Enum> extends Lenient<T> {
  const Known(this.value);

  final T value;
}

final class Unknown<T extends Enum> extends Lenient<T> {
  const Unknown(this.raw);

  final String raw;
}

/// The string form used in the CSV: the enum name for known values, the raw
/// string for unknown ones.
extension LenientValue<T extends Enum> on Lenient<T> {
  String rawValue() => switch (this) {
    Known(value: final value) => _wireName(value),
    Unknown(raw: final raw) => raw,
  };
}

String _wireName(Enum value) => switch (value) {
  AlignmentMode.relaxed => 'r',
  AlignmentMode.strict => 's',
  _ => value.name,
};

/// Parses [raw] against [values], returning [Lenient.unknown] with a warning
/// when the value is outside the set. The match is exact: normalization would
/// hide what the reporter actually sent.
Lenient<T> parseLenient<T extends Enum>(
  List<T> values,
  String raw, {
  required String field,
}) {
  for (final value in values) {
    if (_wireName(value) == raw) {
      return Lenient.known(value);
    }
  }
  _logger.warning('Unknown $field "$raw", keeping the raw string.');
  return Lenient.unknown(raw);
}
