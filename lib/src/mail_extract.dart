/// Finds the aggregate-report payload inside a raw report mail.
///
/// Reporters disagree on packaging: zip or gzip attachments, plain `.xml`
/// files, gzip parts that are inline or carry no disposition at all. Instead
/// of trusting file names or content types, every leaf MIME part is decoded
/// and, by magic bytes, gunzipped or unzipped; the first bytes that parse as
/// a `<feedback>` document win. File names and media types only end up in the
/// log, never in a decision.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

final _logger = Logger('dmarc_mail');

/// Thrown when no MIME part of a mail yields a `<feedback>` document. The
/// message lists what was tried, so the dead-letter reason names it.
class FeedbackNotFound implements Exception {
  const FeedbackNotFound(this.message);

  final String message;

  @override
  String toString() => 'FeedbackNotFound: $message';
}

/// Refuses a single decompressed part larger than this. Reports are bytes to
/// kilobytes; anything past the cap is a malformed or hostile mail, and the
/// pipe must dead-letter it rather than exhaust memory.
const maxDecompressedBytes = 16 * 1024 * 1024;

/// Where the winning bytes came from, for the stderr outcome line.
class FeedbackXml {
  const FeedbackXml({required this.bytes, required this.description});

  final Uint8List bytes;
  final String description;
}

/// Extracts the `<feedback>` XML document from the raw bytes of one mail.
FeedbackXml extractFeedbackXml(Uint8List rawMail) {
  final MimeMessage message;
  try {
    message = MimeMessage.parseFromData(rawMail);
  } catch (e) {
    throw FeedbackNotFound('Not a MIME mail: $e');
  }
  final attempts = <String>[];
  for (final part in message.allPartsFlat) {
    // Multipart containers carry no content of their own.
    if (part.isMultipart) {
      continue;
    }
    final fileName = part.decodeFileName() ?? '(no name)';
    final mediaType = part.getHeaderContentType()?.value ?? '(no type)';
    final decoded = part.decodeContentBinary();
    if (decoded == null || decoded.isEmpty) {
      attempts.add('$fileName <$mediaType>: empty, skipped.');
      continue;
    }
    _logger.finer(
      'Trying part $fileName <$mediaType>, '
      '${decoded.length} bytes.',
    );
    for (final candidate in _candidates(decoded)) {
      final (label, bytes) = candidate;
      if (bytes.length > maxDecompressedBytes) {
        throw FeedbackNotFound(
          'Part $fileName $label decompresses to ${bytes.length} bytes, '
          'past the $maxDecompressedBytes cap.',
        );
      }
      if (_isFeedback(bytes)) {
        return FeedbackXml(bytes: bytes, description: '$fileName $label');
      }
      attempts.add('$fileName <$mediaType> $label: not a <feedback> document.');
    }
  }
  throw FeedbackNotFound(
    'No report payload found (${attempts.length} parts tried): '
    '${attempts.take(8).join(' ')}',
  );
}

/// The byte strings one decoded part can yield: gunzipped, unzipped, or raw,
/// routed by magic bytes rather than names or types.
Iterable<(String, Uint8List)> _candidates(Uint8List decoded) sync* {
  if (_isGzip(decoded)) {
    yield ('(gzip)', const GZipDecoder().decodeBytes(decoded));
    return;
  }
  if (_isZip(decoded)) {
    final archive = ZipDecoder().decodeBytes(decoded);
    final files = archive.files.toList();
    // Prefer `.xml` entries; fall back to any file entry.
    files.sort((a, b) {
      final aXml = a.name.toLowerCase().endsWith('.xml') ? 0 : 1;
      final bXml = b.name.toLowerCase().endsWith('.xml') ? 0 : 1;
      return aXml.compareTo(bXml);
    });
    for (final file in files) {
      if (!file.isFile) {
        continue;
      }
      yield ('(zip:${file.name})', file.content);
    }
    return;
  }
  yield ('(raw)', decoded);
}

bool _isGzip(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

bool _isZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4b &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

bool _isFeedback(Uint8List bytes) {
  try {
    final document = XmlDocument.parse(utf8.decode(bytes));
    return document.rootElement.name.local == 'feedback';
  } catch (_) {
    return false;
  }
}

extension on MimePart {
  bool get isMultipart => mediaType.top == MediaToptype.multipart;
}
