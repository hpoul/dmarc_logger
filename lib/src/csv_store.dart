/// The CSV file: its headers, row mapping, locked appends, duplicate
/// detection, and migration from the 2020 twelve-column layout.
library;

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:dmarc_logger/src/dmarc_model.dart';
import 'package:dmarc_logger/src/results.dart';
import 'package:logging/logging.dart';

final _logger = Logger('dmarc_csv');

/// The twelve columns written since September 2020, kept byte for byte so
/// every old row stays valid and the CSV viewer keeps working.
const legacyHeader = [
  'orgName',
  'begin',
  'end',
  'sourceIp',
  'count',
  'dkim',
  'spf',
  'headerFrom',
  'dkim_domain',
  'dkim_result',
  'spf_domain',
  'spf_result',
];

/// The current header: the legacy twelve plus, in order, the report and
/// policy identity, the receiver's disposition and override reasons, the full
/// DKIM/SPF evidence, the derived alignment and cause.
///
/// The extra policy columns beyond the required set earn their place: without
/// `policyAdkim`/`policyAspf` the `dkimAligned`/`spfAligned` columns are
/// uninterpretable, `policySp`/`policyPct` complete the published policy, and
/// `spfAll` keeps evidence symmetric with `dkimAll` instead of silently
/// dropping repeat SPF results.
const currentHeader = [
  ...legacyHeader,
  'reportId',
  'policyDomain',
  'policyP',
  'policySp',
  'policyPct',
  'policyAdkim',
  'policyAspf',
  'disposition',
  'reasonType',
  'reasonComment',
  'dkimSelector',
  'dkimAll',
  'spfScope',
  'spfAll',
  'dkimAligned',
  'spfAligned',
  'failureCause',
];

/// Placeholder the 2020 writer used for a missing first auth result. Kept so
/// new absent values read the same as the six years of old ones.
const absentMarker = '(absent)';

/// Line ending for appended rows. The 2020 file uses CRLF
/// (`ListToCsvConverter`'s default); staying with it keeps the file uniform.
const csvEol = '\r\n';

/// Maps one parsed report to CSV rows in [currentHeader] order.
List<List<String>> reportToRows(DmarcReport report) {
  final rows = <List<String>>[];
  for (final record in report.records) {
    rows.add(_recordToRow(report, record));
  }
  return rows;
}

List<String> _recordToRow(DmarcReport report, DmarcRecord record) {
  final metadata = report.metadata;
  final policy = report.policy;
  final dkimFirst = record.dkimResults.firstOrNull;
  final spfFirst = record.spfResults.firstOrNull;
  final alignedDkim = dkimAligned(record, policy.adkim);
  final alignedSpf = spfAligned(record, policy.aspf);
  final cause = failureCause(
    dkimPolicy: record.dkimPolicy,
    spfPolicy: record.spfPolicy,
    forwardingReason: hasForwardingReason(record),
    dkim: summarizeDkim(record, policy.adkim),
    spf: summarizeSpf(record, policy.aspf),
  );
  return [
    metadata.orgName,
    metadata.begin.toIso8601String(),
    metadata.end.toIso8601String(),
    record.sourceIp,
    record.count.toString(),
    record.dkimPolicy.rawValue(),
    record.spfPolicy.rawValue(),
    record.headerFrom,
    dkimFirst?.domain ?? absentMarker,
    dkimFirst?.result.rawValue() ?? DkimAuthResult.none.name,
    spfFirst?.domain ?? absentMarker,
    spfFirst?.result.rawValue() ?? SpfAuthResult.none.name,
    metadata.reportId,
    policy.domain,
    policy.p.rawValue(),
    policy.sp?.rawValue() ?? '',
    policy.pct?.toString() ?? '',
    policy.adkim.rawValue(),
    policy.aspf.rawValue(),
    record.disposition.rawValue(),
    record.reasons.map((reason) => reason.type).join(';'),
    record.reasons.map((reason) => reason.comment ?? '').join(';'),
    dkimFirst?.selector ?? '',
    record.dkimResults.map(_describeDkim).join(';'),
    spfFirst?.scope?.rawValue() ?? '',
    record.spfResults.map(_describeSpf).join(';'),
    alignedDkim?.toString() ?? '',
    alignedSpf?.toString() ?? '',
    cause,
  ];
}

