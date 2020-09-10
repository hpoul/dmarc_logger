import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:csv/csv.dart';
import 'package:dmarc_logger/src/dmarc_parse.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';
import 'package:quiver/check.dart';

final _logger = Logger('dmarc_mail_handler');

class IncomingMailHandler {
  IncomingMailHandler({@required this.outputCsvFile});

  final File outputCsvFile;

  Future<void> handle(Stream<List<int>> input) async {
    final content = await input
        .transform(const Utf8Decoder())
        .fold<StringBuffer>(
            StringBuffer(), (previous, element) => previous..write(element));
    _logger.fine('Parsing message ...');
    final message = MimeMessage();
    message.bodyRaw = content.toString();
    message.parse();

    final xmlContent = _findXmlContent(message);
    final tmp = DmarcParser().parse(xmlContent);
    final list = [
      if (!outputCsvFile.existsSync()) ...[
        tmp.first.keys.toList(),
      ],
      ...tmp.map((e) => e.values.map((e) => e?.toString()).toList()),
    ];
    final out = outputCsvFile.openWrite(mode: FileMode.append);
    const converter = ListToCsvConverter();
    out.write(converter.convert(list));
    out.write(converter.eol);
    await out.flush();
    await out.close();
  }

  Uint8List _findXmlContent(MimeMessage message) {
    final ci =
        message.findContentInfo(disposition: ContentDisposition.attachment);
    if (ci.length != 1) {
      _logger.severe('Expected one attachment, got ${ci.length}: $ci');
      throw StateError('Expected one attachment, got ${ci.length}');
    }

    final zipInfo = ci.first;
    final part = message.getPart(zipInfo.fetchId);
    final zipFileBytes = part.decodeContentBinary();
    if (zipInfo.fileName.endsWith('zip')) {
      final archive = ZipDecoder().decodeBytes(zipFileBytes);
      checkState(archive.length == 1);

      return (archive.first.content as Uint8List);
    } else if (zipInfo.fileName.endsWith('gz')) {
      return gzip.decode(zipFileBytes) as Uint8List;
    } else {
      throw StateError('Invalid file ${zipInfo.fileName}');
    }
  }
}
