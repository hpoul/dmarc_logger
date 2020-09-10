import 'package:dmarc_logger/src/xml_extensions.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:xml/xml.dart';

part 'dmarc_model.g.dart';

part 'dmarc_model.freezed.dart';

@freezed
abstract class Metadata with _$Metadata {
  const factory Metadata({
    @required String orgName,
    @required DateTime begin,
    @required DateTime end,
  }) = _Metadata;

  factory Metadata.fromJson(Map<String, dynamic> json) =>
      _$MetadataFromJson(json);
}

enum PolicyResult {
  pass,
  fail,
}

extension PolicyResultString on String {
  PolicyResult toPolicyResult() => PolicyResult.values
      .firstWhere((element) => element.toString().endsWith(this));
}

@freezed
abstract class DmarcRecord with _$DmarcRecord {
  const factory DmarcRecord({
    @required String sourceIp,
    @required int count,
    @required PolicyResult dkim,
    @required PolicyResult spf,
    @required String headerFrom,
  }) = _DmarcRecord;

  factory DmarcRecord.fromJson(Map<String, dynamic> json) =>
      _$DmarcRecordFromJson(json);
}

enum DkimResult {
  none,
  pass,
  fail,
  policy,
  neutral,
  temperror,
  permerror,
}

extension DkimResultString on String {
  DkimResult toDkimResult() => DkimResult.values
      .firstWhere((element) => element.toString().endsWith(this));
}

@freezed
abstract class AuthResult with _$AuthResult {
  const factory AuthResult({
    @required String domain,
    @required DkimResult result,
  }) = _AuthResult;

  factory AuthResult.fromJson(Map<String, dynamic> json) =>
      _$AuthResultFromJson(json);
  factory AuthResult.fromXml(XmlElement el) {
    return AuthResult(
      domain: el.textNode('domain'),
      result: el.textNode('result').toDkimResult(),
    );
  }
}
