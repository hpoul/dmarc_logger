// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies

part of 'dmarc_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;
Metadata _$MetadataFromJson(Map<String, dynamic> json) {
  return _Metadata.fromJson(json);
}

class _$MetadataTearOff {
  const _$MetadataTearOff();

// ignore: unused_element
  _Metadata call(
      {@required String orgName,
      @required DateTime begin,
      @required DateTime end}) {
    return _Metadata(
      orgName: orgName,
      begin: begin,
      end: end,
    );
  }
}

// ignore: unused_element
const $Metadata = _$MetadataTearOff();

mixin _$Metadata {
  String get orgName;
  DateTime get begin;
  DateTime get end;

  Map<String, dynamic> toJson();
  $MetadataCopyWith<Metadata> get copyWith;
}

abstract class $MetadataCopyWith<$Res> {
  factory $MetadataCopyWith(Metadata value, $Res Function(Metadata) then) =
      _$MetadataCopyWithImpl<$Res>;
  $Res call({String orgName, DateTime begin, DateTime end});
}

class _$MetadataCopyWithImpl<$Res> implements $MetadataCopyWith<$Res> {
  _$MetadataCopyWithImpl(this._value, this._then);

  final Metadata _value;
  // ignore: unused_field
  final $Res Function(Metadata) _then;

  @override
  $Res call({
    Object orgName = freezed,
    Object begin = freezed,
    Object end = freezed,
  }) {
    return _then(_value.copyWith(
      orgName: orgName == freezed ? _value.orgName : orgName as String,
      begin: begin == freezed ? _value.begin : begin as DateTime,
      end: end == freezed ? _value.end : end as DateTime,
    ));
  }
}

abstract class _$MetadataCopyWith<$Res> implements $MetadataCopyWith<$Res> {
  factory _$MetadataCopyWith(_Metadata value, $Res Function(_Metadata) then) =
      __$MetadataCopyWithImpl<$Res>;
  @override
  $Res call({String orgName, DateTime begin, DateTime end});
}

class __$MetadataCopyWithImpl<$Res> extends _$MetadataCopyWithImpl<$Res>
    implements _$MetadataCopyWith<$Res> {
  __$MetadataCopyWithImpl(_Metadata _value, $Res Function(_Metadata) _then)
      : super(_value, (v) => _then(v as _Metadata));

  @override
  _Metadata get _value => super._value as _Metadata;

  @override
  $Res call({
    Object orgName = freezed,
    Object begin = freezed,
    Object end = freezed,
  }) {
    return _then(_Metadata(
      orgName: orgName == freezed ? _value.orgName : orgName as String,
      begin: begin == freezed ? _value.begin : begin as DateTime,
      end: end == freezed ? _value.end : end as DateTime,
    ));
  }
}

@JsonSerializable()
class _$_Metadata implements _Metadata {
  const _$_Metadata(
      {@required this.orgName, @required this.begin, @required this.end})
      : assert(orgName != null),
        assert(begin != null),
        assert(end != null);

  factory _$_Metadata.fromJson(Map<String, dynamic> json) =>
      _$_$_MetadataFromJson(json);

  @override
  final String orgName;
  @override
  final DateTime begin;
  @override
  final DateTime end;

  @override
  String toString() {
    return 'Metadata(orgName: $orgName, begin: $begin, end: $end)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other is _Metadata &&
            (identical(other.orgName, orgName) ||
                const DeepCollectionEquality()
                    .equals(other.orgName, orgName)) &&
            (identical(other.begin, begin) ||
                const DeepCollectionEquality().equals(other.begin, begin)) &&
            (identical(other.end, end) ||
                const DeepCollectionEquality().equals(other.end, end)));
  }

  @override
  int get hashCode =>
      runtimeType.hashCode ^
      const DeepCollectionEquality().hash(orgName) ^
      const DeepCollectionEquality().hash(begin) ^
      const DeepCollectionEquality().hash(end);

  @override
  _$MetadataCopyWith<_Metadata> get copyWith =>
      __$MetadataCopyWithImpl<_Metadata>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$_$_MetadataToJson(this);
  }
}

abstract class _Metadata implements Metadata {
  const factory _Metadata(
      {@required String orgName,
      @required DateTime begin,
      @required DateTime end}) = _$_Metadata;

  factory _Metadata.fromJson(Map<String, dynamic> json) = _$_Metadata.fromJson;

  @override
  String get orgName;
  @override
  DateTime get begin;
  @override
  DateTime get end;
  @override
  _$MetadataCopyWith<_Metadata> get copyWith;
}

DmarcRecord _$DmarcRecordFromJson(Map<String, dynamic> json) {
  return _DmarcRecord.fromJson(json);
}

class _$DmarcRecordTearOff {
  const _$DmarcRecordTearOff();

// ignore: unused_element
  _DmarcRecord call(
      {@required String sourceIp,
      @required int count,
      @required PolicyResult dkim,
      @required PolicyResult spf,
      @required String headerFrom}) {
    return _DmarcRecord(
      sourceIp: sourceIp,
      count: count,
      dkim: dkim,
      spf: spf,
      headerFrom: headerFrom,
    );
  }
}

