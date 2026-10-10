/// The dead-letter directory: where raw mails land when they cannot be
/// appended, so a failure never loses the report.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('dmarc_dead_letter');

/// Where reprocessed mails go after their rows land in the CSV.
const processedDirName = 'processed';

/// Saves [rawMail] to [dir] with a `.reason.txt` sidecar naming [reason].
/// Returns the saved mail's path. Throws when the write fails; the caller
/// turns that into exit 75 so postfix queues and retries.
Future<String> saveDeadLetter({
  required Directory dir,
  required Uint8List rawMail,
  required String reason,
}) async {
  await dir.create(recursive: true);
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll('-', '')
      .replaceAll(':', '');
  final nonce = Random.secure().nextInt(0xffffff).toRadixString(16).padLeft(6);
  final base = '$stamp-$pid-$nonce';
  final mailPath = p.join(dir.path, '$base.eml');
  await File(mailPath).writeAsBytes(rawMail);
  await File(p.join(dir.path, '$base.reason.txt')).writeAsString(
    '$reason\nSaved ${DateTime.now().toUtc().toIso8601String()}.\n',
  );
  _logger.info('Saved unprocessable mail to $mailPath: $reason');
  return mailPath;
}

/// Moves a dead-lettered mail and its reason sidecar, if any, to [targetDir].
Future<void> moveDeadLetter({
  required File mail,
  required Directory targetDir,
}) async {
  await targetDir.create(recursive: true);
  final target = p.join(targetDir.path, p.basename(mail.path));
  await mail.rename(target);
  final sidecar = File(
    p.join(
      mail.parent.path,
      '${p.basenameWithoutExtension(mail.path)}.reason.txt',
    ),
  );
  if (await sidecar.exists()) {
    await sidecar.rename(p.join(targetDir.path, p.basename(sidecar.path)));
  }
}
