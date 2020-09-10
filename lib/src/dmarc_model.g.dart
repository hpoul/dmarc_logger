// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dmarc_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_Metadata _$_$_MetadataFromJson(Map<String, dynamic> json) {
  return _$_Metadata(
    orgName: json['orgName'] as String,
    begin:
        json['begin'] == null ? null : DateTime.parse(json['begin'] as String),
    end: json['end'] == null ? null : DateTime.parse(json['end'] as String),
  );
}

Map<String, dynamic> _$_$_MetadataToJson(_$_Metadata instance) =>
    <String, dynamic>{
      'orgName': instance.orgName,
      'begin': instance.begin?.toIso8601String(),
      'end': instance.end?.toIso8601String(),
    };

_$_DmarcRecord _$_$_DmarcRecordFromJson(Map<String, dynamic> json) {
  return _$_DmarcRecord(
    sourceIp: json['sourceIp'] as String,
    count: json['count'] as int,
    dkim: _$enumDecodeNullable(_$PolicyResultEnumMap, json['dkim']),
    spf: _$enumDecodeNullable(_$PolicyResultEnumMap, json['spf']),
    headerFrom: json['headerFrom'] as String,
  );
}

Map<String, dynamic> _$_$_DmarcRecordToJson(_$_DmarcRecord instance) =>
    <String, dynamic>{
      'sourceIp': instance.sourceIp,
      'count': instance.count,
      'dkim': _$PolicyResultEnumMap[instance.dkim],
      'spf': _$PolicyResultEnumMap[instance.spf],
      'headerFrom': instance.headerFrom,
    };

T _$enumDecode<T>(
  Map<T, dynamic> enumValues,
  dynamic source, {
  T unknownValue,
}) {
  if (source == null) {
    throw ArgumentError('A value must be provided. Supported values: '
        '${enumValues.values.join(', ')}');
  }

  final value = enumValues.entries
      .singleWhere((e) => e.value == source, orElse: () => null)
      ?.key;

  if (value == null && unknownValue == null) {
    throw ArgumentError('`$source` is not one of the supported values: '
        '${enumValues.values.join(', ')}');
  }
  return value ?? unknownValue;
}

T _$enumDecodeNullable<T>(
  Map<T, dynamic> enumValues,
  dynamic source, {
  T unknownValue,
}) {
  if (source == null) {
    return null;
  }
  return _$enumDecode<T>(enumValues, source, unknownValue: unknownValue);
}

const _$PolicyResultEnumMap = {
  PolicyResult.pass: 'pass',
  PolicyResult.fail: 'fail',
};

_$_AuthResult _$_$_AuthResultFromJson(Map<String, dynamic> json) {
  return _$_AuthResult(
    domain: json['domain'] as String,
    result: _$enumDecodeNullable(_$DkimResultEnumMap, json['result']),
  );
}

Map<String, dynamic> _$_$_AuthResultToJson(_$_AuthResult instance) =>
    <String, dynamic>{
      'domain': instance.domain,
      'result': _$DkimResultEnumMap[instance.result],
    };

const _$DkimResultEnumMap = {
  DkimResult.none: 'none',
  DkimResult.pass: 'pass',
  DkimResult.fail: 'fail',
  DkimResult.policy: 'policy',
  DkimResult.neutral: 'neutral',
  DkimResult.temperror: 'temperror',
  DkimResult.permerror: 'permerror',
};

// **************************************************************************
// StaticTextGenerator
// **************************************************************************

// modify build.yaml to configure this text.