// ignore: unused_element
const $DmarcRecord = _$DmarcRecordTearOff();

mixin _$DmarcRecord {
  String get sourceIp;
  int get count;
  PolicyResult get dkim;
  PolicyResult get spf;
  String get headerFrom;

  Map<String, dynamic> toJson();
  $DmarcRecordCopyWith<DmarcRecord> get copyWith;
}

abstract class $DmarcRecordCopyWith<$Res> {
  factory $DmarcRecordCopyWith(
          DmarcRecord value, $Res Function(DmarcRecord) then) =
      _$DmarcRecordCopyWithImpl<$Res>;
  $Res call(
      {String sourceIp,
      int count,
      PolicyResult dkim,
      PolicyResult spf,
      String headerFrom});
}

class _$DmarcRecordCopyWithImpl<$Res> implements $DmarcRecordCopyWith<$Res> {
  _$DmarcRecordCopyWithImpl(this._value, this._then);

  final DmarcRecord _value;
  // ignore: unused_field
  final $Res Function(DmarcRecord) _then;

  @override
  $Res call({
    Object sourceIp = freezed,
    Object count = freezed,
    Object dkim = freezed,
    Object spf = freezed,
    Object headerFrom = freezed,
  }) {
    return _then(_value.copyWith(
      sourceIp: sourceIp == freezed ? _value.sourceIp : sourceIp as String,
      count: count == freezed ? _value.count : count as int,
      dkim: dkim == freezed ? _value.dkim : dkim as PolicyResult,
      spf: spf == freezed ? _value.spf : spf as PolicyResult,
      headerFrom:
          headerFrom == freezed ? _value.headerFrom : headerFrom as String,
    ));
  }
}

abstract class _$DmarcRecordCopyWith<$Res>
    implements $DmarcRecordCopyWith<$Res> {
  factory _$DmarcRecordCopyWith(
          _DmarcRecord value, $Res Function(_DmarcRecord) then) =
      __$DmarcRecordCopyWithImpl<$Res>;
  @override
  $Res call(
      {String sourceIp,
      int count,
      PolicyResult dkim,
      PolicyResult spf,
      String headerFrom});
}

class __$DmarcRecordCopyWithImpl<$Res> extends _$DmarcRecordCopyWithImpl<$Res>
    implements _$DmarcRecordCopyWith<$Res> {
  __$DmarcRecordCopyWithImpl(
      _DmarcRecord _value, $Res Function(_DmarcRecord) _then)
      : super(_value, (v) => _then(v as _DmarcRecord));

  @override
  _DmarcRecord get _value => super._value as _DmarcRecord;

  @override
  $Res call({
    Object sourceIp = freezed,
    Object count = freezed,
    Object dkim = freezed,
    Object spf = freezed,
    Object headerFrom = freezed,
  }) {
    return _then(_DmarcRecord(
      sourceIp: sourceIp == freezed ? _value.sourceIp : sourceIp as String,
      count: count == freezed ? _value.count : count as int,
      dkim: dkim == freezed ? _value.dkim : dkim as PolicyResult,
      spf: spf == freezed ? _value.spf : spf as PolicyResult,
      headerFrom:
          headerFrom == freezed ? _value.headerFrom : headerFrom as String,
    ));
  }
}

@JsonSerializable()
class _$_DmarcRecord implements _DmarcRecord {
  const _$_DmarcRecord(
      {@required this.sourceIp,
      @required this.count,
      @required this.dkim,
      @required this.spf,
      @required this.headerFrom})
      : assert(sourceIp != null),
        assert(count != null),
        assert(dkim != null),
        assert(spf != null),
        assert(headerFrom != null);

  factory _$_DmarcRecord.fromJson(Map<String, dynamic> json) =>
      _$_$_DmarcRecordFromJson(json);

  @override
  final String sourceIp;
  @override
  final int count;
  @override
  final PolicyResult dkim;
  @override
  final PolicyResult spf;
  @override
  final String headerFrom;

  @override
  String toString() {
    return 'DmarcRecord(sourceIp: $sourceIp, count: $count, dkim: $dkim, spf: $spf, headerFrom: $headerFrom)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other is _DmarcRecord &&
            (identical(other.sourceIp, sourceIp) ||
                const DeepCollectionEquality()
                    .equals(other.sourceIp, sourceIp)) &&
            (identical(other.count, count) ||
                const DeepCollectionEquality().equals(other.count, count)) &&
            (identical(other.dkim, dkim) ||
                const DeepCollectionEquality().equals(other.dkim, dkim)) &&
            (identical(other.spf, spf) ||
                const DeepCollectionEquality().equals(other.spf, spf)) &&
            (identical(other.headerFrom, headerFrom) ||
                const DeepCollectionEquality()
                    .equals(other.headerFrom, headerFrom)));
  }

  @override
  int get hashCode =>
      runtimeType.hashCode ^
      const DeepCollectionEquality().hash(sourceIp) ^
      const DeepCollectionEquality().hash(count) ^
      const DeepCollectionEquality().hash(dkim) ^
      const DeepCollectionEquality().hash(spf) ^
      const DeepCollectionEquality().hash(headerFrom);

  @override
  _$DmarcRecordCopyWith<_DmarcRecord> get copyWith =>
      __$DmarcRecordCopyWithImpl<_DmarcRecord>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$_$_DmarcRecordToJson(this);
  }
}