String _describeDkim(DkimAuthDetail detail) =>
    '${detail.domain}:${detail.selector ?? ''}:${detail.result.rawValue()}';

String _describeSpf(SpfAuthDetail detail) =>
    '${detail.domain}:${detail.scope?.rawValue() ?? ''}:'
    '${detail.result.rawValue()}';

/// What a locked append found.
sealed class AppendOutcome {
  const AppendOutcome();
}

/// The rows were appended; [count] says how many.
final class Appended extends AppendOutcome {
  const Appended(this.count);

  final int count;
}

/// A report with this `(orgName, reportId)` is already in the file; nothing
/// was written.
final class DuplicateReport extends AppendOutcome {
  const DuplicateReport({required this.orgName, required this.reportId});

  final String orgName;
  final String reportId;
}

/// The file's header is neither the current nor an absent one; nothing was
/// written. The caller dead-letters the mail instead.
final class HeaderMismatch extends AppendOutcome {
  const HeaderMismatch({required this.found});

  /// The header line as found, for the stderr message.
  final List<String> found;
}

/// What a migration run did.
sealed class MigrateOutcome {
  const MigrateOutcome();
}

/// The file was rewritten: [rows] data rows padded to the new header.
final class Migrated extends MigrateOutcome {
  const Migrated(this.rows);

  final int rows;
}

/// The file already carries the current header (or was just created with
/// it); nothing was rewritten.
final class AlreadyCurrent extends MigrateOutcome {
  const AlreadyCurrent();
}

/// Reads and appends the CSV under an exclusive lock.
class CsvStore {
  CsvStore({required this.file});

  final File file;

  /// Appends [report]'s rows: header check, duplicate check and write happen
  /// atomically under one exclusive lock, and the rows go out in a single
  /// write, so concurrent postfix pipes cannot interleave.
  Future<AppendOutcome> appendReport(DmarcReport report) async {
    final rows = reportToRows(report);
    return withLock((content) {
      final lines = _splitLines(content);
      final header = lines.isEmpty ? null : _parseLine(lines.first);
      if (header != null && !_headersEqual(header, currentHeader)) {
        return HeaderMismatch(found: header);
      }
      if (_isDuplicate(lines, report)) {
        return DuplicateReport(
          orgName: report.metadata.orgName,
          reportId: report.metadata.reportId,
        );
      }
      final buffer = StringBuffer();
      if (lines.isEmpty) {
        buffer.write(_convert([currentHeader]));
        buffer.write(csvEol);
      } else if (!content.endsWith('\n')) {
        // A previous writer left no trailing newline; terminate its line
        // before appending ours.
        buffer.write(csvEol);
      }
      if (rows.isNotEmpty) {
        buffer.write(_convert(rows));
        buffer.write(csvEol);
      }
      file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
      _logger.fine('Appended ${rows.length} rows to ${file.path}.');
      return Appended(rows.length);
    });
  }

