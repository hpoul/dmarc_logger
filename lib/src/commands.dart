/// The three commands and their exit codes.
///
/// Pipe mode's contract with postfix: exit 0 once the report's rows are
/// appended, or once the raw mail is safely dead-lettered. Exit 75
/// (`EX_TEMPFAIL`) only when even the dead-letter write fails, so postfix
/// queues and retries. Every outcome writes one stderr line saying what
/// happened; a failure never looks like "nothing arrived".
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dmarc_logger/src/csv_store.dart';
import 'package:dmarc_logger/src/dead_letter.dart';
import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/dmarc_parse.dart';
import 'package:dmarc_logger/src/mail_extract.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('dmarc_commands');

/// `EX_TEMPFAIL`: telling postfix to queue and retry.
const exitTempFail = 75;

/// Usage error, e.g. a missing `--csv-file`.
const exitUsage = 64;

/// A failure the operator must fix (a failed migrate or reprocess).
const exitError = 1;

/// Reads one mail from [input], appends its rows, and returns the process
/// exit code.
Future<int> runPipe({
  required File csvFile,
  required Directory deadLetterDir,
  required Stream<List<int>> input,
}) async {
  _logger.info(
    'Pipe mode: csv=${p.absolute(csvFile.path)} '
    'dead-letter=${p.absolute(deadLetterDir.path)}',
  );
  final rawMail = _collectBytes(await input.toList());
  if (rawMail.isEmpty) {
    return _deadLetterOrTempFail(
      deadLetterDir: deadLetterDir,
      rawMail: rawMail,
      reason: 'Empty mail on stdin, nothing to parse.',
    );
  }
  final DmarcReport report;
  final String source;
  try {
    final feedback = extractFeedbackXml(rawMail);
    source = feedback.description;
    report = DmarcParser().parse(feedback.bytes);
  } catch (e) {
    return _deadLetterOrTempFail(
      deadLetterDir: deadLetterDir,
      rawMail: rawMail,
      reason: 'Unparseable report mail: $e',
    );
  }
  final store = CsvStore(file: csvFile);
  final AppendOutcome outcome;
  try {
    outcome = await store.appendReport(report);
  } catch (e) {
    return _deadLetterOrTempFail(
      deadLetterDir: deadLetterDir,
      rawMail: rawMail,
      reason: 'Could not append to ${csvFile.path}: $e',
    );
  }
  final metadata = report.metadata;
  return switch (outcome) {
    Appended(count: final count) => _ok(
      'Appended $count rows from ${metadata.orgName} '
      'report ${metadata.reportId} ($source).',
    ),
    DuplicateReport(:final orgName, :final reportId) => _ok(
      'Duplicate skipped: $orgName report $reportId is already in '
      '${csvFile.path}.',
    ),
    HeaderMismatch(found: final found) => _deadLetterOrTempFail(
      deadLetterDir: deadLetterDir,
      rawMail: rawMail,
      reason:
          'Header mismatch in ${csvFile.path}: found '
          '${found.length} columns (${found.take(4).join(',')}...), want '
          '${currentHeader.length}. Run `migrate`, then `reprocess`.',
    ),
  };
}

/// Rewrites the CSV to the current header; see [CsvStore.migrate].
Future<int> runMigrate({required File csvFile}) async {
  _logger.info('Migrate: csv=${p.absolute(csvFile.path)}');
  final MigrateOutcome outcome;
  try {
    outcome = await CsvStore(file: csvFile).migrate();
  } catch (e) {
    _logger.severe('Migration of ${csvFile.path} failed: $e');
    return exitError;
  }
  return switch (outcome) {
    Migrated(rows: final rows) => _ok(
      'Migrated ${csvFile.path}: $rows '
      '${rows == 1 ? 'data row' : 'data rows'} padded to '
      '${currentHeader.length} columns.',
    ),
    AlreadyCurrent() => _ok('${csvFile.path} already has the current header.'),
  };
}

