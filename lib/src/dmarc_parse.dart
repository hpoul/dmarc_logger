import 'dart:convert';
import 'dart:typed_data';

import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/xml_extensions.dart';
import 'package:logging/logging.dart';
import 'package:quiver/check.dart';
import 'package:xml/xml.dart';

final _logger = Logger('dmarc_parse');

class DmarcParser {
  List<Map<String, Object>> parse(Uint8List xmlContent) {
    final document = XmlDocument.parse(utf8.decode(xmlContent));
    final feedback = document.findElements('feedback').single;
    _logger.finer('Got document: $document');

    final xmlMetadata = feedback.findElements('report_metadata').single;
    final dateRange = xmlMetadata.findElements('date_range').single;

    final metadata = Metadata(
      orgName: xmlMetadata.textNode('org_name'),
      begin: dateRange.dateNode('begin'),
      end: dateRange.dateNode('end'),
    );

    final ret = <Map<String, Object>>[];

    for (final record in feedback.findElements('record')) {
      final row = record.findElements('row').single;
      final policies = record.findAllElements('policy_evaluated');
      checkState(policies.length == 1, message: 'only 1 policy');
      final policy = policies.single;
      final dmarcRecord = DmarcRecord(
        sourceIp: row.textNode('source_ip'),
        count: int.parse(row.textNode('count')),
        dkim: policy.textNode('dkim').toPolicyResult(),
        spf: policy.textNode('spf').toPolicyResult(),
        headerFrom: record.textNodeRecursive('header_from'),
      );
      final authResult = record.findAllElements('auth_results');
      checkState(authResult.length == 1, message: 'only auth result');

      final authResults = record.findElements('auth_results').single;
      final dkim = AuthResult.fromXml(authResults.findElements('dkim').single);
      final spf = AuthResult.fromXml(authResults.findElements('spf').single);

      final tmp = <String, Object>{
        ...metadata.toJson(),
        ...dmarcRecord.toJson(),
        ...dkim.toJson().prefixKeys('dkim_'),
        ...spf.toJson().prefixKeys('spf_'),
      };
      ret.add(tmp);
    }
    return ret;
  }
}

extension on Map<String, Object> {
  Map<String, Object> prefixKeys(String prefix) =>
      map((key, value) => MapEntry('$prefix$key', value));
}