  /// Rewrites a legacy file to [currentHeader], padding old rows with empty
  /// fields. Old lines are carried over textually, so their old fields stay
  /// byte-identical; only the header line is replaced. Truncated or spliced
  /// lines from the unlocked years are padded on their own parsed field
  /// count and reported, never dropped. Writes a temp file and renames it
  /// into place under the same lock as appends. Running it twice, or on a
  /// current file, changes nothing.
  Future<MigrateOutcome> migrate() async => withLock((content) {
    final lines = _splitLines(content);
    if (lines.isEmpty) {
      file.writeAsStringSync('${_convert([currentHeader])}$csvEol');
      return const AlreadyCurrent();
    }
    final header = _parseLine(lines.first);
    if (_headersEqual(header, currentHeader)) {
      return const AlreadyCurrent();
    }
    if (!_headersEqual(header, legacyHeader)) {
      throw FormatException(
        'Cannot migrate ${file.path}: its header is neither the legacy '
        '12-column nor the current ${currentHeader.length}-column one.',
      );
    }
    final buffer = StringBuffer()
      ..write(_convert([currentHeader]))
      ..write(csvEol);
    var rows = 0;
    var ragged = 0;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        // A fully empty line carries no row; keep it empty so the line
        // count survives the migration.
        buffer.write(csvEol);
        continue;
      }
      // Years of unlocked concurrent appends left truncated and spliced
      // lines behind. Each keeps its bytes and is padded to the new width
      // on its own parsed field count; nothing is reordered or dropped.
      final fields = _parseLine(line);
      final padding = fields.length >= currentHeader.length
          ? ''
          : ',' * (currentHeader.length - fields.length);
      if (fields.length != legacyHeader.length) {
        ragged++;
        _logger.warning(
          'Migrating ${file.path} line ${i + 1} with ${fields.length} '
          'fields instead of ${legacyHeader.length}; carrying it over.',
        );
      }
      buffer
        ..write(line)
        ..write(padding)
        ..write(csvEol);
      rows++;
    }
    if (ragged > 0) {
      _logger.warning(
        'Migrated ${file.path} with $ragged ragged lines carried over; '
        'their old fields are intact.',
      );
    }
    final temp = File('${file.path}.tmp.$pid');
    temp.writeAsStringSync(buffer.toString());
    temp.renameSync(file.path);
    _logger.info('Migrated ${file.path}: $rows rows padded to the new header.');
    return Migrated(rows);
  });

  /// Runs [action] with the file's text while holding the exclusive lock.
  /// The lock lives on a sibling `.lock` file, so the CSV itself is only
  /// ever touched inside the critical section. Exposed for the pipe mode's
  /// header-version logging and for tests.
  Future<T> withLock<T>(T Function(String content) action) async {
    final lockFile = File('${file.path}.lock');
    final access = await lockFile.open(mode: FileMode.write);
    try {
      await access.lock(FileLock.exclusive);
      final content = file.existsSync() ? file.readAsStringSync() : '';
      return action(content);
    } finally {
      await access.unlock();
      await access.close();
    }
  }

  /// Whether a row with the report's `(orgName, reportId)` is already
  /// present. Reports without an id cannot be recognized and are always
  /// appended; the parser warns about them.
  ///
  /// Reading the whole file per mail is fine at today's ~1.5 MB. Past a few
  /// tens of megabytes, or a few hundred thousand rows, this linear scan per
  /// delivery would dominate; then keep a sidecar index of seen ids (or move
  /// the store to SQLite) instead of scanning.
  bool _isDuplicate(List<String> lines, DmarcReport report) {
    final orgName = report.metadata.orgName;
    final reportId = report.metadata.reportId;
    if (orgName.isEmpty || reportId.isEmpty) {
      return false;
    }
    if (lines.length < 2) {
      return false;
    }
    final header = _parseLine(lines.first);
    final orgIndex = header.indexOf('orgName');
    final idIndex = header.indexOf('reportId');
    if (orgIndex == -1 || idIndex == -1) {
      // A current header always has both; anything else was rejected by the
      // header check before this runs.
      return false;
    }
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final fields = _parseLine(line);
      if (orgIndex < fields.length &&
          idIndex < fields.length &&
          fields[orgIndex] == orgName &&
          fields[idIndex] == reportId) {
        return true;
      }
    }
    return false;
  }
}

bool _headersEqual(List<String> found, List<String> expected) {
  if (found.length != expected.length) {
    return false;
  }
  for (var i = 0; i < found.length; i++) {
    if (found[i] != expected[i]) {
      return false;
    }
  }
  return true;
}

List<String> _parseLine(String line) {
  // Never parse numbers: a numeric report id must compare as its exact
  // string, not as a precision-losing double.
  final rows = const CsvToListConverter(shouldParseNumbers: false)
      .convert(line);
  if (rows.isEmpty) {
    return const [];
  }
  return rows.first.map((field) => field.toString()).toList();
}

List<String> _splitLines(String content) {
  if (content.isEmpty) {
    return const [];
  }
  // Split on LF only: a general line splitter would also break on lone CR
  // bytes, and the live file contains at least one. Each piece loses at
  // most one trailing CR, so every old line keeps its bytes.
  final pieces = content.split('\n');
  if (pieces.isNotEmpty && pieces.last.isEmpty) {
    pieces.removeLast();
  }
  return pieces
      .map(
        (piece) =>
            piece.endsWith('\r') ? piece.substring(0, piece.length - 1) : piece,
      )
      .toList();
}

String _convert(List<List<String>> rows) =>
    const ListToCsvConverter(eol: csvEol).convert(rows);

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final element in this) {
      return element;
    }
    return null;
  }
}
