import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dmarc_logger/src/dmarc_mail_handler.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

final _logger = Logger('dmarc_logger');

const ARG_CSV_FILE = 'csv-file';

Future<void> main(List<String> arguments) async {
  PrintAppender.setupLogging(stderrLevel: Level.ALL);
  final parser = ArgParser()
    ..addOption(ARG_CSV_FILE, help: 'CSV file to save output to');
  final result = parser.parse(arguments);
  try {
    await launch(parser, result);
  } on UsageException catch (e, _) {
    final message = e.message ?? '';
    final usage = e.usage ?? parser.usage;
    print('$message\n$usage');
  }
}

Future<void> launch(ArgParser parser, ArgResults result) async {
  final csvFile = result[ARG_CSV_FILE] as String;
  if (csvFile == null) {
    throw UsageException('Missing CSV File', null);
  }

  _logger.fine('Reading stdin ...');
  await IncomingMailHandler(
    outputCsvFile: File(csvFile),
  ).handle(stdin);
}
