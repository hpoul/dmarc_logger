import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:dmarc_logger/src/csv_store.dart';
import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/dmarc_parse.dart';
import 'package:test/test.dart';

import 'support.dart';

DmarcReport reportWithId(String reportId, {String org = 'example.net'}) =>
    DmarcParser().parse(
      Uint8List.fromList(
        utf8.encode(
          minimalXml(
            org: org,
            reportId: reportId,
            records:
                recordXml(
                  ip: '192.0.2.10',
                  dkim: dkimXml('example.com', 'pass', selector: 's1'),
                  spf: spfXml('example.com', 'pass', scope: 'mfrom'),
                ) +
                recordXml(
                  ip: '198.51.100.20',
                  dkimPolicy: 'fail',
                  spfPolicy: 'fail',
                  dkim: dkimXml('example.com', 'fail'),
                ),
          ),
        ),
      ),
    );

List<List<String>> readRows(File file) =>
    const CsvToListConverter(shouldParseNumbers: false)
        .convert(file.readAsStringSync())
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();

void main() {
  late Directory temp;

  setUp(() async {
    temp = await tempDir('csv');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  group('CsvStore.appendReport', () {
    test('creates the file with the current header and appends rows', () async {
      final file = File('${temp.path}/reports.csv');
      final outcome = await CsvStore(file: file)
          .appendReport(reportWithId('new-1'));

      expect(outcome, isA<Appended>().having((o) => o.count, 'count', 2));
      final rows = readRows(file);
      expect(rows.first, currentHeader);
      expect(rows, hasLength(3));
      // The legacy prefix keeps its order and names.
      expect(rows.first.sublist(0, legacyHeader.length), legacyHeader);
      expect(rows[1][0], 'example.net');
      expect(rows[1][12], 'new-1');
      expect(rows[1][22], 's1');
      expect(rows[1][23], 'example.com:s1:pass');
      expect(rows[2][28], 'dkim-broken');
    });

    test('skips a report whose id is already in the file', () async {
      final file = File('${temp.path}/reports.csv');
      final store = CsvStore(file: file);
      await store.appendReport(reportWithId('dup-1'));

      final outcome = await store.appendReport(reportWithId('dup-1'));

      expect(outcome, isA<DuplicateReport>());
      expect(readRows(file), hasLength(3));
    });

    test('tells reports with numeric ids apart exactly', () async {
      final file = File('${temp.path}/reports.csv');
      final store = CsvStore(file: file);
      // 20-digit ids lose precision as doubles; the store must compare
      // strings, or these two distinct reports collapse into one.
      await store.appendReport(reportWithId('20000000000000000001'));

      final outcome = await store.appendReport(
        reportWithId('20000000000000000002'),
      );

      expect(outcome, isA<Appended>());
      expect(readRows(file), hasLength(5));
    });

    test('refuses to append under a foreign header', () async {
      final file = File('${temp.path}/reports.csv')
        ..writeAsStringSync('orgName,begin\nx,y\n');
      final outcome = await CsvStore(file: file)
          .appendReport(reportWithId('x-1'));

      expect(outcome, isA<HeaderMismatch>());
      expect(file.readAsStringSync(), 'orgName,begin\nx,y\n');
    });

    // Lock contention is only exercised across processes (see
    // commands_test.dart): flock does not serialize holders inside one
    // process on macOS, where locks attach to the file rather than the
    // open file description, while postfix pipes are separate processes.
    test('two writers at once keep every row intact', () async {
      final file = File('${temp.path}/reports.csv');
      final store = CsvStore(file: file);
      // The same mail twice plus ten distinct ones, all racing: the
      // duplicate must collapse to one copy and nothing may interleave.
      final ids = [
        'same-mail',
        'same-mail',
        ...List.generate(10, (i) => 'w-$i'),
      ];
      final outcomes = await Future.wait(
        ids.map((id) => store.appendReport(reportWithId(id))),
      );

      expect(outcomes.whereType<DuplicateReport>(), hasLength(1));
      expect(outcomes.whereType<Appended>(), hasLength(11));
      final rows = readRows(file);
      expect(rows.first, currentHeader);
      final foundIds = rows.skip(1).map((row) => row[12]).toSet();
      expect(foundIds, {...List.generate(10, (i) => 'w-$i'), 'same-mail'});
      for (final row in rows.skip(1)) {
        expect(row, hasLength(currentHeader.length));
      }
    });
  });

  group('CsvStore.migrate', () {
    test('pads a legacy file and keeps old fields byte-identical', () async {
      final file = File('${temp.path}/old.csv')
        ..writeAsStringSync(
          '${const ListToCsvConverter(eol: '\r\n').convert([
            legacyHeader,
            ['google.com', '2020-09-09T00:00:00.000Z', '2020-09-09T23:59:59.000Z', '198.51.100.151', '3', 'fail', 'pass', 'example.com', '(absent)', 'none', 'example.com', 'pass'],
          ])}\r\n\r\n',
        );
      final before = readRows(file);

      final outcome = await CsvStore(file: file).migrate();

      expect(outcome, isA<Migrated>().having((o) => o.rows, 'rows', 1));
      final after = readRows(file);
      expect(after.first, currentHeader);
      expect(after[1].sublist(0, 12), before[1]);
      expect(after[1].sublist(12), everyElement(isEmpty));
      // The empty line stays an empty line in the raw file.
      expect(file.readAsLinesSync()[2], isEmpty);
      // Appends land under the new header afterwards.
      final appended = await CsvStore(file: file)
          .appendReport(reportWithId('m-1'));
      expect(appended, isA<Appended>());
    });

    test('running twice changes nothing the second time', () async {
      final file = File('${temp.path}/old.csv')
        ..writeAsStringSync(
          '${const ListToCsvConverter(eol: '\r\n').convert([legacyHeader])}\r\n',
        );

      expect(await CsvStore(file: file).migrate(), isA<Migrated>());
      final once = file.readAsStringSync();
      expect(await CsvStore(file: file).migrate(), isA<AlreadyCurrent>());
      expect(file.readAsStringSync(), once);
    });

    test('pads short lines under an already current header', () async {
      final file = File('${temp.path}/gap.csv')
        ..writeAsStringSync(
          '${currentHeader.join(',')}\n'
          '${List.filled(12, 'v').join(',')}\n',
        );

      expect(
        await CsvStore(file: file).migrate(),
        isA<Migrated>().having((o) => o.rows, 'rows', 1),
      );
      expect(readRows(file)[1], hasLength(currentHeader.length));
      expect(await CsvStore(file: file).migrate(), isA<AlreadyCurrent>());
    });

    test('creates a missing file with the current header', () async {
      final file = File('${temp.path}/missing.csv');

      expect(await CsvStore(file: file).migrate(), isA<AlreadyCurrent>());
      expect(readRows(file).single, currentHeader);
    });

    test('refuses a header that is neither legacy nor current', () async {
      final file = File('${temp.path}/odd.csv')
        ..writeAsStringSync('a,b,c\n1,2,3\n');

      expect(() => CsvStore(file: file).migrate(), throwsFormatException);
      expect(file.readAsStringSync(), 'a,b,c\n1,2,3\n');
    });

    test('carries ragged lines over instead of dropping them', () async {
      final file = File('${temp.path}/ragged.csv')
        ..writeAsStringSync(
          '${legacyHeader.join(',')}\n'
          'truncated,row\n'
          '\n',
        );

      final outcome = await CsvStore(file: file).migrate();

      expect(outcome, isA<Migrated>().having((o) => o.rows, 'rows', 1));
      final after = readRows(file);
      expect(after[1].take(2), ['truncated', 'row']);
      expect(after[1], hasLength(currentHeader.length));
      expect(file.readAsLinesSync()[2], isEmpty);
    });
  });
}
