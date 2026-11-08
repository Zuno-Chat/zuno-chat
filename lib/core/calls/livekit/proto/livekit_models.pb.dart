// This is a generated file - do not edit.
//
// Generated from livekit_models.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $1;

import 'livekit_metrics.pb.dart' as $0;
import 'livekit_models.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'livekit_models.pbenum.dart';

class Pagination extends $pb.GeneratedMessage {
  factory Pagination({
    $core.String? afterId,
    $core.int? limit,
  }) {
    final result = Pagination._();
    if (afterId != null) result.afterId = afterId;
    if (limit != null) result.limit = limit;
    return result;
  }

  Pagination._();

  factory Pagination.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pagination()..mergeFromBuffer(data, registry);
  factory Pagination.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pagination()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pagination',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: Pagination.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'afterId')
    ..aI(2, _omitFieldNames ? '' : 'limit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pagination clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pagination copyWith(void Function(Pagination) updates) =>
      super.copyWith((message) => updates(message as Pagination)) as Pagination;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Pagination() / Pagination.new instead')
  static Pagination create() => Pagination._();
  static $pb.GeneratedMessage $_createMessage() => Pagination._();
  @$core.override
  Pagination createEmptyInstance() => Pagination._();
  @$core.pragma('dart2js:noInline')
  static Pagination getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Pagination>(Pagination.$_createMessage);
  static Pagination? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get afterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set afterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAfterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAfterId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class TokenPagination extends $pb.GeneratedMessage {
  factory TokenPagination({
    $core.String? token,
  }) {
    final result = TokenPagination._();
    if (token != null) result.token = token;
    return result;
  }

  TokenPagination._();

  factory TokenPagination.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TokenPagination()..mergeFromBuffer(data, registry);
  factory TokenPagination.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TokenPagination()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TokenPagination',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: TokenPagination.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'token')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TokenPagination clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TokenPagination copyWith(void Function(TokenPagination) updates) =>
      super.copyWith((message) => updates(message as TokenPagination))
          as TokenPagination;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TokenPagination() / TokenPagination.new instead')
  static TokenPagination create() => TokenPagination._();
  static $pb.GeneratedMessage $_createMessage() => TokenPagination._();
  @$core.override
  TokenPagination createEmptyInstance() => TokenPagination._();
  @$core.pragma('dart2js:noInline')
  static TokenPagination getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TokenPagination>(
          TokenPagination.$_createMessage);
  static TokenPagination? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get token => $_getSZ(0);
  @$pb.TagNumber(1)
  set token($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => $_clearField(1);
}

/// ListUpdate is used for updated APIs where 'repeated string' field is modified.
class ListUpdate extends $pb.GeneratedMessage {
  factory ListUpdate({
    $core.Iterable<$core.String>? set,
    $core.Iterable<$core.String>? add,
    $core.Iterable<$core.String>? remove,
    $core.bool? clear_4,
  }) {
    final result = ListUpdate._();
    if (set != null) result.set.addAll(set);
    if (add != null) result.add.addAll(add);
    if (remove != null) result.remove.addAll(remove);
    if (clear_4 != null) result.clear_4 = clear_4;
    return result;
  }

  ListUpdate._();

  factory ListUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUpdate()..mergeFromBuffer(data, registry);
  factory ListUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListUpdate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListUpdate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ListUpdate.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'set')
    ..pPS(2, _omitFieldNames ? '' : 'add')
    ..pPS(3, _omitFieldNames ? '' : 'remove')
    ..aOB(4, _omitFieldNames ? '' : 'clear')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListUpdate copyWith(void Function(ListUpdate) updates) =>
      super.copyWith((message) => updates(message as ListUpdate)) as ListUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ListUpdate() / ListUpdate.new instead')
  static ListUpdate create() => ListUpdate._();
  static $pb.GeneratedMessage $_createMessage() => ListUpdate._();
  @$core.override
  ListUpdate createEmptyInstance() => ListUpdate._();
  @$core.pragma('dart2js:noInline')
  static ListUpdate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListUpdate>(ListUpdate.$_createMessage);
  static ListUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get set => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get add => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get remove => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get clear_4 => $_getBF(3);
  @$pb.TagNumber(4)
  set clear_4($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasClear_4() => $_has(3);
  @$pb.TagNumber(4)
  void clearClear_4() => $_clearField(4);
}

class Room extends $pb.GeneratedMessage {
  factory Room({
    $core.String? sid,
    $core.String? name,
    $core.int? emptyTimeout,
    $core.int? maxParticipants,
    $fixnum.Int64? creationTime,
    $core.String? turnPassword,
    $core.Iterable<Codec>? enabledCodecs,
    $core.String? metadata,
    $core.int? numParticipants,
    $core.bool? activeRecording,
    $core.int? numPublishers,
    TimedVersion? version,
    $core.int? departureTimeout,
    $fixnum.Int64? creationTimeMs,
  }) {
    final result = Room._();
    if (sid != null) result.sid = sid;
    if (name != null) result.name = name;
    if (emptyTimeout != null) result.emptyTimeout = emptyTimeout;
    if (maxParticipants != null) result.maxParticipants = maxParticipants;
    if (creationTime != null) result.creationTime = creationTime;
    if (turnPassword != null) result.turnPassword = turnPassword;
    if (enabledCodecs != null) result.enabledCodecs.addAll(enabledCodecs);
    if (metadata != null) result.metadata = metadata;
    if (numParticipants != null) result.numParticipants = numParticipants;
    if (activeRecording != null) result.activeRecording = activeRecording;
    if (numPublishers != null) result.numPublishers = numPublishers;
    if (version != null) result.version = version;
    if (departureTimeout != null) result.departureTimeout = departureTimeout;
    if (creationTimeMs != null) result.creationTimeMs = creationTimeMs;
    return result;
  }

  Room._();

  factory Room.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Room()..mergeFromBuffer(data, registry);
  factory Room.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Room()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Room',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: Room.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sid')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aI(3, _omitFieldNames ? '' : 'emptyTimeout',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'maxParticipants',
        fieldType: $pb.PbFieldType.OU3)
    ..aInt64(5, _omitFieldNames ? '' : 'creationTime')
    ..aOS(6, _omitFieldNames ? '' : 'turnPassword')
    ..pPM<Codec>(7, _omitFieldNames ? '' : 'enabledCodecs',
        subBuilder: Codec.$_createMessage)
    ..aOS(8, _omitFieldNames ? '' : 'metadata')
    ..aI(9, _omitFieldNames ? '' : 'numParticipants',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(10, _omitFieldNames ? '' : 'activeRecording')
    ..aI(11, _omitFieldNames ? '' : 'numPublishers',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<TimedVersion>(13, _omitFieldNames ? '' : 'version',
        subBuilder: TimedVersion.$_createMessage)
    ..aI(14, _omitFieldNames ? '' : 'departureTimeout',
        fieldType: $pb.PbFieldType.OU3)
    ..aInt64(15, _omitFieldNames ? '' : 'creationTimeMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Room clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Room copyWith(void Function(Room) updates) =>
      super.copyWith((message) => updates(message as Room)) as Room;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Room() / Room.new instead')
  static Room create() => Room._();
  static $pb.GeneratedMessage $_createMessage() => Room._();
  @$core.override
  Room createEmptyInstance() => Room._();
  @$core.pragma('dart2js:noInline')
  static Room getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Room>(Room.$_createMessage);
  static Room? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sid => $_getSZ(0);
  @$pb.TagNumber(1)
  set sid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSid() => $_has(0);
  @$pb.TagNumber(1)
  void clearSid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get emptyTimeout => $_getIZ(2);
  @$pb.TagNumber(3)
  set emptyTimeout($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEmptyTimeout() => $_has(2);
  @$pb.TagNumber(3)
  void clearEmptyTimeout() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxParticipants => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxParticipants($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxParticipants() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxParticipants() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get creationTime => $_getI64(4);
  @$pb.TagNumber(5)
  set creationTime($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreationTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreationTime() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get turnPassword => $_getSZ(5);
  @$pb.TagNumber(6)
  set turnPassword($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTurnPassword() => $_has(5);
  @$pb.TagNumber(6)
  void clearTurnPassword() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<Codec> get enabledCodecs => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get metadata => $_getSZ(7);
  @$pb.TagNumber(8)
  set metadata($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasMetadata() => $_has(7);
  @$pb.TagNumber(8)
  void clearMetadata() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get numParticipants => $_getIZ(8);
  @$pb.TagNumber(9)
  set numParticipants($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasNumParticipants() => $_has(8);
  @$pb.TagNumber(9)
  void clearNumParticipants() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get activeRecording => $_getBF(9);
  @$pb.TagNumber(10)
  set activeRecording($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasActiveRecording() => $_has(9);
  @$pb.TagNumber(10)
  void clearActiveRecording() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get numPublishers => $_getIZ(10);
  @$pb.TagNumber(11)
  set numPublishers($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasNumPublishers() => $_has(10);
  @$pb.TagNumber(11)
  void clearNumPublishers() => $_clearField(11);

  @$pb.TagNumber(13)
  TimedVersion get version => $_getN(11);
  @$pb.TagNumber(13)
  set version(TimedVersion value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasVersion() => $_has(11);
  @$pb.TagNumber(13)
  void clearVersion() => $_clearField(13);
  @$pb.TagNumber(13)
  TimedVersion ensureVersion() => $_ensure(11);

  @$pb.TagNumber(14)
  $core.int get departureTimeout => $_getIZ(12);
  @$pb.TagNumber(14)
  set departureTimeout($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(14)
  $core.bool hasDepartureTimeout() => $_has(12);
  @$pb.TagNumber(14)
  void clearDepartureTimeout() => $_clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get creationTimeMs => $_getI64(13);
  @$pb.TagNumber(15)
  set creationTimeMs($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(15)
  $core.bool hasCreationTimeMs() => $_has(13);
  @$pb.TagNumber(15)
  void clearCreationTimeMs() => $_clearField(15);
}

class Codec extends $pb.GeneratedMessage {
  factory Codec({
    $core.String? mime,
    $core.String? fmtpLine,
  }) {
    final result = Codec._();
    if (mime != null) result.mime = mime;
    if (fmtpLine != null) result.fmtpLine = fmtpLine;
    return result;
  }

  Codec._();

  factory Codec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Codec()..mergeFromBuffer(data, registry);
  factory Codec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Codec()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Codec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: Codec.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mime')
    ..aOS(2, _omitFieldNames ? '' : 'fmtpLine')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Codec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Codec copyWith(void Function(Codec) updates) =>
      super.copyWith((message) => updates(message as Codec)) as Codec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Codec() / Codec.new instead')
  static Codec create() => Codec._();
  static $pb.GeneratedMessage $_createMessage() => Codec._();
  @$core.override
  Codec createEmptyInstance() => Codec._();
  @$core.pragma('dart2js:noInline')
  static Codec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Codec>(Codec.$_createMessage);
  static Codec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mime => $_getSZ(0);
  @$pb.TagNumber(1)
  set mime($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMime() => $_has(0);
  @$pb.TagNumber(1)
  void clearMime() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get fmtpLine => $_getSZ(1);
  @$pb.TagNumber(2)
  set fmtpLine($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFmtpLine() => $_has(1);
  @$pb.TagNumber(2)
  void clearFmtpLine() => $_clearField(2);
}

class PlayoutDelay extends $pb.GeneratedMessage {
  factory PlayoutDelay({
    $core.bool? enabled,
    $core.int? min,
    $core.int? max,
  }) {
    final result = PlayoutDelay._();
    if (enabled != null) result.enabled = enabled;
    if (min != null) result.min = min;
    if (max != null) result.max = max;
    return result;
  }

  PlayoutDelay._();

  factory PlayoutDelay.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlayoutDelay()..mergeFromBuffer(data, registry);
  factory PlayoutDelay.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlayoutDelay()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlayoutDelay',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: PlayoutDelay.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..aI(2, _omitFieldNames ? '' : 'min', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'max', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlayoutDelay clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlayoutDelay copyWith(void Function(PlayoutDelay) updates) =>
      super.copyWith((message) => updates(message as PlayoutDelay))
          as PlayoutDelay;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PlayoutDelay() / PlayoutDelay.new instead')
  static PlayoutDelay create() => PlayoutDelay._();
  static $pb.GeneratedMessage $_createMessage() => PlayoutDelay._();
  @$core.override
  PlayoutDelay createEmptyInstance() => PlayoutDelay._();
  @$core.pragma('dart2js:noInline')
  static PlayoutDelay getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PlayoutDelay>(
          PlayoutDelay.$_createMessage);
  static PlayoutDelay? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get min => $_getIZ(1);
  @$pb.TagNumber(2)
  set min($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMin() => $_has(1);
  @$pb.TagNumber(2)
  void clearMin() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get max => $_getIZ(2);
  @$pb.TagNumber(3)
  set max($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMax() => $_has(2);
  @$pb.TagNumber(3)
  void clearMax() => $_clearField(3);
}

class ParticipantPermission extends $pb.GeneratedMessage {
  factory ParticipantPermission({
    $core.bool? canSubscribe,
    $core.bool? canPublish,
    $core.bool? canPublishData,
    $core.bool? hidden,
    @$core.Deprecated('This field is deprecated.') $core.bool? recorder,
    $core.Iterable<TrackSource>? canPublishSources,
    $core.bool? canUpdateMetadata,
    @$core.Deprecated('This field is deprecated.') $core.bool? agent,
    $core.bool? canSubscribeMetrics,
    $core.bool? canManageAgentSession,
  }) {
    final result = ParticipantPermission._();
    if (canSubscribe != null) result.canSubscribe = canSubscribe;
    if (canPublish != null) result.canPublish = canPublish;
    if (canPublishData != null) result.canPublishData = canPublishData;
    if (hidden != null) result.hidden = hidden;
    if (recorder != null) result.recorder = recorder;
    if (canPublishSources != null)
      result.canPublishSources.addAll(canPublishSources);
    if (canUpdateMetadata != null) result.canUpdateMetadata = canUpdateMetadata;
    if (agent != null) result.agent = agent;
    if (canSubscribeMetrics != null)
      result.canSubscribeMetrics = canSubscribeMetrics;
    if (canManageAgentSession != null)
      result.canManageAgentSession = canManageAgentSession;
    return result;
  }

  ParticipantPermission._();

  factory ParticipantPermission.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantPermission()..mergeFromBuffer(data, registry);
  factory ParticipantPermission.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantPermission()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ParticipantPermission',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ParticipantPermission.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'canSubscribe')
    ..aOB(2, _omitFieldNames ? '' : 'canPublish')
    ..aOB(3, _omitFieldNames ? '' : 'canPublishData')
    ..aOB(7, _omitFieldNames ? '' : 'hidden')
    ..aOB(8, _omitFieldNames ? '' : 'recorder')
    ..pc<TrackSource>(
        9, _omitFieldNames ? '' : 'canPublishSources', $pb.PbFieldType.KE,
        valueOf: TrackSource.valueOf,
        enumValues: TrackSource.values,
        defaultEnumValue: TrackSource.UNKNOWN)
    ..aOB(10, _omitFieldNames ? '' : 'canUpdateMetadata')
    ..aOB(11, _omitFieldNames ? '' : 'agent')
    ..aOB(12, _omitFieldNames ? '' : 'canSubscribeMetrics')
    ..aOB(13, _omitFieldNames ? '' : 'canManageAgentSession')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantPermission clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantPermission copyWith(
          void Function(ParticipantPermission) updates) =>
      super.copyWith((message) => updates(message as ParticipantPermission))
          as ParticipantPermission;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ParticipantPermission() / ParticipantPermission.new instead')
  static ParticipantPermission create() => ParticipantPermission._();
  static $pb.GeneratedMessage $_createMessage() => ParticipantPermission._();
  @$core.override
  ParticipantPermission createEmptyInstance() => ParticipantPermission._();
  @$core.pragma('dart2js:noInline')
  static ParticipantPermission getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ParticipantPermission>(
          ParticipantPermission.$_createMessage);
  static ParticipantPermission? _defaultInstance;

  /// allow participant to subscribe to other tracks in the room
  @$pb.TagNumber(1)
  $core.bool get canSubscribe => $_getBF(0);
  @$pb.TagNumber(1)
  set canSubscribe($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCanSubscribe() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanSubscribe() => $_clearField(1);

  /// allow participant to publish new tracks to room
  @$pb.TagNumber(2)
  $core.bool get canPublish => $_getBF(1);
  @$pb.TagNumber(2)
  set canPublish($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCanPublish() => $_has(1);
  @$pb.TagNumber(2)
  void clearCanPublish() => $_clearField(2);

  /// allow participant to publish data
  @$pb.TagNumber(3)
  $core.bool get canPublishData => $_getBF(2);
  @$pb.TagNumber(3)
  set canPublishData($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCanPublishData() => $_has(2);
  @$pb.TagNumber(3)
  void clearCanPublishData() => $_clearField(3);

  /// indicates that it's hidden to others
  @$pb.TagNumber(7)
  $core.bool get hidden => $_getBF(3);
  @$pb.TagNumber(7)
  set hidden($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(7)
  $core.bool hasHidden() => $_has(3);
  @$pb.TagNumber(7)
  void clearHidden() => $_clearField(7);

  /// indicates it's a recorder instance
  /// deprecated: use ParticipantInfo.kind instead
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  $core.bool get recorder => $_getBF(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  set recorder($core.bool value) => $_setBool(4, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  $core.bool hasRecorder() => $_has(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  void clearRecorder() => $_clearField(8);

  /// sources that are allowed to be published
  @$pb.TagNumber(9)
  $pb.PbList<TrackSource> get canPublishSources => $_getList(5);

  /// indicates that participant can update own metadata and attributes
  @$pb.TagNumber(10)
  $core.bool get canUpdateMetadata => $_getBF(6);
  @$pb.TagNumber(10)
  set canUpdateMetadata($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(10)
  $core.bool hasCanUpdateMetadata() => $_has(6);
  @$pb.TagNumber(10)
  void clearCanUpdateMetadata() => $_clearField(10);

  /// indicates that participant is an agent
  /// deprecated: use ParticipantInfo.kind instead
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(11)
  $core.bool get agent => $_getBF(7);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(11)
  set agent($core.bool value) => $_setBool(7, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(11)
  $core.bool hasAgent() => $_has(7);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(11)
  void clearAgent() => $_clearField(11);

  /// if a participant can subscribe to metrics
  @$pb.TagNumber(12)
  $core.bool get canSubscribeMetrics => $_getBF(8);
  @$pb.TagNumber(12)
  set canSubscribeMetrics($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(12)
  $core.bool hasCanSubscribeMetrics() => $_has(8);
  @$pb.TagNumber(12)
  void clearCanSubscribeMetrics() => $_clearField(12);

  /// if a participant can manage an agent session via RemoteSession (control and access state)
  @$pb.TagNumber(13)
  $core.bool get canManageAgentSession => $_getBF(9);
  @$pb.TagNumber(13)
  set canManageAgentSession($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(13)
  $core.bool hasCanManageAgentSession() => $_has(9);
  @$pb.TagNumber(13)
  void clearCanManageAgentSession() => $_clearField(13);
}

class ParticipantInfo extends $pb.GeneratedMessage {
  factory ParticipantInfo({
    $core.String? sid,
    $core.String? identity,
    ParticipantInfo_State? state,
    $core.Iterable<TrackInfo>? tracks,
    $core.String? metadata,
    $fixnum.Int64? joinedAt,
    $core.String? name,
    $core.int? version,
    ParticipantPermission? permission,
    $core.String? region,
    $core.bool? isPublisher,
    ParticipantInfo_Kind? kind,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? attributes,
    DisconnectReason? disconnectReason,
    $fixnum.Int64? joinedAtMs,
    $core.Iterable<ParticipantInfo_KindDetail>? kindDetails,
    $core.Iterable<DataTrackInfo>? dataTracks,
    $core.int? clientProtocol,
    $core.Iterable<ClientInfo_Capability>? capabilities,
  }) {
    final result = ParticipantInfo._();
    if (sid != null) result.sid = sid;
    if (identity != null) result.identity = identity;
    if (state != null) result.state = state;
    if (tracks != null) result.tracks.addAll(tracks);
    if (metadata != null) result.metadata = metadata;
    if (joinedAt != null) result.joinedAt = joinedAt;
    if (name != null) result.name = name;
    if (version != null) result.version = version;
    if (permission != null) result.permission = permission;
    if (region != null) result.region = region;
    if (isPublisher != null) result.isPublisher = isPublisher;
    if (kind != null) result.kind = kind;
    if (attributes != null) result.attributes.addEntries(attributes);
    if (disconnectReason != null) result.disconnectReason = disconnectReason;
    if (joinedAtMs != null) result.joinedAtMs = joinedAtMs;
    if (kindDetails != null) result.kindDetails.addAll(kindDetails);
    if (dataTracks != null) result.dataTracks.addAll(dataTracks);
    if (clientProtocol != null) result.clientProtocol = clientProtocol;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    return result;
  }

  ParticipantInfo._();

  factory ParticipantInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantInfo()..mergeFromBuffer(data, registry);
  factory ParticipantInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ParticipantInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ParticipantInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sid')
    ..aOS(2, _omitFieldNames ? '' : 'identity')
    ..aE<ParticipantInfo_State>(3, _omitFieldNames ? '' : 'state',
        enumValues: ParticipantInfo_State.values)
    ..pPM<TrackInfo>(4, _omitFieldNames ? '' : 'tracks',
        subBuilder: TrackInfo.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'metadata')
    ..aInt64(6, _omitFieldNames ? '' : 'joinedAt')
    ..aOS(9, _omitFieldNames ? '' : 'name')
    ..aI(10, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..aOM<ParticipantPermission>(11, _omitFieldNames ? '' : 'permission',
        subBuilder: ParticipantPermission.$_createMessage)
    ..aOS(12, _omitFieldNames ? '' : 'region')
    ..aOB(13, _omitFieldNames ? '' : 'isPublisher')
    ..aE<ParticipantInfo_Kind>(14, _omitFieldNames ? '' : 'kind',
        enumValues: ParticipantInfo_Kind.values)
    ..m<$core.String, $core.String>(15, _omitFieldNames ? '' : 'attributes',
        entryClassName: 'ParticipantInfo.AttributesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('livekit'))
    ..aE<DisconnectReason>(16, _omitFieldNames ? '' : 'disconnectReason',
        enumValues: DisconnectReason.values)
    ..aInt64(17, _omitFieldNames ? '' : 'joinedAtMs')
    ..pc<ParticipantInfo_KindDetail>(
        18, _omitFieldNames ? '' : 'kindDetails', $pb.PbFieldType.KE,
        valueOf: ParticipantInfo_KindDetail.valueOf,
        enumValues: ParticipantInfo_KindDetail.values,
        defaultEnumValue: ParticipantInfo_KindDetail.CLOUD_AGENT)
    ..pPM<DataTrackInfo>(19, _omitFieldNames ? '' : 'dataTracks',
        subBuilder: DataTrackInfo.$_createMessage)
    ..aI(20, _omitFieldNames ? '' : 'clientProtocol')
    ..pc<ClientInfo_Capability>(
        21, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.KE,
        valueOf: ClientInfo_Capability.valueOf,
        enumValues: ClientInfo_Capability.values,
        defaultEnumValue: ClientInfo_Capability.CAP_UNUSED)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantInfo copyWith(void Function(ParticipantInfo) updates) =>
      super.copyWith((message) => updates(message as ParticipantInfo))
          as ParticipantInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ParticipantInfo() / ParticipantInfo.new instead')
  static ParticipantInfo create() => ParticipantInfo._();
  static $pb.GeneratedMessage $_createMessage() => ParticipantInfo._();
  @$core.override
  ParticipantInfo createEmptyInstance() => ParticipantInfo._();
  @$core.pragma('dart2js:noInline')
  static ParticipantInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ParticipantInfo>(
          ParticipantInfo.$_createMessage);
  static ParticipantInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sid => $_getSZ(0);
  @$pb.TagNumber(1)
  set sid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSid() => $_has(0);
  @$pb.TagNumber(1)
  void clearSid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get identity => $_getSZ(1);
  @$pb.TagNumber(2)
  set identity($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIdentity() => $_has(1);
  @$pb.TagNumber(2)
  void clearIdentity() => $_clearField(2);

  @$pb.TagNumber(3)
  ParticipantInfo_State get state => $_getN(2);
  @$pb.TagNumber(3)
  set state(ParticipantInfo_State value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<TrackInfo> get tracks => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get metadata => $_getSZ(4);
  @$pb.TagNumber(5)
  set metadata($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMetadata() => $_has(4);
  @$pb.TagNumber(5)
  void clearMetadata() => $_clearField(5);

  /// timestamp when participant joined room, in seconds
  @$pb.TagNumber(6)
  $fixnum.Int64 get joinedAt => $_getI64(5);
  @$pb.TagNumber(6)
  set joinedAt($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasJoinedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearJoinedAt() => $_clearField(6);

  @$pb.TagNumber(9)
  $core.String get name => $_getSZ(6);
  @$pb.TagNumber(9)
  set name($core.String value) => $_setString(6, value);
  @$pb.TagNumber(9)
  $core.bool hasName() => $_has(6);
  @$pb.TagNumber(9)
  void clearName() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get version => $_getIZ(7);
  @$pb.TagNumber(10)
  set version($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(10)
  $core.bool hasVersion() => $_has(7);
  @$pb.TagNumber(10)
  void clearVersion() => $_clearField(10);

  @$pb.TagNumber(11)
  ParticipantPermission get permission => $_getN(8);
  @$pb.TagNumber(11)
  set permission(ParticipantPermission value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPermission() => $_has(8);
  @$pb.TagNumber(11)
  void clearPermission() => $_clearField(11);
  @$pb.TagNumber(11)
  ParticipantPermission ensurePermission() => $_ensure(8);

  @$pb.TagNumber(12)
  $core.String get region => $_getSZ(9);
  @$pb.TagNumber(12)
  set region($core.String value) => $_setString(9, value);
  @$pb.TagNumber(12)
  $core.bool hasRegion() => $_has(9);
  @$pb.TagNumber(12)
  void clearRegion() => $_clearField(12);

  /// indicates the participant has an active publisher connection
  /// and can publish to the server
  @$pb.TagNumber(13)
  $core.bool get isPublisher => $_getBF(10);
  @$pb.TagNumber(13)
  set isPublisher($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(13)
  $core.bool hasIsPublisher() => $_has(10);
  @$pb.TagNumber(13)
  void clearIsPublisher() => $_clearField(13);

  @$pb.TagNumber(14)
  ParticipantInfo_Kind get kind => $_getN(11);
  @$pb.TagNumber(14)
  set kind(ParticipantInfo_Kind value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasKind() => $_has(11);
  @$pb.TagNumber(14)
  void clearKind() => $_clearField(14);

  @$pb.TagNumber(15)
  $pb.PbMap<$core.String, $core.String> get attributes => $_getMap(12);

  @$pb.TagNumber(16)
  DisconnectReason get disconnectReason => $_getN(13);
  @$pb.TagNumber(16)
  set disconnectReason(DisconnectReason value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasDisconnectReason() => $_has(13);
  @$pb.TagNumber(16)
  void clearDisconnectReason() => $_clearField(16);

  /// timestamp when participant joined room, in milliseconds
  @$pb.TagNumber(17)
  $fixnum.Int64 get joinedAtMs => $_getI64(14);
  @$pb.TagNumber(17)
  set joinedAtMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(17)
  $core.bool hasJoinedAtMs() => $_has(14);
  @$pb.TagNumber(17)
  void clearJoinedAtMs() => $_clearField(17);

  @$pb.TagNumber(18)
  $pb.PbList<ParticipantInfo_KindDetail> get kindDetails => $_getList(15);

  @$pb.TagNumber(19)
  $pb.PbList<DataTrackInfo> get dataTracks => $_getList(16);

  /// protocol version used for client feature compatibility
  @$pb.TagNumber(20)
  $core.int get clientProtocol => $_getIZ(17);
  @$pb.TagNumber(20)
  set clientProtocol($core.int value) => $_setSignedInt32(17, value);
  @$pb.TagNumber(20)
  $core.bool hasClientProtocol() => $_has(17);
  @$pb.TagNumber(20)
  void clearClientProtocol() => $_clearField(20);

  /// capabilities the participant's client advertises, mirrored from ClientInfo.
  /// Lets other participants perform client-side feature detection.
  @$pb.TagNumber(21)
  $pb.PbList<ClientInfo_Capability> get capabilities => $_getList(18);
}

class Encryption extends $pb.GeneratedMessage {
  factory Encryption() => Encryption._();

  Encryption._();

  factory Encryption.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Encryption()..mergeFromBuffer(data, registry);
  factory Encryption.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Encryption()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Encryption',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: Encryption.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Encryption clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Encryption copyWith(void Function(Encryption) updates) =>
      super.copyWith((message) => updates(message as Encryption)) as Encryption;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Encryption() / Encryption.new instead')
  static Encryption create() => Encryption._();
  static $pb.GeneratedMessage $_createMessage() => Encryption._();
  @$core.override
  Encryption createEmptyInstance() => Encryption._();
  @$core.pragma('dart2js:noInline')
  static Encryption getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Encryption>(Encryption.$_createMessage);
  static Encryption? _defaultInstance;
}

class SimulcastCodecInfo extends $pb.GeneratedMessage {
  factory SimulcastCodecInfo({
    $core.String? mimeType,
    $core.String? mid,
    $core.String? cid,
    $core.Iterable<VideoLayer>? layers,
    VideoLayer_Mode? videoLayerMode,
    $core.String? sdpCid,
  }) {
    final result = SimulcastCodecInfo._();
    if (mimeType != null) result.mimeType = mimeType;
    if (mid != null) result.mid = mid;
    if (cid != null) result.cid = cid;
    if (layers != null) result.layers.addAll(layers);
    if (videoLayerMode != null) result.videoLayerMode = videoLayerMode;
    if (sdpCid != null) result.sdpCid = sdpCid;
    return result;
  }

  SimulcastCodecInfo._();

  factory SimulcastCodecInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SimulcastCodecInfo()..mergeFromBuffer(data, registry);
  factory SimulcastCodecInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SimulcastCodecInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SimulcastCodecInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: SimulcastCodecInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mimeType')
    ..aOS(2, _omitFieldNames ? '' : 'mid')
    ..aOS(3, _omitFieldNames ? '' : 'cid')
    ..pPM<VideoLayer>(4, _omitFieldNames ? '' : 'layers',
        subBuilder: VideoLayer.$_createMessage)
    ..aE<VideoLayer_Mode>(5, _omitFieldNames ? '' : 'videoLayerMode',
        enumValues: VideoLayer_Mode.values)
    ..aOS(6, _omitFieldNames ? '' : 'sdpCid')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimulcastCodecInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SimulcastCodecInfo copyWith(void Function(SimulcastCodecInfo) updates) =>
      super.copyWith((message) => updates(message as SimulcastCodecInfo))
          as SimulcastCodecInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SimulcastCodecInfo() / SimulcastCodecInfo.new instead')
  static SimulcastCodecInfo create() => SimulcastCodecInfo._();
  static $pb.GeneratedMessage $_createMessage() => SimulcastCodecInfo._();
  @$core.override
  SimulcastCodecInfo createEmptyInstance() => SimulcastCodecInfo._();
  @$core.pragma('dart2js:noInline')
  static SimulcastCodecInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SimulcastCodecInfo>(
          SimulcastCodecInfo.$_createMessage);
  static SimulcastCodecInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mimeType => $_getSZ(0);
  @$pb.TagNumber(1)
  set mimeType($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMimeType() => $_has(0);
  @$pb.TagNumber(1)
  void clearMimeType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mid => $_getSZ(1);
  @$pb.TagNumber(2)
  set mid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMid() => $_has(1);
  @$pb.TagNumber(2)
  void clearMid() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get cid => $_getSZ(2);
  @$pb.TagNumber(3)
  set cid($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCid() => $_has(2);
  @$pb.TagNumber(3)
  void clearCid() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<VideoLayer> get layers => $_getList(3);

  @$pb.TagNumber(5)
  VideoLayer_Mode get videoLayerMode => $_getN(4);
  @$pb.TagNumber(5)
  set videoLayerMode(VideoLayer_Mode value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasVideoLayerMode() => $_has(4);
  @$pb.TagNumber(5)
  void clearVideoLayerMode() => $_clearField(5);

  /// cid (client side id for track) could be different between
  /// signalling (AddTrackRequest) and SDP offer. This field
  /// will be populated only if it is different to avoid
  /// duplication and keep the representation concise.
  @$pb.TagNumber(6)
  $core.String get sdpCid => $_getSZ(5);
  @$pb.TagNumber(6)
  set sdpCid($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSdpCid() => $_has(5);
  @$pb.TagNumber(6)
  void clearSdpCid() => $_clearField(6);
}

class TrackInfo extends $pb.GeneratedMessage {
  factory TrackInfo({
    $core.String? sid,
    TrackType? type,
    $core.String? name,
    $core.bool? muted,
    $core.int? width,
    $core.int? height,
    @$core.Deprecated('This field is deprecated.') $core.bool? simulcast,
    @$core.Deprecated('This field is deprecated.') $core.bool? disableDtx,
    TrackSource? source,
    @$core.Deprecated('This field is deprecated.')
    $core.Iterable<VideoLayer>? layers,
    $core.String? mimeType,
    $core.String? mid,
    $core.Iterable<SimulcastCodecInfo>? codecs,
    @$core.Deprecated('This field is deprecated.') $core.bool? stereo,
    $core.bool? disableRed,
    Encryption_Type? encryption,
    $core.String? stream,
    TimedVersion? version,
    $core.Iterable<AudioTrackFeature>? audioFeatures,
    BackupCodecPolicy? backupCodecPolicy,
    $core.Iterable<PacketTrailerFeature>? packetTrailerFeatures,
  }) {
    final result = TrackInfo._();
    if (sid != null) result.sid = sid;
    if (type != null) result.type = type;
    if (name != null) result.name = name;
    if (muted != null) result.muted = muted;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (simulcast != null) result.simulcast = simulcast;
    if (disableDtx != null) result.disableDtx = disableDtx;
    if (source != null) result.source = source;
    if (layers != null) result.layers.addAll(layers);
    if (mimeType != null) result.mimeType = mimeType;
    if (mid != null) result.mid = mid;
    if (codecs != null) result.codecs.addAll(codecs);
    if (stereo != null) result.stereo = stereo;
    if (disableRed != null) result.disableRed = disableRed;
    if (encryption != null) result.encryption = encryption;
    if (stream != null) result.stream = stream;
    if (version != null) result.version = version;
    if (audioFeatures != null) result.audioFeatures.addAll(audioFeatures);
    if (backupCodecPolicy != null) result.backupCodecPolicy = backupCodecPolicy;
    if (packetTrailerFeatures != null)
      result.packetTrailerFeatures.addAll(packetTrailerFeatures);
    return result;
  }

  TrackInfo._();

  factory TrackInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackInfo()..mergeFromBuffer(data, registry);
  factory TrackInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TrackInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: TrackInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sid')
    ..aE<TrackType>(2, _omitFieldNames ? '' : 'type',
        enumValues: TrackType.values)
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aOB(4, _omitFieldNames ? '' : 'muted')
    ..aI(5, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aOB(7, _omitFieldNames ? '' : 'simulcast')
    ..aOB(8, _omitFieldNames ? '' : 'disableDtx')
    ..aE<TrackSource>(9, _omitFieldNames ? '' : 'source',
        enumValues: TrackSource.values)
    ..pPM<VideoLayer>(10, _omitFieldNames ? '' : 'layers',
        subBuilder: VideoLayer.$_createMessage)
    ..aOS(11, _omitFieldNames ? '' : 'mimeType')
    ..aOS(12, _omitFieldNames ? '' : 'mid')
    ..pPM<SimulcastCodecInfo>(13, _omitFieldNames ? '' : 'codecs',
        subBuilder: SimulcastCodecInfo.$_createMessage)
    ..aOB(14, _omitFieldNames ? '' : 'stereo')
    ..aOB(15, _omitFieldNames ? '' : 'disableRed')
    ..aE<Encryption_Type>(16, _omitFieldNames ? '' : 'encryption',
        enumValues: Encryption_Type.values)
    ..aOS(17, _omitFieldNames ? '' : 'stream')
    ..aOM<TimedVersion>(18, _omitFieldNames ? '' : 'version',
        subBuilder: TimedVersion.$_createMessage)
    ..pc<AudioTrackFeature>(
        19, _omitFieldNames ? '' : 'audioFeatures', $pb.PbFieldType.KE,
        valueOf: AudioTrackFeature.valueOf,
        enumValues: AudioTrackFeature.values,
        defaultEnumValue: AudioTrackFeature.TF_STEREO)
    ..aE<BackupCodecPolicy>(20, _omitFieldNames ? '' : 'backupCodecPolicy',
        enumValues: BackupCodecPolicy.values)
    ..pc<PacketTrailerFeature>(
        21, _omitFieldNames ? '' : 'packetTrailerFeatures', $pb.PbFieldType.KE,
        valueOf: PacketTrailerFeature.valueOf,
        enumValues: PacketTrailerFeature.values,
        defaultEnumValue: PacketTrailerFeature.PTF_USER_TIMESTAMP)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackInfo copyWith(void Function(TrackInfo) updates) =>
      super.copyWith((message) => updates(message as TrackInfo)) as TrackInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TrackInfo() / TrackInfo.new instead')
  static TrackInfo create() => TrackInfo._();
  static $pb.GeneratedMessage $_createMessage() => TrackInfo._();
  @$core.override
  TrackInfo createEmptyInstance() => TrackInfo._();
  @$core.pragma('dart2js:noInline')
  static TrackInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TrackInfo>(TrackInfo.$_createMessage);
  static TrackInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sid => $_getSZ(0);
  @$pb.TagNumber(1)
  set sid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSid() => $_has(0);
  @$pb.TagNumber(1)
  void clearSid() => $_clearField(1);

  @$pb.TagNumber(2)
  TrackType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(TrackType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get muted => $_getBF(3);
  @$pb.TagNumber(4)
  set muted($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMuted() => $_has(3);
  @$pb.TagNumber(4)
  void clearMuted() => $_clearField(4);

  /// original width of video (unset for audio)
  /// clients may receive a lower resolution version with simulcast
  @$pb.TagNumber(5)
  $core.int get width => $_getIZ(4);
  @$pb.TagNumber(5)
  set width($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearWidth() => $_clearField(5);

  /// original height of video (unset for audio)
  @$pb.TagNumber(6)
  $core.int get height => $_getIZ(5);
  @$pb.TagNumber(6)
  set height($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeight() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeight() => $_clearField(6);

  /// true if track is simulcasted
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  $core.bool get simulcast => $_getBF(6);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  set simulcast($core.bool value) => $_setBool(6, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  $core.bool hasSimulcast() => $_has(6);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  void clearSimulcast() => $_clearField(7);

  /// true if DTX (Discontinuous Transmission) is disabled for audio
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  $core.bool get disableDtx => $_getBF(7);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  set disableDtx($core.bool value) => $_setBool(7, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  $core.bool hasDisableDtx() => $_has(7);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(8)
  void clearDisableDtx() => $_clearField(8);

  /// source of media
  @$pb.TagNumber(9)
  TrackSource get source => $_getN(8);
  @$pb.TagNumber(9)
  set source(TrackSource value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasSource() => $_has(8);
  @$pb.TagNumber(9)
  void clearSource() => $_clearField(9);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(10)
  $pb.PbList<VideoLayer> get layers => $_getList(9);

  /// mime type of codec
  @$pb.TagNumber(11)
  $core.String get mimeType => $_getSZ(10);
  @$pb.TagNumber(11)
  set mimeType($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasMimeType() => $_has(10);
  @$pb.TagNumber(11)
  void clearMimeType() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get mid => $_getSZ(11);
  @$pb.TagNumber(12)
  set mid($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMid() => $_has(11);
  @$pb.TagNumber(12)
  void clearMid() => $_clearField(12);

  @$pb.TagNumber(13)
  $pb.PbList<SimulcastCodecInfo> get codecs => $_getList(12);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(14)
  $core.bool get stereo => $_getBF(13);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(14)
  set stereo($core.bool value) => $_setBool(13, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(14)
  $core.bool hasStereo() => $_has(13);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(14)
  void clearStereo() => $_clearField(14);

  /// true if RED (Redundant Encoding) is disabled for audio
  @$pb.TagNumber(15)
  $core.bool get disableRed => $_getBF(14);
  @$pb.TagNumber(15)
  set disableRed($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasDisableRed() => $_has(14);
  @$pb.TagNumber(15)
  void clearDisableRed() => $_clearField(15);

  @$pb.TagNumber(16)
  Encryption_Type get encryption => $_getN(15);
  @$pb.TagNumber(16)
  set encryption(Encryption_Type value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasEncryption() => $_has(15);
  @$pb.TagNumber(16)
  void clearEncryption() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.String get stream => $_getSZ(16);
  @$pb.TagNumber(17)
  set stream($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasStream() => $_has(16);
  @$pb.TagNumber(17)
  void clearStream() => $_clearField(17);

  @$pb.TagNumber(18)
  TimedVersion get version => $_getN(17);
  @$pb.TagNumber(18)
  set version(TimedVersion value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasVersion() => $_has(17);
  @$pb.TagNumber(18)
  void clearVersion() => $_clearField(18);
  @$pb.TagNumber(18)
  TimedVersion ensureVersion() => $_ensure(17);

  @$pb.TagNumber(19)
  $pb.PbList<AudioTrackFeature> get audioFeatures => $_getList(18);

  @$pb.TagNumber(20)
  BackupCodecPolicy get backupCodecPolicy => $_getN(19);
  @$pb.TagNumber(20)
  set backupCodecPolicy(BackupCodecPolicy value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasBackupCodecPolicy() => $_has(19);
  @$pb.TagNumber(20)
  void clearBackupCodecPolicy() => $_clearField(20);

  @$pb.TagNumber(21)
  $pb.PbList<PacketTrailerFeature> get packetTrailerFeatures => $_getList(20);
}

class DataTrackInfo extends $pb.GeneratedMessage {
  factory DataTrackInfo({
    $core.int? pubHandle,
    $core.String? sid,
    $core.String? name,
    Encryption_Type? encryption,
    DataTrackFrameEncoding? frameEncoding,
    DataTrackSchemaId? schema,
  }) {
    final result = DataTrackInfo._();
    if (pubHandle != null) result.pubHandle = pubHandle;
    if (sid != null) result.sid = sid;
    if (name != null) result.name = name;
    if (encryption != null) result.encryption = encryption;
    if (frameEncoding != null) result.frameEncoding = frameEncoding;
    if (schema != null) result.schema = schema;
    return result;
  }

  DataTrackInfo._();

  factory DataTrackInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackInfo()..mergeFromBuffer(data, registry);
  factory DataTrackInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackInfo.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'pubHandle', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'sid')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aE<Encryption_Type>(4, _omitFieldNames ? '' : 'encryption',
        enumValues: Encryption_Type.values)
    ..aOM<DataTrackFrameEncoding>(5, _omitFieldNames ? '' : 'frameEncoding',
        subBuilder: DataTrackFrameEncoding.$_createMessage)
    ..aOM<DataTrackSchemaId>(6, _omitFieldNames ? '' : 'schema',
        subBuilder: DataTrackSchemaId.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackInfo copyWith(void Function(DataTrackInfo) updates) =>
      super.copyWith((message) => updates(message as DataTrackInfo))
          as DataTrackInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataTrackInfo() / DataTrackInfo.new instead')
  static DataTrackInfo create() => DataTrackInfo._();
  static $pb.GeneratedMessage $_createMessage() => DataTrackInfo._();
  @$core.override
  DataTrackInfo createEmptyInstance() => DataTrackInfo._();
  @$core.pragma('dart2js:noInline')
  static DataTrackInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataTrackInfo>(
          DataTrackInfo.$_createMessage);
  static DataTrackInfo? _defaultInstance;

  /// Client-assigned, 16-bit identifier that will be attached to packets sent by the publisher.
  @$pb.TagNumber(1)
  $core.int get pubHandle => $_getIZ(0);
  @$pb.TagNumber(1)
  set pubHandle($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPubHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearPubHandle() => $_clearField(1);

  /// Server-assigned track identifier.
  @$pb.TagNumber(2)
  $core.String get sid => $_getSZ(1);
  @$pb.TagNumber(2)
  set sid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSid() => $_has(1);
  @$pb.TagNumber(2)
  void clearSid() => $_clearField(2);

  /// Human-readable identifier (e.g., `geoLocation`, `servoPosition.x`, etc.), unique per publisher.
  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  /// Method used for end-to-end encryption (E2EE) on packet payloads.
  @$pb.TagNumber(4)
  Encryption_Type get encryption => $_getN(3);
  @$pb.TagNumber(4)
  set encryption(Encryption_Type value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEncryption() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncryption() => $_clearField(4);

  /// Encoding for frame payloads on this track. If unspecified, the track is untyped.
  @$pb.TagNumber(5)
  DataTrackFrameEncoding get frameEncoding => $_getN(4);
  @$pb.TagNumber(5)
  set frameEncoding(DataTrackFrameEncoding value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasFrameEncoding() => $_has(4);
  @$pb.TagNumber(5)
  void clearFrameEncoding() => $_clearField(5);
  @$pb.TagNumber(5)
  DataTrackFrameEncoding ensureFrameEncoding() => $_ensure(4);

  /// ID of the schema used by frames on this track if the track is typed.
  @$pb.TagNumber(6)
  DataTrackSchemaId get schema => $_getN(5);
  @$pb.TagNumber(6)
  set schema(DataTrackSchemaId value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSchema() => $_has(5);
  @$pb.TagNumber(6)
  void clearSchema() => $_clearField(6);
  @$pb.TagNumber(6)
  DataTrackSchemaId ensureSchema() => $_ensure(5);
}

enum DataTrackFrameEncoding_Value { wellKnown, custom, notSet }

/// Encoding for frame payloads.
class DataTrackFrameEncoding extends $pb.GeneratedMessage {
  factory DataTrackFrameEncoding({
    DataTrackFrameEncoding_WellKnownFrameEncoding? wellKnown,
    $core.String? custom,
  }) {
    final result = DataTrackFrameEncoding._();
    if (wellKnown != null) result.wellKnown = wellKnown;
    if (custom != null) result.custom = custom;
    return result;
  }

  DataTrackFrameEncoding._();

  factory DataTrackFrameEncoding.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackFrameEncoding()..mergeFromBuffer(data, registry);
  factory DataTrackFrameEncoding.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackFrameEncoding()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DataTrackFrameEncoding_Value>
      _DataTrackFrameEncoding_ValueByTag = {
    1: DataTrackFrameEncoding_Value.wellKnown,
    2: DataTrackFrameEncoding_Value.custom,
    0: DataTrackFrameEncoding_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackFrameEncoding',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackFrameEncoding.$_createMessage)
    ..oo(0, [1, 2])
    ..aE<DataTrackFrameEncoding_WellKnownFrameEncoding>(
        1, _omitFieldNames ? '' : 'wellKnown',
        enumValues: DataTrackFrameEncoding_WellKnownFrameEncoding.values)
    ..aOS(2, _omitFieldNames ? '' : 'custom')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackFrameEncoding clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackFrameEncoding copyWith(
          void Function(DataTrackFrameEncoding) updates) =>
      super.copyWith((message) => updates(message as DataTrackFrameEncoding))
          as DataTrackFrameEncoding;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataTrackFrameEncoding() / DataTrackFrameEncoding.new instead')
  static DataTrackFrameEncoding create() => DataTrackFrameEncoding._();
  static $pb.GeneratedMessage $_createMessage() => DataTrackFrameEncoding._();
  @$core.override
  DataTrackFrameEncoding createEmptyInstance() => DataTrackFrameEncoding._();
  @$core.pragma('dart2js:noInline')
  static DataTrackFrameEncoding getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataTrackFrameEncoding>(
          DataTrackFrameEncoding.$_createMessage);
  static DataTrackFrameEncoding? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  DataTrackFrameEncoding_Value whichValue() =>
      _DataTrackFrameEncoding_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearValue() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  DataTrackFrameEncoding_WellKnownFrameEncoding get wellKnown => $_getN(0);
  @$pb.TagNumber(1)
  set wellKnown(DataTrackFrameEncoding_WellKnownFrameEncoding value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWellKnown() => $_has(0);
  @$pb.TagNumber(1)
  void clearWellKnown() => $_clearField(1);

  /// Identifier of a custom encoding not covered by the well-known cases.
  /// This must be non-empty and no longer than 32 characters.
  @$pb.TagNumber(2)
  $core.String get custom => $_getSZ(1);
  @$pb.TagNumber(2)
  set custom($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCustom() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustom() => $_clearField(2);
}

enum DataTrackSchemaEncoding_Value { wellKnown, custom, notSet }

/// Encoding for schema definition.
class DataTrackSchemaEncoding extends $pb.GeneratedMessage {
  factory DataTrackSchemaEncoding({
    DataTrackSchemaEncoding_WellKnownSchemaEncoding? wellKnown,
    $core.String? custom,
  }) {
    final result = DataTrackSchemaEncoding._();
    if (wellKnown != null) result.wellKnown = wellKnown;
    if (custom != null) result.custom = custom;
    return result;
  }

  DataTrackSchemaEncoding._();

  factory DataTrackSchemaEncoding.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSchemaEncoding()..mergeFromBuffer(data, registry);
  factory DataTrackSchemaEncoding.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSchemaEncoding()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DataTrackSchemaEncoding_Value>
      _DataTrackSchemaEncoding_ValueByTag = {
    1: DataTrackSchemaEncoding_Value.wellKnown,
    2: DataTrackSchemaEncoding_Value.custom,
    0: DataTrackSchemaEncoding_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackSchemaEncoding',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackSchemaEncoding.$_createMessage)
    ..oo(0, [1, 2])
    ..aE<DataTrackSchemaEncoding_WellKnownSchemaEncoding>(
        1, _omitFieldNames ? '' : 'wellKnown',
        enumValues: DataTrackSchemaEncoding_WellKnownSchemaEncoding.values)
    ..aOS(2, _omitFieldNames ? '' : 'custom')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSchemaEncoding clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSchemaEncoding copyWith(
          void Function(DataTrackSchemaEncoding) updates) =>
      super.copyWith((message) => updates(message as DataTrackSchemaEncoding))
          as DataTrackSchemaEncoding;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataTrackSchemaEncoding() / DataTrackSchemaEncoding.new instead')
  static DataTrackSchemaEncoding create() => DataTrackSchemaEncoding._();
  static $pb.GeneratedMessage $_createMessage() => DataTrackSchemaEncoding._();
  @$core.override
  DataTrackSchemaEncoding createEmptyInstance() => DataTrackSchemaEncoding._();
  @$core.pragma('dart2js:noInline')
  static DataTrackSchemaEncoding getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataTrackSchemaEncoding>(
          DataTrackSchemaEncoding.$_createMessage);
  static DataTrackSchemaEncoding? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  DataTrackSchemaEncoding_Value whichValue() =>
      _DataTrackSchemaEncoding_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearValue() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  DataTrackSchemaEncoding_WellKnownSchemaEncoding get wellKnown => $_getN(0);
  @$pb.TagNumber(1)
  set wellKnown(DataTrackSchemaEncoding_WellKnownSchemaEncoding value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasWellKnown() => $_has(0);
  @$pb.TagNumber(1)
  void clearWellKnown() => $_clearField(1);

  /// Identifier of a custom encoding not covered by the well-known cases.
  /// This must be non-empty and no longer than 32 characters.
  @$pb.TagNumber(2)
  $core.String get custom => $_getSZ(1);
  @$pb.TagNumber(2)
  set custom($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCustom() => $_has(1);
  @$pb.TagNumber(2)
  void clearCustom() => $_clearField(2);
}

/// Identifier for a data track schema.
///
/// Schemas with the same name but different encodings are distinct.
class DataTrackSchemaId extends $pb.GeneratedMessage {
  factory DataTrackSchemaId({
    $core.String? name,
    DataTrackSchemaEncoding? encoding,
  }) {
    final result = DataTrackSchemaId._();
    if (name != null) result.name = name;
    if (encoding != null) result.encoding = encoding;
    return result;
  }

  DataTrackSchemaId._();

  factory DataTrackSchemaId.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSchemaId()..mergeFromBuffer(data, registry);
  factory DataTrackSchemaId.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSchemaId()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackSchemaId',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackSchemaId.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<DataTrackSchemaEncoding>(2, _omitFieldNames ? '' : 'encoding',
        subBuilder: DataTrackSchemaEncoding.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSchemaId clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSchemaId copyWith(void Function(DataTrackSchemaId) updates) =>
      super.copyWith((message) => updates(message as DataTrackSchemaId))
          as DataTrackSchemaId;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataTrackSchemaId() / DataTrackSchemaId.new instead')
  static DataTrackSchemaId create() => DataTrackSchemaId._();
  static $pb.GeneratedMessage $_createMessage() => DataTrackSchemaId._();
  @$core.override
  DataTrackSchemaId createEmptyInstance() => DataTrackSchemaId._();
  @$core.pragma('dart2js:noInline')
  static DataTrackSchemaId getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataTrackSchemaId>(
          DataTrackSchemaId.$_createMessage);
  static DataTrackSchemaId? _defaultInstance;

  /// This must be non-empty and no longer than 256 characters.
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  DataTrackSchemaEncoding get encoding => $_getN(1);
  @$pb.TagNumber(2)
  set encoding(DataTrackSchemaEncoding value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEncoding() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncoding() => $_clearField(2);
  @$pb.TagNumber(2)
  DataTrackSchemaEncoding ensureEncoding() => $_ensure(1);
}

class DataTrackExtensionParticipantSid extends $pb.GeneratedMessage {
  factory DataTrackExtensionParticipantSid({
    DataTrackExtensionID? id,
    $core.String? participantSid,
  }) {
    final result = DataTrackExtensionParticipantSid._();
    if (id != null) result.id = id;
    if (participantSid != null) result.participantSid = participantSid;
    return result;
  }

  DataTrackExtensionParticipantSid._();

  factory DataTrackExtensionParticipantSid.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackExtensionParticipantSid()..mergeFromBuffer(data, registry);
  factory DataTrackExtensionParticipantSid.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackExtensionParticipantSid()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackExtensionParticipantSid',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackExtensionParticipantSid.$_createMessage)
    ..aE<DataTrackExtensionID>(1, _omitFieldNames ? '' : 'id',
        enumValues: DataTrackExtensionID.values)
    ..aOS(2, _omitFieldNames ? '' : 'participantSid')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackExtensionParticipantSid clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackExtensionParticipantSid copyWith(
          void Function(DataTrackExtensionParticipantSid) updates) =>
      super.copyWith(
              (message) => updates(message as DataTrackExtensionParticipantSid))
          as DataTrackExtensionParticipantSid;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataTrackExtensionParticipantSid() / DataTrackExtensionParticipantSid.new instead')
  static DataTrackExtensionParticipantSid create() =>
      DataTrackExtensionParticipantSid._();
  static $pb.GeneratedMessage $_createMessage() =>
      DataTrackExtensionParticipantSid._();
  @$core.override
  DataTrackExtensionParticipantSid createEmptyInstance() =>
      DataTrackExtensionParticipantSid._();
  @$core.pragma('dart2js:noInline')
  static DataTrackExtensionParticipantSid getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataTrackExtensionParticipantSid>(
          DataTrackExtensionParticipantSid.$_createMessage);
  static DataTrackExtensionParticipantSid? _defaultInstance;

  @$pb.TagNumber(1)
  DataTrackExtensionID get id => $_getN(0);
  @$pb.TagNumber(1)
  set id(DataTrackExtensionID value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get participantSid => $_getSZ(1);
  @$pb.TagNumber(2)
  set participantSid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParticipantSid() => $_has(1);
  @$pb.TagNumber(2)
  void clearParticipantSid() => $_clearField(2);
}

class DataTrackSubscriptionOptions extends $pb.GeneratedMessage {
  factory DataTrackSubscriptionOptions({
    $core.int? targetFps,
  }) {
    final result = DataTrackSubscriptionOptions._();
    if (targetFps != null) result.targetFps = targetFps;
    return result;
  }

  DataTrackSubscriptionOptions._();

  factory DataTrackSubscriptionOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSubscriptionOptions()..mergeFromBuffer(data, registry);
  factory DataTrackSubscriptionOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataTrackSubscriptionOptions()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataTrackSubscriptionOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataTrackSubscriptionOptions.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'targetFps', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSubscriptionOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataTrackSubscriptionOptions copyWith(
          void Function(DataTrackSubscriptionOptions) updates) =>
      super.copyWith(
              (message) => updates(message as DataTrackSubscriptionOptions))
          as DataTrackSubscriptionOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataTrackSubscriptionOptions() / DataTrackSubscriptionOptions.new instead')
  static DataTrackSubscriptionOptions create() =>
      DataTrackSubscriptionOptions._();
  static $pb.GeneratedMessage $_createMessage() =>
      DataTrackSubscriptionOptions._();
  @$core.override
  DataTrackSubscriptionOptions createEmptyInstance() =>
      DataTrackSubscriptionOptions._();
  @$core.pragma('dart2js:noInline')
  static DataTrackSubscriptionOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataTrackSubscriptionOptions>(
          DataTrackSubscriptionOptions.$_createMessage);
  static DataTrackSubscriptionOptions? _defaultInstance;

  /// Rate in frames per second (FPS) the subscriber wants to receive frames at.
  /// If omitted, the subscriber defaults to the publisher's fps
  @$pb.TagNumber(1)
  $core.int get targetFps => $_getIZ(0);
  @$pb.TagNumber(1)
  set targetFps($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTargetFps() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetFps() => $_clearField(1);
}

enum DataBlobKey_Key { generic, schemaId, notSet }

/// Key used to uniquely identify a data blob for storage and retrieval.
class DataBlobKey extends $pb.GeneratedMessage {
  factory DataBlobKey({
    $core.String? generic,
    DataTrackSchemaId? schemaId,
  }) {
    final result = DataBlobKey._();
    if (generic != null) result.generic = generic;
    if (schemaId != null) result.schemaId = schemaId;
    return result;
  }

  DataBlobKey._();

  factory DataBlobKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataBlobKey()..mergeFromBuffer(data, registry);
  factory DataBlobKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataBlobKey()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DataBlobKey_Key> _DataBlobKey_KeyByTag = {
    1: DataBlobKey_Key.generic,
    2: DataBlobKey_Key.schemaId,
    0: DataBlobKey_Key.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataBlobKey',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataBlobKey.$_createMessage)
    ..oo(0, [1, 2])
    ..aOS(1, _omitFieldNames ? '' : 'generic')
    ..aOM<DataTrackSchemaId>(2, _omitFieldNames ? '' : 'schemaId',
        subBuilder: DataTrackSchemaId.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataBlobKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataBlobKey copyWith(void Function(DataBlobKey) updates) =>
      super.copyWith((message) => updates(message as DataBlobKey))
          as DataBlobKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataBlobKey() / DataBlobKey.new instead')
  static DataBlobKey create() => DataBlobKey._();
  static $pb.GeneratedMessage $_createMessage() => DataBlobKey._();
  @$core.override
  DataBlobKey createEmptyInstance() => DataBlobKey._();
  @$core.pragma('dart2js:noInline')
  static DataBlobKey getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataBlobKey>(
          DataBlobKey.$_createMessage);
  static DataBlobKey? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  DataBlobKey_Key whichKey() => _DataBlobKey_KeyByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  void clearKey() => $_clearField($_whichOneof(0));

  /// Generic string key, blob contains arbitrary data.
  @$pb.TagNumber(1)
  $core.String get generic => $_getSZ(0);
  @$pb.TagNumber(1)
  set generic($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGeneric() => $_has(0);
  @$pb.TagNumber(1)
  void clearGeneric() => $_clearField(1);

  /// Data track schema identifier, blob contains schema definition.
  @$pb.TagNumber(2)
  DataTrackSchemaId get schemaId => $_getN(1);
  @$pb.TagNumber(2)
  set schemaId(DataTrackSchemaId value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSchemaId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSchemaId() => $_clearField(2);
  @$pb.TagNumber(2)
  DataTrackSchemaId ensureSchemaId() => $_ensure(1);
}

/// A blob of data stored in a room identified by a unique key.
class DataBlob extends $pb.GeneratedMessage {
  factory DataBlob({
    DataBlobKey? key,
    $core.List<$core.int>? contents,
  }) {
    final result = DataBlob._();
    if (key != null) result.key = key;
    if (contents != null) result.contents = contents;
    return result;
  }

  DataBlob._();

  factory DataBlob.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataBlob()..mergeFromBuffer(data, registry);
  factory DataBlob.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataBlob()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataBlob',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataBlob.$_createMessage)
    ..aOM<DataBlobKey>(1, _omitFieldNames ? '' : 'key',
        subBuilder: DataBlobKey.$_createMessage)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'contents', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataBlob clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataBlob copyWith(void Function(DataBlob) updates) =>
      super.copyWith((message) => updates(message as DataBlob)) as DataBlob;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataBlob() / DataBlob.new instead')
  static DataBlob create() => DataBlob._();
  static $pb.GeneratedMessage $_createMessage() => DataBlob._();
  @$core.override
  DataBlob createEmptyInstance() => DataBlob._();
  @$core.pragma('dart2js:noInline')
  static DataBlob getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataBlob>(DataBlob.$_createMessage);
  static DataBlob? _defaultInstance;

  /// Unique key the data blob is identified by.
  @$pb.TagNumber(1)
  DataBlobKey get key => $_getN(0);
  @$pb.TagNumber(1)
  set key(DataBlobKey value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);
  @$pb.TagNumber(1)
  DataBlobKey ensureKey() => $_ensure(0);

  /// Contents of the data blob. This must not exceed 50 KB.
  @$pb.TagNumber(2)
  $core.List<$core.int> get contents => $_getN(1);
  @$pb.TagNumber(2)
  set contents($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContents() => $_has(1);
  @$pb.TagNumber(2)
  void clearContents() => $_clearField(2);
}

/// provide information about available spatial layers
class VideoLayer extends $pb.GeneratedMessage {
  factory VideoLayer({
    VideoQuality? quality,
    $core.int? width,
    $core.int? height,
    $core.int? bitrate,
    $core.int? ssrc,
    $core.int? spatialLayer,
    $core.String? rid,
    $core.int? repairSsrc,
  }) {
    final result = VideoLayer._();
    if (quality != null) result.quality = quality;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (bitrate != null) result.bitrate = bitrate;
    if (ssrc != null) result.ssrc = ssrc;
    if (spatialLayer != null) result.spatialLayer = spatialLayer;
    if (rid != null) result.rid = rid;
    if (repairSsrc != null) result.repairSsrc = repairSsrc;
    return result;
  }

  VideoLayer._();

  factory VideoLayer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VideoLayer()..mergeFromBuffer(data, registry);
  factory VideoLayer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VideoLayer()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VideoLayer',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: VideoLayer.$_createMessage)
    ..aE<VideoQuality>(1, _omitFieldNames ? '' : 'quality',
        enumValues: VideoQuality.values)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'bitrate', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'ssrc', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'spatialLayer')
    ..aOS(7, _omitFieldNames ? '' : 'rid')
    ..aI(8, _omitFieldNames ? '' : 'repairSsrc', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VideoLayer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VideoLayer copyWith(void Function(VideoLayer) updates) =>
      super.copyWith((message) => updates(message as VideoLayer)) as VideoLayer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use VideoLayer() / VideoLayer.new instead')
  static VideoLayer create() => VideoLayer._();
  static $pb.GeneratedMessage $_createMessage() => VideoLayer._();
  @$core.override
  VideoLayer createEmptyInstance() => VideoLayer._();
  @$core.pragma('dart2js:noInline')
  static VideoLayer getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VideoLayer>(VideoLayer.$_createMessage);
  static VideoLayer? _defaultInstance;

  /// for tracks with a single layer, this should be HIGH
  @$pb.TagNumber(1)
  VideoQuality get quality => $_getN(0);
  @$pb.TagNumber(1)
  set quality(VideoQuality value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasQuality() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuality() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => $_clearField(3);

  /// target bitrate in bit per second (bps), server will measure actual
  @$pb.TagNumber(4)
  $core.int get bitrate => $_getIZ(3);
  @$pb.TagNumber(4)
  set bitrate($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBitrate() => $_has(3);
  @$pb.TagNumber(4)
  void clearBitrate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get ssrc => $_getIZ(4);
  @$pb.TagNumber(5)
  set ssrc($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSsrc() => $_has(4);
  @$pb.TagNumber(5)
  void clearSsrc() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get spatialLayer => $_getIZ(5);
  @$pb.TagNumber(6)
  set spatialLayer($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSpatialLayer() => $_has(5);
  @$pb.TagNumber(6)
  void clearSpatialLayer() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get rid => $_getSZ(6);
  @$pb.TagNumber(7)
  set rid($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRid() => $_has(6);
  @$pb.TagNumber(7)
  void clearRid() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get repairSsrc => $_getIZ(7);
  @$pb.TagNumber(8)
  set repairSsrc($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRepairSsrc() => $_has(7);
  @$pb.TagNumber(8)
  void clearRepairSsrc() => $_clearField(8);
}

enum DataPacket_Value {
  user,
  speaker,
  sipDtmf,
  transcription,
  metrics,
  chatMessage,
  rpcRequest,
  rpcAck,
  rpcResponse,
  streamHeader,
  streamChunk,
  streamTrailer,
  encryptedPacket,
  notSet
}

/// new DataPacket API
class DataPacket extends $pb.GeneratedMessage {
  factory DataPacket({
    @$core.Deprecated('This field is deprecated.') DataPacket_Kind? kind,
    UserPacket? user,
    @$core.Deprecated('This field is deprecated.') ActiveSpeakerUpdate? speaker,
    $core.String? participantIdentity,
    $core.Iterable<$core.String>? destinationIdentities,
    SipDTMF? sipDtmf,
    Transcription? transcription,
    $0.MetricsBatch? metrics,
    ChatMessage? chatMessage,
    RpcRequest? rpcRequest,
    RpcAck? rpcAck,
    RpcResponse? rpcResponse,
    DataStream_Header? streamHeader,
    DataStream_Chunk? streamChunk,
    DataStream_Trailer? streamTrailer,
    $core.int? sequence,
    $core.String? participantSid,
    EncryptedPacket? encryptedPacket,
  }) {
    final result = DataPacket._();
    if (kind != null) result.kind = kind;
    if (user != null) result.user = user;
    if (speaker != null) result.speaker = speaker;
    if (participantIdentity != null)
      result.participantIdentity = participantIdentity;
    if (destinationIdentities != null)
      result.destinationIdentities.addAll(destinationIdentities);
    if (sipDtmf != null) result.sipDtmf = sipDtmf;
    if (transcription != null) result.transcription = transcription;
    if (metrics != null) result.metrics = metrics;
    if (chatMessage != null) result.chatMessage = chatMessage;
    if (rpcRequest != null) result.rpcRequest = rpcRequest;
    if (rpcAck != null) result.rpcAck = rpcAck;
    if (rpcResponse != null) result.rpcResponse = rpcResponse;
    if (streamHeader != null) result.streamHeader = streamHeader;
    if (streamChunk != null) result.streamChunk = streamChunk;
    if (streamTrailer != null) result.streamTrailer = streamTrailer;
    if (sequence != null) result.sequence = sequence;
    if (participantSid != null) result.participantSid = participantSid;
    if (encryptedPacket != null) result.encryptedPacket = encryptedPacket;
    return result;
  }

  DataPacket._();

  factory DataPacket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataPacket()..mergeFromBuffer(data, registry);
  factory DataPacket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataPacket()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DataPacket_Value> _DataPacket_ValueByTag = {
    2: DataPacket_Value.user,
    3: DataPacket_Value.speaker,
    6: DataPacket_Value.sipDtmf,
    7: DataPacket_Value.transcription,
    8: DataPacket_Value.metrics,
    9: DataPacket_Value.chatMessage,
    10: DataPacket_Value.rpcRequest,
    11: DataPacket_Value.rpcAck,
    12: DataPacket_Value.rpcResponse,
    13: DataPacket_Value.streamHeader,
    14: DataPacket_Value.streamChunk,
    15: DataPacket_Value.streamTrailer,
    18: DataPacket_Value.encryptedPacket,
    0: DataPacket_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataPacket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataPacket.$_createMessage)
    ..oo(0, [2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18])
    ..aE<DataPacket_Kind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: DataPacket_Kind.values)
    ..aOM<UserPacket>(2, _omitFieldNames ? '' : 'user',
        subBuilder: UserPacket.$_createMessage)
    ..aOM<ActiveSpeakerUpdate>(3, _omitFieldNames ? '' : 'speaker',
        subBuilder: ActiveSpeakerUpdate.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'participantIdentity')
    ..pPS(5, _omitFieldNames ? '' : 'destinationIdentities')
    ..aOM<SipDTMF>(6, _omitFieldNames ? '' : 'sipDtmf',
        subBuilder: SipDTMF.$_createMessage)
    ..aOM<Transcription>(7, _omitFieldNames ? '' : 'transcription',
        subBuilder: Transcription.$_createMessage)
    ..aOM<$0.MetricsBatch>(8, _omitFieldNames ? '' : 'metrics',
        subBuilder: $0.MetricsBatch.$_createMessage)
    ..aOM<ChatMessage>(9, _omitFieldNames ? '' : 'chatMessage',
        subBuilder: ChatMessage.$_createMessage)
    ..aOM<RpcRequest>(10, _omitFieldNames ? '' : 'rpcRequest',
        subBuilder: RpcRequest.$_createMessage)
    ..aOM<RpcAck>(11, _omitFieldNames ? '' : 'rpcAck',
        subBuilder: RpcAck.$_createMessage)
    ..aOM<RpcResponse>(12, _omitFieldNames ? '' : 'rpcResponse',
        subBuilder: RpcResponse.$_createMessage)
    ..aOM<DataStream_Header>(13, _omitFieldNames ? '' : 'streamHeader',
        subBuilder: DataStream_Header.$_createMessage)
    ..aOM<DataStream_Chunk>(14, _omitFieldNames ? '' : 'streamChunk',
        subBuilder: DataStream_Chunk.$_createMessage)
    ..aOM<DataStream_Trailer>(15, _omitFieldNames ? '' : 'streamTrailer',
        subBuilder: DataStream_Trailer.$_createMessage)
    ..aI(16, _omitFieldNames ? '' : 'sequence', fieldType: $pb.PbFieldType.OU3)
    ..aOS(17, _omitFieldNames ? '' : 'participantSid')
    ..aOM<EncryptedPacket>(18, _omitFieldNames ? '' : 'encryptedPacket',
        subBuilder: EncryptedPacket.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataPacket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataPacket copyWith(void Function(DataPacket) updates) =>
      super.copyWith((message) => updates(message as DataPacket)) as DataPacket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataPacket() / DataPacket.new instead')
  static DataPacket create() => DataPacket._();
  static $pb.GeneratedMessage $_createMessage() => DataPacket._();
  @$core.override
  DataPacket createEmptyInstance() => DataPacket._();
  @$core.pragma('dart2js:noInline')
  static DataPacket getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataPacket>(DataPacket.$_createMessage);
  static DataPacket? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(18)
  DataPacket_Value whichValue() => _DataPacket_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(18)
  void clearValue() => $_clearField($_whichOneof(0));

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  DataPacket_Kind get kind => $_getN(0);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  set kind(DataPacket_Kind value) => $_setField(1, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  UserPacket get user => $_getN(1);
  @$pb.TagNumber(2)
  set user(UserPacket value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasUser() => $_has(1);
  @$pb.TagNumber(2)
  void clearUser() => $_clearField(2);
  @$pb.TagNumber(2)
  UserPacket ensureUser() => $_ensure(1);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  ActiveSpeakerUpdate get speaker => $_getN(2);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  set speaker(ActiveSpeakerUpdate value) => $_setField(3, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  $core.bool hasSpeaker() => $_has(2);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  void clearSpeaker() => $_clearField(3);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  ActiveSpeakerUpdate ensureSpeaker() => $_ensure(2);

  /// participant identity of user that sent the message
  @$pb.TagNumber(4)
  $core.String get participantIdentity => $_getSZ(3);
  @$pb.TagNumber(4)
  set participantIdentity($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasParticipantIdentity() => $_has(3);
  @$pb.TagNumber(4)
  void clearParticipantIdentity() => $_clearField(4);

  /// identities of participants who will receive the message (sent to all by default)
  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get destinationIdentities => $_getList(4);

  @$pb.TagNumber(6)
  SipDTMF get sipDtmf => $_getN(5);
  @$pb.TagNumber(6)
  set sipDtmf(SipDTMF value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSipDtmf() => $_has(5);
  @$pb.TagNumber(6)
  void clearSipDtmf() => $_clearField(6);
  @$pb.TagNumber(6)
  SipDTMF ensureSipDtmf() => $_ensure(5);

  @$pb.TagNumber(7)
  Transcription get transcription => $_getN(6);
  @$pb.TagNumber(7)
  set transcription(Transcription value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasTranscription() => $_has(6);
  @$pb.TagNumber(7)
  void clearTranscription() => $_clearField(7);
  @$pb.TagNumber(7)
  Transcription ensureTranscription() => $_ensure(6);

  @$pb.TagNumber(8)
  $0.MetricsBatch get metrics => $_getN(7);
  @$pb.TagNumber(8)
  set metrics($0.MetricsBatch value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasMetrics() => $_has(7);
  @$pb.TagNumber(8)
  void clearMetrics() => $_clearField(8);
  @$pb.TagNumber(8)
  $0.MetricsBatch ensureMetrics() => $_ensure(7);

  @$pb.TagNumber(9)
  ChatMessage get chatMessage => $_getN(8);
  @$pb.TagNumber(9)
  set chatMessage(ChatMessage value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasChatMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearChatMessage() => $_clearField(9);
  @$pb.TagNumber(9)
  ChatMessage ensureChatMessage() => $_ensure(8);

  @$pb.TagNumber(10)
  RpcRequest get rpcRequest => $_getN(9);
  @$pb.TagNumber(10)
  set rpcRequest(RpcRequest value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasRpcRequest() => $_has(9);
  @$pb.TagNumber(10)
  void clearRpcRequest() => $_clearField(10);
  @$pb.TagNumber(10)
  RpcRequest ensureRpcRequest() => $_ensure(9);

  @$pb.TagNumber(11)
  RpcAck get rpcAck => $_getN(10);
  @$pb.TagNumber(11)
  set rpcAck(RpcAck value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasRpcAck() => $_has(10);
  @$pb.TagNumber(11)
  void clearRpcAck() => $_clearField(11);
  @$pb.TagNumber(11)
  RpcAck ensureRpcAck() => $_ensure(10);

  @$pb.TagNumber(12)
  RpcResponse get rpcResponse => $_getN(11);
  @$pb.TagNumber(12)
  set rpcResponse(RpcResponse value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasRpcResponse() => $_has(11);
  @$pb.TagNumber(12)
  void clearRpcResponse() => $_clearField(12);
  @$pb.TagNumber(12)
  RpcResponse ensureRpcResponse() => $_ensure(11);

  @$pb.TagNumber(13)
  DataStream_Header get streamHeader => $_getN(12);
  @$pb.TagNumber(13)
  set streamHeader(DataStream_Header value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasStreamHeader() => $_has(12);
  @$pb.TagNumber(13)
  void clearStreamHeader() => $_clearField(13);
  @$pb.TagNumber(13)
  DataStream_Header ensureStreamHeader() => $_ensure(12);

  @$pb.TagNumber(14)
  DataStream_Chunk get streamChunk => $_getN(13);
  @$pb.TagNumber(14)
  set streamChunk(DataStream_Chunk value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasStreamChunk() => $_has(13);
  @$pb.TagNumber(14)
  void clearStreamChunk() => $_clearField(14);
  @$pb.TagNumber(14)
  DataStream_Chunk ensureStreamChunk() => $_ensure(13);

  @$pb.TagNumber(15)
  DataStream_Trailer get streamTrailer => $_getN(14);
  @$pb.TagNumber(15)
  set streamTrailer(DataStream_Trailer value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasStreamTrailer() => $_has(14);
  @$pb.TagNumber(15)
  void clearStreamTrailer() => $_clearField(15);
  @$pb.TagNumber(15)
  DataStream_Trailer ensureStreamTrailer() => $_ensure(14);

  /// sequence number of reliable packet
  @$pb.TagNumber(16)
  $core.int get sequence => $_getIZ(15);
  @$pb.TagNumber(16)
  set sequence($core.int value) => $_setUnsignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasSequence() => $_has(15);
  @$pb.TagNumber(16)
  void clearSequence() => $_clearField(16);

  /// sid of the user that sent the message
  @$pb.TagNumber(17)
  $core.String get participantSid => $_getSZ(16);
  @$pb.TagNumber(17)
  set participantSid($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasParticipantSid() => $_has(16);
  @$pb.TagNumber(17)
  void clearParticipantSid() => $_clearField(17);

  @$pb.TagNumber(18)
  EncryptedPacket get encryptedPacket => $_getN(17);
  @$pb.TagNumber(18)
  set encryptedPacket(EncryptedPacket value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasEncryptedPacket() => $_has(17);
  @$pb.TagNumber(18)
  void clearEncryptedPacket() => $_clearField(18);
  @$pb.TagNumber(18)
  EncryptedPacket ensureEncryptedPacket() => $_ensure(17);
}

class EncryptedPacket extends $pb.GeneratedMessage {
  factory EncryptedPacket({
    Encryption_Type? encryptionType,
    $core.List<$core.int>? iv,
    $core.int? keyIndex,
    $core.List<$core.int>? encryptedValue,
  }) {
    final result = EncryptedPacket._();
    if (encryptionType != null) result.encryptionType = encryptionType;
    if (iv != null) result.iv = iv;
    if (keyIndex != null) result.keyIndex = keyIndex;
    if (encryptedValue != null) result.encryptedValue = encryptedValue;
    return result;
  }

  EncryptedPacket._();

  factory EncryptedPacket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptedPacket()..mergeFromBuffer(data, registry);
  factory EncryptedPacket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptedPacket()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncryptedPacket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: EncryptedPacket.$_createMessage)
    ..aE<Encryption_Type>(1, _omitFieldNames ? '' : 'encryptionType',
        enumValues: Encryption_Type.values)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'iv', $pb.PbFieldType.OY)
    ..aI(3, _omitFieldNames ? '' : 'keyIndex', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'encryptedValue', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptedPacket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptedPacket copyWith(void Function(EncryptedPacket) updates) =>
      super.copyWith((message) => updates(message as EncryptedPacket))
          as EncryptedPacket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use EncryptedPacket() / EncryptedPacket.new instead')
  static EncryptedPacket create() => EncryptedPacket._();
  static $pb.GeneratedMessage $_createMessage() => EncryptedPacket._();
  @$core.override
  EncryptedPacket createEmptyInstance() => EncryptedPacket._();
  @$core.pragma('dart2js:noInline')
  static EncryptedPacket getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EncryptedPacket>(
          EncryptedPacket.$_createMessage);
  static EncryptedPacket? _defaultInstance;

  @$pb.TagNumber(1)
  Encryption_Type get encryptionType => $_getN(0);
  @$pb.TagNumber(1)
  set encryptionType(Encryption_Type value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEncryptionType() => $_has(0);
  @$pb.TagNumber(1)
  void clearEncryptionType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get iv => $_getN(1);
  @$pb.TagNumber(2)
  set iv($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIv() => $_has(1);
  @$pb.TagNumber(2)
  void clearIv() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get keyIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set keyIndex($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKeyIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearKeyIndex() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get encryptedValue => $_getN(3);
  @$pb.TagNumber(4)
  set encryptedValue($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEncryptedValue() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncryptedValue() => $_clearField(4);
}

enum EncryptedPacketPayload_Value {
  user,
  chatMessage,
  rpcRequest,
  rpcAck,
  rpcResponse,
  streamHeader,
  streamChunk,
  streamTrailer,
  notSet
}

class EncryptedPacketPayload extends $pb.GeneratedMessage {
  factory EncryptedPacketPayload({
    UserPacket? user,
    ChatMessage? chatMessage,
    RpcRequest? rpcRequest,
    RpcAck? rpcAck,
    RpcResponse? rpcResponse,
    DataStream_Header? streamHeader,
    DataStream_Chunk? streamChunk,
    DataStream_Trailer? streamTrailer,
  }) {
    final result = EncryptedPacketPayload._();
    if (user != null) result.user = user;
    if (chatMessage != null) result.chatMessage = chatMessage;
    if (rpcRequest != null) result.rpcRequest = rpcRequest;
    if (rpcAck != null) result.rpcAck = rpcAck;
    if (rpcResponse != null) result.rpcResponse = rpcResponse;
    if (streamHeader != null) result.streamHeader = streamHeader;
    if (streamChunk != null) result.streamChunk = streamChunk;
    if (streamTrailer != null) result.streamTrailer = streamTrailer;
    return result;
  }

  EncryptedPacketPayload._();

  factory EncryptedPacketPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptedPacketPayload()..mergeFromBuffer(data, registry);
  factory EncryptedPacketPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      EncryptedPacketPayload()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, EncryptedPacketPayload_Value>
      _EncryptedPacketPayload_ValueByTag = {
    1: EncryptedPacketPayload_Value.user,
    3: EncryptedPacketPayload_Value.chatMessage,
    4: EncryptedPacketPayload_Value.rpcRequest,
    5: EncryptedPacketPayload_Value.rpcAck,
    6: EncryptedPacketPayload_Value.rpcResponse,
    7: EncryptedPacketPayload_Value.streamHeader,
    8: EncryptedPacketPayload_Value.streamChunk,
    9: EncryptedPacketPayload_Value.streamTrailer,
    0: EncryptedPacketPayload_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EncryptedPacketPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: EncryptedPacketPayload.$_createMessage)
    ..oo(0, [1, 3, 4, 5, 6, 7, 8, 9])
    ..aOM<UserPacket>(1, _omitFieldNames ? '' : 'user',
        subBuilder: UserPacket.$_createMessage)
    ..aOM<ChatMessage>(3, _omitFieldNames ? '' : 'chatMessage',
        subBuilder: ChatMessage.$_createMessage)
    ..aOM<RpcRequest>(4, _omitFieldNames ? '' : 'rpcRequest',
        subBuilder: RpcRequest.$_createMessage)
    ..aOM<RpcAck>(5, _omitFieldNames ? '' : 'rpcAck',
        subBuilder: RpcAck.$_createMessage)
    ..aOM<RpcResponse>(6, _omitFieldNames ? '' : 'rpcResponse',
        subBuilder: RpcResponse.$_createMessage)
    ..aOM<DataStream_Header>(7, _omitFieldNames ? '' : 'streamHeader',
        subBuilder: DataStream_Header.$_createMessage)
    ..aOM<DataStream_Chunk>(8, _omitFieldNames ? '' : 'streamChunk',
        subBuilder: DataStream_Chunk.$_createMessage)
    ..aOM<DataStream_Trailer>(9, _omitFieldNames ? '' : 'streamTrailer',
        subBuilder: DataStream_Trailer.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptedPacketPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EncryptedPacketPayload copyWith(
          void Function(EncryptedPacketPayload) updates) =>
      super.copyWith((message) => updates(message as EncryptedPacketPayload))
          as EncryptedPacketPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use EncryptedPacketPayload() / EncryptedPacketPayload.new instead')
  static EncryptedPacketPayload create() => EncryptedPacketPayload._();
  static $pb.GeneratedMessage $_createMessage() => EncryptedPacketPayload._();
  @$core.override
  EncryptedPacketPayload createEmptyInstance() => EncryptedPacketPayload._();
  @$core.pragma('dart2js:noInline')
  static EncryptedPacketPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EncryptedPacketPayload>(
          EncryptedPacketPayload.$_createMessage);
  static EncryptedPacketPayload? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  EncryptedPacketPayload_Value whichValue() =>
      _EncryptedPacketPayload_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  void clearValue() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  UserPacket get user => $_getN(0);
  @$pb.TagNumber(1)
  set user(UserPacket value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasUser() => $_has(0);
  @$pb.TagNumber(1)
  void clearUser() => $_clearField(1);
  @$pb.TagNumber(1)
  UserPacket ensureUser() => $_ensure(0);

  @$pb.TagNumber(3)
  ChatMessage get chatMessage => $_getN(1);
  @$pb.TagNumber(3)
  set chatMessage(ChatMessage value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasChatMessage() => $_has(1);
  @$pb.TagNumber(3)
  void clearChatMessage() => $_clearField(3);
  @$pb.TagNumber(3)
  ChatMessage ensureChatMessage() => $_ensure(1);

  @$pb.TagNumber(4)
  RpcRequest get rpcRequest => $_getN(2);
  @$pb.TagNumber(4)
  set rpcRequest(RpcRequest value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasRpcRequest() => $_has(2);
  @$pb.TagNumber(4)
  void clearRpcRequest() => $_clearField(4);
  @$pb.TagNumber(4)
  RpcRequest ensureRpcRequest() => $_ensure(2);

  @$pb.TagNumber(5)
  RpcAck get rpcAck => $_getN(3);
  @$pb.TagNumber(5)
  set rpcAck(RpcAck value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasRpcAck() => $_has(3);
  @$pb.TagNumber(5)
  void clearRpcAck() => $_clearField(5);
  @$pb.TagNumber(5)
  RpcAck ensureRpcAck() => $_ensure(3);

  @$pb.TagNumber(6)
  RpcResponse get rpcResponse => $_getN(4);
  @$pb.TagNumber(6)
  set rpcResponse(RpcResponse value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRpcResponse() => $_has(4);
  @$pb.TagNumber(6)
  void clearRpcResponse() => $_clearField(6);
  @$pb.TagNumber(6)
  RpcResponse ensureRpcResponse() => $_ensure(4);

  @$pb.TagNumber(7)
  DataStream_Header get streamHeader => $_getN(5);
  @$pb.TagNumber(7)
  set streamHeader(DataStream_Header value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasStreamHeader() => $_has(5);
  @$pb.TagNumber(7)
  void clearStreamHeader() => $_clearField(7);
  @$pb.TagNumber(7)
  DataStream_Header ensureStreamHeader() => $_ensure(5);

  @$pb.TagNumber(8)
  DataStream_Chunk get streamChunk => $_getN(6);
  @$pb.TagNumber(8)
  set streamChunk(DataStream_Chunk value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasStreamChunk() => $_has(6);
  @$pb.TagNumber(8)
  void clearStreamChunk() => $_clearField(8);
  @$pb.TagNumber(8)
  DataStream_Chunk ensureStreamChunk() => $_ensure(6);

  @$pb.TagNumber(9)
  DataStream_Trailer get streamTrailer => $_getN(7);
  @$pb.TagNumber(9)
  set streamTrailer(DataStream_Trailer value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasStreamTrailer() => $_has(7);
  @$pb.TagNumber(9)
  void clearStreamTrailer() => $_clearField(9);
  @$pb.TagNumber(9)
  DataStream_Trailer ensureStreamTrailer() => $_ensure(7);
}

@$core.Deprecated('This message is deprecated')
class ActiveSpeakerUpdate extends $pb.GeneratedMessage {
  factory ActiveSpeakerUpdate({
    $core.Iterable<SpeakerInfo>? speakers,
  }) {
    final result = ActiveSpeakerUpdate._();
    if (speakers != null) result.speakers.addAll(speakers);
    return result;
  }

  ActiveSpeakerUpdate._();

  factory ActiveSpeakerUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ActiveSpeakerUpdate()..mergeFromBuffer(data, registry);
  factory ActiveSpeakerUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ActiveSpeakerUpdate()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ActiveSpeakerUpdate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ActiveSpeakerUpdate.$_createMessage)
    ..pPM<SpeakerInfo>(1, _omitFieldNames ? '' : 'speakers',
        subBuilder: SpeakerInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ActiveSpeakerUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ActiveSpeakerUpdate copyWith(void Function(ActiveSpeakerUpdate) updates) =>
      super.copyWith((message) => updates(message as ActiveSpeakerUpdate))
          as ActiveSpeakerUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ActiveSpeakerUpdate() / ActiveSpeakerUpdate.new instead')
  static ActiveSpeakerUpdate create() => ActiveSpeakerUpdate._();
  static $pb.GeneratedMessage $_createMessage() => ActiveSpeakerUpdate._();
  @$core.override
  ActiveSpeakerUpdate createEmptyInstance() => ActiveSpeakerUpdate._();
  @$core.pragma('dart2js:noInline')
  static ActiveSpeakerUpdate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ActiveSpeakerUpdate>(
          ActiveSpeakerUpdate.$_createMessage);
  static ActiveSpeakerUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SpeakerInfo> get speakers => $_getList(0);
}

class SpeakerInfo extends $pb.GeneratedMessage {
  factory SpeakerInfo({
    $core.String? sid,
    $core.double? level,
    $core.bool? active,
  }) {
    final result = SpeakerInfo._();
    if (sid != null) result.sid = sid;
    if (level != null) result.level = level;
    if (active != null) result.active = active;
    return result;
  }

  SpeakerInfo._();

  factory SpeakerInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerInfo()..mergeFromBuffer(data, registry);
  factory SpeakerInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SpeakerInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeakerInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: SpeakerInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sid')
    ..aD(2, _omitFieldNames ? '' : 'level', fieldType: $pb.PbFieldType.OF)
    ..aOB(3, _omitFieldNames ? '' : 'active')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeakerInfo copyWith(void Function(SpeakerInfo) updates) =>
      super.copyWith((message) => updates(message as SpeakerInfo))
          as SpeakerInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SpeakerInfo() / SpeakerInfo.new instead')
  static SpeakerInfo create() => SpeakerInfo._();
  static $pb.GeneratedMessage $_createMessage() => SpeakerInfo._();
  @$core.override
  SpeakerInfo createEmptyInstance() => SpeakerInfo._();
  @$core.pragma('dart2js:noInline')
  static SpeakerInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeakerInfo>(
          SpeakerInfo.$_createMessage);
  static SpeakerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sid => $_getSZ(0);
  @$pb.TagNumber(1)
  set sid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSid() => $_has(0);
  @$pb.TagNumber(1)
  void clearSid() => $_clearField(1);

  /// audio level, 0-1.0, 1 is loudest
  @$pb.TagNumber(2)
  $core.double get level => $_getN(1);
  @$pb.TagNumber(2)
  set level($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLevel() => $_clearField(2);

  /// true if speaker is currently active
  @$pb.TagNumber(3)
  $core.bool get active => $_getBF(2);
  @$pb.TagNumber(3)
  set active($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasActive() => $_has(2);
  @$pb.TagNumber(3)
  void clearActive() => $_clearField(3);
}

class UserPacket extends $pb.GeneratedMessage {
  factory UserPacket({
    @$core.Deprecated('This field is deprecated.') $core.String? participantSid,
    $core.List<$core.int>? payload,
    @$core.Deprecated('This field is deprecated.')
    $core.Iterable<$core.String>? destinationSids,
    $core.String? topic,
    @$core.Deprecated('This field is deprecated.')
    $core.String? participantIdentity,
    @$core.Deprecated('This field is deprecated.')
    $core.Iterable<$core.String>? destinationIdentities,
    $core.String? id,
    $fixnum.Int64? startTime,
    $fixnum.Int64? endTime,
    $core.List<$core.int>? nonce,
  }) {
    final result = UserPacket._();
    if (participantSid != null) result.participantSid = participantSid;
    if (payload != null) result.payload = payload;
    if (destinationSids != null) result.destinationSids.addAll(destinationSids);
    if (topic != null) result.topic = topic;
    if (participantIdentity != null)
      result.participantIdentity = participantIdentity;
    if (destinationIdentities != null)
      result.destinationIdentities.addAll(destinationIdentities);
    if (id != null) result.id = id;
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (nonce != null) result.nonce = nonce;
    return result;
  }

  UserPacket._();

  factory UserPacket.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserPacket()..mergeFromBuffer(data, registry);
  factory UserPacket.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserPacket()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserPacket',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: UserPacket.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'participantSid')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..pPS(3, _omitFieldNames ? '' : 'destinationSids')
    ..aOS(4, _omitFieldNames ? '' : 'topic')
    ..aOS(5, _omitFieldNames ? '' : 'participantIdentity')
    ..pPS(6, _omitFieldNames ? '' : 'destinationIdentities')
    ..aOS(8, _omitFieldNames ? '' : 'id')
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'startTime', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        10, _omitFieldNames ? '' : 'endTime', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserPacket clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserPacket copyWith(void Function(UserPacket) updates) =>
      super.copyWith((message) => updates(message as UserPacket)) as UserPacket;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserPacket() / UserPacket.new instead')
  static UserPacket create() => UserPacket._();
  static $pb.GeneratedMessage $_createMessage() => UserPacket._();
  @$core.override
  UserPacket createEmptyInstance() => UserPacket._();
  @$core.pragma('dart2js:noInline')
  static UserPacket getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserPacket>(UserPacket.$_createMessage);
  static UserPacket? _defaultInstance;

  /// participant ID of user that sent the message
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  $core.String get participantSid => $_getSZ(0);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  set participantSid($core.String value) => $_setString(0, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  $core.bool hasParticipantSid() => $_has(0);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(1)
  void clearParticipantSid() => $_clearField(1);

  /// user defined payload
  @$pb.TagNumber(2)
  $core.List<$core.int> get payload => $_getN(1);
  @$pb.TagNumber(2)
  set payload($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField(2);

  /// the ID of the participants who will receive the message (sent to all by default)
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get destinationSids => $_getList(2);

  /// topic under which the message was published
  @$pb.TagNumber(4)
  $core.String get topic => $_getSZ(3);
  @$pb.TagNumber(4)
  set topic($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopic() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopic() => $_clearField(4);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  $core.String get participantIdentity => $_getSZ(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  set participantIdentity($core.String value) => $_setString(4, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  $core.bool hasParticipantIdentity() => $_has(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  void clearParticipantIdentity() => $_clearField(5);

  /// identities of participants who will receive the message (sent to all by default)
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get destinationIdentities => $_getList(5);

  /// Unique ID to identify the message
  @$pb.TagNumber(8)
  $core.String get id => $_getSZ(6);
  @$pb.TagNumber(8)
  set id($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasId() => $_has(6);
  @$pb.TagNumber(8)
  void clearId() => $_clearField(8);

  /// start and end time allow relating the message to specific media time
  @$pb.TagNumber(9)
  $fixnum.Int64 get startTime => $_getI64(7);
  @$pb.TagNumber(9)
  set startTime($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(9)
  $core.bool hasStartTime() => $_has(7);
  @$pb.TagNumber(9)
  void clearStartTime() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get endTime => $_getI64(8);
  @$pb.TagNumber(10)
  set endTime($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(10)
  $core.bool hasEndTime() => $_has(8);
  @$pb.TagNumber(10)
  void clearEndTime() => $_clearField(10);

  /// added by SDK to enable de-duping of messages, for INTERNAL USE ONLY
  @$pb.TagNumber(11)
  $core.List<$core.int> get nonce => $_getN(9);
  @$pb.TagNumber(11)
  set nonce($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(11)
  $core.bool hasNonce() => $_has(9);
  @$pb.TagNumber(11)
  void clearNonce() => $_clearField(11);
}

class SipDTMF extends $pb.GeneratedMessage {
  factory SipDTMF({
    $core.int? code,
    $core.String? digit,
  }) {
    final result = SipDTMF._();
    if (code != null) result.code = code;
    if (digit != null) result.digit = digit;
    return result;
  }

  SipDTMF._();

  factory SipDTMF.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SipDTMF()..mergeFromBuffer(data, registry);
  factory SipDTMF.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SipDTMF()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SipDTMF',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: SipDTMF.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'code', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'digit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SipDTMF clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SipDTMF copyWith(void Function(SipDTMF) updates) =>
      super.copyWith((message) => updates(message as SipDTMF)) as SipDTMF;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SipDTMF() / SipDTMF.new instead')
  static SipDTMF create() => SipDTMF._();
  static $pb.GeneratedMessage $_createMessage() => SipDTMF._();
  @$core.override
  SipDTMF createEmptyInstance() => SipDTMF._();
  @$core.pragma('dart2js:noInline')
  static SipDTMF getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SipDTMF>(SipDTMF.$_createMessage);
  static SipDTMF? _defaultInstance;

  @$pb.TagNumber(3)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(3)
  set code($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(3)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(3)
  void clearCode() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get digit => $_getSZ(1);
  @$pb.TagNumber(4)
  set digit($core.String value) => $_setString(1, value);
  @$pb.TagNumber(4)
  $core.bool hasDigit() => $_has(1);
  @$pb.TagNumber(4)
  void clearDigit() => $_clearField(4);
}

class Transcription extends $pb.GeneratedMessage {
  factory Transcription({
    $core.String? transcribedParticipantIdentity,
    $core.String? trackId,
    $core.Iterable<TranscriptionSegment>? segments,
  }) {
    final result = Transcription._();
    if (transcribedParticipantIdentity != null)
      result.transcribedParticipantIdentity = transcribedParticipantIdentity;
    if (trackId != null) result.trackId = trackId;
    if (segments != null) result.segments.addAll(segments);
    return result;
  }

  Transcription._();

  factory Transcription.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Transcription()..mergeFromBuffer(data, registry);
  factory Transcription.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Transcription()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Transcription',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: Transcription.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'transcribedParticipantIdentity')
    ..aOS(3, _omitFieldNames ? '' : 'trackId')
    ..pPM<TranscriptionSegment>(4, _omitFieldNames ? '' : 'segments',
        subBuilder: TranscriptionSegment.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transcription clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transcription copyWith(void Function(Transcription) updates) =>
      super.copyWith((message) => updates(message as Transcription))
          as Transcription;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Transcription() / Transcription.new instead')
  static Transcription create() => Transcription._();
  static $pb.GeneratedMessage $_createMessage() => Transcription._();
  @$core.override
  Transcription createEmptyInstance() => Transcription._();
  @$core.pragma('dart2js:noInline')
  static Transcription getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Transcription>(
          Transcription.$_createMessage);
  static Transcription? _defaultInstance;

  /// Participant that got its speech transcribed
  @$pb.TagNumber(2)
  $core.String get transcribedParticipantIdentity => $_getSZ(0);
  @$pb.TagNumber(2)
  set transcribedParticipantIdentity($core.String value) =>
      $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTranscribedParticipantIdentity() => $_has(0);
  @$pb.TagNumber(2)
  void clearTranscribedParticipantIdentity() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get trackId => $_getSZ(1);
  @$pb.TagNumber(3)
  set trackId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasTrackId() => $_has(1);
  @$pb.TagNumber(3)
  void clearTrackId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<TranscriptionSegment> get segments => $_getList(2);
}

class TranscriptionSegment extends $pb.GeneratedMessage {
  factory TranscriptionSegment({
    $core.String? id,
    $core.String? text,
    $fixnum.Int64? startTime,
    $fixnum.Int64? endTime,
    $core.bool? final_5,
    $core.String? language,
  }) {
    final result = TranscriptionSegment._();
    if (id != null) result.id = id;
    if (text != null) result.text = text;
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (final_5 != null) result.final_5 = final_5;
    if (language != null) result.language = language;
    return result;
  }

  TranscriptionSegment._();

  factory TranscriptionSegment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TranscriptionSegment()..mergeFromBuffer(data, registry);
  factory TranscriptionSegment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TranscriptionSegment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TranscriptionSegment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: TranscriptionSegment.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'startTime', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'endTime', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(5, _omitFieldNames ? '' : 'final')
    ..aOS(6, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionSegment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranscriptionSegment copyWith(void Function(TranscriptionSegment) updates) =>
      super.copyWith((message) => updates(message as TranscriptionSegment))
          as TranscriptionSegment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use TranscriptionSegment() / TranscriptionSegment.new instead')
  static TranscriptionSegment create() => TranscriptionSegment._();
  static $pb.GeneratedMessage $_createMessage() => TranscriptionSegment._();
  @$core.override
  TranscriptionSegment createEmptyInstance() => TranscriptionSegment._();
  @$core.pragma('dart2js:noInline')
  static TranscriptionSegment getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TranscriptionSegment>(
          TranscriptionSegment.$_createMessage);
  static TranscriptionSegment? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get startTime => $_getI64(2);
  @$pb.TagNumber(3)
  set startTime($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartTime() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get endTime => $_getI64(3);
  @$pb.TagNumber(4)
  set endTime($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEndTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get final_5 => $_getBF(4);
  @$pb.TagNumber(5)
  set final_5($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFinal_5() => $_has(4);
  @$pb.TagNumber(5)
  void clearFinal_5() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get language => $_getSZ(5);
  @$pb.TagNumber(6)
  set language($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLanguage() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanguage() => $_clearField(6);
}

class ChatMessage extends $pb.GeneratedMessage {
  factory ChatMessage({
    $core.String? id,
    $fixnum.Int64? timestamp,
    $fixnum.Int64? editTimestamp,
    $core.String? message,
    $core.bool? deleted,
    $core.bool? generated,
  }) {
    final result = ChatMessage._();
    if (id != null) result.id = id;
    if (timestamp != null) result.timestamp = timestamp;
    if (editTimestamp != null) result.editTimestamp = editTimestamp;
    if (message != null) result.message = message;
    if (deleted != null) result.deleted = deleted;
    if (generated != null) result.generated = generated;
    return result;
  }

  ChatMessage._();

  factory ChatMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChatMessage()..mergeFromBuffer(data, registry);
  factory ChatMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChatMessage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ChatMessage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..aInt64(3, _omitFieldNames ? '' : 'editTimestamp')
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..aOB(5, _omitFieldNames ? '' : 'deleted')
    ..aOB(6, _omitFieldNames ? '' : 'generated')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage copyWith(void Function(ChatMessage) updates) =>
      super.copyWith((message) => updates(message as ChatMessage))
          as ChatMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChatMessage() / ChatMessage.new instead')
  static ChatMessage create() => ChatMessage._();
  static $pb.GeneratedMessage $_createMessage() => ChatMessage._();
  @$core.override
  ChatMessage createEmptyInstance() => ChatMessage._();
  @$core.pragma('dart2js:noInline')
  static ChatMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessage>(
          ChatMessage.$_createMessage);
  static ChatMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get editTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set editTimestamp($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEditTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearEditTimestamp() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get deleted => $_getBF(4);
  @$pb.TagNumber(5)
  set deleted($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDeleted() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeleted() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get generated => $_getBF(5);
  @$pb.TagNumber(6)
  set generated($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGenerated() => $_has(5);
  @$pb.TagNumber(6)
  void clearGenerated() => $_clearField(6);
}

class RpcRequest extends $pb.GeneratedMessage {
  factory RpcRequest({
    $core.String? id,
    $core.String? method,
    $core.String? payload,
    $core.int? responseTimeoutMs,
    $core.int? version,
    $core.List<$core.int>? compressedPayload,
  }) {
    final result = RpcRequest._();
    if (id != null) result.id = id;
    if (method != null) result.method = method;
    if (payload != null) result.payload = payload;
    if (responseTimeoutMs != null) result.responseTimeoutMs = responseTimeoutMs;
    if (version != null) result.version = version;
    if (compressedPayload != null) result.compressedPayload = compressedPayload;
    return result;
  }

  RpcRequest._();

  factory RpcRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcRequest()..mergeFromBuffer(data, registry);
  factory RpcRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RpcRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RpcRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'method')
    ..aOS(3, _omitFieldNames ? '' : 'payload')
    ..aI(4, _omitFieldNames ? '' : 'responseTimeoutMs',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'version', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'compressedPayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcRequest copyWith(void Function(RpcRequest) updates) =>
      super.copyWith((message) => updates(message as RpcRequest)) as RpcRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RpcRequest() / RpcRequest.new instead')
  static RpcRequest create() => RpcRequest._();
  static $pb.GeneratedMessage $_createMessage() => RpcRequest._();
  @$core.override
  RpcRequest createEmptyInstance() => RpcRequest._();
  @$core.pragma('dart2js:noInline')
  static RpcRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RpcRequest>(RpcRequest.$_createMessage);
  static RpcRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get method => $_getSZ(1);
  @$pb.TagNumber(2)
  set method($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMethod() => $_has(1);
  @$pb.TagNumber(2)
  void clearMethod() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get payload => $_getSZ(2);
  @$pb.TagNumber(3)
  set payload($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearPayload() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get responseTimeoutMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set responseTimeoutMs($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResponseTimeoutMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearResponseTimeoutMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get version => $_getIZ(4);
  @$pb.TagNumber(5)
  set version($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearVersion() => $_clearField(5);

  /// Compressed payload data. When set, this field is used instead of `payload`.
  @$pb.TagNumber(6)
  $core.List<$core.int> get compressedPayload => $_getN(5);
  @$pb.TagNumber(6)
  set compressedPayload($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCompressedPayload() => $_has(5);
  @$pb.TagNumber(6)
  void clearCompressedPayload() => $_clearField(6);
}

class RpcAck extends $pb.GeneratedMessage {
  factory RpcAck({
    $core.String? requestId,
  }) {
    final result = RpcAck._();
    if (requestId != null) result.requestId = requestId;
    return result;
  }

  RpcAck._();

  factory RpcAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcAck()..mergeFromBuffer(data, registry);
  factory RpcAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcAck()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RpcAck',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RpcAck.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcAck copyWith(void Function(RpcAck) updates) =>
      super.copyWith((message) => updates(message as RpcAck)) as RpcAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RpcAck() / RpcAck.new instead')
  static RpcAck create() => RpcAck._();
  static $pb.GeneratedMessage $_createMessage() => RpcAck._();
  @$core.override
  RpcAck createEmptyInstance() => RpcAck._();
  @$core.pragma('dart2js:noInline')
  static RpcAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RpcAck>(RpcAck.$_createMessage);
  static RpcAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);
}

enum RpcResponse_Value { payload, error, compressedPayload, notSet }

class RpcResponse extends $pb.GeneratedMessage {
  factory RpcResponse({
    $core.String? requestId,
    $core.String? payload,
    RpcError? error,
    $core.List<$core.int>? compressedPayload,
  }) {
    final result = RpcResponse._();
    if (requestId != null) result.requestId = requestId;
    if (payload != null) result.payload = payload;
    if (error != null) result.error = error;
    if (compressedPayload != null) result.compressedPayload = compressedPayload;
    return result;
  }

  RpcResponse._();

  factory RpcResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcResponse()..mergeFromBuffer(data, registry);
  factory RpcResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, RpcResponse_Value> _RpcResponse_ValueByTag =
      {
    2: RpcResponse_Value.payload,
    3: RpcResponse_Value.error,
    4: RpcResponse_Value.compressedPayload,
    0: RpcResponse_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RpcResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RpcResponse.$_createMessage)
    ..oo(0, [2, 3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'payload')
    ..aOM<RpcError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: RpcError.$_createMessage)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'compressedPayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcResponse copyWith(void Function(RpcResponse) updates) =>
      super.copyWith((message) => updates(message as RpcResponse))
          as RpcResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RpcResponse() / RpcResponse.new instead')
  static RpcResponse create() => RpcResponse._();
  static $pb.GeneratedMessage $_createMessage() => RpcResponse._();
  @$core.override
  RpcResponse createEmptyInstance() => RpcResponse._();
  @$core.pragma('dart2js:noInline')
  static RpcResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RpcResponse>(
          RpcResponse.$_createMessage);
  static RpcResponse? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  RpcResponse_Value whichValue() => _RpcResponse_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearValue() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get payload => $_getSZ(1);
  @$pb.TagNumber(2)
  set payload($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField(2);

  @$pb.TagNumber(3)
  RpcError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(RpcError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  RpcError ensureError() => $_ensure(2);

  /// Compressed payload data. When set, this field is used instead of `payload`.
  @$pb.TagNumber(4)
  $core.List<$core.int> get compressedPayload => $_getN(3);
  @$pb.TagNumber(4)
  set compressedPayload($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCompressedPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearCompressedPayload() => $_clearField(4);
}

class RpcError extends $pb.GeneratedMessage {
  factory RpcError({
    $core.int? code,
    $core.String? message,
    $core.String? data,
  }) {
    final result = RpcError._();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (data != null) result.data = data;
    return result;
  }

  RpcError._();

  factory RpcError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcError()..mergeFromBuffer(data, registry);
  factory RpcError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcError()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RpcError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RpcError.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'code', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'data')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcError copyWith(void Function(RpcError) updates) =>
      super.copyWith((message) => updates(message as RpcError)) as RpcError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RpcError() / RpcError.new instead')
  static RpcError create() => RpcError._();
  static $pb.GeneratedMessage $_createMessage() => RpcError._();
  @$core.override
  RpcError createEmptyInstance() => RpcError._();
  @$core.pragma('dart2js:noInline')
  static RpcError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RpcError>(RpcError.$_createMessage);
  static RpcError? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get data => $_getSZ(2);
  @$pb.TagNumber(3)
  set data($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => $_clearField(3);
}

class ParticipantTracks extends $pb.GeneratedMessage {
  factory ParticipantTracks({
    $core.String? participantSid,
    $core.Iterable<$core.String>? trackSids,
  }) {
    final result = ParticipantTracks._();
    if (participantSid != null) result.participantSid = participantSid;
    if (trackSids != null) result.trackSids.addAll(trackSids);
    return result;
  }

  ParticipantTracks._();

  factory ParticipantTracks.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantTracks()..mergeFromBuffer(data, registry);
  factory ParticipantTracks.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ParticipantTracks()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ParticipantTracks',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ParticipantTracks.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'participantSid')
    ..pPS(2, _omitFieldNames ? '' : 'trackSids')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantTracks clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ParticipantTracks copyWith(void Function(ParticipantTracks) updates) =>
      super.copyWith((message) => updates(message as ParticipantTracks))
          as ParticipantTracks;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ParticipantTracks() / ParticipantTracks.new instead')
  static ParticipantTracks create() => ParticipantTracks._();
  static $pb.GeneratedMessage $_createMessage() => ParticipantTracks._();
  @$core.override
  ParticipantTracks createEmptyInstance() => ParticipantTracks._();
  @$core.pragma('dart2js:noInline')
  static ParticipantTracks getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ParticipantTracks>(
          ParticipantTracks.$_createMessage);
  static ParticipantTracks? _defaultInstance;

  /// participant ID of participant to whom the tracks belong
  @$pb.TagNumber(1)
  $core.String get participantSid => $_getSZ(0);
  @$pb.TagNumber(1)
  set participantSid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasParticipantSid() => $_has(0);
  @$pb.TagNumber(1)
  void clearParticipantSid() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get trackSids => $_getList(1);
}

/// details about the server
class ServerInfo extends $pb.GeneratedMessage {
  factory ServerInfo({
    ServerInfo_Edition? edition,
    $core.String? version,
    $core.int? protocol,
    $core.String? region,
    $core.String? nodeId,
    $core.String? debugInfo,
    $core.int? agentProtocol,
  }) {
    final result = ServerInfo._();
    if (edition != null) result.edition = edition;
    if (version != null) result.version = version;
    if (protocol != null) result.protocol = protocol;
    if (region != null) result.region = region;
    if (nodeId != null) result.nodeId = nodeId;
    if (debugInfo != null) result.debugInfo = debugInfo;
    if (agentProtocol != null) result.agentProtocol = agentProtocol;
    return result;
  }

  ServerInfo._();

  factory ServerInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerInfo()..mergeFromBuffer(data, registry);
  factory ServerInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ServerInfo.$_createMessage)
    ..aE<ServerInfo_Edition>(1, _omitFieldNames ? '' : 'edition',
        enumValues: ServerInfo_Edition.values)
    ..aOS(2, _omitFieldNames ? '' : 'version')
    ..aI(3, _omitFieldNames ? '' : 'protocol')
    ..aOS(4, _omitFieldNames ? '' : 'region')
    ..aOS(5, _omitFieldNames ? '' : 'nodeId')
    ..aOS(6, _omitFieldNames ? '' : 'debugInfo')
    ..aI(7, _omitFieldNames ? '' : 'agentProtocol')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerInfo copyWith(void Function(ServerInfo) updates) =>
      super.copyWith((message) => updates(message as ServerInfo)) as ServerInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ServerInfo() / ServerInfo.new instead')
  static ServerInfo create() => ServerInfo._();
  static $pb.GeneratedMessage $_createMessage() => ServerInfo._();
  @$core.override
  ServerInfo createEmptyInstance() => ServerInfo._();
  @$core.pragma('dart2js:noInline')
  static ServerInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerInfo>(ServerInfo.$_createMessage);
  static ServerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  ServerInfo_Edition get edition => $_getN(0);
  @$pb.TagNumber(1)
  set edition(ServerInfo_Edition value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEdition() => $_has(0);
  @$pb.TagNumber(1)
  void clearEdition() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get version => $_getSZ(1);
  @$pb.TagNumber(2)
  set version($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get protocol => $_getIZ(2);
  @$pb.TagNumber(3)
  set protocol($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get region => $_getSZ(3);
  @$pb.TagNumber(4)
  set region($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRegion() => $_has(3);
  @$pb.TagNumber(4)
  void clearRegion() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get nodeId => $_getSZ(4);
  @$pb.TagNumber(5)
  set nodeId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNodeId() => $_has(4);
  @$pb.TagNumber(5)
  void clearNodeId() => $_clearField(5);

  /// additional debugging information. sent only if server is in development mode
  @$pb.TagNumber(6)
  $core.String get debugInfo => $_getSZ(5);
  @$pb.TagNumber(6)
  set debugInfo($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDebugInfo() => $_has(5);
  @$pb.TagNumber(6)
  void clearDebugInfo() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get agentProtocol => $_getIZ(6);
  @$pb.TagNumber(7)
  set agentProtocol($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAgentProtocol() => $_has(6);
  @$pb.TagNumber(7)
  void clearAgentProtocol() => $_clearField(7);
}

/// details about the client
class ClientInfo extends $pb.GeneratedMessage {
  factory ClientInfo({
    ClientInfo_SDK? sdk,
    $core.String? version,
    $core.int? protocol,
    $core.String? os,
    $core.String? osVersion,
    $core.String? deviceModel,
    $core.String? browser,
    $core.String? browserVersion,
    $core.String? address,
    $core.String? network,
    $core.String? otherSdks,
    $core.int? clientProtocol,
    $core.Iterable<ClientInfo_Capability>? capabilities,
  }) {
    final result = ClientInfo._();
    if (sdk != null) result.sdk = sdk;
    if (version != null) result.version = version;
    if (protocol != null) result.protocol = protocol;
    if (os != null) result.os = os;
    if (osVersion != null) result.osVersion = osVersion;
    if (deviceModel != null) result.deviceModel = deviceModel;
    if (browser != null) result.browser = browser;
    if (browserVersion != null) result.browserVersion = browserVersion;
    if (address != null) result.address = address;
    if (network != null) result.network = network;
    if (otherSdks != null) result.otherSdks = otherSdks;
    if (clientProtocol != null) result.clientProtocol = clientProtocol;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    return result;
  }

  ClientInfo._();

  factory ClientInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientInfo()..mergeFromBuffer(data, registry);
  factory ClientInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ClientInfo.$_createMessage)
    ..aE<ClientInfo_SDK>(1, _omitFieldNames ? '' : 'sdk',
        enumValues: ClientInfo_SDK.values)
    ..aOS(2, _omitFieldNames ? '' : 'version')
    ..aI(3, _omitFieldNames ? '' : 'protocol')
    ..aOS(4, _omitFieldNames ? '' : 'os')
    ..aOS(5, _omitFieldNames ? '' : 'osVersion')
    ..aOS(6, _omitFieldNames ? '' : 'deviceModel')
    ..aOS(7, _omitFieldNames ? '' : 'browser')
    ..aOS(8, _omitFieldNames ? '' : 'browserVersion')
    ..aOS(9, _omitFieldNames ? '' : 'address')
    ..aOS(10, _omitFieldNames ? '' : 'network')
    ..aOS(11, _omitFieldNames ? '' : 'otherSdks')
    ..aI(12, _omitFieldNames ? '' : 'clientProtocol')
    ..pc<ClientInfo_Capability>(
        13, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.KE,
        valueOf: ClientInfo_Capability.valueOf,
        enumValues: ClientInfo_Capability.values,
        defaultEnumValue: ClientInfo_Capability.CAP_UNUSED)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientInfo copyWith(void Function(ClientInfo) updates) =>
      super.copyWith((message) => updates(message as ClientInfo)) as ClientInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClientInfo() / ClientInfo.new instead')
  static ClientInfo create() => ClientInfo._();
  static $pb.GeneratedMessage $_createMessage() => ClientInfo._();
  @$core.override
  ClientInfo createEmptyInstance() => ClientInfo._();
  @$core.pragma('dart2js:noInline')
  static ClientInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClientInfo>(ClientInfo.$_createMessage);
  static ClientInfo? _defaultInstance;

  @$pb.TagNumber(1)
  ClientInfo_SDK get sdk => $_getN(0);
  @$pb.TagNumber(1)
  set sdk(ClientInfo_SDK value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSdk() => $_has(0);
  @$pb.TagNumber(1)
  void clearSdk() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get version => $_getSZ(1);
  @$pb.TagNumber(2)
  set version($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get protocol => $_getIZ(2);
  @$pb.TagNumber(3)
  set protocol($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get os => $_getSZ(3);
  @$pb.TagNumber(4)
  set os($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOs() => $_has(3);
  @$pb.TagNumber(4)
  void clearOs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get osVersion => $_getSZ(4);
  @$pb.TagNumber(5)
  set osVersion($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOsVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearOsVersion() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get deviceModel => $_getSZ(5);
  @$pb.TagNumber(6)
  set deviceModel($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDeviceModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearDeviceModel() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get browser => $_getSZ(6);
  @$pb.TagNumber(7)
  set browser($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBrowser() => $_has(6);
  @$pb.TagNumber(7)
  void clearBrowser() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get browserVersion => $_getSZ(7);
  @$pb.TagNumber(8)
  set browserVersion($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBrowserVersion() => $_has(7);
  @$pb.TagNumber(8)
  void clearBrowserVersion() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get address => $_getSZ(8);
  @$pb.TagNumber(9)
  set address($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAddress() => $_has(8);
  @$pb.TagNumber(9)
  void clearAddress() => $_clearField(9);

  /// wifi, wired, cellular, vpn, empty if not known
  @$pb.TagNumber(10)
  $core.String get network => $_getSZ(9);
  @$pb.TagNumber(10)
  set network($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNetwork() => $_has(9);
  @$pb.TagNumber(10)
  void clearNetwork() => $_clearField(10);

  /// comma separated list of additional LiveKit SDKs in use of this client, with versions
  /// e.g. "components-js:1.2.3,track-processors-js:1.2.3"
  @$pb.TagNumber(11)
  $core.String get otherSdks => $_getSZ(10);
  @$pb.TagNumber(11)
  set otherSdks($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasOtherSdks() => $_has(10);
  @$pb.TagNumber(11)
  void clearOtherSdks() => $_clearField(11);

  /// client protocol version
  @$pb.TagNumber(12)
  $core.int get clientProtocol => $_getIZ(11);
  @$pb.TagNumber(12)
  set clientProtocol($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasClientProtocol() => $_has(11);
  @$pb.TagNumber(12)
  void clearClientProtocol() => $_clearField(12);

  /// capabilities the client advertises. Populated automatically by each SDK;
  /// not a user-configurable setting.
  @$pb.TagNumber(13)
  $pb.PbList<ClientInfo_Capability> get capabilities => $_getList(12);
}

/// server provided client configuration
class ClientConfiguration extends $pb.GeneratedMessage {
  factory ClientConfiguration({
    VideoConfiguration? video,
    VideoConfiguration? screen,
    ClientConfigSetting? resumeConnection,
    DisabledCodecs? disabledCodecs,
    ClientConfigSetting? forceRelay,
  }) {
    final result = ClientConfiguration._();
    if (video != null) result.video = video;
    if (screen != null) result.screen = screen;
    if (resumeConnection != null) result.resumeConnection = resumeConnection;
    if (disabledCodecs != null) result.disabledCodecs = disabledCodecs;
    if (forceRelay != null) result.forceRelay = forceRelay;
    return result;
  }

  ClientConfiguration._();

  factory ClientConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientConfiguration()..mergeFromBuffer(data, registry);
  factory ClientConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientConfiguration()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: ClientConfiguration.$_createMessage)
    ..aOM<VideoConfiguration>(1, _omitFieldNames ? '' : 'video',
        subBuilder: VideoConfiguration.$_createMessage)
    ..aOM<VideoConfiguration>(2, _omitFieldNames ? '' : 'screen',
        subBuilder: VideoConfiguration.$_createMessage)
    ..aE<ClientConfigSetting>(3, _omitFieldNames ? '' : 'resumeConnection',
        enumValues: ClientConfigSetting.values)
    ..aOM<DisabledCodecs>(4, _omitFieldNames ? '' : 'disabledCodecs',
        subBuilder: DisabledCodecs.$_createMessage)
    ..aE<ClientConfigSetting>(5, _omitFieldNames ? '' : 'forceRelay',
        enumValues: ClientConfigSetting.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientConfiguration copyWith(void Function(ClientConfiguration) updates) =>
      super.copyWith((message) => updates(message as ClientConfiguration))
          as ClientConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ClientConfiguration() / ClientConfiguration.new instead')
  static ClientConfiguration create() => ClientConfiguration._();
  static $pb.GeneratedMessage $_createMessage() => ClientConfiguration._();
  @$core.override
  ClientConfiguration createEmptyInstance() => ClientConfiguration._();
  @$core.pragma('dart2js:noInline')
  static ClientConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClientConfiguration>(
          ClientConfiguration.$_createMessage);
  static ClientConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  VideoConfiguration get video => $_getN(0);
  @$pb.TagNumber(1)
  set video(VideoConfiguration value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasVideo() => $_has(0);
  @$pb.TagNumber(1)
  void clearVideo() => $_clearField(1);
  @$pb.TagNumber(1)
  VideoConfiguration ensureVideo() => $_ensure(0);

  @$pb.TagNumber(2)
  VideoConfiguration get screen => $_getN(1);
  @$pb.TagNumber(2)
  set screen(VideoConfiguration value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasScreen() => $_has(1);
  @$pb.TagNumber(2)
  void clearScreen() => $_clearField(2);
  @$pb.TagNumber(2)
  VideoConfiguration ensureScreen() => $_ensure(1);

  @$pb.TagNumber(3)
  ClientConfigSetting get resumeConnection => $_getN(2);
  @$pb.TagNumber(3)
  set resumeConnection(ClientConfigSetting value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasResumeConnection() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeConnection() => $_clearField(3);

  @$pb.TagNumber(4)
  DisabledCodecs get disabledCodecs => $_getN(3);
  @$pb.TagNumber(4)
  set disabledCodecs(DisabledCodecs value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasDisabledCodecs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDisabledCodecs() => $_clearField(4);
  @$pb.TagNumber(4)
  DisabledCodecs ensureDisabledCodecs() => $_ensure(3);

  @$pb.TagNumber(5)
  ClientConfigSetting get forceRelay => $_getN(4);
  @$pb.TagNumber(5)
  set forceRelay(ClientConfigSetting value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasForceRelay() => $_has(4);
  @$pb.TagNumber(5)
  void clearForceRelay() => $_clearField(5);
}

class VideoConfiguration extends $pb.GeneratedMessage {
  factory VideoConfiguration({
    ClientConfigSetting? hardwareEncoder,
  }) {
    final result = VideoConfiguration._();
    if (hardwareEncoder != null) result.hardwareEncoder = hardwareEncoder;
    return result;
  }

  VideoConfiguration._();

  factory VideoConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VideoConfiguration()..mergeFromBuffer(data, registry);
  factory VideoConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VideoConfiguration()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VideoConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: VideoConfiguration.$_createMessage)
    ..aE<ClientConfigSetting>(1, _omitFieldNames ? '' : 'hardwareEncoder',
        enumValues: ClientConfigSetting.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VideoConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VideoConfiguration copyWith(void Function(VideoConfiguration) updates) =>
      super.copyWith((message) => updates(message as VideoConfiguration))
          as VideoConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use VideoConfiguration() / VideoConfiguration.new instead')
  static VideoConfiguration create() => VideoConfiguration._();
  static $pb.GeneratedMessage $_createMessage() => VideoConfiguration._();
  @$core.override
  VideoConfiguration createEmptyInstance() => VideoConfiguration._();
  @$core.pragma('dart2js:noInline')
  static VideoConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VideoConfiguration>(
          VideoConfiguration.$_createMessage);
  static VideoConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  ClientConfigSetting get hardwareEncoder => $_getN(0);
  @$pb.TagNumber(1)
  set hardwareEncoder(ClientConfigSetting value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasHardwareEncoder() => $_has(0);
  @$pb.TagNumber(1)
  void clearHardwareEncoder() => $_clearField(1);
}

class DisabledCodecs extends $pb.GeneratedMessage {
  factory DisabledCodecs({
    $core.Iterable<Codec>? codecs,
    $core.Iterable<Codec>? publish,
  }) {
    final result = DisabledCodecs._();
    if (codecs != null) result.codecs.addAll(codecs);
    if (publish != null) result.publish.addAll(publish);
    return result;
  }

  DisabledCodecs._();

  factory DisabledCodecs.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisabledCodecs()..mergeFromBuffer(data, registry);
  factory DisabledCodecs.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DisabledCodecs()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DisabledCodecs',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DisabledCodecs.$_createMessage)
    ..pPM<Codec>(1, _omitFieldNames ? '' : 'codecs',
        subBuilder: Codec.$_createMessage)
    ..pPM<Codec>(2, _omitFieldNames ? '' : 'publish',
        subBuilder: Codec.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisabledCodecs clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DisabledCodecs copyWith(void Function(DisabledCodecs) updates) =>
      super.copyWith((message) => updates(message as DisabledCodecs))
          as DisabledCodecs;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DisabledCodecs() / DisabledCodecs.new instead')
  static DisabledCodecs create() => DisabledCodecs._();
  static $pb.GeneratedMessage $_createMessage() => DisabledCodecs._();
  @$core.override
  DisabledCodecs createEmptyInstance() => DisabledCodecs._();
  @$core.pragma('dart2js:noInline')
  static DisabledCodecs getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DisabledCodecs>(
          DisabledCodecs.$_createMessage);
  static DisabledCodecs? _defaultInstance;

  /// disabled for both publish and subscribe
  @$pb.TagNumber(1)
  $pb.PbList<Codec> get codecs => $_getList(0);

  /// only disable for publish
  @$pb.TagNumber(2)
  $pb.PbList<Codec> get publish => $_getList(1);
}

class RTPDrift extends $pb.GeneratedMessage {
  factory RTPDrift({
    $1.Timestamp? startTime,
    $1.Timestamp? endTime,
    $core.double? duration,
    $fixnum.Int64? startTimestamp,
    $fixnum.Int64? endTimestamp,
    $fixnum.Int64? rtpClockTicks,
    $fixnum.Int64? driftSamples,
    $core.double? driftMs,
    $core.double? clockRate,
  }) {
    final result = RTPDrift._();
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (duration != null) result.duration = duration;
    if (startTimestamp != null) result.startTimestamp = startTimestamp;
    if (endTimestamp != null) result.endTimestamp = endTimestamp;
    if (rtpClockTicks != null) result.rtpClockTicks = rtpClockTicks;
    if (driftSamples != null) result.driftSamples = driftSamples;
    if (driftMs != null) result.driftMs = driftMs;
    if (clockRate != null) result.clockRate = clockRate;
    return result;
  }

  RTPDrift._();

  factory RTPDrift.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPDrift()..mergeFromBuffer(data, registry);
  factory RTPDrift.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPDrift()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RTPDrift',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RTPDrift.$_createMessage)
    ..aOM<$1.Timestamp>(1, _omitFieldNames ? '' : 'startTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'endTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aD(3, _omitFieldNames ? '' : 'duration')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'startTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'endTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'rtpClockTicks', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(7, _omitFieldNames ? '' : 'driftSamples')
    ..aD(8, _omitFieldNames ? '' : 'driftMs')
    ..aD(9, _omitFieldNames ? '' : 'clockRate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPDrift clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPDrift copyWith(void Function(RTPDrift) updates) =>
      super.copyWith((message) => updates(message as RTPDrift)) as RTPDrift;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RTPDrift() / RTPDrift.new instead')
  static RTPDrift create() => RTPDrift._();
  static $pb.GeneratedMessage $_createMessage() => RTPDrift._();
  @$core.override
  RTPDrift createEmptyInstance() => RTPDrift._();
  @$core.pragma('dart2js:noInline')
  static RTPDrift getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RTPDrift>(RTPDrift.$_createMessage);
  static RTPDrift? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Timestamp get startTime => $_getN(0);
  @$pb.TagNumber(1)
  set startTime($1.Timestamp value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStartTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartTime() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Timestamp ensureStartTime() => $_ensure(0);

  @$pb.TagNumber(2)
  $1.Timestamp get endTime => $_getN(1);
  @$pb.TagNumber(2)
  set endTime($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEndTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureEndTime() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.double get duration => $_getN(2);
  @$pb.TagNumber(3)
  set duration($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDuration() => $_has(2);
  @$pb.TagNumber(3)
  void clearDuration() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get startTimestamp => $_getI64(3);
  @$pb.TagNumber(4)
  set startTimestamp($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStartTimestamp() => $_has(3);
  @$pb.TagNumber(4)
  void clearStartTimestamp() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get endTimestamp => $_getI64(4);
  @$pb.TagNumber(5)
  set endTimestamp($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEndTimestamp() => $_has(4);
  @$pb.TagNumber(5)
  void clearEndTimestamp() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get rtpClockTicks => $_getI64(5);
  @$pb.TagNumber(6)
  set rtpClockTicks($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRtpClockTicks() => $_has(5);
  @$pb.TagNumber(6)
  void clearRtpClockTicks() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get driftSamples => $_getI64(6);
  @$pb.TagNumber(7)
  set driftSamples($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDriftSamples() => $_has(6);
  @$pb.TagNumber(7)
  void clearDriftSamples() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get driftMs => $_getN(7);
  @$pb.TagNumber(8)
  set driftMs($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDriftMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearDriftMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get clockRate => $_getN(8);
  @$pb.TagNumber(9)
  set clockRate($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasClockRate() => $_has(8);
  @$pb.TagNumber(9)
  void clearClockRate() => $_clearField(9);
}

class RTPStats extends $pb.GeneratedMessage {
  factory RTPStats({
    $1.Timestamp? startTime,
    $1.Timestamp? endTime,
    $core.double? duration,
    $core.int? packets,
    $core.double? packetRate,
    $fixnum.Int64? bytes,
    $core.double? bitrate,
    $core.int? packetsLost,
    $core.double? packetLossRate,
    $core.double? packetLossPercentage,
    $core.int? packetsDuplicate,
    $core.double? packetDuplicateRate,
    $fixnum.Int64? bytesDuplicate,
    $core.double? bitrateDuplicate,
    $core.int? packetsPadding,
    $core.double? packetPaddingRate,
    $fixnum.Int64? bytesPadding,
    $core.double? bitratePadding,
    $core.int? packetsOutOfOrder,
    $core.int? frames,
    $core.double? frameRate,
    $core.double? jitterCurrent,
    $core.double? jitterMax,
    $core.Iterable<$core.MapEntry<$core.int, $core.int>>? gapHistogram,
    $core.int? nacks,
    $core.int? nackMisses,
    $core.int? plis,
    $1.Timestamp? lastPli,
    $core.int? firs,
    $1.Timestamp? lastFir,
    $core.int? rttCurrent,
    $core.int? rttMax,
    $core.int? keyFrames,
    $1.Timestamp? lastKeyFrame,
    $core.int? layerLockPlis,
    $1.Timestamp? lastLayerLockPli,
    $core.int? nackAcks,
    $core.int? nackRepeated,
    $fixnum.Int64? headerBytes,
    $fixnum.Int64? headerBytesDuplicate,
    $fixnum.Int64? headerBytesPadding,
    RTPDrift? packetDrift,
    RTPDrift? ntpReportDrift,
    RTPDrift? rebasedReportDrift,
    RTPDrift? receivedReportDrift,
    $core.int? fecPackets,
    $fixnum.Int64? fecBytes,
    $core.int? fecPacketsDiscarded,
    $core.int? fecPacketsRecovered,
  }) {
    final result = RTPStats._();
    if (startTime != null) result.startTime = startTime;
    if (endTime != null) result.endTime = endTime;
    if (duration != null) result.duration = duration;
    if (packets != null) result.packets = packets;
    if (packetRate != null) result.packetRate = packetRate;
    if (bytes != null) result.bytes = bytes;
    if (bitrate != null) result.bitrate = bitrate;
    if (packetsLost != null) result.packetsLost = packetsLost;
    if (packetLossRate != null) result.packetLossRate = packetLossRate;
    if (packetLossPercentage != null)
      result.packetLossPercentage = packetLossPercentage;
    if (packetsDuplicate != null) result.packetsDuplicate = packetsDuplicate;
    if (packetDuplicateRate != null)
      result.packetDuplicateRate = packetDuplicateRate;
    if (bytesDuplicate != null) result.bytesDuplicate = bytesDuplicate;
    if (bitrateDuplicate != null) result.bitrateDuplicate = bitrateDuplicate;
    if (packetsPadding != null) result.packetsPadding = packetsPadding;
    if (packetPaddingRate != null) result.packetPaddingRate = packetPaddingRate;
    if (bytesPadding != null) result.bytesPadding = bytesPadding;
    if (bitratePadding != null) result.bitratePadding = bitratePadding;
    if (packetsOutOfOrder != null) result.packetsOutOfOrder = packetsOutOfOrder;
    if (frames != null) result.frames = frames;
    if (frameRate != null) result.frameRate = frameRate;
    if (jitterCurrent != null) result.jitterCurrent = jitterCurrent;
    if (jitterMax != null) result.jitterMax = jitterMax;
    if (gapHistogram != null) result.gapHistogram.addEntries(gapHistogram);
    if (nacks != null) result.nacks = nacks;
    if (nackMisses != null) result.nackMisses = nackMisses;
    if (plis != null) result.plis = plis;
    if (lastPli != null) result.lastPli = lastPli;
    if (firs != null) result.firs = firs;
    if (lastFir != null) result.lastFir = lastFir;
    if (rttCurrent != null) result.rttCurrent = rttCurrent;
    if (rttMax != null) result.rttMax = rttMax;
    if (keyFrames != null) result.keyFrames = keyFrames;
    if (lastKeyFrame != null) result.lastKeyFrame = lastKeyFrame;
    if (layerLockPlis != null) result.layerLockPlis = layerLockPlis;
    if (lastLayerLockPli != null) result.lastLayerLockPli = lastLayerLockPli;
    if (nackAcks != null) result.nackAcks = nackAcks;
    if (nackRepeated != null) result.nackRepeated = nackRepeated;
    if (headerBytes != null) result.headerBytes = headerBytes;
    if (headerBytesDuplicate != null)
      result.headerBytesDuplicate = headerBytesDuplicate;
    if (headerBytesPadding != null)
      result.headerBytesPadding = headerBytesPadding;
    if (packetDrift != null) result.packetDrift = packetDrift;
    if (ntpReportDrift != null) result.ntpReportDrift = ntpReportDrift;
    if (rebasedReportDrift != null)
      result.rebasedReportDrift = rebasedReportDrift;
    if (receivedReportDrift != null)
      result.receivedReportDrift = receivedReportDrift;
    if (fecPackets != null) result.fecPackets = fecPackets;
    if (fecBytes != null) result.fecBytes = fecBytes;
    if (fecPacketsDiscarded != null)
      result.fecPacketsDiscarded = fecPacketsDiscarded;
    if (fecPacketsRecovered != null)
      result.fecPacketsRecovered = fecPacketsRecovered;
    return result;
  }

  RTPStats._();

  factory RTPStats.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPStats()..mergeFromBuffer(data, registry);
  factory RTPStats.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPStats()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RTPStats',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RTPStats.$_createMessage)
    ..aOM<$1.Timestamp>(1, _omitFieldNames ? '' : 'startTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aOM<$1.Timestamp>(2, _omitFieldNames ? '' : 'endTime',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aD(3, _omitFieldNames ? '' : 'duration')
    ..aI(4, _omitFieldNames ? '' : 'packets', fieldType: $pb.PbFieldType.OU3)
    ..aD(5, _omitFieldNames ? '' : 'packetRate')
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'bytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(7, _omitFieldNames ? '' : 'bitrate')
    ..aI(8, _omitFieldNames ? '' : 'packetsLost',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(9, _omitFieldNames ? '' : 'packetLossRate')
    ..aD(10, _omitFieldNames ? '' : 'packetLossPercentage',
        fieldType: $pb.PbFieldType.OF)
    ..aI(11, _omitFieldNames ? '' : 'packetsDuplicate',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(12, _omitFieldNames ? '' : 'packetDuplicateRate')
    ..a<$fixnum.Int64>(
        13, _omitFieldNames ? '' : 'bytesDuplicate', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(14, _omitFieldNames ? '' : 'bitrateDuplicate')
    ..aI(15, _omitFieldNames ? '' : 'packetsPadding',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(16, _omitFieldNames ? '' : 'packetPaddingRate')
    ..a<$fixnum.Int64>(
        17, _omitFieldNames ? '' : 'bytesPadding', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(18, _omitFieldNames ? '' : 'bitratePadding')
    ..aI(19, _omitFieldNames ? '' : 'packetsOutOfOrder',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(20, _omitFieldNames ? '' : 'frames', fieldType: $pb.PbFieldType.OU3)
    ..aD(21, _omitFieldNames ? '' : 'frameRate')
    ..aD(22, _omitFieldNames ? '' : 'jitterCurrent')
    ..aD(23, _omitFieldNames ? '' : 'jitterMax')
    ..m<$core.int, $core.int>(24, _omitFieldNames ? '' : 'gapHistogram',
        entryClassName: 'RTPStats.GapHistogramEntry',
        keyFieldType: $pb.PbFieldType.O3,
        valueFieldType: $pb.PbFieldType.OU3,
        packageName: const $pb.PackageName('livekit'))
    ..aI(25, _omitFieldNames ? '' : 'nacks', fieldType: $pb.PbFieldType.OU3)
    ..aI(26, _omitFieldNames ? '' : 'nackMisses',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(27, _omitFieldNames ? '' : 'plis', fieldType: $pb.PbFieldType.OU3)
    ..aOM<$1.Timestamp>(28, _omitFieldNames ? '' : 'lastPli',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(29, _omitFieldNames ? '' : 'firs', fieldType: $pb.PbFieldType.OU3)
    ..aOM<$1.Timestamp>(30, _omitFieldNames ? '' : 'lastFir',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(31, _omitFieldNames ? '' : 'rttCurrent',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(32, _omitFieldNames ? '' : 'rttMax', fieldType: $pb.PbFieldType.OU3)
    ..aI(33, _omitFieldNames ? '' : 'keyFrames', fieldType: $pb.PbFieldType.OU3)
    ..aOM<$1.Timestamp>(34, _omitFieldNames ? '' : 'lastKeyFrame',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(35, _omitFieldNames ? '' : 'layerLockPlis',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<$1.Timestamp>(36, _omitFieldNames ? '' : 'lastLayerLockPli',
        subBuilder: $1.Timestamp.$_createMessage)
    ..aI(37, _omitFieldNames ? '' : 'nackAcks', fieldType: $pb.PbFieldType.OU3)
    ..aI(38, _omitFieldNames ? '' : 'nackRepeated',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        39, _omitFieldNames ? '' : 'headerBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        40, _omitFieldNames ? '' : 'headerBytesDuplicate', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        41, _omitFieldNames ? '' : 'headerBytesPadding', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<RTPDrift>(44, _omitFieldNames ? '' : 'packetDrift',
        subBuilder: RTPDrift.$_createMessage)
    ..aOM<RTPDrift>(45, _omitFieldNames ? '' : 'ntpReportDrift',
        subBuilder: RTPDrift.$_createMessage)
    ..aOM<RTPDrift>(46, _omitFieldNames ? '' : 'rebasedReportDrift',
        subBuilder: RTPDrift.$_createMessage)
    ..aOM<RTPDrift>(47, _omitFieldNames ? '' : 'receivedReportDrift',
        subBuilder: RTPDrift.$_createMessage)
    ..aI(48, _omitFieldNames ? '' : 'fecPackets',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        49, _omitFieldNames ? '' : 'fecBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(50, _omitFieldNames ? '' : 'fecPacketsDiscarded',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(51, _omitFieldNames ? '' : 'fecPacketsRecovered',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPStats clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPStats copyWith(void Function(RTPStats) updates) =>
      super.copyWith((message) => updates(message as RTPStats)) as RTPStats;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RTPStats() / RTPStats.new instead')
  static RTPStats create() => RTPStats._();
  static $pb.GeneratedMessage $_createMessage() => RTPStats._();
  @$core.override
  RTPStats createEmptyInstance() => RTPStats._();
  @$core.pragma('dart2js:noInline')
  static RTPStats getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RTPStats>(RTPStats.$_createMessage);
  static RTPStats? _defaultInstance;

  @$pb.TagNumber(1)
  $1.Timestamp get startTime => $_getN(0);
  @$pb.TagNumber(1)
  set startTime($1.Timestamp value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStartTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartTime() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.Timestamp ensureStartTime() => $_ensure(0);

  @$pb.TagNumber(2)
  $1.Timestamp get endTime => $_getN(1);
  @$pb.TagNumber(2)
  set endTime($1.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEndTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndTime() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.Timestamp ensureEndTime() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.double get duration => $_getN(2);
  @$pb.TagNumber(3)
  set duration($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDuration() => $_has(2);
  @$pb.TagNumber(3)
  void clearDuration() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get packets => $_getIZ(3);
  @$pb.TagNumber(4)
  set packets($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPackets() => $_has(3);
  @$pb.TagNumber(4)
  void clearPackets() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get packetRate => $_getN(4);
  @$pb.TagNumber(5)
  set packetRate($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPacketRate() => $_has(4);
  @$pb.TagNumber(5)
  void clearPacketRate() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get bytes => $_getI64(5);
  @$pb.TagNumber(6)
  set bytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearBytes() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get bitrate => $_getN(6);
  @$pb.TagNumber(7)
  set bitrate($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBitrate() => $_has(6);
  @$pb.TagNumber(7)
  void clearBitrate() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get packetsLost => $_getIZ(7);
  @$pb.TagNumber(8)
  set packetsLost($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasPacketsLost() => $_has(7);
  @$pb.TagNumber(8)
  void clearPacketsLost() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get packetLossRate => $_getN(8);
  @$pb.TagNumber(9)
  set packetLossRate($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPacketLossRate() => $_has(8);
  @$pb.TagNumber(9)
  void clearPacketLossRate() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.double get packetLossPercentage => $_getN(9);
  @$pb.TagNumber(10)
  set packetLossPercentage($core.double value) => $_setFloat(9, value);
  @$pb.TagNumber(10)
  $core.bool hasPacketLossPercentage() => $_has(9);
  @$pb.TagNumber(10)
  void clearPacketLossPercentage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get packetsDuplicate => $_getIZ(10);
  @$pb.TagNumber(11)
  set packetsDuplicate($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasPacketsDuplicate() => $_has(10);
  @$pb.TagNumber(11)
  void clearPacketsDuplicate() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get packetDuplicateRate => $_getN(11);
  @$pb.TagNumber(12)
  set packetDuplicateRate($core.double value) => $_setDouble(11, value);
  @$pb.TagNumber(12)
  $core.bool hasPacketDuplicateRate() => $_has(11);
  @$pb.TagNumber(12)
  void clearPacketDuplicateRate() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get bytesDuplicate => $_getI64(12);
  @$pb.TagNumber(13)
  set bytesDuplicate($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasBytesDuplicate() => $_has(12);
  @$pb.TagNumber(13)
  void clearBytesDuplicate() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.double get bitrateDuplicate => $_getN(13);
  @$pb.TagNumber(14)
  set bitrateDuplicate($core.double value) => $_setDouble(13, value);
  @$pb.TagNumber(14)
  $core.bool hasBitrateDuplicate() => $_has(13);
  @$pb.TagNumber(14)
  void clearBitrateDuplicate() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get packetsPadding => $_getIZ(14);
  @$pb.TagNumber(15)
  set packetsPadding($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasPacketsPadding() => $_has(14);
  @$pb.TagNumber(15)
  void clearPacketsPadding() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.double get packetPaddingRate => $_getN(15);
  @$pb.TagNumber(16)
  set packetPaddingRate($core.double value) => $_setDouble(15, value);
  @$pb.TagNumber(16)
  $core.bool hasPacketPaddingRate() => $_has(15);
  @$pb.TagNumber(16)
  void clearPacketPaddingRate() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get bytesPadding => $_getI64(16);
  @$pb.TagNumber(17)
  set bytesPadding($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasBytesPadding() => $_has(16);
  @$pb.TagNumber(17)
  void clearBytesPadding() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.double get bitratePadding => $_getN(17);
  @$pb.TagNumber(18)
  set bitratePadding($core.double value) => $_setDouble(17, value);
  @$pb.TagNumber(18)
  $core.bool hasBitratePadding() => $_has(17);
  @$pb.TagNumber(18)
  void clearBitratePadding() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.int get packetsOutOfOrder => $_getIZ(18);
  @$pb.TagNumber(19)
  set packetsOutOfOrder($core.int value) => $_setUnsignedInt32(18, value);
  @$pb.TagNumber(19)
  $core.bool hasPacketsOutOfOrder() => $_has(18);
  @$pb.TagNumber(19)
  void clearPacketsOutOfOrder() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.int get frames => $_getIZ(19);
  @$pb.TagNumber(20)
  set frames($core.int value) => $_setUnsignedInt32(19, value);
  @$pb.TagNumber(20)
  $core.bool hasFrames() => $_has(19);
  @$pb.TagNumber(20)
  void clearFrames() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.double get frameRate => $_getN(20);
  @$pb.TagNumber(21)
  set frameRate($core.double value) => $_setDouble(20, value);
  @$pb.TagNumber(21)
  $core.bool hasFrameRate() => $_has(20);
  @$pb.TagNumber(21)
  void clearFrameRate() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.double get jitterCurrent => $_getN(21);
  @$pb.TagNumber(22)
  set jitterCurrent($core.double value) => $_setDouble(21, value);
  @$pb.TagNumber(22)
  $core.bool hasJitterCurrent() => $_has(21);
  @$pb.TagNumber(22)
  void clearJitterCurrent() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.double get jitterMax => $_getN(22);
  @$pb.TagNumber(23)
  set jitterMax($core.double value) => $_setDouble(22, value);
  @$pb.TagNumber(23)
  $core.bool hasJitterMax() => $_has(22);
  @$pb.TagNumber(23)
  void clearJitterMax() => $_clearField(23);

  @$pb.TagNumber(24)
  $pb.PbMap<$core.int, $core.int> get gapHistogram => $_getMap(23);

  @$pb.TagNumber(25)
  $core.int get nacks => $_getIZ(24);
  @$pb.TagNumber(25)
  set nacks($core.int value) => $_setUnsignedInt32(24, value);
  @$pb.TagNumber(25)
  $core.bool hasNacks() => $_has(24);
  @$pb.TagNumber(25)
  void clearNacks() => $_clearField(25);

  @$pb.TagNumber(26)
  $core.int get nackMisses => $_getIZ(25);
  @$pb.TagNumber(26)
  set nackMisses($core.int value) => $_setUnsignedInt32(25, value);
  @$pb.TagNumber(26)
  $core.bool hasNackMisses() => $_has(25);
  @$pb.TagNumber(26)
  void clearNackMisses() => $_clearField(26);

  @$pb.TagNumber(27)
  $core.int get plis => $_getIZ(26);
  @$pb.TagNumber(27)
  set plis($core.int value) => $_setUnsignedInt32(26, value);
  @$pb.TagNumber(27)
  $core.bool hasPlis() => $_has(26);
  @$pb.TagNumber(27)
  void clearPlis() => $_clearField(27);

  @$pb.TagNumber(28)
  $1.Timestamp get lastPli => $_getN(27);
  @$pb.TagNumber(28)
  set lastPli($1.Timestamp value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasLastPli() => $_has(27);
  @$pb.TagNumber(28)
  void clearLastPli() => $_clearField(28);
  @$pb.TagNumber(28)
  $1.Timestamp ensureLastPli() => $_ensure(27);

  @$pb.TagNumber(29)
  $core.int get firs => $_getIZ(28);
  @$pb.TagNumber(29)
  set firs($core.int value) => $_setUnsignedInt32(28, value);
  @$pb.TagNumber(29)
  $core.bool hasFirs() => $_has(28);
  @$pb.TagNumber(29)
  void clearFirs() => $_clearField(29);

  @$pb.TagNumber(30)
  $1.Timestamp get lastFir => $_getN(29);
  @$pb.TagNumber(30)
  set lastFir($1.Timestamp value) => $_setField(30, value);
  @$pb.TagNumber(30)
  $core.bool hasLastFir() => $_has(29);
  @$pb.TagNumber(30)
  void clearLastFir() => $_clearField(30);
  @$pb.TagNumber(30)
  $1.Timestamp ensureLastFir() => $_ensure(29);

  @$pb.TagNumber(31)
  $core.int get rttCurrent => $_getIZ(30);
  @$pb.TagNumber(31)
  set rttCurrent($core.int value) => $_setUnsignedInt32(30, value);
  @$pb.TagNumber(31)
  $core.bool hasRttCurrent() => $_has(30);
  @$pb.TagNumber(31)
  void clearRttCurrent() => $_clearField(31);

  @$pb.TagNumber(32)
  $core.int get rttMax => $_getIZ(31);
  @$pb.TagNumber(32)
  set rttMax($core.int value) => $_setUnsignedInt32(31, value);
  @$pb.TagNumber(32)
  $core.bool hasRttMax() => $_has(31);
  @$pb.TagNumber(32)
  void clearRttMax() => $_clearField(32);

  @$pb.TagNumber(33)
  $core.int get keyFrames => $_getIZ(32);
  @$pb.TagNumber(33)
  set keyFrames($core.int value) => $_setUnsignedInt32(32, value);
  @$pb.TagNumber(33)
  $core.bool hasKeyFrames() => $_has(32);
  @$pb.TagNumber(33)
  void clearKeyFrames() => $_clearField(33);

  @$pb.TagNumber(34)
  $1.Timestamp get lastKeyFrame => $_getN(33);
  @$pb.TagNumber(34)
  set lastKeyFrame($1.Timestamp value) => $_setField(34, value);
  @$pb.TagNumber(34)
  $core.bool hasLastKeyFrame() => $_has(33);
  @$pb.TagNumber(34)
  void clearLastKeyFrame() => $_clearField(34);
  @$pb.TagNumber(34)
  $1.Timestamp ensureLastKeyFrame() => $_ensure(33);

  @$pb.TagNumber(35)
  $core.int get layerLockPlis => $_getIZ(34);
  @$pb.TagNumber(35)
  set layerLockPlis($core.int value) => $_setUnsignedInt32(34, value);
  @$pb.TagNumber(35)
  $core.bool hasLayerLockPlis() => $_has(34);
  @$pb.TagNumber(35)
  void clearLayerLockPlis() => $_clearField(35);

  @$pb.TagNumber(36)
  $1.Timestamp get lastLayerLockPli => $_getN(35);
  @$pb.TagNumber(36)
  set lastLayerLockPli($1.Timestamp value) => $_setField(36, value);
  @$pb.TagNumber(36)
  $core.bool hasLastLayerLockPli() => $_has(35);
  @$pb.TagNumber(36)
  void clearLastLayerLockPli() => $_clearField(36);
  @$pb.TagNumber(36)
  $1.Timestamp ensureLastLayerLockPli() => $_ensure(35);

  @$pb.TagNumber(37)
  $core.int get nackAcks => $_getIZ(36);
  @$pb.TagNumber(37)
  set nackAcks($core.int value) => $_setUnsignedInt32(36, value);
  @$pb.TagNumber(37)
  $core.bool hasNackAcks() => $_has(36);
  @$pb.TagNumber(37)
  void clearNackAcks() => $_clearField(37);

  @$pb.TagNumber(38)
  $core.int get nackRepeated => $_getIZ(37);
  @$pb.TagNumber(38)
  set nackRepeated($core.int value) => $_setUnsignedInt32(37, value);
  @$pb.TagNumber(38)
  $core.bool hasNackRepeated() => $_has(37);
  @$pb.TagNumber(38)
  void clearNackRepeated() => $_clearField(38);

  @$pb.TagNumber(39)
  $fixnum.Int64 get headerBytes => $_getI64(38);
  @$pb.TagNumber(39)
  set headerBytes($fixnum.Int64 value) => $_setInt64(38, value);
  @$pb.TagNumber(39)
  $core.bool hasHeaderBytes() => $_has(38);
  @$pb.TagNumber(39)
  void clearHeaderBytes() => $_clearField(39);

  @$pb.TagNumber(40)
  $fixnum.Int64 get headerBytesDuplicate => $_getI64(39);
  @$pb.TagNumber(40)
  set headerBytesDuplicate($fixnum.Int64 value) => $_setInt64(39, value);
  @$pb.TagNumber(40)
  $core.bool hasHeaderBytesDuplicate() => $_has(39);
  @$pb.TagNumber(40)
  void clearHeaderBytesDuplicate() => $_clearField(40);

  @$pb.TagNumber(41)
  $fixnum.Int64 get headerBytesPadding => $_getI64(40);
  @$pb.TagNumber(41)
  set headerBytesPadding($fixnum.Int64 value) => $_setInt64(40, value);
  @$pb.TagNumber(41)
  $core.bool hasHeaderBytesPadding() => $_has(40);
  @$pb.TagNumber(41)
  void clearHeaderBytesPadding() => $_clearField(41);

  @$pb.TagNumber(44)
  RTPDrift get packetDrift => $_getN(41);
  @$pb.TagNumber(44)
  set packetDrift(RTPDrift value) => $_setField(44, value);
  @$pb.TagNumber(44)
  $core.bool hasPacketDrift() => $_has(41);
  @$pb.TagNumber(44)
  void clearPacketDrift() => $_clearField(44);
  @$pb.TagNumber(44)
  RTPDrift ensurePacketDrift() => $_ensure(41);

  @$pb.TagNumber(45)
  RTPDrift get ntpReportDrift => $_getN(42);
  @$pb.TagNumber(45)
  set ntpReportDrift(RTPDrift value) => $_setField(45, value);
  @$pb.TagNumber(45)
  $core.bool hasNtpReportDrift() => $_has(42);
  @$pb.TagNumber(45)
  void clearNtpReportDrift() => $_clearField(45);
  @$pb.TagNumber(45)
  RTPDrift ensureNtpReportDrift() => $_ensure(42);

  @$pb.TagNumber(46)
  RTPDrift get rebasedReportDrift => $_getN(43);
  @$pb.TagNumber(46)
  set rebasedReportDrift(RTPDrift value) => $_setField(46, value);
  @$pb.TagNumber(46)
  $core.bool hasRebasedReportDrift() => $_has(43);
  @$pb.TagNumber(46)
  void clearRebasedReportDrift() => $_clearField(46);
  @$pb.TagNumber(46)
  RTPDrift ensureRebasedReportDrift() => $_ensure(43);

  @$pb.TagNumber(47)
  RTPDrift get receivedReportDrift => $_getN(44);
  @$pb.TagNumber(47)
  set receivedReportDrift(RTPDrift value) => $_setField(47, value);
  @$pb.TagNumber(47)
  $core.bool hasReceivedReportDrift() => $_has(44);
  @$pb.TagNumber(47)
  void clearReceivedReportDrift() => $_clearField(47);
  @$pb.TagNumber(47)
  RTPDrift ensureReceivedReportDrift() => $_ensure(44);

  @$pb.TagNumber(48)
  $core.int get fecPackets => $_getIZ(45);
  @$pb.TagNumber(48)
  set fecPackets($core.int value) => $_setUnsignedInt32(45, value);
  @$pb.TagNumber(48)
  $core.bool hasFecPackets() => $_has(45);
  @$pb.TagNumber(48)
  void clearFecPackets() => $_clearField(48);

  @$pb.TagNumber(49)
  $fixnum.Int64 get fecBytes => $_getI64(46);
  @$pb.TagNumber(49)
  set fecBytes($fixnum.Int64 value) => $_setInt64(46, value);
  @$pb.TagNumber(49)
  $core.bool hasFecBytes() => $_has(46);
  @$pb.TagNumber(49)
  void clearFecBytes() => $_clearField(49);

  @$pb.TagNumber(50)
  $core.int get fecPacketsDiscarded => $_getIZ(47);
  @$pb.TagNumber(50)
  set fecPacketsDiscarded($core.int value) => $_setUnsignedInt32(47, value);
  @$pb.TagNumber(50)
  $core.bool hasFecPacketsDiscarded() => $_has(47);
  @$pb.TagNumber(50)
  void clearFecPacketsDiscarded() => $_clearField(50);

  @$pb.TagNumber(51)
  $core.int get fecPacketsRecovered => $_getIZ(48);
  @$pb.TagNumber(51)
  set fecPacketsRecovered($core.int value) => $_setUnsignedInt32(48, value);
  @$pb.TagNumber(51)
  $core.bool hasFecPacketsRecovered() => $_has(48);
  @$pb.TagNumber(51)
  void clearFecPacketsRecovered() => $_clearField(51);
}

class RTCPSenderReportState extends $pb.GeneratedMessage {
  factory RTCPSenderReportState({
    $core.int? rtpTimestamp,
    $fixnum.Int64? rtpTimestampExt,
    $fixnum.Int64? ntpTimestamp,
    $fixnum.Int64? at,
    $fixnum.Int64? atAdjusted,
    $core.int? packets,
    $fixnum.Int64? octets,
  }) {
    final result = RTCPSenderReportState._();
    if (rtpTimestamp != null) result.rtpTimestamp = rtpTimestamp;
    if (rtpTimestampExt != null) result.rtpTimestampExt = rtpTimestampExt;
    if (ntpTimestamp != null) result.ntpTimestamp = ntpTimestamp;
    if (at != null) result.at = at;
    if (atAdjusted != null) result.atAdjusted = atAdjusted;
    if (packets != null) result.packets = packets;
    if (octets != null) result.octets = octets;
    return result;
  }

  RTCPSenderReportState._();

  factory RTCPSenderReportState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTCPSenderReportState()..mergeFromBuffer(data, registry);
  factory RTCPSenderReportState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTCPSenderReportState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RTCPSenderReportState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RTCPSenderReportState.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'rtpTimestamp',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'rtpTimestampExt', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'ntpTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(4, _omitFieldNames ? '' : 'at')
    ..aInt64(5, _omitFieldNames ? '' : 'atAdjusted')
    ..aI(6, _omitFieldNames ? '' : 'packets', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'octets', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTCPSenderReportState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTCPSenderReportState copyWith(
          void Function(RTCPSenderReportState) updates) =>
      super.copyWith((message) => updates(message as RTCPSenderReportState))
          as RTCPSenderReportState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RTCPSenderReportState() / RTCPSenderReportState.new instead')
  static RTCPSenderReportState create() => RTCPSenderReportState._();
  static $pb.GeneratedMessage $_createMessage() => RTCPSenderReportState._();
  @$core.override
  RTCPSenderReportState createEmptyInstance() => RTCPSenderReportState._();
  @$core.pragma('dart2js:noInline')
  static RTCPSenderReportState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RTCPSenderReportState>(
          RTCPSenderReportState.$_createMessage);
  static RTCPSenderReportState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get rtpTimestamp => $_getIZ(0);
  @$pb.TagNumber(1)
  set rtpTimestamp($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRtpTimestamp() => $_has(0);
  @$pb.TagNumber(1)
  void clearRtpTimestamp() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get rtpTimestampExt => $_getI64(1);
  @$pb.TagNumber(2)
  set rtpTimestampExt($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRtpTimestampExt() => $_has(1);
  @$pb.TagNumber(2)
  void clearRtpTimestampExt() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get ntpTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set ntpTimestamp($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNtpTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearNtpTimestamp() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get at => $_getI64(3);
  @$pb.TagNumber(4)
  set at($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAt() => $_has(3);
  @$pb.TagNumber(4)
  void clearAt() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get atAdjusted => $_getI64(4);
  @$pb.TagNumber(5)
  set atAdjusted($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAtAdjusted() => $_has(4);
  @$pb.TagNumber(5)
  void clearAtAdjusted() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get packets => $_getIZ(5);
  @$pb.TagNumber(6)
  set packets($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPackets() => $_has(5);
  @$pb.TagNumber(6)
  void clearPackets() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get octets => $_getI64(6);
  @$pb.TagNumber(7)
  set octets($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasOctets() => $_has(6);
  @$pb.TagNumber(7)
  void clearOctets() => $_clearField(7);
}

enum RTPForwarderState_CodecMunger { vp8Munger, notSet }

class RTPForwarderState extends $pb.GeneratedMessage {
  factory RTPForwarderState({
    $core.bool? started,
    $core.int? referenceLayerSpatial,
    $fixnum.Int64? preStartTime,
    $fixnum.Int64? extFirstTimestamp,
    $fixnum.Int64? dummyStartTimestampOffset,
    RTPMungerState? rtpMunger,
    VP8MungerState? vp8Munger,
    $core.Iterable<RTCPSenderReportState>? senderReportState,
    DependencyDescriptorForwarderState? dependencyDescriptorForwarder,
  }) {
    final result = RTPForwarderState._();
    if (started != null) result.started = started;
    if (referenceLayerSpatial != null)
      result.referenceLayerSpatial = referenceLayerSpatial;
    if (preStartTime != null) result.preStartTime = preStartTime;
    if (extFirstTimestamp != null) result.extFirstTimestamp = extFirstTimestamp;
    if (dummyStartTimestampOffset != null)
      result.dummyStartTimestampOffset = dummyStartTimestampOffset;
    if (rtpMunger != null) result.rtpMunger = rtpMunger;
    if (vp8Munger != null) result.vp8Munger = vp8Munger;
    if (senderReportState != null)
      result.senderReportState.addAll(senderReportState);
    if (dependencyDescriptorForwarder != null)
      result.dependencyDescriptorForwarder = dependencyDescriptorForwarder;
    return result;
  }

  RTPForwarderState._();

  factory RTPForwarderState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPForwarderState()..mergeFromBuffer(data, registry);
  factory RTPForwarderState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPForwarderState()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, RTPForwarderState_CodecMunger>
      _RTPForwarderState_CodecMungerByTag = {
    7: RTPForwarderState_CodecMunger.vp8Munger,
    0: RTPForwarderState_CodecMunger.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RTPForwarderState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RTPForwarderState.$_createMessage)
    ..oo(0, [7])
    ..aOB(1, _omitFieldNames ? '' : 'started')
    ..aI(2, _omitFieldNames ? '' : 'referenceLayerSpatial')
    ..aInt64(3, _omitFieldNames ? '' : 'preStartTime')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'extFirstTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'dummyStartTimestampOffset',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<RTPMungerState>(6, _omitFieldNames ? '' : 'rtpMunger',
        subBuilder: RTPMungerState.$_createMessage)
    ..aOM<VP8MungerState>(7, _omitFieldNames ? '' : 'vp8Munger',
        subBuilder: VP8MungerState.$_createMessage)
    ..pPM<RTCPSenderReportState>(8, _omitFieldNames ? '' : 'senderReportState',
        subBuilder: RTCPSenderReportState.$_createMessage)
    ..aOM<DependencyDescriptorForwarderState>(
        9, _omitFieldNames ? '' : 'dependencyDescriptorForwarder',
        subBuilder: DependencyDescriptorForwarderState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPForwarderState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPForwarderState copyWith(void Function(RTPForwarderState) updates) =>
      super.copyWith((message) => updates(message as RTPForwarderState))
          as RTPForwarderState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RTPForwarderState() / RTPForwarderState.new instead')
  static RTPForwarderState create() => RTPForwarderState._();
  static $pb.GeneratedMessage $_createMessage() => RTPForwarderState._();
  @$core.override
  RTPForwarderState createEmptyInstance() => RTPForwarderState._();
  @$core.pragma('dart2js:noInline')
  static RTPForwarderState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RTPForwarderState>(
          RTPForwarderState.$_createMessage);
  static RTPForwarderState? _defaultInstance;

  @$pb.TagNumber(7)
  RTPForwarderState_CodecMunger whichCodecMunger() =>
      _RTPForwarderState_CodecMungerByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(7)
  void clearCodecMunger() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.bool get started => $_getBF(0);
  @$pb.TagNumber(1)
  set started($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStarted() => $_has(0);
  @$pb.TagNumber(1)
  void clearStarted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get referenceLayerSpatial => $_getIZ(1);
  @$pb.TagNumber(2)
  set referenceLayerSpatial($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReferenceLayerSpatial() => $_has(1);
  @$pb.TagNumber(2)
  void clearReferenceLayerSpatial() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get preStartTime => $_getI64(2);
  @$pb.TagNumber(3)
  set preStartTime($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPreStartTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearPreStartTime() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get extFirstTimestamp => $_getI64(3);
  @$pb.TagNumber(4)
  set extFirstTimestamp($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExtFirstTimestamp() => $_has(3);
  @$pb.TagNumber(4)
  void clearExtFirstTimestamp() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get dummyStartTimestampOffset => $_getI64(4);
  @$pb.TagNumber(5)
  set dummyStartTimestampOffset($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDummyStartTimestampOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearDummyStartTimestampOffset() => $_clearField(5);

  @$pb.TagNumber(6)
  RTPMungerState get rtpMunger => $_getN(5);
  @$pb.TagNumber(6)
  set rtpMunger(RTPMungerState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasRtpMunger() => $_has(5);
  @$pb.TagNumber(6)
  void clearRtpMunger() => $_clearField(6);
  @$pb.TagNumber(6)
  RTPMungerState ensureRtpMunger() => $_ensure(5);

  @$pb.TagNumber(7)
  VP8MungerState get vp8Munger => $_getN(6);
  @$pb.TagNumber(7)
  set vp8Munger(VP8MungerState value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasVp8Munger() => $_has(6);
  @$pb.TagNumber(7)
  void clearVp8Munger() => $_clearField(7);
  @$pb.TagNumber(7)
  VP8MungerState ensureVp8Munger() => $_ensure(6);

  @$pb.TagNumber(8)
  $pb.PbList<RTCPSenderReportState> get senderReportState => $_getList(7);

  @$pb.TagNumber(9)
  DependencyDescriptorForwarderState get dependencyDescriptorForwarder =>
      $_getN(8);
  @$pb.TagNumber(9)
  set dependencyDescriptorForwarder(DependencyDescriptorForwarderState value) =>
      $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasDependencyDescriptorForwarder() => $_has(8);
  @$pb.TagNumber(9)
  void clearDependencyDescriptorForwarder() => $_clearField(9);
  @$pb.TagNumber(9)
  DependencyDescriptorForwarderState ensureDependencyDescriptorForwarder() =>
      $_ensure(8);
}

/// State of a forwarder that writes the dependency descriptor for the subscriber, so
/// its frame numbers continue on a migrated subscriber.
class DependencyDescriptorForwarderState extends $pb.GeneratedMessage {
  factory DependencyDescriptorForwarderState({
    $fixnum.Int64? extLastFrameNumber,
  }) {
    final result = DependencyDescriptorForwarderState._();
    if (extLastFrameNumber != null)
      result.extLastFrameNumber = extLastFrameNumber;
    return result;
  }

  DependencyDescriptorForwarderState._();

  factory DependencyDescriptorForwarderState.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DependencyDescriptorForwarderState()..mergeFromBuffer(data, registry);
  factory DependencyDescriptorForwarderState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DependencyDescriptorForwarderState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DependencyDescriptorForwarderState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DependencyDescriptorForwarderState.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'extLastFrameNumber', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DependencyDescriptorForwarderState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DependencyDescriptorForwarderState copyWith(
          void Function(DependencyDescriptorForwarderState) updates) =>
      super.copyWith((message) =>
              updates(message as DependencyDescriptorForwarderState))
          as DependencyDescriptorForwarderState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DependencyDescriptorForwarderState() / DependencyDescriptorForwarderState.new instead')
  static DependencyDescriptorForwarderState create() =>
      DependencyDescriptorForwarderState._();
  static $pb.GeneratedMessage $_createMessage() =>
      DependencyDescriptorForwarderState._();
  @$core.override
  DependencyDescriptorForwarderState createEmptyInstance() =>
      DependencyDescriptorForwarderState._();
  @$core.pragma('dart2js:noInline')
  static DependencyDescriptorForwarderState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DependencyDescriptorForwarderState>(
          DependencyDescriptorForwarderState.$_createMessage);
  static DependencyDescriptorForwarderState? _defaultInstance;

  /// highest extended frame number sent to the subscriber
  @$pb.TagNumber(1)
  $fixnum.Int64 get extLastFrameNumber => $_getI64(0);
  @$pb.TagNumber(1)
  set extLastFrameNumber($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasExtLastFrameNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearExtLastFrameNumber() => $_clearField(1);
}

class RTPMungerState extends $pb.GeneratedMessage {
  factory RTPMungerState({
    $fixnum.Int64? extLastSequenceNumber,
    $fixnum.Int64? extSecondLastSequenceNumber,
    $fixnum.Int64? extLastTimestamp,
    $fixnum.Int64? extSecondLastTimestamp,
    $core.bool? lastMarker,
    $core.bool? secondLastMarker,
  }) {
    final result = RTPMungerState._();
    if (extLastSequenceNumber != null)
      result.extLastSequenceNumber = extLastSequenceNumber;
    if (extSecondLastSequenceNumber != null)
      result.extSecondLastSequenceNumber = extSecondLastSequenceNumber;
    if (extLastTimestamp != null) result.extLastTimestamp = extLastTimestamp;
    if (extSecondLastTimestamp != null)
      result.extSecondLastTimestamp = extSecondLastTimestamp;
    if (lastMarker != null) result.lastMarker = lastMarker;
    if (secondLastMarker != null) result.secondLastMarker = secondLastMarker;
    return result;
  }

  RTPMungerState._();

  factory RTPMungerState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPMungerState()..mergeFromBuffer(data, registry);
  factory RTPMungerState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RTPMungerState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RTPMungerState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: RTPMungerState.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'extLastSequenceNumber', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'extSecondLastSequenceNumber',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'extLastTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'extSecondLastTimestamp', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(5, _omitFieldNames ? '' : 'lastMarker')
    ..aOB(6, _omitFieldNames ? '' : 'secondLastMarker')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPMungerState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RTPMungerState copyWith(void Function(RTPMungerState) updates) =>
      super.copyWith((message) => updates(message as RTPMungerState))
          as RTPMungerState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RTPMungerState() / RTPMungerState.new instead')
  static RTPMungerState create() => RTPMungerState._();
  static $pb.GeneratedMessage $_createMessage() => RTPMungerState._();
  @$core.override
  RTPMungerState createEmptyInstance() => RTPMungerState._();
  @$core.pragma('dart2js:noInline')
  static RTPMungerState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RTPMungerState>(
          RTPMungerState.$_createMessage);
  static RTPMungerState? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get extLastSequenceNumber => $_getI64(0);
  @$pb.TagNumber(1)
  set extLastSequenceNumber($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasExtLastSequenceNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearExtLastSequenceNumber() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get extSecondLastSequenceNumber => $_getI64(1);
  @$pb.TagNumber(2)
  set extSecondLastSequenceNumber($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExtSecondLastSequenceNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearExtSecondLastSequenceNumber() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get extLastTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set extLastTimestamp($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExtLastTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearExtLastTimestamp() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get extSecondLastTimestamp => $_getI64(3);
  @$pb.TagNumber(4)
  set extSecondLastTimestamp($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExtSecondLastTimestamp() => $_has(3);
  @$pb.TagNumber(4)
  void clearExtSecondLastTimestamp() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get lastMarker => $_getBF(4);
  @$pb.TagNumber(5)
  set lastMarker($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLastMarker() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastMarker() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get secondLastMarker => $_getBF(5);
  @$pb.TagNumber(6)
  set secondLastMarker($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSecondLastMarker() => $_has(5);
  @$pb.TagNumber(6)
  void clearSecondLastMarker() => $_clearField(6);
}

class VP8MungerState extends $pb.GeneratedMessage {
  factory VP8MungerState({
    $core.int? extLastPictureId,
    $core.bool? pictureIdUsed,
    $core.int? lastTl0PicIdx,
    $core.bool? tl0PicIdxUsed,
    $core.bool? tidUsed,
    $core.int? lastKeyIdx,
    $core.bool? keyIdxUsed,
  }) {
    final result = VP8MungerState._();
    if (extLastPictureId != null) result.extLastPictureId = extLastPictureId;
    if (pictureIdUsed != null) result.pictureIdUsed = pictureIdUsed;
    if (lastTl0PicIdx != null) result.lastTl0PicIdx = lastTl0PicIdx;
    if (tl0PicIdxUsed != null) result.tl0PicIdxUsed = tl0PicIdxUsed;
    if (tidUsed != null) result.tidUsed = tidUsed;
    if (lastKeyIdx != null) result.lastKeyIdx = lastKeyIdx;
    if (keyIdxUsed != null) result.keyIdxUsed = keyIdxUsed;
    return result;
  }

  VP8MungerState._();

  factory VP8MungerState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VP8MungerState()..mergeFromBuffer(data, registry);
  factory VP8MungerState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      VP8MungerState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VP8MungerState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: VP8MungerState.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'extLastPictureId')
    ..aOB(2, _omitFieldNames ? '' : 'pictureIdUsed')
    ..aI(3, _omitFieldNames ? '' : 'lastTl0PicIdx',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'tl0PicIdxUsed')
    ..aOB(5, _omitFieldNames ? '' : 'tidUsed')
    ..aI(6, _omitFieldNames ? '' : 'lastKeyIdx', fieldType: $pb.PbFieldType.OU3)
    ..aOB(7, _omitFieldNames ? '' : 'keyIdxUsed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VP8MungerState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VP8MungerState copyWith(void Function(VP8MungerState) updates) =>
      super.copyWith((message) => updates(message as VP8MungerState))
          as VP8MungerState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use VP8MungerState() / VP8MungerState.new instead')
  static VP8MungerState create() => VP8MungerState._();
  static $pb.GeneratedMessage $_createMessage() => VP8MungerState._();
  @$core.override
  VP8MungerState createEmptyInstance() => VP8MungerState._();
  @$core.pragma('dart2js:noInline')
  static VP8MungerState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VP8MungerState>(
          VP8MungerState.$_createMessage);
  static VP8MungerState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get extLastPictureId => $_getIZ(0);
  @$pb.TagNumber(1)
  set extLastPictureId($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasExtLastPictureId() => $_has(0);
  @$pb.TagNumber(1)
  void clearExtLastPictureId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get pictureIdUsed => $_getBF(1);
  @$pb.TagNumber(2)
  set pictureIdUsed($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPictureIdUsed() => $_has(1);
  @$pb.TagNumber(2)
  void clearPictureIdUsed() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get lastTl0PicIdx => $_getIZ(2);
  @$pb.TagNumber(3)
  set lastTl0PicIdx($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLastTl0PicIdx() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastTl0PicIdx() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get tl0PicIdxUsed => $_getBF(3);
  @$pb.TagNumber(4)
  set tl0PicIdxUsed($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTl0PicIdxUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearTl0PicIdxUsed() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get tidUsed => $_getBF(4);
  @$pb.TagNumber(5)
  set tidUsed($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTidUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearTidUsed() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get lastKeyIdx => $_getIZ(5);
  @$pb.TagNumber(6)
  set lastKeyIdx($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLastKeyIdx() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastKeyIdx() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get keyIdxUsed => $_getBF(6);
  @$pb.TagNumber(7)
  set keyIdxUsed($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasKeyIdxUsed() => $_has(6);
  @$pb.TagNumber(7)
  void clearKeyIdxUsed() => $_clearField(7);
}

class TimedVersion extends $pb.GeneratedMessage {
  factory TimedVersion({
    $fixnum.Int64? unixMicro,
    $core.int? ticks,
  }) {
    final result = TimedVersion._();
    if (unixMicro != null) result.unixMicro = unixMicro;
    if (ticks != null) result.ticks = ticks;
    return result;
  }

  TimedVersion._();

  factory TimedVersion.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimedVersion()..mergeFromBuffer(data, registry);
  factory TimedVersion.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TimedVersion()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimedVersion',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: TimedVersion.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'unixMicro')
    ..aI(2, _omitFieldNames ? '' : 'ticks')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimedVersion clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimedVersion copyWith(void Function(TimedVersion) updates) =>
      super.copyWith((message) => updates(message as TimedVersion))
          as TimedVersion;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TimedVersion() / TimedVersion.new instead')
  static TimedVersion create() => TimedVersion._();
  static $pb.GeneratedMessage $_createMessage() => TimedVersion._();
  @$core.override
  TimedVersion createEmptyInstance() => TimedVersion._();
  @$core.pragma('dart2js:noInline')
  static TimedVersion getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TimedVersion>(
          TimedVersion.$_createMessage);
  static TimedVersion? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get unixMicro => $_getI64(0);
  @$pb.TagNumber(1)
  set unixMicro($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUnixMicro() => $_has(0);
  @$pb.TagNumber(1)
  void clearUnixMicro() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get ticks => $_getIZ(1);
  @$pb.TagNumber(2)
  set ticks($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTicks() => $_has(1);
  @$pb.TagNumber(2)
  void clearTicks() => $_clearField(2);
}

/// header properties specific to text streams
class DataStream_TextHeader extends $pb.GeneratedMessage {
  factory DataStream_TextHeader({
    DataStream_OperationType? operationType,
    $core.int? version,
    $core.String? replyToStreamId,
    $core.Iterable<$core.String>? attachedStreamIds,
    $core.bool? generated,
  }) {
    final result = DataStream_TextHeader._();
    if (operationType != null) result.operationType = operationType;
    if (version != null) result.version = version;
    if (replyToStreamId != null) result.replyToStreamId = replyToStreamId;
    if (attachedStreamIds != null)
      result.attachedStreamIds.addAll(attachedStreamIds);
    if (generated != null) result.generated = generated;
    return result;
  }

  DataStream_TextHeader._();

  factory DataStream_TextHeader.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_TextHeader()..mergeFromBuffer(data, registry);
  factory DataStream_TextHeader.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_TextHeader()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream.TextHeader',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream_TextHeader.$_createMessage)
    ..aE<DataStream_OperationType>(1, _omitFieldNames ? '' : 'operationType',
        enumValues: DataStream_OperationType.values)
    ..aI(2, _omitFieldNames ? '' : 'version')
    ..aOS(3, _omitFieldNames ? '' : 'replyToStreamId')
    ..pPS(4, _omitFieldNames ? '' : 'attachedStreamIds')
    ..aOB(5, _omitFieldNames ? '' : 'generated')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_TextHeader clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_TextHeader copyWith(
          void Function(DataStream_TextHeader) updates) =>
      super.copyWith((message) => updates(message as DataStream_TextHeader))
          as DataStream_TextHeader;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataStream_TextHeader() / DataStream_TextHeader.new instead')
  static DataStream_TextHeader create() => DataStream_TextHeader._();
  static $pb.GeneratedMessage $_createMessage() => DataStream_TextHeader._();
  @$core.override
  DataStream_TextHeader createEmptyInstance() => DataStream_TextHeader._();
  @$core.pragma('dart2js:noInline')
  static DataStream_TextHeader getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataStream_TextHeader>(
          DataStream_TextHeader.$_createMessage);
  static DataStream_TextHeader? _defaultInstance;

  @$pb.TagNumber(1)
  DataStream_OperationType get operationType => $_getN(0);
  @$pb.TagNumber(1)
  set operationType(DataStream_OperationType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationType() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get version => $_getIZ(1);
  @$pb.TagNumber(2)
  set version($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get replyToStreamId => $_getSZ(2);
  @$pb.TagNumber(3)
  set replyToStreamId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReplyToStreamId() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplyToStreamId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get attachedStreamIds => $_getList(3);

  @$pb.TagNumber(5)
  $core.bool get generated => $_getBF(4);
  @$pb.TagNumber(5)
  set generated($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGenerated() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerated() => $_clearField(5);
}

/// header properties specific to byte or file streams
class DataStream_ByteHeader extends $pb.GeneratedMessage {
  factory DataStream_ByteHeader({
    $core.String? name,
  }) {
    final result = DataStream_ByteHeader._();
    if (name != null) result.name = name;
    return result;
  }

  DataStream_ByteHeader._();

  factory DataStream_ByteHeader.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_ByteHeader()..mergeFromBuffer(data, registry);
  factory DataStream_ByteHeader.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_ByteHeader()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream.ByteHeader',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream_ByteHeader.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_ByteHeader clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_ByteHeader copyWith(
          void Function(DataStream_ByteHeader) updates) =>
      super.copyWith((message) => updates(message as DataStream_ByteHeader))
          as DataStream_ByteHeader;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use DataStream_ByteHeader() / DataStream_ByteHeader.new instead')
  static DataStream_ByteHeader create() => DataStream_ByteHeader._();
  static $pb.GeneratedMessage $_createMessage() => DataStream_ByteHeader._();
  @$core.override
  DataStream_ByteHeader createEmptyInstance() => DataStream_ByteHeader._();
  @$core.pragma('dart2js:noInline')
  static DataStream_ByteHeader getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataStream_ByteHeader>(
          DataStream_ByteHeader.$_createMessage);
  static DataStream_ByteHeader? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);
}

enum DataStream_Header_ContentHeader { textHeader, byteHeader, notSet }

/// main DataStream.Header that contains a oneof for specific headers
class DataStream_Header extends $pb.GeneratedMessage {
  factory DataStream_Header({
    $core.String? streamId,
    $fixnum.Int64? timestamp,
    $core.String? topic,
    $core.String? mimeType,
    $fixnum.Int64? totalLength,
    @$core.Deprecated('This field is deprecated.')
    Encryption_Type? encryptionType,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? attributes,
    DataStream_TextHeader? textHeader,
    DataStream_ByteHeader? byteHeader,
    $core.List<$core.int>? inlineContent,
    DataStream_CompressionType? compression,
  }) {
    final result = DataStream_Header._();
    if (streamId != null) result.streamId = streamId;
    if (timestamp != null) result.timestamp = timestamp;
    if (topic != null) result.topic = topic;
    if (mimeType != null) result.mimeType = mimeType;
    if (totalLength != null) result.totalLength = totalLength;
    if (encryptionType != null) result.encryptionType = encryptionType;
    if (attributes != null) result.attributes.addEntries(attributes);
    if (textHeader != null) result.textHeader = textHeader;
    if (byteHeader != null) result.byteHeader = byteHeader;
    if (inlineContent != null) result.inlineContent = inlineContent;
    if (compression != null) result.compression = compression;
    return result;
  }

  DataStream_Header._();

  factory DataStream_Header.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Header()..mergeFromBuffer(data, registry);
  factory DataStream_Header.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Header()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DataStream_Header_ContentHeader>
      _DataStream_Header_ContentHeaderByTag = {
    9: DataStream_Header_ContentHeader.textHeader,
    10: DataStream_Header_ContentHeader.byteHeader,
    0: DataStream_Header_ContentHeader.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream.Header',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream_Header.$_createMessage)
    ..oo(0, [9, 10])
    ..aOS(1, _omitFieldNames ? '' : 'streamId')
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..aOS(3, _omitFieldNames ? '' : 'topic')
    ..aOS(4, _omitFieldNames ? '' : 'mimeType')
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'totalLength', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aE<Encryption_Type>(7, _omitFieldNames ? '' : 'encryptionType',
        enumValues: Encryption_Type.values)
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'attributes',
        entryClassName: 'DataStream.Header.AttributesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('livekit'))
    ..aOM<DataStream_TextHeader>(9, _omitFieldNames ? '' : 'textHeader',
        subBuilder: DataStream_TextHeader.$_createMessage)
    ..aOM<DataStream_ByteHeader>(10, _omitFieldNames ? '' : 'byteHeader',
        subBuilder: DataStream_ByteHeader.$_createMessage)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'inlineContent', $pb.PbFieldType.OY)
    ..aE<DataStream_CompressionType>(12, _omitFieldNames ? '' : 'compression',
        enumValues: DataStream_CompressionType.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Header clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Header copyWith(void Function(DataStream_Header) updates) =>
      super.copyWith((message) => updates(message as DataStream_Header))
          as DataStream_Header;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataStream_Header() / DataStream_Header.new instead')
  static DataStream_Header create() => DataStream_Header._();
  static $pb.GeneratedMessage $_createMessage() => DataStream_Header._();
  @$core.override
  DataStream_Header createEmptyInstance() => DataStream_Header._();
  @$core.pragma('dart2js:noInline')
  static DataStream_Header getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataStream_Header>(
          DataStream_Header.$_createMessage);
  static DataStream_Header? _defaultInstance;

  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  DataStream_Header_ContentHeader whichContentHeader() =>
      _DataStream_Header_ContentHeaderByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  void clearContentHeader() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get streamId => $_getSZ(0);
  @$pb.TagNumber(1)
  set streamId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStreamId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStreamId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get topic => $_getSZ(2);
  @$pb.TagNumber(3)
  set topic($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTopic() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopic() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get mimeType => $_getSZ(3);
  @$pb.TagNumber(4)
  set mimeType($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMimeType() => $_has(3);
  @$pb.TagNumber(4)
  void clearMimeType() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalLength => $_getI64(4);
  @$pb.TagNumber(5)
  set totalLength($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalLength() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalLength() => $_clearField(5);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  Encryption_Type get encryptionType => $_getN(5);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  set encryptionType(Encryption_Type value) => $_setField(7, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  $core.bool hasEncryptionType() => $_has(5);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(7)
  void clearEncryptionType() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbMap<$core.String, $core.String> get attributes => $_getMap(6);

  @$pb.TagNumber(9)
  DataStream_TextHeader get textHeader => $_getN(7);
  @$pb.TagNumber(9)
  set textHeader(DataStream_TextHeader value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasTextHeader() => $_has(7);
  @$pb.TagNumber(9)
  void clearTextHeader() => $_clearField(9);
  @$pb.TagNumber(9)
  DataStream_TextHeader ensureTextHeader() => $_ensure(7);

  @$pb.TagNumber(10)
  DataStream_ByteHeader get byteHeader => $_getN(8);
  @$pb.TagNumber(10)
  set byteHeader(DataStream_ByteHeader value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasByteHeader() => $_has(8);
  @$pb.TagNumber(10)
  void clearByteHeader() => $_clearField(10);
  @$pb.TagNumber(10)
  DataStream_ByteHeader ensureByteHeader() => $_ensure(8);

  /// Optional inline content so that a data stream can be sent as a single packet for short payloads.
  @$pb.TagNumber(11)
  $core.List<$core.int> get inlineContent => $_getN(9);
  @$pb.TagNumber(11)
  set inlineContent($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(11)
  $core.bool hasInlineContent() => $_has(9);
  @$pb.TagNumber(11)
  void clearInlineContent() => $_clearField(11);

  @$pb.TagNumber(12)
  DataStream_CompressionType get compression => $_getN(10);
  @$pb.TagNumber(12)
  set compression(DataStream_CompressionType value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasCompression() => $_has(10);
  @$pb.TagNumber(12)
  void clearCompression() => $_clearField(12);
}

class DataStream_Chunk extends $pb.GeneratedMessage {
  factory DataStream_Chunk({
    $core.String? streamId,
    $fixnum.Int64? chunkIndex,
    $core.List<$core.int>? content,
    $core.int? version,
    @$core.Deprecated('This field is deprecated.') $core.List<$core.int>? iv,
  }) {
    final result = DataStream_Chunk._();
    if (streamId != null) result.streamId = streamId;
    if (chunkIndex != null) result.chunkIndex = chunkIndex;
    if (content != null) result.content = content;
    if (version != null) result.version = version;
    if (iv != null) result.iv = iv;
    return result;
  }

  DataStream_Chunk._();

  factory DataStream_Chunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Chunk()..mergeFromBuffer(data, registry);
  factory DataStream_Chunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Chunk()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream.Chunk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream_Chunk.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'streamId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..aI(4, _omitFieldNames ? '' : 'version')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'iv', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Chunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Chunk copyWith(void Function(DataStream_Chunk) updates) =>
      super.copyWith((message) => updates(message as DataStream_Chunk))
          as DataStream_Chunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataStream_Chunk() / DataStream_Chunk.new instead')
  static DataStream_Chunk create() => DataStream_Chunk._();
  static $pb.GeneratedMessage $_createMessage() => DataStream_Chunk._();
  @$core.override
  DataStream_Chunk createEmptyInstance() => DataStream_Chunk._();
  @$core.pragma('dart2js:noInline')
  static DataStream_Chunk getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DataStream_Chunk>(
          DataStream_Chunk.$_createMessage);
  static DataStream_Chunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get streamId => $_getSZ(0);
  @$pb.TagNumber(1)
  set streamId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStreamId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStreamId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get chunkIndex => $_getI64(1);
  @$pb.TagNumber(2)
  set chunkIndex($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChunkIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearChunkIndex() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get content => $_getN(2);
  @$pb.TagNumber(3)
  set content($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearContent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get version => $_getIZ(3);
  @$pb.TagNumber(4)
  set version($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearVersion() => $_clearField(4);

  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  $core.List<$core.int> get iv => $_getN(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  set iv($core.List<$core.int> value) => $_setBytes(4, value);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  $core.bool hasIv() => $_has(4);
  @$core.Deprecated('This field is deprecated.')
  @$pb.TagNumber(5)
  void clearIv() => $_clearField(5);
}

class DataStream_Trailer extends $pb.GeneratedMessage {
  factory DataStream_Trailer({
    $core.String? streamId,
    $core.String? reason,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? attributes,
  }) {
    final result = DataStream_Trailer._();
    if (streamId != null) result.streamId = streamId;
    if (reason != null) result.reason = reason;
    if (attributes != null) result.attributes.addEntries(attributes);
    return result;
  }

  DataStream_Trailer._();

  factory DataStream_Trailer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Trailer()..mergeFromBuffer(data, registry);
  factory DataStream_Trailer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream_Trailer()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream.Trailer',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream_Trailer.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'streamId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'attributes',
        entryClassName: 'DataStream.Trailer.AttributesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('livekit'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Trailer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream_Trailer copyWith(void Function(DataStream_Trailer) updates) =>
      super.copyWith((message) => updates(message as DataStream_Trailer))
          as DataStream_Trailer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataStream_Trailer() / DataStream_Trailer.new instead')
  static DataStream_Trailer create() => DataStream_Trailer._();
  static $pb.GeneratedMessage $_createMessage() => DataStream_Trailer._();
  @$core.override
  DataStream_Trailer createEmptyInstance() => DataStream_Trailer._();
  @$core.pragma('dart2js:noInline')
  static DataStream_Trailer getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataStream_Trailer>(
          DataStream_Trailer.$_createMessage);
  static DataStream_Trailer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get streamId => $_getSZ(0);
  @$pb.TagNumber(1)
  set streamId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStreamId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStreamId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get attributes => $_getMap(2);
}

class DataStream extends $pb.GeneratedMessage {
  factory DataStream() => DataStream._();

  DataStream._();

  factory DataStream.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream()..mergeFromBuffer(data, registry);
  factory DataStream.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DataStream()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataStream',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: DataStream.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataStream copyWith(void Function(DataStream) updates) =>
      super.copyWith((message) => updates(message as DataStream)) as DataStream;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DataStream() / DataStream.new instead')
  static DataStream create() => DataStream._();
  static $pb.GeneratedMessage $_createMessage() => DataStream._();
  @$core.override
  DataStream createEmptyInstance() => DataStream._();
  @$core.pragma('dart2js:noInline')
  static DataStream getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataStream>(DataStream.$_createMessage);
  static DataStream? _defaultInstance;
}

class FilterParams extends $pb.GeneratedMessage {
  factory FilterParams({
    $core.Iterable<$core.String>? includeEvents,
    $core.Iterable<$core.String>? excludeEvents,
  }) {
    final result = FilterParams._();
    if (includeEvents != null) result.includeEvents.addAll(includeEvents);
    if (excludeEvents != null) result.excludeEvents.addAll(excludeEvents);
    return result;
  }

  FilterParams._();

  factory FilterParams.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterParams()..mergeFromBuffer(data, registry);
  factory FilterParams.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterParams()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterParams',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: FilterParams.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'includeEvents')
    ..pPS(2, _omitFieldNames ? '' : 'excludeEvents')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterParams clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterParams copyWith(void Function(FilterParams) updates) =>
      super.copyWith((message) => updates(message as FilterParams))
          as FilterParams;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterParams() / FilterParams.new instead')
  static FilterParams create() => FilterParams._();
  static $pb.GeneratedMessage $_createMessage() => FilterParams._();
  @$core.override
  FilterParams createEmptyInstance() => FilterParams._();
  @$core.pragma('dart2js:noInline')
  static FilterParams getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterParams>(
          FilterParams.$_createMessage);
  static FilterParams? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get includeEvents => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get excludeEvents => $_getList(1);
}

class WebhookConfig extends $pb.GeneratedMessage {
  factory WebhookConfig({
    $core.String? url,
    $core.String? signingKey,
    FilterParams? filterParams,
  }) {
    final result = WebhookConfig._();
    if (url != null) result.url = url;
    if (signingKey != null) result.signingKey = signingKey;
    if (filterParams != null) result.filterParams = filterParams;
    return result;
  }

  WebhookConfig._();

  factory WebhookConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WebhookConfig()..mergeFromBuffer(data, registry);
  factory WebhookConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WebhookConfig()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WebhookConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: WebhookConfig.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'signingKey')
    ..aOM<FilterParams>(3, _omitFieldNames ? '' : 'filterParams',
        subBuilder: FilterParams.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebhookConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebhookConfig copyWith(void Function(WebhookConfig) updates) =>
      super.copyWith((message) => updates(message as WebhookConfig))
          as WebhookConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WebhookConfig() / WebhookConfig.new instead')
  static WebhookConfig create() => WebhookConfig._();
  static $pb.GeneratedMessage $_createMessage() => WebhookConfig._();
  @$core.override
  WebhookConfig createEmptyInstance() => WebhookConfig._();
  @$core.pragma('dart2js:noInline')
  static WebhookConfig getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WebhookConfig>(
          WebhookConfig.$_createMessage);
  static WebhookConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get signingKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set signingKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSigningKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigningKey() => $_clearField(2);

  @$pb.TagNumber(3)
  FilterParams get filterParams => $_getN(2);
  @$pb.TagNumber(3)
  set filterParams(FilterParams value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFilterParams() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilterParams() => $_clearField(3);
  @$pb.TagNumber(3)
  FilterParams ensureFilterParams() => $_ensure(2);
}

class SubscribedAudioCodec extends $pb.GeneratedMessage {
  factory SubscribedAudioCodec({
    $core.String? codec,
    $core.bool? enabled,
  }) {
    final result = SubscribedAudioCodec._();
    if (codec != null) result.codec = codec;
    if (enabled != null) result.enabled = enabled;
    return result;
  }

  SubscribedAudioCodec._();

  factory SubscribedAudioCodec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SubscribedAudioCodec()..mergeFromBuffer(data, registry);
  factory SubscribedAudioCodec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SubscribedAudioCodec()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribedAudioCodec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'livekit'),
      createEmptyInstance: SubscribedAudioCodec.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'codec')
    ..aOB(2, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribedAudioCodec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribedAudioCodec copyWith(void Function(SubscribedAudioCodec) updates) =>
      super.copyWith((message) => updates(message as SubscribedAudioCodec))
          as SubscribedAudioCodec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SubscribedAudioCodec() / SubscribedAudioCodec.new instead')
  static SubscribedAudioCodec create() => SubscribedAudioCodec._();
  static $pb.GeneratedMessage $_createMessage() => SubscribedAudioCodec._();
  @$core.override
  SubscribedAudioCodec createEmptyInstance() => SubscribedAudioCodec._();
  @$core.pragma('dart2js:noInline')
  static SubscribedAudioCodec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SubscribedAudioCodec>(
          SubscribedAudioCodec.$_createMessage);
  static SubscribedAudioCodec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get codec => $_getSZ(0);
  @$pb.TagNumber(1)
  set codec($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCodec() => $_has(0);
  @$pb.TagNumber(1)
  void clearCodec() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enabled => $_getBF(1);
  @$pb.TagNumber(2)
  set enabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabled() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
