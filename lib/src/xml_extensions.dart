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

  String textNodeRecursive(String name) => findAllElements(name).first.text;

  DateTime dateNode(String name) {
    final str = findElements(name).first.text;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(str) * 1000,
        isUtc: true);
  }
}