/// Runs every dead-lettered mail through the current parser. A success
/// appends and moves the mail to `processed/`; a failure stays put with its
/// reason on stderr. Returns 0 when nothing is left failing.
Future<int> runReprocess({
  required Directory deadLetterDir,
  required File csvFile,
}) async {
  _logger.info(
    'Reprocess: dead-letter=${p.absolute(deadLetterDir.path)} '
    'csv=${p.absolute(csvFile.path)}',
  );
  if (!await deadLetterDir.exists()) {
    _logger.warning(
      'Dead-letter directory ${deadLetterDir.path} does not '
      'exist, nothing to reprocess.',
    );
    return 0;
  }
  final mails =
      deadLetterDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.eml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (mails.isEmpty) {
    _logger.info('No dead-lettered mails in ${deadLetterDir.path}.');
    return 0;
  }
  final store = CsvStore(file: csvFile);
  final processed = Directory(p.join(deadLetterDir.path, processedDirName));
  var failures = 0;
  for (final mail in mails) {
    final failed = await _reprocessOne(
      mail: mail,
      store: store,
      processed: processed,
    );
    if (failed) {
      failures++;
    }
  }
  if (failures > 0) {
    _logger.severe(
      '$failures of ${mails.length} mails still fail; '
      'they stay in ${deadLetterDir.path}.',
    );
    return exitError;
  }
  _logger.info(
    'Reprocessed ${mails.length} mails, all landed in '
    '${csvFile.path}.',
  );
  return 0;
}

/// Reprocesses one dead-lettered mail; returns whether it still fails.
Future<bool> _reprocessOne({
  required File mail,
  required CsvStore store,
  required Directory processed,
}) async {
  final Uint8List rawMail;
  try {
    rawMail = await mail.readAsBytes();
  } catch (e) {
    _logger.severe('${mail.path} stays put: cannot read it: $e');
    return true;
  }
  final DmarcReport report;
  try {
    report = DmarcParser().parse(extractFeedbackXml(rawMail).bytes);
  } catch (e) {
    _logger.severe('${mail.path} stays put: still unparseable: $e');
    return true;
  }
  final AppendOutcome outcome;
  try {
    outcome = await store.appendReport(report);
  } catch (e) {
    _logger.severe('${mail.path} stays put: cannot append: $e');
    return true;
  }
  final metadata = report.metadata;
  return switch (outcome) {
    Appended(count: final count) => _moved(
      mail: mail,
      processed: processed,
      note:
          'appended $count rows from ${metadata.orgName} '
          'report ${metadata.reportId}',
    ),
    // A duplicate's rows are already in the file; keeping the mail would
    // only retry it forever.
    DuplicateReport(:final orgName, :final reportId) => _moved(
      mail: mail,
      processed: processed,
      note: 'duplicate of $orgName report $reportId, already in the file',
    ),
    HeaderMismatch(found: final found) => _staysPut(
      mail.path,
      'header mismatch: ${found.length} columns found, '
      '${currentHeader.length} want; run `migrate` first',
    ),
  };
}

Future<bool> _moved({
  required File mail,
  required Directory processed,
  required String note,
}) async {
  try {
    await moveDeadLetter(mail: mail, targetDir: processed);
  } catch (e) {
    _logger.severe(
      '${mail.path} stays put: rows landed but the move to '
      '${processed.path} failed: $e',
    );
    return true;
  }
  _logger.info('${mail.path}: $note; moved to ${processed.path}.');
  return false;
}

Future<bool> _staysPut(String path, String reason) async {
  _logger.severe('$path stays put: $reason.');
  return true;
}

/// Dead-letters [rawMail] and returns the exit code: 0 once it is safe,
/// 75 when even that failed.
Future<int> _deadLetterOrTempFail({
  required Directory deadLetterDir,
  required Uint8List rawMail,
  required String reason,
}) async {
  _logger.severe(reason);
  try {
    final path = await saveDeadLetter(
      dir: deadLetterDir,
      rawMail: rawMail,
      reason: reason,
    );
    _logger.info('Mail saved to $path; exiting 0 so postfix does not bounce.');
    return 0;
  } catch (e) {
    _logger.severe(
      'Dead-letter write to ${deadLetterDir.path} failed: $e; '
      'exiting $exitTempFail so postfix queues and retries.',
    );
    return exitTempFail;
  }
}

int _ok(String message) {
  _logger.info(message);
  return 0;
}

Uint8List _collectBytes(List<List<int>> chunks) {
  final total = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final bytes = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    bytes.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return bytes;
}
