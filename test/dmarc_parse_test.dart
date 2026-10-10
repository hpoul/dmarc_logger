import 'dart:convert';
import 'dart:typed_data';

import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/dmarc_parse.dart';
import 'package:dmarc_logger/src/results.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'support.dart';

DmarcReport parse(String xml) =>
    DmarcParser().parse(Uint8List.fromList(utf8.encode(xml)));

void main() {
  group('DmarcParser', () {
    test('parses the Google report shape', () {
      final report = parse(
        minimalXml(
          org: 'google.com',
          reportId: 'google-1',
          records: recordXml(
            ip: '198.51.100.151',
            count: '3',
            dkimPolicy: 'fail',
            spfPolicy: 'pass',
            spf: spfXml('example.com', 'pass', scope: 'mfrom'),
          ),
        ),
      );

      expect(report.metadata.orgName, 'google.com');
      expect(report.records, hasLength(1));
      final record = report.records.single;
      expect(record.sourceIp, '198.51.100.151');
      expect(record.count, 3);
      expect(record.spfResults.single.scope, isA<Known<SpfScope>>());
      expect(report.policy.p, isA<Known<Disposition>>());
    });

    test('keeps softfail and neutral instead of losing the report', () {
      final report = parse(
        minimalXml(
          reportId: 'softfail-1',
          records:
              recordXml(
                ip: '203.0.113.7',
                dkimPolicy: 'fail',
                spfPolicy: 'fail',
                spf: spfXml('example.com', 'softfail', scope: 'mfrom'),
              ) +
              recordXml(
                ip: '203.0.113.8',
                dkimPolicy: 'fail',
                spfPolicy: 'fail',
                dkim: dkimXml('example.com', 'neutral'),
                spf: spfXml('example.com', 'neutral', scope: 'helo'),
              ),
        ),
      );

      expect(report.records, hasLength(2));
      expect(
        report.records[0].spfResults.single.result,
        isA<Known<SpfAuthResult>>().having(
          (known) => known.value,
          'value',
          SpfAuthResult.softfail,
        ),
      );
      expect(
        report.records[1].spfResults.single.result,
        isA<Known<SpfAuthResult>>().having(
          (known) => known.value,
          'value',
          SpfAuthResult.neutral,
        ),
      );
    });

    test('keeps every DKIM result of a record with its selector', () {
      final report = parse(
        minimalXml(
          reportId: 'multi-dkim-1',
          records: recordXml(
            dkimPolicy: 'fail',
            spfPolicy: 'fail',
            dkim:
                dkimXml('esp.example.net', 'pass', selector: 'news1') +
                dkimXml('example.com', 'fail', selector: 'jan2024'),
          ),
        ),
      );

      final results = report.records.single.dkimResults;
      expect(results, hasLength(2));
      expect(results[0].domain, 'esp.example.net');
      expect(results[0].selector, 'news1');
      expect(results[1].selector, 'jan2024');
    });

    test('keeps unknown values as raw strings with a warning', () async {
      final warnings = <String>[];
      final subscription = Logger.root.onRecord
          .where((record) => record.level >= Level.WARNING)
          .listen((record) => warnings.add(record.message));
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      try {
        final report = parse(
          minimalXml(
            reportId: 'unknown-1',
            records: recordXml(
              disposition: 'quarantine-later',
              dkimPolicy: 'fail',
              spfPolicy: 'fail',
              dkim: dkimXml('example.com', 'bogus'),
              spf: spfXml('example.com', 'bogus', scope: 'carrier-pigeon'),
            ),
          ),
        );

        final record = report.records.single;
        expect(record.disposition, isA<Unknown<Disposition>>());
        expect(
          (record.disposition as Unknown<Disposition>).raw,
          'quarantine-later',
        );
        expect(
          (record.dkimResults.single.result as Unknown<DkimAuthResult>).raw,
          'bogus',
        );
        expect(
          (record.spfResults.single.result as Unknown<SpfAuthResult>).raw,
          'bogus',
        );
        expect(
          (record.spfResults.single.scope! as Unknown<SpfScope>).raw,
          'carrier-pigeon',
        );
        // The warnings arrive asynchronously; drain the event queue first.
        await Future<void>.delayed(Duration.zero);
        expect(
          warnings.where((message) => message.contains('bogus')),
          hasLength(2),
        );
      } finally {
        await subscription.cancel();
        Logger.root.level = previousLevel;
      }
    });

    test('parses reasons, scopes and the published policy', () {
      final report = parse(
        minimalXml(
          reportId: 'reasons-1',
          records: recordXml(
            reasons: '''
        <reason>
          <type>forwarded</type>
          <comment>mailing list</comment>
        </reason>
        <reason>
          <type>sampled_out</type>
        </reason>
''',
            spf: spfXml('example.com', 'pass', scope: 'helo'),
          ),
        ),
      );

      final record = report.records.single;
      expect(record.reasons, hasLength(2));
      expect(record.reasons[0].type, 'forwarded');
      expect(record.reasons[0].comment, 'mailing list');
      expect(record.reasons[1].comment, isNull);
      expect(report.policy.domain, 'example.com');
      expect(report.policy.adkim, isA<Known<AlignmentMode>>());
    });

    test('tolerates a record without auth_results', () {
      final report = parse(
        minimalXml(
          reportId: 'no-auth-1',
          records: '''
  <record>
    <row>
      <source_ip>192.0.2.10</source_ip>
      <count>1</count>
      <policy_evaluated>
        <disposition>none</disposition>
        <dkim>fail</dkim>
        <spf>fail</spf>
      </policy_evaluated>
    </row>
    <identifiers>
      <header_from>example.com</header_from>
    </identifiers>
  </record>
''',
        ),
      );

      final record = report.records.single;
      expect(record.dkimResults, isEmpty);
      expect(record.spfResults, isEmpty);
    });

    test('rejects a document without a feedback root', () {
      expect(() => parse('<not-a-report/>'), throwsA(isA<FormatException>()));
    });

    test('rejects a record without a source_ip', () {
      expect(
        () => parse(
          minimalXml(
            records: '''
  <record>
    <row>
      <count>1</count>
      <policy_evaluated>
        <disposition>none</disposition>
        <dkim>fail</dkim>
        <spf>fail</spf>
      </policy_evaluated>
    </row>
    <identifiers>
      <header_from>example.com</header_from>
    </identifiers>
    <auth_results/>
  </record>
''',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a non-numeric count', () {
      expect(
        () => parse(minimalXml(records: recordXml(count: 'many'))),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('domainsAlign', () {
    const relaxed = Lenient<AlignmentMode>.known(AlignmentMode.relaxed);
    const strict = Lenient<AlignmentMode>.known(AlignmentMode.strict);
    const unknown = Lenient<AlignmentMode>.unknown('sideways');

    test('strict passes only on exact match', () {
      expect(domainsAlign('example.com', 'example.com', strict), isTrue);
      expect(domainsAlign('mail.example.com', 'example.com', strict), isFalse);
      expect(domainsAlign('example.com', 'mail.example.com', strict), isFalse);
    });

    test('relaxed passes on same or subdomain', () {
      expect(domainsAlign('example.com', 'example.com', relaxed), isTrue);
      expect(domainsAlign('mail.example.com', 'example.com', relaxed), isTrue);
      expect(domainsAlign('example.com', 'mail.example.com', relaxed), isTrue);
      expect(domainsAlign('other.example', 'example.com', relaxed), isFalse);
      expect(domainsAlign('notexample.com', 'example.com', relaxed), isFalse);
    });

    test('ignores case and a trailing dot', () {
      expect(domainsAlign('Example.COM', 'example.com', strict), isTrue);
      expect(domainsAlign('example.com.', 'example.com', strict), isTrue);
    });

    test('unknown mode counts only an exact match', () {
      expect(domainsAlign('example.com', 'example.com', unknown), isTrue);
      expect(domainsAlign('mail.example.com', 'example.com', unknown), isFalse);
    });

    test('empty domains never align', () {
      expect(domainsAlign('', 'example.com', relaxed), isFalse);
      expect(domainsAlign('example.com', '', relaxed), isFalse);
    });
  });

  group('dkimAligned/spfAligned', () {
    const relaxed = Lenient<AlignmentMode>.known(AlignmentMode.relaxed);

    DmarcRecord recordWith({
      List<DkimAuthDetail> dkimResults = const [],
      List<SpfAuthDetail> spfResults = const [],
    }) => DmarcRecord(
      sourceIp: '192.0.2.10',
      count: 1,
      disposition: const Lenient.known(Disposition.none),
      dkimPolicy: const Lenient.known(PolicyResult.fail),
      spfPolicy: const Lenient.known(PolicyResult.fail),
      reasons: const [],
      headerFrom: 'example.com',
      dkimResults: dkimResults,
      spfResults: spfResults,
    );

    test('is null without a pass, true when any pass aligns', () {
      expect(
        dkimAligned(
          recordWith(
            dkimResults: const [
              DkimAuthDetail(
                domain: 'esp.example.net',
                result: Lenient.known(DkimAuthResult.pass),
              ),
              DkimAuthDetail(
                domain: 'example.com',
                result: Lenient.known(DkimAuthResult.pass),
              ),
            ],
          ),
          relaxed,
        ),
        isTrue,
      );
      expect(
        dkimAligned(
          recordWith(
            dkimResults: const [
              DkimAuthDetail(
                domain: 'example.com',
                result: Lenient.known(DkimAuthResult.fail),
              ),
            ],
          ),
          relaxed,
        ),
        isNull,
      );
      expect(dkimAligned(recordWith(), relaxed), isNull);
    });

    test('is false when passes exist but none aligns', () {
      expect(
        dkimAligned(
          recordWith(
            dkimResults: const [
              DkimAuthDetail(
                domain: 'esp.example.net',
                result: Lenient.known(DkimAuthResult.pass),
              ),
            ],
          ),
          relaxed,
        ),
        isFalse,
      );
      expect(
        spfAligned(
          recordWith(
            spfResults: const [
              SpfAuthDetail(
                domain: 'esp.example.net',
                result: Lenient.known(SpfAuthResult.pass),
              ),
            ],
          ),
          relaxed,
        ),
        isFalse,
      );
    });
  });

  group('failureCause', () {
    const pass = Lenient<PolicyResult>.known(PolicyResult.pass);
    const fail = Lenient<PolicyResult>.known(PolicyResult.fail);
    const unknownPolicy = Lenient<PolicyResult>.unknown('maybe');

    String cause({
      Lenient<PolicyResult> dkimPolicy = fail,
      Lenient<PolicyResult> spfPolicy = fail,
      bool forwardingReason = false,
      DkimSummary dkim = DkimSummary.absent,
      SpfSummary spf = SpfSummary.absent,
    }) => failureCause(
      dkimPolicy: dkimPolicy,
      spfPolicy: spfPolicy,
      forwardingReason: forwardingReason,
      dkim: dkim,
      spf: spf,
    );

    test('a receiver pass is ok whatever else is present', () {
      expect(cause(dkimPolicy: pass), 'ok');
      expect(
        cause(
          spfPolicy: pass,
          forwardingReason: true,
          dkim: DkimSummary.temperror,
          spf: SpfSummary.failed,
        ),
        'ok',
      );
    });

    test('an unknown verdict is not a pass', () {
      expect(cause(dkimPolicy: unknownPolicy), 'unsigned');
    });

    test('forwarding beats result evidence', () {
      expect(
        cause(
          forwardingReason: true,
          dkim: DkimSummary.failed,
          spf: SpfSummary.failed,
        ),
        'forwarded',
      );
    });

    test('an aligned pass the receiver failed is verdict-differs', () {
      expect(cause(dkim: DkimSummary.passAligned), 'verdict-differs');
      expect(cause(spf: SpfSummary.passAligned), 'verdict-differs');
    });

    test('temperror beats unaligned and failed evidence', () {
      expect(
        cause(dkim: DkimSummary.temperror, spf: SpfSummary.passUnaligned),
        'temperror',
      );
      expect(
        cause(dkim: DkimSummary.failed, spf: SpfSummary.temperror),
        'temperror',
      );
    });

    test('an unaligned pass beats a failure on the other side', () {
      expect(
        cause(dkim: DkimSummary.passUnaligned, spf: SpfSummary.failed),
        'dkim-unaligned',
      );
      expect(
        cause(dkim: DkimSummary.failed, spf: SpfSummary.passUnaligned),
        'spf-unaligned',
      );
    });

    test('a lone failure names its mechanism', () {
      expect(cause(dkim: DkimSummary.failed), 'dkim-broken');
      expect(cause(spf: SpfSummary.failed), 'spf-not-listed');
      expect(
        cause(dkim: DkimSummary.failed, spf: SpfSummary.failed),
        'dkim-broken',
      );
    });

    test('no signal at all is unsigned', () {
      expect(cause(), 'unsigned');
    });

    test('unknown values surface as unrecognized', () {
      expect(cause(dkim: DkimSummary.other), 'unrecognized');
      expect(cause(spf: SpfSummary.other), 'unrecognized');
    });
  });

  group('summaries', () {
    const relaxed = Lenient<AlignmentMode>.known(AlignmentMode.relaxed);

    DmarcRecord recordWith({
      List<DkimAuthDetail> dkimResults = const [],
      List<SpfAuthDetail> spfResults = const [],
    }) => DmarcRecord(
      sourceIp: '192.0.2.10',
      count: 1,
      disposition: const Lenient.known(Disposition.none),
      dkimPolicy: const Lenient.known(PolicyResult.fail),
      spfPolicy: const Lenient.known(PolicyResult.fail),
      reasons: const [],
      headerFrom: 'example.com',
      dkimResults: dkimResults,
      spfResults: spfResults,
    );

    test('a pass outranks failures and the alignment decides the kind', () {
      expect(
        summarizeDkim(
          recordWith(
            dkimResults: const [
              DkimAuthDetail(
                domain: 'example.com',
                result: Lenient.known(DkimAuthResult.fail),
              ),
              DkimAuthDetail(
                domain: 'esp.example.net',
                result: Lenient.known(DkimAuthResult.pass),
              ),
            ],
          ),
          relaxed,
        ),
        DkimSummary.passUnaligned,
      );
    });

    test('softfail alone counts as SPF failure', () {
      expect(
        summarizeSpf(
          recordWith(
            spfResults: const [
              SpfAuthDetail(
                domain: 'example.com',
                result: Lenient.known(SpfAuthResult.softfail),
              ),
            ],
          ),
          relaxed,
        ),
        SpfSummary.failed,
      );
    });

    test('softfail counts as SPF failure, temperror as provisional', () {
      expect(
        summarizeSpf(
          recordWith(
            spfResults: const [
              SpfAuthDetail(
                domain: 'example.com',
                result: Lenient.known(SpfAuthResult.softfail),
              ),
              SpfAuthDetail(
                domain: 'example.com',
                result: Lenient.known(SpfAuthResult.temperror),
              ),
            ],
          ),
          relaxed,
        ),
        SpfSummary.temperror,
      );
    });

    test('neutral and none carry no signal', () {
      expect(
        summarizeSpf(
          recordWith(
            spfResults: const [
              SpfAuthDetail(
                domain: 'example.com',
                result: Lenient.known(SpfAuthResult.neutral),
              ),
            ],
          ),
          relaxed,
        ),
        SpfSummary.absent,
      );
      expect(summarizeDkim(recordWith(), relaxed), DkimSummary.absent);
    });
  });
}
