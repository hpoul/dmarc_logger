/// Small null-safe helpers over `package:xml` for the DMARC schema.
library;

import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

final _logger = Logger('dmarc_xml');

extension XmlNodeExt on XmlElement {
  /// The text of the single [name] child. Throws [FormatException] when the
  /// child is missing or repeated: callers use this for schema-required
  /// elements whose absence means the report is malformed.
  String requiredText(String name) {
    final found = findElements(name).toList();
    if (found.length != 1) {
      throw FormatException(
        'Expected exactly one <$name> in <${this.name.qualified}>, '
        'found ${found.length}.',
      );
    }
    return found.single.innerText;
  }

  /// The text of the [name] child, or `null` when absent. Warns and takes the
  /// first on repeats: a malformed report still yields its rows.
  String? optionalText(String name) {
    final found = findElements(name).toList();
    if (found.isEmpty) {
      return null;
    }
    if (found.length > 1) {
      _logger.warning(
        'Expected at most one <$name> in <${this.name.qualified}>, '
        'taking the first of ${found.length}.',
      );
    }
    return found.first.innerText;
  }

  /// The single [name] child element, or `null` when absent. Warns and takes
  /// the first on repeats.
  XmlElement? optionalElement(String name) {
    final found = findElements(name).toList();
    if (found.isEmpty) {
      return null;
    }
    if (found.length > 1) {
      _logger.warning(
        'Expected at most one <$name> in <${this.name.qualified}>, '
        'taking the first of ${found.length}.',
      );
    }
    return found.first;
  }

  /// A Unix-epoch child parsed as a UTC [DateTime].
  DateTime epochDate(String name) {
    final raw = requiredText(name);
    final seconds = int.tryParse(raw.trim());
    if (seconds == null) {
      throw FormatException('Invalid <$name> "$raw": not a Unix timestamp.');
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
