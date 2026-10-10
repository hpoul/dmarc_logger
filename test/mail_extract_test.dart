import 'dart:convert';
import 'dart:typed_data';

import 'package:dmarc_logger/src/mail_extract.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('extractFeedbackXml', () {
    test('finds the Yahoo-style gzip attachment', () {
      final found = extractFeedbackXml(exampleMail('mail1.eml'));

      expect(utf8.decode(found.bytes), contains('<org_name>Yahoo! Inc.'));
      expect(found.description, contains('.xml.gz'));
    });

    test('finds the Google-style zip attachment', () {
      final found = extractFeedbackXml(exampleMail('mail2.eml'));

      expect(utf8.decode(found.bytes), contains('<org_name>google.com'));
      expect(found.description, contains('.zip'));
    });

    test('finds a plain .xml attachment', () {
      final found = extractFeedbackXml(exampleMail('mail3.eml'));

      expect(utf8.decode(found.bytes), contains('<org_name>example.net'));
    });

    test('finds a gzip part with no disposition at all', () {
      final found = extractFeedbackXml(exampleMail('mail4.eml'));

      expect(
        utf8.decode(found.bytes),
        contains('<org_name>enterprise.example.org'),
      );
    });

    test('finds an inline gzip part', () {
      final xml = minimalXml(
        records: recordXml(
          dkim: dkimXml('example.com', 'pass'),
          spf: spfXml('example.com', 'pass', scope: 'mfrom'),
        ),
      );
      final mail = multipartMail(
        parts: [
          (
            {
              'Content-Type': 'text/plain; charset=utf-8',
              'Content-Disposition': 'inline',
            },
            Uint8List.fromList(utf8.encode('See the inline report.\r\n')),
          ),
          (
            {
              'Content-Type': 'application/x-gzip; name="report.xml.gz"',
              'Content-Disposition': 'inline; filename="report.xml.gz"',
              'Content-Transfer-Encoding': 'base64',
            },
            b64bytes(gz(xml)),
          ),
        ],
      );

      final found = extractFeedbackXml(mail);

      expect(utf8.decode(found.bytes), contains('<org_name>example.net'));
    });

    test('finds a Microsoft-style .xml.gz attachment', () {
      final xml = minimalXml(
        org: 'outlook.com',
        reportId: 'outlook-1',
        records: recordXml(
          ip: '198.51.100.60',
          spf: spfXml('example.com', 'pass', scope: 'mfrom'),
        ),
      );
      final mail = singlePartMail(
        headers: {
          'From': 'dmarcreports@outlook.com',
          'To': 'dmarc-reports@example.com',
          'Subject': 'Report domain: example.com Submitter: outlook.com',
          'Content-Type':
              'application/gzip; name="outlook.com!example.com!1!2.xml.gz"',
          'Content-Disposition':
              'attachment; filename="outlook.com!example.com!1!2.xml.gz"',
          'Content-Transfer-Encoding': 'base64',
        },
        body: b64bytes(gz(xml)),
      );

      final found = extractFeedbackXml(mail);

      expect(utf8.decode(found.bytes), contains('<org_name>outlook.com'));
    });

    test('picks the part whose content parses as feedback', () {
      final xml = minimalXml(
        records: recordXml(spf: spfXml('example.com', 'pass')),
      );
      final mail = multipartMail(
        parts: [
          (
            {
              'Content-Type': 'application/gzip; name="decoy.xml.gz"',
              'Content-Disposition': 'attachment; filename="decoy.xml.gz"',
              'Content-Transfer-Encoding': 'base64',
            },
            b64bytes(gz('<not-a-report/>')),
          ),
          (
            {
              'Content-Type': 'application/gzip; name="real.xml.gz"',
              'Content-Disposition': 'attachment; filename="real.xml.gz"',
              'Content-Transfer-Encoding': 'base64',
            },
            b64bytes(gz(xml)),
          ),
        ],
      );

      final found = extractFeedbackXml(mail);

      expect(utf8.decode(found.bytes), contains('<feedback>'));
      expect(found.description, contains('real.xml.gz'));
    });

    test('throws a descriptive error when nothing qualifies', () {
      final mail = multipartMail(
        parts: [
          (
            {'Content-Type': 'text/plain'},
            Uint8List.fromList(utf8.encode('Just prose, no report.\r\n')),
          ),
        ],
      );

      expect(
        () => extractFeedbackXml(mail),
        throwsA(
          isA<FeedbackNotFound>().having(
            (e) => e.message,
            'message',
            contains('No report payload found'),
          ),
        ),
      );
    });

    test('throws a descriptive error for a non-mail', () {
      expect(
        () => extractFeedbackXml(Uint8List.fromList(utf8.encode('junk'))),
        throwsA(isA<FeedbackNotFound>()),
      );
    });
  });
}