abstract class _DmarcRecord implements DmarcRecord {
  const factory _DmarcRecord(
      {@required String sourceIp,
      @required int count,
      @required PolicyResult dkim,
      @required PolicyResult spf,
      @required String headerFrom}) = _$_DmarcRecord;

  factory _DmarcRecord.fromJson(Map<String, dynamic> json) =
      _$_DmarcRecord.fromJson;

  @override
  String get sourceIp;
  @override
  int get count;
  @override
  PolicyResult get dkim;
  @override
  PolicyResult get spf;
  @override
  String get headerFrom;
  @override
  _$DmarcRecordCopyWith<_DmarcRecord> get copyWith;
}

AuthResult _$AuthResultFromJson(Map<String, dynamic> json) {
  return _AuthResult.fromJson(json);
}

class _$AuthResultTearOff {
  const _$AuthResultTearOff();

// ignore: unused_element
  _AuthResult call({@required String domain, @required DkimResult result}) {
    return _AuthResult(
      domain: domain,
      result: result,
    );
  }
}

// ignore: unused_element
const $AuthResult = _$AuthResultTearOff();

mixin _$AuthResult {
  String get domain;
  DkimResult get result;

  Map<String, dynamic> toJson();
  $AuthResultCopyWith<AuthResult> get copyWith;
}

abstract class $AuthResultCopyWith<$Res> {
  factory $AuthResultCopyWith(
          AuthResult value, $Res Function(AuthResult) then) =
      _$AuthResultCopyWithImpl<$Res>;
  $Res call({String domain, DkimResult result});
}

class _$AuthResultCopyWithImpl<$Res> implements $AuthResultCopyWith<$Res> {
  _$AuthResultCopyWithImpl(this._value, this._then);

  final AuthResult _value;
  // ignore: unused_field
  final $Res Function(AuthResult) _then;

  @override
  $Res call({
    Object domain = freezed,
    Object result = freezed,
  }) {
    return _then(_value.copyWith(
      domain: domain == freezed ? _value.domain : domain as String,
      result: result == freezed ? _value.result : result as DkimResult,
    ));
  }
}

abstract class _$AuthResultCopyWith<$Res> implements $AuthResultCopyWith<$Res> {
  factory _$AuthResultCopyWith(
          _AuthResult value, $Res Function(_AuthResult) then) =
      __$AuthResultCopyWithImpl<$Res>;
  @override
  $Res call({String domain, DkimResult result});
}

class __$AuthResultCopyWithImpl<$Res> extends _$AuthResultCopyWithImpl<$Res>
    implements _$AuthResultCopyWith<$Res> {
  __$AuthResultCopyWithImpl(
      _AuthResult _value, $Res Function(_AuthResult) _then)
      : super(_value, (v) => _then(v as _AuthResult));

  @override
  _AuthResult get _value => super._value as _AuthResult;

  @override
  $Res call({
    Object domain = freezed,
    Object result = freezed,
  }) {
    return _then(_AuthResult(
      domain: domain == freezed ? _value.domain : domain as String,
      result: result == freezed ? _value.result : result as DkimResult,
    ));
  }
}

@JsonSerializable()
class _$_AuthResult implements _AuthResult {
  const _$_AuthResult({@required this.domain, @required this.result})
      : assert(domain != null),
        assert(result != null);

  factory _$_AuthResult.fromJson(Map<String, dynamic> json) =>
      _$_$_AuthResultFromJson(json);

  @override
  final String domain;
  @override
  final DkimResult result;

  @override
  String toString() {
    return 'AuthResult(domain: $domain, result: $result)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other is _AuthResult &&
            (identical(other.domain, domain) ||
                const DeepCollectionEquality().equals(other.domain, domain)) &&
            (identical(other.result, result) ||
                const DeepCollectionEquality().equals(other.result, result)));
  }

  @override
  int get hashCode =>
      runtimeType.hashCode ^
      const DeepCollectionEquality().hash(domain) ^
      const DeepCollectionEquality().hash(result);

  @override
  _$AuthResultCopyWith<_AuthResult> get copyWith =>
      __$AuthResultCopyWithImpl<_AuthResult>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$_$_AuthResultToJson(this);
  }
}

abstract class _AuthResult implements AuthResult {
  const factory _AuthResult(
      {@required String domain, @required DkimResult result}) = _$_AuthResult;

  factory _AuthResult.fromJson(Map<String, dynamic> json) =
      _$_AuthResult.fromJson;

  @override
  String get domain;
  @override
  DkimResult get result;
  @override
  _$AuthResultCopyWith<_AuthResult> get copyWith;
}
