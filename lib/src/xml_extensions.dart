import 'package:xml/xml.dart';

import 'package:logging/logging.dart';

final _logger = Logger('xml_extensions');

extension XmlNodeExt on XmlNode {
  String textNode(String name) {
    try {
      return findElements(name).first.text;
    } catch (e, stackTrace) {
      _logger.severe('Error while finding $name in $this', e, stackTrace);
    }
  }

  XmlElement opt(String name) {
    final els = findElements(name);
    final it = els.iterator;
    if (it.moveNext()) {
      final val = it.current;
      if (it.moveNext()) {
        throw StateError('Expected at most 1 element for $name in $this');
      }
      return val;
    }
    return null;
  }

  String textNodeRecursive(String name) => findAllElements(name).first.text;

  DateTime dateNode(String name) {
    final str = findElements(name).first.text;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(str) * 1000,
        isUtc: true);
  }
}
