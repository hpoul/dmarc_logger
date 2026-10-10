/// Parses a DMARC aggregate-report XML document into a [DmarcReport].
///
/// The parser is lenient where a row can still be formed (unknown enum
/// values, repeated optional elements, missing `auth_results`) and strict
/// where it cannot (missing `source_ip`, `count`, dates, policy block),
/// throwing [FormatException] with the offending element named. Callers turn
/// that into a dead-lettered mail, never a lost one.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/results.dart';
import 'package:dmarc_logger/src/xml_extensions.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

final _logger = Logger('dmarc_parse');

class DmarcParser {
  /// Parses the raw bytes of one `<feedback>` document.
  DmarcReport parse(Uint8List xmlContent) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(xmlContent));
    } on FormatException catch (e) {
      throw FormatException('Not a UTF-8 XML document: ${e.message}');
    }
    final roots = document.findElements('feedback').toList();
    if (roots.length != 1) {
      throw FormatException(
        'Expected exactly one <feedback> root, found ${roots.length}.',
      );
    }
    final feedback = roots.single;

    final metadataElement = feedback.optionalElement('report_metadata');
    if (metadataElement == null) {
      throw const FormatException('Missing <report_metadata>.');
    }
    final metadata = _parseMetadata(metadataElement);

    final policyElement = feedback.optionalElement('policy_published');
    if (policyElement == null) {
      throw FormatException(
        'Missing <policy_published> in report ${metadata.reportId} '
        'from ${metadata.orgName}.',
      );
    }
    final policy = _parsePolicy(policyElement);

    final records = <DmarcRecord>[];
    for (final record in feedback.findElements('record')) {
      records.add(_parseRecord(record, metadata));
    }
    if (records.isEmpty) {
      _logger.warning(
        'Report ${metadata.reportId} from ${metadata.orgName} '
        'carries no <record> elements.',
      );
    }
    return DmarcReport(metadata: metadata, policy: policy, records: records);
  }

  ReportMetadata _parseMetadata(XmlElement element) {
    final dateRange = element.optionalElement('date_range');
    if (dateRange == null) {
      throw const FormatException('Missing <report_metadata>/<date_range>.');
    }
    final reportId = element.optionalText('report_id') ?? '';
    if (reportId.isEmpty) {
      _logger.warning(
        'Report without <report_id>; duplicates of it cannot '
        'be recognized.',
      );
    }
    return ReportMetadata(
      orgName: element.optionalText('org_name') ?? '',
      reportId: reportId,
      begin: dateRange.epochDate('begin'),
      end: dateRange.epochDate('end'),
      email: element.optionalText('email'),
      extraContactInfo: element.optionalText('extra_contact_info'),
    );
  }

  PolicyPublished _parsePolicy(XmlElement element) {
    // The RFC defaults relaxed alignment when the tags are absent.
    const relaxed = Lenient<AlignmentMode>.known(AlignmentMode.relaxed);
    final adkimText = element.optionalText('adkim');
    final aspfText = element.optionalText('aspf');
    final pText = element.optionalText('p');
    if (pText == null) {
      throw const FormatException('Missing <policy_published>/<p>.');
    }
    final spText = element.optionalText('sp');
    final pctText = element.optionalText('pct');
    return PolicyPublished(
      domain: element.optionalText('domain') ?? '',
      adkim: adkimText == null
          ? relaxed
          : parseLenient(AlignmentMode.values, adkimText, field: 'adkim'),
      aspf: aspfText == null
          ? relaxed
          : parseLenient(AlignmentMode.values, aspfText, field: 'aspf'),
      p: parseLenient(Disposition.values, pText, field: 'policy p'),
      sp: spText == null
          ? null
          : parseLenient(Disposition.values, spText, field: 'policy sp'),
      pct: pctText == null ? null : int.tryParse(pctText.trim()),
    );
  }

  DmarcRecord _parseRecord(XmlElement element, ReportMetadata metadata) {
    final row = element.optionalElement('row');
    if (row == null) {
      throw FormatException(
        'A <record> without <row> in report ${metadata.reportId}.',
      );
    }
    final evaluated = row.optionalElement('policy_evaluated');
    if (evaluated == null) {
      throw FormatException(
        'A <record> without <policy_evaluated> in report ${metadata.reportId}.',
      );
    }
    final reasons = <PolicyReason>[];
    for (final reason in evaluated.findElements('reason')) {
      reasons.add(
        PolicyReason(
          type: reason.optionalText('type') ?? '',
          comment: reason.optionalText('comment'),
        ),
      );
    }
    final identifiers = element.optionalElement('identifiers');
    final headerFrom = identifiers?.optionalText('header_from') ?? '';
    if (headerFrom.isEmpty) {
      _logger.warning(
        'A <record> without <header_from> in report '
        '${metadata.reportId}; alignment is left empty.',
      );
    }
    final authResults = element.optionalElement('auth_results');
    if (authResults == null) {
      _logger.warning(
        'A <record> without <auth_results> in report '
        '${metadata.reportId}; keeping it with empty auth results.',
      );
    }
    return DmarcRecord(
      sourceIp: row.requiredText('source_ip'),
      count: _parseCount(row, metadata),
      disposition: parseLenient(
        Disposition.values,
        evaluated.optionalText('disposition') ?? '',
        field: 'disposition',
      ),
      dkimPolicy: parseLenient(
        PolicyResult.values,
        evaluated.optionalText('dkim') ?? '',
        field: 'policy_evaluated/dkim',
      ),
      spfPolicy: parseLenient(
        PolicyResult.values,
        evaluated.optionalText('spf') ?? '',
        field: 'policy_evaluated/spf',
      ),
      reasons: reasons,
      headerFrom: headerFrom,
      dkimResults: [
        if (authResults != null)
          ...authResults.findElements('dkim').map(_parseDkim),
      ],
      spfResults: [
        if (authResults != null)
          ...authResults.findElements('spf').map(_parseSpf),
      ],
    );
  }

  int _parseCount(XmlElement row, ReportMetadata metadata) {
    final raw = row.requiredText('count');
    final count = int.tryParse(raw.trim());
    if (count == null) {
      throw FormatException(
        'Invalid <count> "$raw" in report ${metadata.reportId}.',
      );
    }
    return count;
  }

  DkimAuthDetail _parseDkim(XmlElement element) => DkimAuthDetail(
    domain: element.optionalText('domain') ?? '',
    selector: element.optionalText('selector'),
    result: parseLenient(
      DkimAuthResult.values,
      element.optionalText('result') ?? '',
      field: 'dkim/result',
    ),
  );

  SpfAuthDetail _parseSpf(XmlElement element) {
    final scopeText = element.optionalText('scope');
    return SpfAuthDetail(
      domain: element.optionalText('domain') ?? '',
      scope: scopeText == null
          ? null
          : parseLenient(SpfScope.values, scopeText, field: 'spf/scope'),
      result: parseLenient(
        SpfAuthResult.values,
        element.optionalText('result') ?? '',
        field: 'spf/result',
      ),
    );
  }
}
