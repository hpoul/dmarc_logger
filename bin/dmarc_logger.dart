/// The `dmarc_logger` pipe and its `migrate`/`reprocess` companions.
///
/// With no command the binary reads one mail from stdin and appends its rows
/// to the CSV; that bare form is what the postfix alias runs. Everything is
/// logged to stderr, because stdout belongs to postfix.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dmarc_logger/src/commands.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path/path.dart' as p;

const csvFileOption = 'csv-file';
const deadLetterDirOption = 'dead-letter-dir';

Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(stderrLevel: Level.ALL);
  final firstPositional = arguments
      .where((arg) => !arg.startsWith('-'))
      .firstOrNull;
  if (firstPositional == 'migrate' || firstPositional == 'reprocess') {
    await _runCommand(arguments);
    return;
  }
  await _runPipe(arguments);
}

/// The bare form: one mail on stdin, rows into the CSV.
Future<void> _runPipe(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(csvFileOption, help: 'CSV file to append report rows to.')
    ..addOption(
      deadLetterDirOption,
      help:
          'Directory for mails that cannot be appended.\n'
          'Defaults to "failed/" beside the CSV file.',
    );
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exitCode = exitUsage;
    return;
  }
  final csvPath = results[csvFileOption] as String?;
  if (csvPath == null || csvPath.isEmpty) {
    stderr.writeln('Missing --$csvFileOption.\n\n${parser.usage}');
    exitCode = exitUsage;
    return;
  }
  exitCode = await runPipe(
    csvFile: File(csvPath),
    deadLetterDir: Directory(
      _deadLetterPath(results[deadLetterDirOption] as String?, csvPath),
    ),
    input: stdin,
  );
}

Future<void> _runCommand(List<String> arguments) async {
  final runner =
      CommandRunner<int>(
          'dmarc_logger',
          'Turns DMARC aggregate-report emails into rows of a flat CSV.',
        )
        ..addCommand(MigrateCommand())
        ..addCommand(ReprocessCommand());
  try {
    final code = await runner.run(arguments) ?? 0;
    exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln('$e');
    exitCode = exitUsage;
  }
}

String _deadLetterPath(String? flag, String csvPath) {
  if (flag != null && flag.isNotEmpty) {
    return flag;
  }
  return p.join(p.dirname(p.absolute(csvPath)), 'failed');
}

/// Rewrites the CSV file to the current header; see `CsvStore.migrate`.
class MigrateCommand extends Command<int> {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Rewrites the CSV file to the current header, '
      'padding old rows with empty fields.';

  MigrateCommand() {
    argParser.addOption(csvFileOption, help: 'CSV file to migrate.');
  }

  @override
  Future<int> run() async {
    final csvPath = argResults?[csvFileOption] as String?;
    if (csvPath == null || csvPath.isEmpty) {
      throw UsageException('Missing --$csvFileOption.', usage);
    }
    return runMigrate(csvFile: File(csvPath));
  }
}

/// Replays dead-lettered mails through the current parser.
class ReprocessCommand extends Command<int> {
  @override
  String get name => 'reprocess';

  @override
  String get description =>
      'Runs every mail in the dead-letter directory '
      'through the current parser, appending successes and moving them to '
      '"processed/".';

  ReprocessCommand() {
    argParser
      ..addOption(csvFileOption, help: 'CSV file to append report rows to.')
      ..addOption(
        deadLetterDirOption,
        help:
            'Directory holding the dead-lettered mails.\n'
            'Defaults to "failed/" beside the CSV file.',
      );
  }

  @override
  Future<int> run() async {
    final csvPath = argResults?[csvFileOption] as String?;
    if (csvPath == null || csvPath.isEmpty) {
      throw UsageException('Missing --$csvFileOption.', usage);
    }
    return runReprocess(
      deadLetterDir: Directory(
        _deadLetterPath(argResults?[deadLetterDirOption] as String?, csvPath),
      ),
      csvFile: File(csvPath),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    for (final element in this) {
      return element;
    }
    return null;
  }
}
