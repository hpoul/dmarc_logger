import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:dmarc_logger/src/commands.dart';
import 'package:dmarc_logger/src/csv_store.dart';
import 'package:test/test.dart';

import 'support.dart';

Stream<List<int>> stdinOf(Uint8List bytes) => Stream.value(bytes);

List<List<String>> readRows(File file) =>
    const CsvToListConverter(shouldParseNumbers: false)
        .convert(file.readAsStringSync())
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();

void main() {
  late Directory temp;

  setUp(() async {
    temp = await tempDir('cmd');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  group('runPipe', () {
    test('appends a report and exits 0', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail1.eml')),
      );

      expect(code, 0);
      expect(readRows(csv), hasLength(2));
      expect(await dead.exists(), isFalse);
    });

    test('an unknown value lands as its raw string, not a bounce', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail4.eml')),
      );

      expect(code, 0);
      final rows = readRows(csv);
      expect(rows, hasLength(3));
      expect(rows[1][23], contains('bogus'));
      expect(rows[1][28], 'forwarded');
      expect(rows[2][28], 'temperror');
      expect(await dead.exists(), isFalse);
    });

    test('keeps the legacy columns in order and fills the new ones', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');
      for (final name in ['mail1.eml', 'mail3.eml']) {
        final code = await runPipe(
          csvFile: csv,
          deadLetterDir: dead,
          input: stdinOf(exampleMail(name)),
        );
        expect(code, 0);
      }

      final rows = readRows(csv);
      expect(rows.first, currentHeader);
      // mail1: Yahoo-style, DKIM pass, SPF fail.
      expect(rows[1].sublist(0, 12), [
        'Yahoo! Inc.',
        '2020-09-06T00:00:00.000Z',
        '2020-09-06T23:59:59.000Z',
        '192.0.2.181',
        '2',
        'pass',
        'fail',
        'example.com',
        'example.com',
        'pass',
        'mail181.esp.example.net',
        'pass',
      ]);
      expect(rows[1][12], '1000000000.100001');
      expect(rows[1][13], 'example.com');
      expect(rows[1][14], 'quarantine');
      expect(rows[1][19], 'none');
      expect(rows[1][26], 'true');
      expect(rows[1][27], 'false');
      expect(rows[1][28], 'ok');
      // mail3: plain xml, SPF softfail, quarantined.
      expect(rows[2][5], 'fail');
      expect(rows[2][6], 'fail');
      expect(rows[2][11], 'softfail');
      expect(rows[2][19], 'quarantine');
      expect(rows[2][24], 'mfrom');
      expect(rows[2][28], 'spf-not-listed');
    });

    test('a duplicate exits 0 without writing', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');
      await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail2.eml')),
      );

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail2.eml')),
      );

      expect(code, 0);
      expect(readRows(csv), hasLength(2));
    });

    test('an unparseable mail is dead-lettered and exits 0', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(Uint8List.fromList(utf8.encode('not a mail'))),
      );

      expect(code, 0);
      expect(await dead.exists(), isTrue);
      final saved = dead
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.eml'))
          .toList();
      expect(saved, hasLength(1));
      final sidecar = File(
        '${saved.single.path.substring(0, saved.single.path.length - 4)}.reason.txt',
      );
      expect(sidecar.readAsStringSync(), contains('Unparseable'));
      expect(await csv.exists(), isFalse);
    });

    test('empty stdin is dead-lettered and exits 0', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(Uint8List(0)),
      );

      expect(code, 0);
      expect(
        dead.listSync().whereType<File>().where((f) => f.path.endsWith('.eml')),
        hasLength(1),
      );
    });

    test('a header mismatch is dead-lettered and exits 0', () async {
      final csv = File('${temp.path}/reports.csv')
        ..writeAsStringSync('${legacyHeader.join(',')}\n');
      final dead = Directory('${temp.path}/failed');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail1.eml')),
      );

      expect(code, 0);
      expect(
        dead.listSync().whereType<File>().where((f) => f.path.endsWith('.eml')),
        hasLength(1),
      );
      expect(csv.readAsStringSync(), '${legacyHeader.join(',')}\n');
    });

    test('a failed dead-letter write exits 75', () async {
      final csv = File('${temp.path}/reports.csv');
      // A dead-letter "directory" that is really a file cannot be created.
      final blocker = File('${temp.path}/blocker')
        ..writeAsStringSync('in the way');

      final code = await runPipe(
        csvFile: csv,
        deadLetterDir: Directory(blocker.path),
        input: stdinOf(Uint8List.fromList(utf8.encode('not a mail'))),
      );

      expect(code, exitTempFail);
    });
  });

  group('runMigrate', () {
    test('migrates a legacy file and exits 0', () async {
      final csv = File('${temp.path}/old.csv')
        ..writeAsStringSync('${legacyHeader.join(',')}\n');

      expect(await runMigrate(csvFile: csv), 0);
      expect(readRows(csv).single, currentHeader);
    });

    test('a foreign header exits 1 and leaves the file alone', () async {
      final csv = File('${temp.path}/odd.csv')..writeAsStringSync('a,b\n1,2\n');

      expect(await runMigrate(csvFile: csv), exitError);
      expect(csv.readAsStringSync(), 'a,b\n1,2\n');
    });
  });

  group('runReprocess', () {
    test('appends good mails, moves them, leaves bad ones', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed')..createSync();
      File('${dead.path}/good.eml').writeAsBytesSync(exampleMail('mail1.eml'));
      File('${dead.path}/bad.eml').writeAsStringSync('not a mail');

      final code = await runReprocess(deadLetterDir: dead, csvFile: csv);

      expect(code, exitError);
      expect(readRows(csv), hasLength(2));
      expect(File('${dead.path}/good.eml').existsSync(), isFalse);
      expect(File('${dead.path}/processed/good.eml').existsSync(), isTrue);
      expect(File('${dead.path}/bad.eml').existsSync(), isTrue);
    });

    test('a duplicate on reprocess is filed as processed', () async {
      final csv = File('${temp.path}/reports.csv');
      final dead = Directory('${temp.path}/failed')..createSync();
      await runPipe(
        csvFile: csv,
        deadLetterDir: dead,
        input: stdinOf(exampleMail('mail2.eml')),
      );
      File('${dead.path}/again.eml').writeAsBytesSync(exampleMail('mail2.eml'));

      final code = await runReprocess(deadLetterDir: dead, csvFile: csv);

      expect(code, 0);
      expect(readRows(csv), hasLength(2));
      expect(File('${dead.path}/processed/again.eml').existsSync(), isTrue);
    });

    test('an empty or missing directory exits 0', () async {
      final csv = File('${temp.path}/reports.csv');
      final empty = Directory('${temp.path}/empty')..createSync();

      expect(await runReprocess(deadLetterDir: empty, csvFile: csv), 0);
      expect(
        await runReprocess(
          deadLetterDir: Directory('${temp.path}/absent'),
          csvFile: csv,
        ),
        0,
      );
    });
  });

  group('separate processes', () {
    // Pipes are separate processes in production, and flock only
    // serializes across processes, so the locking tests spawn the real
    // binary instead of racing in-process futures.
    Future<Process> startPipe(File csv, Uint8List mail) async {
      final process = await Process.start(Platform.resolvedExecutable, [
        '${Directory.current.path}/bin/dmarc_logger.dart',
        '--csv-file',
        csv.path,
      ], workingDirectory: Directory.current.path);
      process.stdin.add(mail);
      await process.stdin.close();
      return process;
    }

    Future<(int, String, String)> finishPipe(Process process) async {
      final exit = await process.exitCode;
      final out = await process.stdout.transform(utf8.decoder).join();
      final err = await process.stderr.transform(utf8.decoder).join();
      return (exit, out, err);
    }

    test(
      'four pipes racing the same mail append it once and stay off stdout',
      timeout: const Timeout(Duration(seconds: 180)),
      () async {
        final csv = File('${temp.path}/reports.csv');
        final mail = exampleMail('mail1.eml');

        final processes = await Future.wait([
          startPipe(csv, mail),
          startPipe(csv, mail),
          startPipe(csv, mail),
          startPipe(csv, mail),
        ]);
        final results = await Future.wait(processes.map(finishPipe));

        for (final (exit, out, err) in results) {
          expect(exit, 0, reason: 'stderr: $err');
          expect(out, isEmpty, reason: 'stdout belongs to postfix');
        }
        final rows = readRows(csv);
        expect(rows.first, currentHeader);
        expect(rows.skip(1), hasLength(1));
      },
    );

    test(
      'a pipe waits while the lock is held elsewhere',
      timeout: const Timeout(Duration(seconds: 180)),
      () async {
        final csv = File('${temp.path}/reports.csv');
        final mail = exampleMail('mail1.eml');
        final acquired = Completer<void>();
        final release = Completer<void>();
        final hold = CsvStore(file: csv).withLock((_) async {
          acquired.complete();
          await release.future;
        });
        await acquired.future;
        final process = await startPipe(csv, mail);
        // The pipe creates the lock file before blocking on it; wait for
        // that instead of assuming a startup time.
        final lockFile = File('${csv.path}.lock');
        for (var i = 0; i < 300 && !lockFile.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(lockFile.existsSync(), isTrue);
        // Give an unlocked pipe time to land its rows, then check it did
        // not: with the lock held it must still be waiting.
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(
          csv.existsSync(),
          isFalse,
          reason: 'the pipe wrote while the lock was held',
        );
        release.complete();
        final (exit, _, err) = await finishPipe(process);
        await hold;

        expect(exit, 0, reason: 'stderr: $err');
        expect(readRows(csv).skip(1), hasLength(1));
      },
    );
  });
}
