/// Shared builders and helpers for the dmarc_logger tests.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reads an anonymized example mail by file name. Tests run with the
/// package root as the working directory, so this is CWD-relative.
Uint8List exampleMail(String name) => File('example/$name').readAsBytesSync();

/// Builds a single-part mail from [headers] and a raw [body].
Uint8List singlePartMail({
  required Map<String, String> headers,
  required Uint8List body,
}) {
  final buffer = StringBuffer();
  for (final entry in headers.entries) {
    buffer.write('${entry.key}: ${entry.value}\r\n');
  }
  buffer.write('\r\n');
  final head = Uint8List.fromList(utf8.encode(buffer.toString()));
  return Uint8List.fromList([...head, ...body]);
}

/// Builds a multipart/mixed mail. Each part is its headers plus its raw
/// (already transfer-encoded) body.
Uint8List multipartMail({
  required List<(Map<String, String>, Uint8List)> parts,
  Map<String, String> headers = const {},
  String boundary = '----=_Part_test_000000.000000000000',
}) {
  final buffer = StringBuffer()
    ..write('MIME-Version: 1.0\r\n')
    ..write('Date: Fri, 11 Oct 2024 07:00:00 +0000\r\n')
    ..write('Message-ID: <test-report@example.com>\r\n')
    ..write('Subject: test report\r\n')
    ..write('From: dmarc@example.net\r\n')
    ..write('To: dmarc-reports@example.com\r\n');
  for (final entry in headers.entries) {
    buffer.write('${entry.key}: ${entry.value}\r\n');
  }
  buffer
    ..write('Content-Type: multipart/mixed; boundary="$boundary"\r\n')
    ..write('\r\n');
  final out = BytesBuilder();
  out.add(utf8.encode(buffer.toString()));
  for (final (partHeaders, body) in parts) {
    final head = StringBuffer()..write('--$boundary\r\n');
    for (final entry in partHeaders.entries) {
      head.write('${entry.key}: ${entry.value}\r\n');
    }
    head.write('\r\n');
    out
      ..add(utf8.encode(head.toString()))
      ..add(body)
      ..add(utf8.encode('\r\n'));
  }
  out.add(utf8.encode('--$boundary--\r\n'));
  return out.toBytes();
}

/// Base64 body bytes for a text payload, folded at 64 columns.
Uint8List b64(String text) => b64bytes(Uint8List.fromList(utf8.encode(text)));

/// Base64 body bytes for a binary payload, folded at 64 columns.
Uint8List b64bytes(Uint8List payload) {
  final raw = base64.encode(payload);
  final folded = StringBuffer();
  for (var i = 0; i < raw.length; i += 64) {
    folded.write(raw.substring(i, i + 64 > raw.length ? raw.length : i + 64));
    folded.write('\r\n');
  }
  return Uint8List.fromList(utf8.encode(folded.toString()));
}

/// Gzip body bytes for a text payload.
Uint8List gz(String text) =>
    Uint8List.fromList(const GZipEncoder().encode(utf8.encode(text)));

/// Zip body bytes holding [fileName] with [text].
Uint8List zip(String fileName, String text) {
  final payload = utf8.encode(text);
  final archive = Archive()
    ..addFile(ArchiveFile(fileName, payload.length, payload));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Creates a fresh temporary directory, deleted by the caller's tearDown.
Future<Directory> tempDir(String prefix) =>
    Directory.systemTemp.createTemp('dmarc_test_${prefix}_');

/// The smallest valid aggregate report, with placeholders filled by the
/// caller. Domains are `example.*`, IPs documentation-range only.
String minimalXml({
  String org = 'example.net',
  String reportId = 'test-report-1',
  String domain = 'example.com',
  String records = '',
}) =>
    '''
<?xml version="1.0" encoding="UTF-8" ?>
<feedback>
  <report_metadata>
    <org_name>$org</org_name>
    <email>dmarc@example.net</email>
    <report_id>$reportId</report_id>
    <date_range>
      <begin>1728518400</begin>
      <end>1728604799</end>
    </date_range>
  </report_metadata>
  <policy_published>
    <domain>$domain</domain>
    <adkim>r</adkim>
    <aspf>r</aspf>
    <p>quarantine</p>
    <pct>100</pct>
  </policy_published>
$records
</feedback>
''';

/// One record with the given row and auth details.
String recordXml({
  String ip = '192.0.2.10',
  String count = '1',
  String disposition = 'none',
  String dkimPolicy = 'pass',
  String spfPolicy = 'pass',
  String reasons = '',
  String headerFrom = 'example.com',
  String dkim = '',
  String spf = '',
}) =>
    '''
  <record>
    <row>
      <source_ip>$ip</source_ip>
      <count>$count</count>
      <policy_evaluated>
        <disposition>$disposition</disposition>
        <dkim>$dkimPolicy</dkim>
        <spf>$spfPolicy</spf>
$reasons
      </policy_evaluated>
    </row>
    <identifiers>
      <header_from>$headerFrom</header_from>
    </identifiers>
    <auth_results>
$dkim
$spf
    </auth_results>
  </record>
''';

String dkimXml(String domain, String result, {String? selector}) =>
    '''
      <dkim>
        <domain>$domain</domain>
${selector == null ? '' : '        <selector>$selector</selector>\n'}        <result>$result</result>
      </dkim>
''';

String spfXml(String domain, String result, {String? scope}) =>
    '''
      <spf>
        <domain>$domain</domain>
${scope == null ? '' : '        <scope>$scope</scope>\n'}        <result>$result</result>
      </spf>
''';
