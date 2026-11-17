// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class DatasetState extends Table
    with TableInfo<DatasetState, DatasetStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DatasetState(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (singleton = 1)',
  );
  static const VerificationMeta _datasetIdMeta = const VerificationMeta(
    'datasetId',
  );
  late final GeneratedColumn<String> datasetId = GeneratedColumn<String>(
    'dataset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE CHECK (length(dataset_id) = 36 AND dataset_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(dataset_id, \'-\', \'\')) = 32 AND "replace"(dataset_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(device_id) = 36 AND device_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(device_id, \'-\', \'\')) = 32 AND "replace"(device_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _nextLocalSeqMeta = const VerificationMeta(
    'nextLocalSeq',
  );
  late final GeneratedColumn<int> nextLocalSeq = GeneratedColumn<int>(
    'next_local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (next_local_seq > 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    datasetId,
    deviceId,
    nextLocalSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dataset_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<DatasetStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('dataset_id')) {
      context.handle(
        _datasetIdMeta,
        datasetId.isAcceptableOrUnknown(data['dataset_id']!, _datasetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('next_local_seq')) {
      context.handle(
        _nextLocalSeqMeta,
        nextLocalSeq.isAcceptableOrUnknown(
          data['next_local_seq']!,
          _nextLocalSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextLocalSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  DatasetStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DatasetStateData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      datasetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      nextLocalSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_local_seq'],
      )!,
    );
  }

  @override
  DatasetState createAlias(String alias) {
    return DatasetState(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  bool get dontWriteConstraints => true;
}

class DatasetStateData extends DataClass
    implements Insertable<DatasetStateData> {
  final int singleton;
  final String datasetId;
  final String deviceId;
  final int nextLocalSeq;
  const DatasetStateData({
    required this.singleton,
    required this.datasetId,
    required this.deviceId,
    required this.nextLocalSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['dataset_id'] = Variable<String>(datasetId);
    map['device_id'] = Variable<String>(deviceId);
    map['next_local_seq'] = Variable<int>(nextLocalSeq);
    return map;
  }

  DatasetStateCompanion toCompanion(bool nullToAbsent) {
    return DatasetStateCompanion(
      singleton: Value(singleton),
      datasetId: Value(datasetId),
      deviceId: Value(deviceId),
      nextLocalSeq: Value(nextLocalSeq),
    );
  }

  factory DatasetStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DatasetStateData(
      singleton: serializer.fromJson<int>(json['singleton']),
      datasetId: serializer.fromJson<String>(json['dataset_id']),
      deviceId: serializer.fromJson<String>(json['device_id']),
      nextLocalSeq: serializer.fromJson<int>(json['next_local_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'dataset_id': serializer.toJson<String>(datasetId),
      'device_id': serializer.toJson<String>(deviceId),
      'next_local_seq': serializer.toJson<int>(nextLocalSeq),
    };
  }

  DatasetStateData copyWith({
    int? singleton,
    String? datasetId,
    String? deviceId,
    int? nextLocalSeq,
  }) => DatasetStateData(
    singleton: singleton ?? this.singleton,
    datasetId: datasetId ?? this.datasetId,
    deviceId: deviceId ?? this.deviceId,
    nextLocalSeq: nextLocalSeq ?? this.nextLocalSeq,
  );
  DatasetStateData copyWithCompanion(DatasetStateCompanion data) {
    return DatasetStateData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      datasetId: data.datasetId.present ? data.datasetId.value : this.datasetId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      nextLocalSeq: data.nextLocalSeq.present
          ? data.nextLocalSeq.value
          : this.nextLocalSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DatasetStateData(')
          ..write('singleton: $singleton, ')
          ..write('datasetId: $datasetId, ')
          ..write('deviceId: $deviceId, ')
          ..write('nextLocalSeq: $nextLocalSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, datasetId, deviceId, nextLocalSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatasetStateData &&
          other.singleton == this.singleton &&
          other.datasetId == this.datasetId &&
          other.deviceId == this.deviceId &&
          other.nextLocalSeq == this.nextLocalSeq);
}

class DatasetStateCompanion extends UpdateCompanion<DatasetStateData> {
  final Value<int> singleton;
  final Value<String> datasetId;
  final Value<String> deviceId;
  final Value<int> nextLocalSeq;
  const DatasetStateCompanion({
    this.singleton = const Value.absent(),
    this.datasetId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.nextLocalSeq = const Value.absent(),
  });
  DatasetStateCompanion.insert({
    this.singleton = const Value.absent(),
    required String datasetId,
    required String deviceId,
    required int nextLocalSeq,
  }) : datasetId = Value(datasetId),
       deviceId = Value(deviceId),
       nextLocalSeq = Value(nextLocalSeq);
  static Insertable<DatasetStateData> custom({
    Expression<int>? singleton,
    Expression<String>? datasetId,
    Expression<String>? deviceId,
    Expression<int>? nextLocalSeq,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (datasetId != null) 'dataset_id': datasetId,
      if (deviceId != null) 'device_id': deviceId,
      if (nextLocalSeq != null) 'next_local_seq': nextLocalSeq,
    });
  }

  DatasetStateCompanion copyWith({
    Value<int>? singleton,
    Value<String>? datasetId,
    Value<String>? deviceId,
    Value<int>? nextLocalSeq,
  }) {
    return DatasetStateCompanion(
      singleton: singleton ?? this.singleton,
      datasetId: datasetId ?? this.datasetId,
      deviceId: deviceId ?? this.deviceId,
      nextLocalSeq: nextLocalSeq ?? this.nextLocalSeq,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (datasetId.present) {
      map['dataset_id'] = Variable<String>(datasetId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (nextLocalSeq.present) {
      map['next_local_seq'] = Variable<int>(nextLocalSeq.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DatasetStateCompanion(')
          ..write('singleton: $singleton, ')
          ..write('datasetId: $datasetId, ')
          ..write('deviceId: $deviceId, ')
          ..write('nextLocalSeq: $nextLocalSeq')
          ..write(')'))
        .toString();
  }
}

class ChangeLog extends Table with TableInfo<ChangeLog, ChangeLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ChangeLog(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(origin_device_id) = 36 AND origin_device_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(origin_device_id, \'-\', \'\')) = 32 AND "replace"(origin_device_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _originSeqMeta = const VerificationMeta(
    'originSeq',
  );
  late final GeneratedColumn<int> originSeq = GeneratedColumn<int>(
    'origin_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (origin_seq > 0 AND origin_seq < 9223372036854775807)',
  );
  static const VerificationMeta _datasetIdMeta = const VerificationMeta(
    'datasetId',
  );
  late final GeneratedColumn<String> datasetId = GeneratedColumn<String>(
    'dataset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES dataset_state(dataset_id)',
  );
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (entity_kind IN (\'store\', \'receipt\', \'product\', \'alias\'))',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(entity_id) = 36 AND entity_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(entity_id, \'-\', \'\')) = 32 AND "replace"(entity_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _payloadVersionMeta = const VerificationMeta(
    'payloadVersion',
  );
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
    'payload_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (payload_version = 1)',
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (operation IN (\'snapshot\', \'tombstone\') AND(operation <> \'tombstone\' OR entity_kind = \'receipt\'))',
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(payload))',
  );
  static const VerificationMeta _canonicalEventMeta = const VerificationMeta(
    'canonicalEvent',
  );
  late final GeneratedColumn<String> canonicalEvent = GeneratedColumn<String>(
    'canonical_event',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (json_valid(canonical_event))',
  );
  static const VerificationMeta _eventSha256Meta = const VerificationMeta(
    'eventSha256',
  );
  late final GeneratedColumn<String> eventSha256 = GeneratedColumn<String>(
    'event_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(event_sha256) = 64 AND event_sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _auditAtMsMeta = const VerificationMeta(
    'auditAtMs',
  );
  late final GeneratedColumn<int> auditAtMs = GeneratedColumn<int>(
    'audit_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (audit_at_ms >= 0)',
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(mutation_id) = 36 AND mutation_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(mutation_id, \'-\', \'\')) = 32 AND "replace"(mutation_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _mutationIndexMeta = const VerificationMeta(
    'mutationIndex',
  );
  late final GeneratedColumn<int> mutationIndex = GeneratedColumn<int>(
    'mutation_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (mutation_index >= 0 AND mutation_index < mutation_count)',
  );
  static const VerificationMeta _mutationCountMeta = const VerificationMeta(
    'mutationCount',
  );
  late final GeneratedColumn<int> mutationCount = GeneratedColumn<int>(
    'mutation_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (mutation_count IN (1, 2))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    originDeviceId,
    originSeq,
    datasetId,
    entityKind,
    entityId,
    payloadVersion,
    operation,
    payload,
    canonicalEvent,
    eventSha256,
    auditAtMs,
    mutationId,
    mutationIndex,
    mutationCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'change_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChangeLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceIdMeta);
    }
    if (data.containsKey('origin_seq')) {
      context.handle(
        _originSeqMeta,
        originSeq.isAcceptableOrUnknown(data['origin_seq']!, _originSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_originSeqMeta);
    }
    if (data.containsKey('dataset_id')) {
      context.handle(
        _datasetIdMeta,
        datasetId.isAcceptableOrUnknown(data['dataset_id']!, _datasetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetIdMeta);
    }
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload_version')) {
      context.handle(
        _payloadVersionMeta,
        payloadVersion.isAcceptableOrUnknown(
          data['payload_version']!,
          _payloadVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadVersionMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('canonical_event')) {
      context.handle(
        _canonicalEventMeta,
        canonicalEvent.isAcceptableOrUnknown(
          data['canonical_event']!,
          _canonicalEventMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalEventMeta);
    }
    if (data.containsKey('event_sha256')) {
      context.handle(
        _eventSha256Meta,
        eventSha256.isAcceptableOrUnknown(
          data['event_sha256']!,
          _eventSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventSha256Meta);
    }
    if (data.containsKey('audit_at_ms')) {
      context.handle(
        _auditAtMsMeta,
        auditAtMs.isAcceptableOrUnknown(data['audit_at_ms']!, _auditAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_auditAtMsMeta);
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('mutation_index')) {
      context.handle(
        _mutationIndexMeta,
        mutationIndex.isAcceptableOrUnknown(
          data['mutation_index']!,
          _mutationIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mutationIndexMeta);
    }
    if (data.containsKey('mutation_count')) {
      context.handle(
        _mutationCountMeta,
        mutationCount.isAcceptableOrUnknown(
          data['mutation_count']!,
          _mutationCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_mutationCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {originDeviceId, originSeq};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {originDeviceId, originSeq, entityKind, entityId},
    {originDeviceId, mutationId, mutationIndex},
  ];
  @override
  ChangeLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChangeLogData(
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      )!,
      originSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}origin_seq'],
      )!,
      datasetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_id'],
      )!,
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      payloadVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_version'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      canonicalEvent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_event'],
      )!,
      eventSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_sha256'],
      )!,
      auditAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audit_at_ms'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      mutationIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mutation_index'],
      )!,
      mutationCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mutation_count'],
      )!,
    );
  }

  @override
  ChangeLog createAlias(String alias) {
    return ChangeLog(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(origin_device_id, origin_seq)',
    'UNIQUE(origin_device_id, origin_seq, entity_kind, entity_id)',
    'UNIQUE(origin_device_id, mutation_id, mutation_index)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ChangeLogData extends DataClass implements Insertable<ChangeLogData> {
  final String originDeviceId;
  final int originSeq;
  final String datasetId;
  final String entityKind;
  final String entityId;
  final int payloadVersion;
  final String operation;
  final String payload;
  final String canonicalEvent;
  final String eventSha256;
  final int auditAtMs;
  final String mutationId;
  final int mutationIndex;
  final int mutationCount;
  const ChangeLogData({
    required this.originDeviceId,
    required this.originSeq,
    required this.datasetId,
    required this.entityKind,
    required this.entityId,
    required this.payloadVersion,
    required this.operation,
    required this.payload,
    required this.canonicalEvent,
    required this.eventSha256,
    required this.auditAtMs,
    required this.mutationId,
    required this.mutationIndex,
    required this.mutationCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['origin_device_id'] = Variable<String>(originDeviceId);
    map['origin_seq'] = Variable<int>(originSeq);
    map['dataset_id'] = Variable<String>(datasetId);
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    map['payload_version'] = Variable<int>(payloadVersion);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['canonical_event'] = Variable<String>(canonicalEvent);
    map['event_sha256'] = Variable<String>(eventSha256);
    map['audit_at_ms'] = Variable<int>(auditAtMs);
    map['mutation_id'] = Variable<String>(mutationId);
    map['mutation_index'] = Variable<int>(mutationIndex);
    map['mutation_count'] = Variable<int>(mutationCount);
    return map;
  }

  ChangeLogCompanion toCompanion(bool nullToAbsent) {
    return ChangeLogCompanion(
      originDeviceId: Value(originDeviceId),
      originSeq: Value(originSeq),
      datasetId: Value(datasetId),
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      payloadVersion: Value(payloadVersion),
      operation: Value(operation),
      payload: Value(payload),
      canonicalEvent: Value(canonicalEvent),
      eventSha256: Value(eventSha256),
      auditAtMs: Value(auditAtMs),
      mutationId: Value(mutationId),
      mutationIndex: Value(mutationIndex),
      mutationCount: Value(mutationCount),
    );
  }

  factory ChangeLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChangeLogData(
      originDeviceId: serializer.fromJson<String>(json['origin_device_id']),
      originSeq: serializer.fromJson<int>(json['origin_seq']),
      datasetId: serializer.fromJson<String>(json['dataset_id']),
      entityKind: serializer.fromJson<String>(json['entity_kind']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      payloadVersion: serializer.fromJson<int>(json['payload_version']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      canonicalEvent: serializer.fromJson<String>(json['canonical_event']),
      eventSha256: serializer.fromJson<String>(json['event_sha256']),
      auditAtMs: serializer.fromJson<int>(json['audit_at_ms']),
      mutationId: serializer.fromJson<String>(json['mutation_id']),
      mutationIndex: serializer.fromJson<int>(json['mutation_index']),
      mutationCount: serializer.fromJson<int>(json['mutation_count']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'origin_device_id': serializer.toJson<String>(originDeviceId),
      'origin_seq': serializer.toJson<int>(originSeq),
      'dataset_id': serializer.toJson<String>(datasetId),
      'entity_kind': serializer.toJson<String>(entityKind),
      'entity_id': serializer.toJson<String>(entityId),
      'payload_version': serializer.toJson<int>(payloadVersion),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'canonical_event': serializer.toJson<String>(canonicalEvent),
      'event_sha256': serializer.toJson<String>(eventSha256),
      'audit_at_ms': serializer.toJson<int>(auditAtMs),
      'mutation_id': serializer.toJson<String>(mutationId),
      'mutation_index': serializer.toJson<int>(mutationIndex),
      'mutation_count': serializer.toJson<int>(mutationCount),
    };
  }

  ChangeLogData copyWith({
    String? originDeviceId,
    int? originSeq,
    String? datasetId,
    String? entityKind,
    String? entityId,
    int? payloadVersion,
    String? operation,
    String? payload,
    String? canonicalEvent,
    String? eventSha256,
    int? auditAtMs,
    String? mutationId,
    int? mutationIndex,
    int? mutationCount,
  }) => ChangeLogData(
    originDeviceId: originDeviceId ?? this.originDeviceId,
    originSeq: originSeq ?? this.originSeq,
    datasetId: datasetId ?? this.datasetId,
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    payloadVersion: payloadVersion ?? this.payloadVersion,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    canonicalEvent: canonicalEvent ?? this.canonicalEvent,
    eventSha256: eventSha256 ?? this.eventSha256,
    auditAtMs: auditAtMs ?? this.auditAtMs,
    mutationId: mutationId ?? this.mutationId,
    mutationIndex: mutationIndex ?? this.mutationIndex,
    mutationCount: mutationCount ?? this.mutationCount,
  );
  ChangeLogData copyWithCompanion(ChangeLogCompanion data) {
    return ChangeLogData(
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      originSeq: data.originSeq.present ? data.originSeq.value : this.originSeq,
      datasetId: data.datasetId.present ? data.datasetId.value : this.datasetId,
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      canonicalEvent: data.canonicalEvent.present
          ? data.canonicalEvent.value
          : this.canonicalEvent,
      eventSha256: data.eventSha256.present
          ? data.eventSha256.value
          : this.eventSha256,
      auditAtMs: data.auditAtMs.present ? data.auditAtMs.value : this.auditAtMs,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      mutationIndex: data.mutationIndex.present
          ? data.mutationIndex.value
          : this.mutationIndex,
      mutationCount: data.mutationCount.present
          ? data.mutationCount.value
          : this.mutationCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChangeLogData(')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('originSeq: $originSeq, ')
          ..write('datasetId: $datasetId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('canonicalEvent: $canonicalEvent, ')
          ..write('eventSha256: $eventSha256, ')
          ..write('auditAtMs: $auditAtMs, ')
          ..write('mutationId: $mutationId, ')
          ..write('mutationIndex: $mutationIndex, ')
          ..write('mutationCount: $mutationCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originDeviceId,
    originSeq,
    datasetId,
    entityKind,
    entityId,
    payloadVersion,
    operation,
    payload,
    canonicalEvent,
    eventSha256,
    auditAtMs,
    mutationId,
    mutationIndex,
    mutationCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChangeLogData &&
          other.originDeviceId == this.originDeviceId &&
          other.originSeq == this.originSeq &&
          other.datasetId == this.datasetId &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.payloadVersion == this.payloadVersion &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.canonicalEvent == this.canonicalEvent &&
          other.eventSha256 == this.eventSha256 &&
          other.auditAtMs == this.auditAtMs &&
          other.mutationId == this.mutationId &&
          other.mutationIndex == this.mutationIndex &&
          other.mutationCount == this.mutationCount);
}

class ChangeLogCompanion extends UpdateCompanion<ChangeLogData> {
  final Value<String> originDeviceId;
  final Value<int> originSeq;
  final Value<String> datasetId;
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<int> payloadVersion;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String> canonicalEvent;
  final Value<String> eventSha256;
  final Value<int> auditAtMs;
  final Value<String> mutationId;
  final Value<int> mutationIndex;
  final Value<int> mutationCount;
  final Value<int> rowid;
  const ChangeLogCompanion({
    this.originDeviceId = const Value.absent(),
    this.originSeq = const Value.absent(),
    this.datasetId = const Value.absent(),
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.canonicalEvent = const Value.absent(),
    this.eventSha256 = const Value.absent(),
    this.auditAtMs = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.mutationIndex = const Value.absent(),
    this.mutationCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChangeLogCompanion.insert({
    required String originDeviceId,
    required int originSeq,
    required String datasetId,
    required String entityKind,
    required String entityId,
    required int payloadVersion,
    required String operation,
    required String payload,
    required String canonicalEvent,
    required String eventSha256,
    required int auditAtMs,
    required String mutationId,
    required int mutationIndex,
    required int mutationCount,
    this.rowid = const Value.absent(),
  }) : originDeviceId = Value(originDeviceId),
       originSeq = Value(originSeq),
       datasetId = Value(datasetId),
       entityKind = Value(entityKind),
       entityId = Value(entityId),
       payloadVersion = Value(payloadVersion),
       operation = Value(operation),
       payload = Value(payload),
       canonicalEvent = Value(canonicalEvent),
       eventSha256 = Value(eventSha256),
       auditAtMs = Value(auditAtMs),
       mutationId = Value(mutationId),
       mutationIndex = Value(mutationIndex),
       mutationCount = Value(mutationCount);
  static Insertable<ChangeLogData> custom({
    Expression<String>? originDeviceId,
    Expression<int>? originSeq,
    Expression<String>? datasetId,
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<int>? payloadVersion,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? canonicalEvent,
    Expression<String>? eventSha256,
    Expression<int>? auditAtMs,
    Expression<String>? mutationId,
    Expression<int>? mutationIndex,
    Expression<int>? mutationCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (originSeq != null) 'origin_seq': originSeq,
      if (datasetId != null) 'dataset_id': datasetId,
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (canonicalEvent != null) 'canonical_event': canonicalEvent,
      if (eventSha256 != null) 'event_sha256': eventSha256,
      if (auditAtMs != null) 'audit_at_ms': auditAtMs,
      if (mutationId != null) 'mutation_id': mutationId,
      if (mutationIndex != null) 'mutation_index': mutationIndex,
      if (mutationCount != null) 'mutation_count': mutationCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChangeLogCompanion copyWith({
    Value<String>? originDeviceId,
    Value<int>? originSeq,
    Value<String>? datasetId,
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<int>? payloadVersion,
    Value<String>? operation,
    Value<String>? payload,
    Value<String>? canonicalEvent,
    Value<String>? eventSha256,
    Value<int>? auditAtMs,
    Value<String>? mutationId,
    Value<int>? mutationIndex,
    Value<int>? mutationCount,
    Value<int>? rowid,
  }) {
    return ChangeLogCompanion(
      originDeviceId: originDeviceId ?? this.originDeviceId,
      originSeq: originSeq ?? this.originSeq,
      datasetId: datasetId ?? this.datasetId,
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      canonicalEvent: canonicalEvent ?? this.canonicalEvent,
      eventSha256: eventSha256 ?? this.eventSha256,
      auditAtMs: auditAtMs ?? this.auditAtMs,
      mutationId: mutationId ?? this.mutationId,
      mutationIndex: mutationIndex ?? this.mutationIndex,
      mutationCount: mutationCount ?? this.mutationCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (originSeq.present) {
      map['origin_seq'] = Variable<int>(originSeq.value);
    }
    if (datasetId.present) {
      map['dataset_id'] = Variable<String>(datasetId.value);
    }
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (canonicalEvent.present) {
      map['canonical_event'] = Variable<String>(canonicalEvent.value);
    }
    if (eventSha256.present) {
      map['event_sha256'] = Variable<String>(eventSha256.value);
    }
    if (auditAtMs.present) {
      map['audit_at_ms'] = Variable<int>(auditAtMs.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (mutationIndex.present) {
      map['mutation_index'] = Variable<int>(mutationIndex.value);
    }
    if (mutationCount.present) {
      map['mutation_count'] = Variable<int>(mutationCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChangeLogCompanion(')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('originSeq: $originSeq, ')
          ..write('datasetId: $datasetId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('canonicalEvent: $canonicalEvent, ')
          ..write('eventSha256: $eventSha256, ')
          ..write('auditAtMs: $auditAtMs, ')
          ..write('mutationId: $mutationId, ')
          ..write('mutationIndex: $mutationIndex, ')
          ..write('mutationCount: $mutationCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class RevisionParents extends Table
    with TableInfo<RevisionParents, RevisionParent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RevisionParents(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _childOriginMeta = const VerificationMeta(
    'childOrigin',
  );
  late final GeneratedColumn<String> childOrigin = GeneratedColumn<String>(
    'child_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _childSeqMeta = const VerificationMeta(
    'childSeq',
  );
  late final GeneratedColumn<int> childSeq = GeneratedColumn<int>(
    'child_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _parentOriginMeta = const VerificationMeta(
    'parentOrigin',
  );
  late final GeneratedColumn<String> parentOrigin = GeneratedColumn<String>(
    'parent_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _parentSeqMeta = const VerificationMeta(
    'parentSeq',
  );
  late final GeneratedColumn<int> parentSeq = GeneratedColumn<int>(
    'parent_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    childOrigin,
    childSeq,
    parentOrigin,
    parentSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revision_parents';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevisionParent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('child_origin')) {
      context.handle(
        _childOriginMeta,
        childOrigin.isAcceptableOrUnknown(
          data['child_origin']!,
          _childOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_childOriginMeta);
    }
    if (data.containsKey('child_seq')) {
      context.handle(
        _childSeqMeta,
        childSeq.isAcceptableOrUnknown(data['child_seq']!, _childSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_childSeqMeta);
    }
    if (data.containsKey('parent_origin')) {
      context.handle(
        _parentOriginMeta,
        parentOrigin.isAcceptableOrUnknown(
          data['parent_origin']!,
          _parentOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parentOriginMeta);
    }
    if (data.containsKey('parent_seq')) {
      context.handle(
        _parentSeqMeta,
        parentSeq.isAcceptableOrUnknown(data['parent_seq']!, _parentSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_parentSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    childOrigin,
    childSeq,
    parentOrigin,
    parentSeq,
  };
  @override
  RevisionParent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevisionParent(
      childOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}child_origin'],
      )!,
      childSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}child_seq'],
      )!,
      parentOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_origin'],
      )!,
      parentSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_seq'],
      )!,
    );
  }

  @override
  RevisionParents createAlias(String alias) {
    return RevisionParents(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(child_origin, child_seq, parent_origin, parent_seq)',
    'FOREIGN KEY(child_origin, child_seq)REFERENCES change_log(origin_device_id, origin_seq)',
    'FOREIGN KEY(parent_origin, parent_seq)REFERENCES change_log(origin_device_id, origin_seq)',
    'CHECK(child_origin <> parent_origin OR child_seq <> parent_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RevisionParent extends DataClass implements Insertable<RevisionParent> {
  final String childOrigin;
  final int childSeq;
  final String parentOrigin;
  final int parentSeq;
  const RevisionParent({
    required this.childOrigin,
    required this.childSeq,
    required this.parentOrigin,
    required this.parentSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['child_origin'] = Variable<String>(childOrigin);
    map['child_seq'] = Variable<int>(childSeq);
    map['parent_origin'] = Variable<String>(parentOrigin);
    map['parent_seq'] = Variable<int>(parentSeq);
    return map;
  }

  RevisionParentsCompanion toCompanion(bool nullToAbsent) {
    return RevisionParentsCompanion(
      childOrigin: Value(childOrigin),
      childSeq: Value(childSeq),
      parentOrigin: Value(parentOrigin),
      parentSeq: Value(parentSeq),
    );
  }

  factory RevisionParent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevisionParent(
      childOrigin: serializer.fromJson<String>(json['child_origin']),
      childSeq: serializer.fromJson<int>(json['child_seq']),
      parentOrigin: serializer.fromJson<String>(json['parent_origin']),
      parentSeq: serializer.fromJson<int>(json['parent_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'child_origin': serializer.toJson<String>(childOrigin),
      'child_seq': serializer.toJson<int>(childSeq),
      'parent_origin': serializer.toJson<String>(parentOrigin),
      'parent_seq': serializer.toJson<int>(parentSeq),
    };
  }

  RevisionParent copyWith({
    String? childOrigin,
    int? childSeq,
    String? parentOrigin,
    int? parentSeq,
  }) => RevisionParent(
    childOrigin: childOrigin ?? this.childOrigin,
    childSeq: childSeq ?? this.childSeq,
    parentOrigin: parentOrigin ?? this.parentOrigin,
    parentSeq: parentSeq ?? this.parentSeq,
  );
  RevisionParent copyWithCompanion(RevisionParentsCompanion data) {
    return RevisionParent(
      childOrigin: data.childOrigin.present
          ? data.childOrigin.value
          : this.childOrigin,
      childSeq: data.childSeq.present ? data.childSeq.value : this.childSeq,
      parentOrigin: data.parentOrigin.present
          ? data.parentOrigin.value
          : this.parentOrigin,
      parentSeq: data.parentSeq.present ? data.parentSeq.value : this.parentSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevisionParent(')
          ..write('childOrigin: $childOrigin, ')
          ..write('childSeq: $childSeq, ')
          ..write('parentOrigin: $parentOrigin, ')
          ..write('parentSeq: $parentSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(childOrigin, childSeq, parentOrigin, parentSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionParent &&
          other.childOrigin == this.childOrigin &&
          other.childSeq == this.childSeq &&
          other.parentOrigin == this.parentOrigin &&
          other.parentSeq == this.parentSeq);
}

class RevisionParentsCompanion extends UpdateCompanion<RevisionParent> {
  final Value<String> childOrigin;
  final Value<int> childSeq;
  final Value<String> parentOrigin;
  final Value<int> parentSeq;
  final Value<int> rowid;
  const RevisionParentsCompanion({
    this.childOrigin = const Value.absent(),
    this.childSeq = const Value.absent(),
    this.parentOrigin = const Value.absent(),
    this.parentSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevisionParentsCompanion.insert({
    required String childOrigin,
    required int childSeq,
    required String parentOrigin,
    required int parentSeq,
    this.rowid = const Value.absent(),
  }) : childOrigin = Value(childOrigin),
       childSeq = Value(childSeq),
       parentOrigin = Value(parentOrigin),
       parentSeq = Value(parentSeq);
  static Insertable<RevisionParent> custom({
    Expression<String>? childOrigin,
    Expression<int>? childSeq,
    Expression<String>? parentOrigin,
    Expression<int>? parentSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (childOrigin != null) 'child_origin': childOrigin,
      if (childSeq != null) 'child_seq': childSeq,
      if (parentOrigin != null) 'parent_origin': parentOrigin,
      if (parentSeq != null) 'parent_seq': parentSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevisionParentsCompanion copyWith({
    Value<String>? childOrigin,
    Value<int>? childSeq,
    Value<String>? parentOrigin,
    Value<int>? parentSeq,
    Value<int>? rowid,
  }) {
    return RevisionParentsCompanion(
      childOrigin: childOrigin ?? this.childOrigin,
      childSeq: childSeq ?? this.childSeq,
      parentOrigin: parentOrigin ?? this.parentOrigin,
      parentSeq: parentSeq ?? this.parentSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (childOrigin.present) {
      map['child_origin'] = Variable<String>(childOrigin.value);
    }
    if (childSeq.present) {
      map['child_seq'] = Variable<int>(childSeq.value);
    }
    if (parentOrigin.present) {
      map['parent_origin'] = Variable<String>(parentOrigin.value);
    }
    if (parentSeq.present) {
      map['parent_seq'] = Variable<int>(parentSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevisionParentsCompanion(')
          ..write('childOrigin: $childOrigin, ')
          ..write('childSeq: $childSeq, ')
          ..write('parentOrigin: $parentOrigin, ')
          ..write('parentSeq: $parentSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class EventDependencies extends Table
    with TableInfo<EventDependencies, EventDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EventDependencies(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _childOriginMeta = const VerificationMeta(
    'childOrigin',
  );
  late final GeneratedColumn<String> childOrigin = GeneratedColumn<String>(
    'child_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _childSeqMeta = const VerificationMeta(
    'childSeq',
  );
  late final GeneratedColumn<int> childSeq = GeneratedColumn<int>(
    'child_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _dependencyOriginMeta = const VerificationMeta(
    'dependencyOrigin',
  );
  late final GeneratedColumn<String> dependencyOrigin = GeneratedColumn<String>(
    'dependency_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _dependencySeqMeta = const VerificationMeta(
    'dependencySeq',
  );
  late final GeneratedColumn<int> dependencySeq = GeneratedColumn<int>(
    'dependency_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    childOrigin,
    childSeq,
    dependencyOrigin,
    dependencySeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_dependencies';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventDependency> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('child_origin')) {
      context.handle(
        _childOriginMeta,
        childOrigin.isAcceptableOrUnknown(
          data['child_origin']!,
          _childOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_childOriginMeta);
    }
    if (data.containsKey('child_seq')) {
      context.handle(
        _childSeqMeta,
        childSeq.isAcceptableOrUnknown(data['child_seq']!, _childSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_childSeqMeta);
    }
    if (data.containsKey('dependency_origin')) {
      context.handle(
        _dependencyOriginMeta,
        dependencyOrigin.isAcceptableOrUnknown(
          data['dependency_origin']!,
          _dependencyOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dependencyOriginMeta);
    }
    if (data.containsKey('dependency_seq')) {
      context.handle(
        _dependencySeqMeta,
        dependencySeq.isAcceptableOrUnknown(
          data['dependency_seq']!,
          _dependencySeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dependencySeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    childOrigin,
    childSeq,
    dependencyOrigin,
    dependencySeq,
  };
  @override
  EventDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventDependency(
      childOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}child_origin'],
      )!,
      childSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}child_seq'],
      )!,
      dependencyOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dependency_origin'],
      )!,
      dependencySeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dependency_seq'],
      )!,
    );
  }

  @override
  EventDependencies createAlias(String alias) {
    return EventDependencies(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(child_origin, child_seq, dependency_origin, dependency_seq)',
    'FOREIGN KEY(child_origin, child_seq)REFERENCES change_log(origin_device_id, origin_seq)',
    'FOREIGN KEY(dependency_origin, dependency_seq)REFERENCES change_log(origin_device_id, origin_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class EventDependency extends DataClass implements Insertable<EventDependency> {
  final String childOrigin;
  final int childSeq;
  final String dependencyOrigin;
  final int dependencySeq;
  const EventDependency({
    required this.childOrigin,
    required this.childSeq,
    required this.dependencyOrigin,
    required this.dependencySeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['child_origin'] = Variable<String>(childOrigin);
    map['child_seq'] = Variable<int>(childSeq);
    map['dependency_origin'] = Variable<String>(dependencyOrigin);
    map['dependency_seq'] = Variable<int>(dependencySeq);
    return map;
  }

  EventDependenciesCompanion toCompanion(bool nullToAbsent) {
    return EventDependenciesCompanion(
      childOrigin: Value(childOrigin),
      childSeq: Value(childSeq),
      dependencyOrigin: Value(dependencyOrigin),
      dependencySeq: Value(dependencySeq),
    );
  }

  factory EventDependency.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventDependency(
      childOrigin: serializer.fromJson<String>(json['child_origin']),
      childSeq: serializer.fromJson<int>(json['child_seq']),
      dependencyOrigin: serializer.fromJson<String>(json['dependency_origin']),
      dependencySeq: serializer.fromJson<int>(json['dependency_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'child_origin': serializer.toJson<String>(childOrigin),
      'child_seq': serializer.toJson<int>(childSeq),
      'dependency_origin': serializer.toJson<String>(dependencyOrigin),
      'dependency_seq': serializer.toJson<int>(dependencySeq),
    };
  }

  EventDependency copyWith({
    String? childOrigin,
    int? childSeq,
    String? dependencyOrigin,
    int? dependencySeq,
  }) => EventDependency(
    childOrigin: childOrigin ?? this.childOrigin,
    childSeq: childSeq ?? this.childSeq,
    dependencyOrigin: dependencyOrigin ?? this.dependencyOrigin,
    dependencySeq: dependencySeq ?? this.dependencySeq,
  );
  EventDependency copyWithCompanion(EventDependenciesCompanion data) {
    return EventDependency(
      childOrigin: data.childOrigin.present
          ? data.childOrigin.value
          : this.childOrigin,
      childSeq: data.childSeq.present ? data.childSeq.value : this.childSeq,
      dependencyOrigin: data.dependencyOrigin.present
          ? data.dependencyOrigin.value
          : this.dependencyOrigin,
      dependencySeq: data.dependencySeq.present
          ? data.dependencySeq.value
          : this.dependencySeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventDependency(')
          ..write('childOrigin: $childOrigin, ')
          ..write('childSeq: $childSeq, ')
          ..write('dependencyOrigin: $dependencyOrigin, ')
          ..write('dependencySeq: $dependencySeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(childOrigin, childSeq, dependencyOrigin, dependencySeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventDependency &&
          other.childOrigin == this.childOrigin &&
          other.childSeq == this.childSeq &&
          other.dependencyOrigin == this.dependencyOrigin &&
          other.dependencySeq == this.dependencySeq);
}

class EventDependenciesCompanion extends UpdateCompanion<EventDependency> {
  final Value<String> childOrigin;
  final Value<int> childSeq;
  final Value<String> dependencyOrigin;
  final Value<int> dependencySeq;
  final Value<int> rowid;
  const EventDependenciesCompanion({
    this.childOrigin = const Value.absent(),
    this.childSeq = const Value.absent(),
    this.dependencyOrigin = const Value.absent(),
    this.dependencySeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventDependenciesCompanion.insert({
    required String childOrigin,
    required int childSeq,
    required String dependencyOrigin,
    required int dependencySeq,
    this.rowid = const Value.absent(),
  }) : childOrigin = Value(childOrigin),
       childSeq = Value(childSeq),
       dependencyOrigin = Value(dependencyOrigin),
       dependencySeq = Value(dependencySeq);
  static Insertable<EventDependency> custom({
    Expression<String>? childOrigin,
    Expression<int>? childSeq,
    Expression<String>? dependencyOrigin,
    Expression<int>? dependencySeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (childOrigin != null) 'child_origin': childOrigin,
      if (childSeq != null) 'child_seq': childSeq,
      if (dependencyOrigin != null) 'dependency_origin': dependencyOrigin,
      if (dependencySeq != null) 'dependency_seq': dependencySeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventDependenciesCompanion copyWith({
    Value<String>? childOrigin,
    Value<int>? childSeq,
    Value<String>? dependencyOrigin,
    Value<int>? dependencySeq,
    Value<int>? rowid,
  }) {
    return EventDependenciesCompanion(
      childOrigin: childOrigin ?? this.childOrigin,
      childSeq: childSeq ?? this.childSeq,
      dependencyOrigin: dependencyOrigin ?? this.dependencyOrigin,
      dependencySeq: dependencySeq ?? this.dependencySeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (childOrigin.present) {
      map['child_origin'] = Variable<String>(childOrigin.value);
    }
    if (childSeq.present) {
      map['child_seq'] = Variable<int>(childSeq.value);
    }
    if (dependencyOrigin.present) {
      map['dependency_origin'] = Variable<String>(dependencyOrigin.value);
    }
    if (dependencySeq.present) {
      map['dependency_seq'] = Variable<int>(dependencySeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventDependenciesCompanion(')
          ..write('childOrigin: $childOrigin, ')
          ..write('childSeq: $childSeq, ')
          ..write('dependencyOrigin: $dependencyOrigin, ')
          ..write('dependencySeq: $dependencySeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class EntityHeads extends Table with TableInfo<EntityHeads, EntityHead> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EntityHeads(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (entity_kind IN (\'store\', \'receipt\', \'product\', \'alias\'))',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _originSeqMeta = const VerificationMeta(
    'originSeq',
  );
  late final GeneratedColumn<int> originSeq = GeneratedColumn<int>(
    'origin_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    entityKind,
    entityId,
    originDeviceId,
    originSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entity_heads';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityHead> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceIdMeta);
    }
    if (data.containsKey('origin_seq')) {
      context.handle(
        _originSeqMeta,
        originSeq.isAcceptableOrUnknown(data['origin_seq']!, _originSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_originSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    entityKind,
    entityId,
    originDeviceId,
    originSeq,
  };
  @override
  EntityHead map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityHead(
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      )!,
      originSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}origin_seq'],
      )!,
    );
  }

  @override
  EntityHeads createAlias(String alias) {
    return EntityHeads(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'PRIMARY KEY(entity_kind, entity_id, origin_device_id, origin_seq)',
    'FOREIGN KEY(origin_device_id, origin_seq, entity_kind, entity_id)REFERENCES change_log(origin_device_id, origin_seq, entity_kind, entity_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class EntityHead extends DataClass implements Insertable<EntityHead> {
  final String entityKind;
  final String entityId;
  final String originDeviceId;
  final int originSeq;
  const EntityHead({
    required this.entityKind,
    required this.entityId,
    required this.originDeviceId,
    required this.originSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    map['origin_device_id'] = Variable<String>(originDeviceId);
    map['origin_seq'] = Variable<int>(originSeq);
    return map;
  }

  EntityHeadsCompanion toCompanion(bool nullToAbsent) {
    return EntityHeadsCompanion(
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      originDeviceId: Value(originDeviceId),
      originSeq: Value(originSeq),
    );
  }

  factory EntityHead.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityHead(
      entityKind: serializer.fromJson<String>(json['entity_kind']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      originDeviceId: serializer.fromJson<String>(json['origin_device_id']),
      originSeq: serializer.fromJson<int>(json['origin_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity_kind': serializer.toJson<String>(entityKind),
      'entity_id': serializer.toJson<String>(entityId),
      'origin_device_id': serializer.toJson<String>(originDeviceId),
      'origin_seq': serializer.toJson<int>(originSeq),
    };
  }

  EntityHead copyWith({
    String? entityKind,
    String? entityId,
    String? originDeviceId,
    int? originSeq,
  }) => EntityHead(
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    originDeviceId: originDeviceId ?? this.originDeviceId,
    originSeq: originSeq ?? this.originSeq,
  );
  EntityHead copyWithCompanion(EntityHeadsCompanion data) {
    return EntityHead(
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      originSeq: data.originSeq.present ? data.originSeq.value : this.originSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityHead(')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('originSeq: $originSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(entityKind, entityId, originDeviceId, originSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityHead &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.originDeviceId == this.originDeviceId &&
          other.originSeq == this.originSeq);
}

class EntityHeadsCompanion extends UpdateCompanion<EntityHead> {
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<String> originDeviceId;
  final Value<int> originSeq;
  final Value<int> rowid;
  const EntityHeadsCompanion({
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.originDeviceId = const Value.absent(),
    this.originSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntityHeadsCompanion.insert({
    required String entityKind,
    required String entityId,
    required String originDeviceId,
    required int originSeq,
    this.rowid = const Value.absent(),
  }) : entityKind = Value(entityKind),
       entityId = Value(entityId),
       originDeviceId = Value(originDeviceId),
       originSeq = Value(originSeq);
  static Insertable<EntityHead> custom({
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<String>? originDeviceId,
    Expression<int>? originSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (originSeq != null) 'origin_seq': originSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntityHeadsCompanion copyWith({
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<String>? originDeviceId,
    Value<int>? originSeq,
    Value<int>? rowid,
  }) {
    return EntityHeadsCompanion(
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      originDeviceId: originDeviceId ?? this.originDeviceId,
      originSeq: originSeq ?? this.originSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (originSeq.present) {
      map['origin_seq'] = Variable<int>(originSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntityHeadsCompanion(')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('originSeq: $originSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Stores extends Table with TableInfo<Stores, Store> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Stores(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(display_name)) > 0 AND display_name = trim(display_name))',
  );
  static const VerificationMeta _chainMeta = const VerificationMeta('chain');
  late final GeneratedColumn<String> chain = GeneratedColumn<String>(
    'chain',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (chain IS NULL OR(length(trim(chain)) > 0 AND chain = trim(chain)))',
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (address IS NULL OR(length(trim(address)) > 0 AND address = trim(address)))',
  );
  static const VerificationMeta _printedIdentifierMeta = const VerificationMeta(
    'printedIdentifier',
  );
  late final GeneratedColumn<String> printedIdentifier =
      GeneratedColumn<String>(
        'printed_identifier',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: 'CHECK (printed_identifier IS NULL OR(length(trim(printed_identifier)) > 0 AND printed_identifier = trim(printed_identifier)))',
      );
  static const VerificationMeta _currentRevisionOriginMeta =
      const VerificationMeta('currentRevisionOrigin');
  late final GeneratedColumn<String> currentRevisionOrigin =
      GeneratedColumn<String>(
        'current_revision_origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _currentRevisionSeqMeta =
      const VerificationMeta('currentRevisionSeq');
  late final GeneratedColumn<int> currentRevisionSeq = GeneratedColumn<int>(
    'current_revision_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (created_at_ms >= 0)',
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (updated_at_ms >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    displayName,
    chain,
    address,
    printedIdentifier,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stores';
  @override
  VerificationContext validateIntegrity(
    Insertable<Store> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('chain')) {
      context.handle(
        _chainMeta,
        chain.isAcceptableOrUnknown(data['chain']!, _chainMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('printed_identifier')) {
      context.handle(
        _printedIdentifierMeta,
        printedIdentifier.isAcceptableOrUnknown(
          data['printed_identifier']!,
          _printedIdentifierMeta,
        ),
      );
    }
    if (data.containsKey('current_revision_origin')) {
      context.handle(
        _currentRevisionOriginMeta,
        currentRevisionOrigin.isAcceptableOrUnknown(
          data['current_revision_origin']!,
          _currentRevisionOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionOriginMeta);
    }
    if (data.containsKey('current_revision_seq')) {
      context.handle(
        _currentRevisionSeqMeta,
        currentRevisionSeq.isAcceptableOrUnknown(
          data['current_revision_seq']!,
          _currentRevisionSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionSeqMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Store map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Store(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      chain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chain'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      printedIdentifier: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}printed_identifier'],
      ),
      currentRevisionOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_origin'],
      )!,
      currentRevisionSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision_seq'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  Stores createAlias(String alias) {
    return Stores(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(current_revision_origin, current_revision_seq)REFERENCES change_log(origin_device_id, origin_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Store extends DataClass implements Insertable<Store> {
  final String id;
  final String displayName;
  final String? chain;
  final String? address;
  final String? printedIdentifier;
  final String currentRevisionOrigin;
  final int currentRevisionSeq;
  final int createdAtMs;
  final int updatedAtMs;
  const Store({
    required this.id,
    required this.displayName,
    this.chain,
    this.address,
    this.printedIdentifier,
    required this.currentRevisionOrigin,
    required this.currentRevisionSeq,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || chain != null) {
      map['chain'] = Variable<String>(chain);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || printedIdentifier != null) {
      map['printed_identifier'] = Variable<String>(printedIdentifier);
    }
    map['current_revision_origin'] = Variable<String>(currentRevisionOrigin);
    map['current_revision_seq'] = Variable<int>(currentRevisionSeq);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  StoresCompanion toCompanion(bool nullToAbsent) {
    return StoresCompanion(
      id: Value(id),
      displayName: Value(displayName),
      chain: chain == null && nullToAbsent
          ? const Value.absent()
          : Value(chain),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      printedIdentifier: printedIdentifier == null && nullToAbsent
          ? const Value.absent()
          : Value(printedIdentifier),
      currentRevisionOrigin: Value(currentRevisionOrigin),
      currentRevisionSeq: Value(currentRevisionSeq),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory Store.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Store(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['display_name']),
      chain: serializer.fromJson<String?>(json['chain']),
      address: serializer.fromJson<String?>(json['address']),
      printedIdentifier: serializer.fromJson<String?>(
        json['printed_identifier'],
      ),
      currentRevisionOrigin: serializer.fromJson<String>(
        json['current_revision_origin'],
      ),
      currentRevisionSeq: serializer.fromJson<int>(
        json['current_revision_seq'],
      ),
      createdAtMs: serializer.fromJson<int>(json['created_at_ms']),
      updatedAtMs: serializer.fromJson<int>(json['updated_at_ms']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'display_name': serializer.toJson<String>(displayName),
      'chain': serializer.toJson<String?>(chain),
      'address': serializer.toJson<String?>(address),
      'printed_identifier': serializer.toJson<String?>(printedIdentifier),
      'current_revision_origin': serializer.toJson<String>(
        currentRevisionOrigin,
      ),
      'current_revision_seq': serializer.toJson<int>(currentRevisionSeq),
      'created_at_ms': serializer.toJson<int>(createdAtMs),
      'updated_at_ms': serializer.toJson<int>(updatedAtMs),
    };
  }

  Store copyWith({
    String? id,
    String? displayName,
    Value<String?> chain = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> printedIdentifier = const Value.absent(),
    String? currentRevisionOrigin,
    int? currentRevisionSeq,
    int? createdAtMs,
    int? updatedAtMs,
  }) => Store(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    chain: chain.present ? chain.value : this.chain,
    address: address.present ? address.value : this.address,
    printedIdentifier: printedIdentifier.present
        ? printedIdentifier.value
        : this.printedIdentifier,
    currentRevisionOrigin: currentRevisionOrigin ?? this.currentRevisionOrigin,
    currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  Store copyWithCompanion(StoresCompanion data) {
    return Store(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      chain: data.chain.present ? data.chain.value : this.chain,
      address: data.address.present ? data.address.value : this.address,
      printedIdentifier: data.printedIdentifier.present
          ? data.printedIdentifier.value
          : this.printedIdentifier,
      currentRevisionOrigin: data.currentRevisionOrigin.present
          ? data.currentRevisionOrigin.value
          : this.currentRevisionOrigin,
      currentRevisionSeq: data.currentRevisionSeq.present
          ? data.currentRevisionSeq.value
          : this.currentRevisionSeq,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Store(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('chain: $chain, ')
          ..write('address: $address, ')
          ..write('printedIdentifier: $printedIdentifier, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    chain,
    address,
    printedIdentifier,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Store &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.chain == this.chain &&
          other.address == this.address &&
          other.printedIdentifier == this.printedIdentifier &&
          other.currentRevisionOrigin == this.currentRevisionOrigin &&
          other.currentRevisionSeq == this.currentRevisionSeq &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class StoresCompanion extends UpdateCompanion<Store> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String?> chain;
  final Value<String?> address;
  final Value<String?> printedIdentifier;
  final Value<String> currentRevisionOrigin;
  final Value<int> currentRevisionSeq;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const StoresCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.chain = const Value.absent(),
    this.address = const Value.absent(),
    this.printedIdentifier = const Value.absent(),
    this.currentRevisionOrigin = const Value.absent(),
    this.currentRevisionSeq = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoresCompanion.insert({
    required String id,
    required String displayName,
    this.chain = const Value.absent(),
    this.address = const Value.absent(),
    this.printedIdentifier = const Value.absent(),
    required String currentRevisionOrigin,
    required int currentRevisionSeq,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName),
       currentRevisionOrigin = Value(currentRevisionOrigin),
       currentRevisionSeq = Value(currentRevisionSeq),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<Store> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? chain,
    Expression<String>? address,
    Expression<String>? printedIdentifier,
    Expression<String>? currentRevisionOrigin,
    Expression<int>? currentRevisionSeq,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (chain != null) 'chain': chain,
      if (address != null) 'address': address,
      if (printedIdentifier != null) 'printed_identifier': printedIdentifier,
      if (currentRevisionOrigin != null)
        'current_revision_origin': currentRevisionOrigin,
      if (currentRevisionSeq != null)
        'current_revision_seq': currentRevisionSeq,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoresCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<String?>? chain,
    Value<String?>? address,
    Value<String?>? printedIdentifier,
    Value<String>? currentRevisionOrigin,
    Value<int>? currentRevisionSeq,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return StoresCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      chain: chain ?? this.chain,
      address: address ?? this.address,
      printedIdentifier: printedIdentifier ?? this.printedIdentifier,
      currentRevisionOrigin:
          currentRevisionOrigin ?? this.currentRevisionOrigin,
      currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (chain.present) {
      map['chain'] = Variable<String>(chain.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (printedIdentifier.present) {
      map['printed_identifier'] = Variable<String>(printedIdentifier.value);
    }
    if (currentRevisionOrigin.present) {
      map['current_revision_origin'] = Variable<String>(
        currentRevisionOrigin.value,
      );
    }
    if (currentRevisionSeq.present) {
      map['current_revision_seq'] = Variable<int>(currentRevisionSeq.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoresCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('chain: $chain, ')
          ..write('address: $address, ')
          ..write('printedIdentifier: $printedIdentifier, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Receipts extends Table with TableInfo<Receipts, Receipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Receipts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  late final GeneratedColumn<int> isDeleted = GeneratedColumn<int>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'REFERENCES stores(id)',
  );
  static const VerificationMeta _printedYearMeta = const VerificationMeta(
    'printedYear',
  );
  late final GeneratedColumn<int> printedYear = GeneratedColumn<int>(
    'printed_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (printed_year BETWEEN 1970 AND 2099)',
  );
  static const VerificationMeta _printedMonthMeta = const VerificationMeta(
    'printedMonth',
  );
  late final GeneratedColumn<int> printedMonth = GeneratedColumn<int>(
    'printed_month',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (printed_month BETWEEN 1 AND 12)',
  );
  static const VerificationMeta _printedDayMeta = const VerificationMeta(
    'printedDay',
  );
  late final GeneratedColumn<int> printedDay = GeneratedColumn<int>(
    'printed_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (printed_day BETWEEN 1 AND 31)',
  );
  static const VerificationMeta _printedHourMeta = const VerificationMeta(
    'printedHour',
  );
  late final GeneratedColumn<int> printedHour = GeneratedColumn<int>(
    'printed_hour',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (printed_hour IS NULL OR printed_hour BETWEEN 0 AND 23)',
  );
  static const VerificationMeta _printedMinuteMeta = const VerificationMeta(
    'printedMinute',
  );
  late final GeneratedColumn<int> printedMinute = GeneratedColumn<int>(
    'printed_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (printed_minute IS NULL OR printed_minute BETWEEN 0 AND 59)',
  );
  static const VerificationMeta _printedSecondMeta = const VerificationMeta(
    'printedSecond',
  );
  late final GeneratedColumn<int> printedSecond = GeneratedColumn<int>(
    'printed_second',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (printed_second IS NULL OR printed_second BETWEEN 0 AND 59)',
  );
  static const VerificationMeta _datePrecisionMeta = const VerificationMeta(
    'datePrecision',
  );
  late final GeneratedColumn<String> datePrecision = GeneratedColumn<String>(
    'date_precision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (date_precision IN (\'day\', \'minute\', \'second\'))',
  );
  static const VerificationMeta _timezoneIdMeta = const VerificationMeta(
    'timezoneId',
  );
  late final GeneratedColumn<String> timezoneId = GeneratedColumn<String>(
    'timezone_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (timezone_id = \'Europe/Helsinki\')',
  );
  static const VerificationMeta _utcInstantMsMeta = const VerificationMeta(
    'utcInstantMs',
  );
  late final GeneratedColumn<int> utcInstantMs = GeneratedColumn<int>(
    'utc_instant_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (currency = \'EUR\')',
  );
  static const VerificationMeta _totalAmountCentsMeta = const VerificationMeta(
    'totalAmountCents',
  );
  late final GeneratedColumn<int> totalAmountCents = GeneratedColumn<int>(
    'total_amount_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _reviewedAtMsMeta = const VerificationMeta(
    'reviewedAtMs',
  );
  late final GeneratedColumn<int> reviewedAtMs = GeneratedColumn<int>(
    'reviewed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (reviewed_at_ms >= 0)',
  );
  static const VerificationMeta _currentRevisionOriginMeta =
      const VerificationMeta('currentRevisionOrigin');
  late final GeneratedColumn<String> currentRevisionOrigin =
      GeneratedColumn<String>(
        'current_revision_origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _currentRevisionSeqMeta =
      const VerificationMeta('currentRevisionSeq');
  late final GeneratedColumn<int> currentRevisionSeq = GeneratedColumn<int>(
    'current_revision_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (created_at_ms >= 0)',
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (updated_at_ms >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isDeleted,
    storeId,
    printedYear,
    printedMonth,
    printedDay,
    printedHour,
    printedMinute,
    printedSecond,
    datePrecision,
    timezoneId,
    utcInstantMs,
    currency,
    totalAmountCents,
    reviewedAtMs,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Receipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('printed_year')) {
      context.handle(
        _printedYearMeta,
        printedYear.isAcceptableOrUnknown(
          data['printed_year']!,
          _printedYearMeta,
        ),
      );
    }
    if (data.containsKey('printed_month')) {
      context.handle(
        _printedMonthMeta,
        printedMonth.isAcceptableOrUnknown(
          data['printed_month']!,
          _printedMonthMeta,
        ),
      );
    }
    if (data.containsKey('printed_day')) {
      context.handle(
        _printedDayMeta,
        printedDay.isAcceptableOrUnknown(data['printed_day']!, _printedDayMeta),
      );
    }
    if (data.containsKey('printed_hour')) {
      context.handle(
        _printedHourMeta,
        printedHour.isAcceptableOrUnknown(
          data['printed_hour']!,
          _printedHourMeta,
        ),
      );
    }
    if (data.containsKey('printed_minute')) {
      context.handle(
        _printedMinuteMeta,
        printedMinute.isAcceptableOrUnknown(
          data['printed_minute']!,
          _printedMinuteMeta,
        ),
      );
    }
    if (data.containsKey('printed_second')) {
      context.handle(
        _printedSecondMeta,
        printedSecond.isAcceptableOrUnknown(
          data['printed_second']!,
          _printedSecondMeta,
        ),
      );
    }
    if (data.containsKey('date_precision')) {
      context.handle(
        _datePrecisionMeta,
        datePrecision.isAcceptableOrUnknown(
          data['date_precision']!,
          _datePrecisionMeta,
        ),
      );
    }
    if (data.containsKey('timezone_id')) {
      context.handle(
        _timezoneIdMeta,
        timezoneId.isAcceptableOrUnknown(data['timezone_id']!, _timezoneIdMeta),
      );
    }
    if (data.containsKey('utc_instant_ms')) {
      context.handle(
        _utcInstantMsMeta,
        utcInstantMs.isAcceptableOrUnknown(
          data['utc_instant_ms']!,
          _utcInstantMsMeta,
        ),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('total_amount_cents')) {
      context.handle(
        _totalAmountCentsMeta,
        totalAmountCents.isAcceptableOrUnknown(
          data['total_amount_cents']!,
          _totalAmountCentsMeta,
        ),
      );
    }
    if (data.containsKey('reviewed_at_ms')) {
      context.handle(
        _reviewedAtMsMeta,
        reviewedAtMs.isAcceptableOrUnknown(
          data['reviewed_at_ms']!,
          _reviewedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('current_revision_origin')) {
      context.handle(
        _currentRevisionOriginMeta,
        currentRevisionOrigin.isAcceptableOrUnknown(
          data['current_revision_origin']!,
          _currentRevisionOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionOriginMeta);
    }
    if (data.containsKey('current_revision_seq')) {
      context.handle(
        _currentRevisionSeqMeta,
        currentRevisionSeq.isAcceptableOrUnknown(
          data['current_revision_seq']!,
          _currentRevisionSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionSeqMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {id, storeId},
  ];
  @override
  Receipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Receipt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_deleted'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      printedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_year'],
      ),
      printedMonth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_month'],
      ),
      printedDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_day'],
      ),
      printedHour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_hour'],
      ),
      printedMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_minute'],
      ),
      printedSecond: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}printed_second'],
      ),
      datePrecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_precision'],
      ),
      timezoneId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone_id'],
      ),
      utcInstantMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}utc_instant_ms'],
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      ),
      totalAmountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_amount_cents'],
      ),
      reviewedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed_at_ms'],
      ),
      currentRevisionOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_origin'],
      )!,
      currentRevisionSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision_seq'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  Receipts createAlias(String alias) {
    return Receipts(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'UNIQUE(id, store_id)',
    'FOREIGN KEY(current_revision_origin, current_revision_seq)REFERENCES change_log(origin_device_id, origin_seq)',
    'CHECK(is_deleted = 1 OR((date_precision = \'day\' AND printed_hour IS NULL AND printed_minute IS NULL AND printed_second IS NULL AND utc_instant_ms IS NULL)OR(date_precision = \'minute\' AND printed_hour IS NOT NULL AND printed_minute IS NOT NULL AND printed_second IS NULL AND utc_instant_ms IS NOT NULL)OR(date_precision = \'second\' AND printed_hour IS NOT NULL AND printed_minute IS NOT NULL AND printed_second IS NOT NULL AND utc_instant_ms IS NOT NULL)))',
    'CHECK((is_deleted = 0 AND store_id IS NOT NULL AND printed_year IS NOT NULL AND printed_month IS NOT NULL AND printed_day IS NOT NULL AND date_precision IS NOT NULL AND timezone_id IS NOT NULL AND currency IS NOT NULL AND total_amount_cents IS NOT NULL AND reviewed_at_ms IS NOT NULL)OR(is_deleted = 1 AND store_id IS NULL AND printed_year IS NULL AND printed_month IS NULL AND printed_day IS NULL AND printed_hour IS NULL AND printed_minute IS NULL AND printed_second IS NULL AND date_precision IS NULL AND timezone_id IS NULL AND utc_instant_ms IS NULL AND currency IS NULL AND total_amount_cents IS NULL AND reviewed_at_ms IS NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Receipt extends DataClass implements Insertable<Receipt> {
  final String id;
  final int isDeleted;
  final String? storeId;
  final int? printedYear;
  final int? printedMonth;
  final int? printedDay;
  final int? printedHour;
  final int? printedMinute;
  final int? printedSecond;
  final String? datePrecision;
  final String? timezoneId;
  final int? utcInstantMs;
  final String? currency;
  final int? totalAmountCents;
  final int? reviewedAtMs;
  final String currentRevisionOrigin;
  final int currentRevisionSeq;
  final int createdAtMs;
  final int updatedAtMs;
  const Receipt({
    required this.id,
    required this.isDeleted,
    this.storeId,
    this.printedYear,
    this.printedMonth,
    this.printedDay,
    this.printedHour,
    this.printedMinute,
    this.printedSecond,
    this.datePrecision,
    this.timezoneId,
    this.utcInstantMs,
    this.currency,
    this.totalAmountCents,
    this.reviewedAtMs,
    required this.currentRevisionOrigin,
    required this.currentRevisionSeq,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['is_deleted'] = Variable<int>(isDeleted);
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    if (!nullToAbsent || printedYear != null) {
      map['printed_year'] = Variable<int>(printedYear);
    }
    if (!nullToAbsent || printedMonth != null) {
      map['printed_month'] = Variable<int>(printedMonth);
    }
    if (!nullToAbsent || printedDay != null) {
      map['printed_day'] = Variable<int>(printedDay);
    }
    if (!nullToAbsent || printedHour != null) {
      map['printed_hour'] = Variable<int>(printedHour);
    }
    if (!nullToAbsent || printedMinute != null) {
      map['printed_minute'] = Variable<int>(printedMinute);
    }
    if (!nullToAbsent || printedSecond != null) {
      map['printed_second'] = Variable<int>(printedSecond);
    }
    if (!nullToAbsent || datePrecision != null) {
      map['date_precision'] = Variable<String>(datePrecision);
    }
    if (!nullToAbsent || timezoneId != null) {
      map['timezone_id'] = Variable<String>(timezoneId);
    }
    if (!nullToAbsent || utcInstantMs != null) {
      map['utc_instant_ms'] = Variable<int>(utcInstantMs);
    }
    if (!nullToAbsent || currency != null) {
      map['currency'] = Variable<String>(currency);
    }
    if (!nullToAbsent || totalAmountCents != null) {
      map['total_amount_cents'] = Variable<int>(totalAmountCents);
    }
    if (!nullToAbsent || reviewedAtMs != null) {
      map['reviewed_at_ms'] = Variable<int>(reviewedAtMs);
    }
    map['current_revision_origin'] = Variable<String>(currentRevisionOrigin);
    map['current_revision_seq'] = Variable<int>(currentRevisionSeq);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptsCompanion(
      id: Value(id),
      isDeleted: Value(isDeleted),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      printedYear: printedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(printedYear),
      printedMonth: printedMonth == null && nullToAbsent
          ? const Value.absent()
          : Value(printedMonth),
      printedDay: printedDay == null && nullToAbsent
          ? const Value.absent()
          : Value(printedDay),
      printedHour: printedHour == null && nullToAbsent
          ? const Value.absent()
          : Value(printedHour),
      printedMinute: printedMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(printedMinute),
      printedSecond: printedSecond == null && nullToAbsent
          ? const Value.absent()
          : Value(printedSecond),
      datePrecision: datePrecision == null && nullToAbsent
          ? const Value.absent()
          : Value(datePrecision),
      timezoneId: timezoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(timezoneId),
      utcInstantMs: utcInstantMs == null && nullToAbsent
          ? const Value.absent()
          : Value(utcInstantMs),
      currency: currency == null && nullToAbsent
          ? const Value.absent()
          : Value(currency),
      totalAmountCents: totalAmountCents == null && nullToAbsent
          ? const Value.absent()
          : Value(totalAmountCents),
      reviewedAtMs: reviewedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedAtMs),
      currentRevisionOrigin: Value(currentRevisionOrigin),
      currentRevisionSeq: Value(currentRevisionSeq),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory Receipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Receipt(
      id: serializer.fromJson<String>(json['id']),
      isDeleted: serializer.fromJson<int>(json['is_deleted']),
      storeId: serializer.fromJson<String?>(json['store_id']),
      printedYear: serializer.fromJson<int?>(json['printed_year']),
      printedMonth: serializer.fromJson<int?>(json['printed_month']),
      printedDay: serializer.fromJson<int?>(json['printed_day']),
      printedHour: serializer.fromJson<int?>(json['printed_hour']),
      printedMinute: serializer.fromJson<int?>(json['printed_minute']),
      printedSecond: serializer.fromJson<int?>(json['printed_second']),
      datePrecision: serializer.fromJson<String?>(json['date_precision']),
      timezoneId: serializer.fromJson<String?>(json['timezone_id']),
      utcInstantMs: serializer.fromJson<int?>(json['utc_instant_ms']),
      currency: serializer.fromJson<String?>(json['currency']),
      totalAmountCents: serializer.fromJson<int?>(json['total_amount_cents']),
      reviewedAtMs: serializer.fromJson<int?>(json['reviewed_at_ms']),
      currentRevisionOrigin: serializer.fromJson<String>(
        json['current_revision_origin'],
      ),
      currentRevisionSeq: serializer.fromJson<int>(
        json['current_revision_seq'],
      ),
      createdAtMs: serializer.fromJson<int>(json['created_at_ms']),
      updatedAtMs: serializer.fromJson<int>(json['updated_at_ms']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'is_deleted': serializer.toJson<int>(isDeleted),
      'store_id': serializer.toJson<String?>(storeId),
      'printed_year': serializer.toJson<int?>(printedYear),
      'printed_month': serializer.toJson<int?>(printedMonth),
      'printed_day': serializer.toJson<int?>(printedDay),
      'printed_hour': serializer.toJson<int?>(printedHour),
      'printed_minute': serializer.toJson<int?>(printedMinute),
      'printed_second': serializer.toJson<int?>(printedSecond),
      'date_precision': serializer.toJson<String?>(datePrecision),
      'timezone_id': serializer.toJson<String?>(timezoneId),
      'utc_instant_ms': serializer.toJson<int?>(utcInstantMs),
      'currency': serializer.toJson<String?>(currency),
      'total_amount_cents': serializer.toJson<int?>(totalAmountCents),
      'reviewed_at_ms': serializer.toJson<int?>(reviewedAtMs),
      'current_revision_origin': serializer.toJson<String>(
        currentRevisionOrigin,
      ),
      'current_revision_seq': serializer.toJson<int>(currentRevisionSeq),
      'created_at_ms': serializer.toJson<int>(createdAtMs),
      'updated_at_ms': serializer.toJson<int>(updatedAtMs),
    };
  }

  Receipt copyWith({
    String? id,
    int? isDeleted,
    Value<String?> storeId = const Value.absent(),
    Value<int?> printedYear = const Value.absent(),
    Value<int?> printedMonth = const Value.absent(),
    Value<int?> printedDay = const Value.absent(),
    Value<int?> printedHour = const Value.absent(),
    Value<int?> printedMinute = const Value.absent(),
    Value<int?> printedSecond = const Value.absent(),
    Value<String?> datePrecision = const Value.absent(),
    Value<String?> timezoneId = const Value.absent(),
    Value<int?> utcInstantMs = const Value.absent(),
    Value<String?> currency = const Value.absent(),
    Value<int?> totalAmountCents = const Value.absent(),
    Value<int?> reviewedAtMs = const Value.absent(),
    String? currentRevisionOrigin,
    int? currentRevisionSeq,
    int? createdAtMs,
    int? updatedAtMs,
  }) => Receipt(
    id: id ?? this.id,
    isDeleted: isDeleted ?? this.isDeleted,
    storeId: storeId.present ? storeId.value : this.storeId,
    printedYear: printedYear.present ? printedYear.value : this.printedYear,
    printedMonth: printedMonth.present ? printedMonth.value : this.printedMonth,
    printedDay: printedDay.present ? printedDay.value : this.printedDay,
    printedHour: printedHour.present ? printedHour.value : this.printedHour,
    printedMinute: printedMinute.present
        ? printedMinute.value
        : this.printedMinute,
    printedSecond: printedSecond.present
        ? printedSecond.value
        : this.printedSecond,
    datePrecision: datePrecision.present
        ? datePrecision.value
        : this.datePrecision,
    timezoneId: timezoneId.present ? timezoneId.value : this.timezoneId,
    utcInstantMs: utcInstantMs.present ? utcInstantMs.value : this.utcInstantMs,
    currency: currency.present ? currency.value : this.currency,
    totalAmountCents: totalAmountCents.present
        ? totalAmountCents.value
        : this.totalAmountCents,
    reviewedAtMs: reviewedAtMs.present ? reviewedAtMs.value : this.reviewedAtMs,
    currentRevisionOrigin: currentRevisionOrigin ?? this.currentRevisionOrigin,
    currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  Receipt copyWithCompanion(ReceiptsCompanion data) {
    return Receipt(
      id: data.id.present ? data.id.value : this.id,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      printedYear: data.printedYear.present
          ? data.printedYear.value
          : this.printedYear,
      printedMonth: data.printedMonth.present
          ? data.printedMonth.value
          : this.printedMonth,
      printedDay: data.printedDay.present
          ? data.printedDay.value
          : this.printedDay,
      printedHour: data.printedHour.present
          ? data.printedHour.value
          : this.printedHour,
      printedMinute: data.printedMinute.present
          ? data.printedMinute.value
          : this.printedMinute,
      printedSecond: data.printedSecond.present
          ? data.printedSecond.value
          : this.printedSecond,
      datePrecision: data.datePrecision.present
          ? data.datePrecision.value
          : this.datePrecision,
      timezoneId: data.timezoneId.present
          ? data.timezoneId.value
          : this.timezoneId,
      utcInstantMs: data.utcInstantMs.present
          ? data.utcInstantMs.value
          : this.utcInstantMs,
      currency: data.currency.present ? data.currency.value : this.currency,
      totalAmountCents: data.totalAmountCents.present
          ? data.totalAmountCents.value
          : this.totalAmountCents,
      reviewedAtMs: data.reviewedAtMs.present
          ? data.reviewedAtMs.value
          : this.reviewedAtMs,
      currentRevisionOrigin: data.currentRevisionOrigin.present
          ? data.currentRevisionOrigin.value
          : this.currentRevisionOrigin,
      currentRevisionSeq: data.currentRevisionSeq.present
          ? data.currentRevisionSeq.value
          : this.currentRevisionSeq,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Receipt(')
          ..write('id: $id, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('storeId: $storeId, ')
          ..write('printedYear: $printedYear, ')
          ..write('printedMonth: $printedMonth, ')
          ..write('printedDay: $printedDay, ')
          ..write('printedHour: $printedHour, ')
          ..write('printedMinute: $printedMinute, ')
          ..write('printedSecond: $printedSecond, ')
          ..write('datePrecision: $datePrecision, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('utcInstantMs: $utcInstantMs, ')
          ..write('currency: $currency, ')
          ..write('totalAmountCents: $totalAmountCents, ')
          ..write('reviewedAtMs: $reviewedAtMs, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isDeleted,
    storeId,
    printedYear,
    printedMonth,
    printedDay,
    printedHour,
    printedMinute,
    printedSecond,
    datePrecision,
    timezoneId,
    utcInstantMs,
    currency,
    totalAmountCents,
    reviewedAtMs,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Receipt &&
          other.id == this.id &&
          other.isDeleted == this.isDeleted &&
          other.storeId == this.storeId &&
          other.printedYear == this.printedYear &&
          other.printedMonth == this.printedMonth &&
          other.printedDay == this.printedDay &&
          other.printedHour == this.printedHour &&
          other.printedMinute == this.printedMinute &&
          other.printedSecond == this.printedSecond &&
          other.datePrecision == this.datePrecision &&
          other.timezoneId == this.timezoneId &&
          other.utcInstantMs == this.utcInstantMs &&
          other.currency == this.currency &&
          other.totalAmountCents == this.totalAmountCents &&
          other.reviewedAtMs == this.reviewedAtMs &&
          other.currentRevisionOrigin == this.currentRevisionOrigin &&
          other.currentRevisionSeq == this.currentRevisionSeq &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ReceiptsCompanion extends UpdateCompanion<Receipt> {
  final Value<String> id;
  final Value<int> isDeleted;
  final Value<String?> storeId;
  final Value<int?> printedYear;
  final Value<int?> printedMonth;
  final Value<int?> printedDay;
  final Value<int?> printedHour;
  final Value<int?> printedMinute;
  final Value<int?> printedSecond;
  final Value<String?> datePrecision;
  final Value<String?> timezoneId;
  final Value<int?> utcInstantMs;
  final Value<String?> currency;
  final Value<int?> totalAmountCents;
  final Value<int?> reviewedAtMs;
  final Value<String> currentRevisionOrigin;
  final Value<int> currentRevisionSeq;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ReceiptsCompanion({
    this.id = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.storeId = const Value.absent(),
    this.printedYear = const Value.absent(),
    this.printedMonth = const Value.absent(),
    this.printedDay = const Value.absent(),
    this.printedHour = const Value.absent(),
    this.printedMinute = const Value.absent(),
    this.printedSecond = const Value.absent(),
    this.datePrecision = const Value.absent(),
    this.timezoneId = const Value.absent(),
    this.utcInstantMs = const Value.absent(),
    this.currency = const Value.absent(),
    this.totalAmountCents = const Value.absent(),
    this.reviewedAtMs = const Value.absent(),
    this.currentRevisionOrigin = const Value.absent(),
    this.currentRevisionSeq = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptsCompanion.insert({
    required String id,
    this.isDeleted = const Value.absent(),
    this.storeId = const Value.absent(),
    this.printedYear = const Value.absent(),
    this.printedMonth = const Value.absent(),
    this.printedDay = const Value.absent(),
    this.printedHour = const Value.absent(),
    this.printedMinute = const Value.absent(),
    this.printedSecond = const Value.absent(),
    this.datePrecision = const Value.absent(),
    this.timezoneId = const Value.absent(),
    this.utcInstantMs = const Value.absent(),
    this.currency = const Value.absent(),
    this.totalAmountCents = const Value.absent(),
    this.reviewedAtMs = const Value.absent(),
    required String currentRevisionOrigin,
    required int currentRevisionSeq,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       currentRevisionOrigin = Value(currentRevisionOrigin),
       currentRevisionSeq = Value(currentRevisionSeq),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<Receipt> custom({
    Expression<String>? id,
    Expression<int>? isDeleted,
    Expression<String>? storeId,
    Expression<int>? printedYear,
    Expression<int>? printedMonth,
    Expression<int>? printedDay,
    Expression<int>? printedHour,
    Expression<int>? printedMinute,
    Expression<int>? printedSecond,
    Expression<String>? datePrecision,
    Expression<String>? timezoneId,
    Expression<int>? utcInstantMs,
    Expression<String>? currency,
    Expression<int>? totalAmountCents,
    Expression<int>? reviewedAtMs,
    Expression<String>? currentRevisionOrigin,
    Expression<int>? currentRevisionSeq,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (storeId != null) 'store_id': storeId,
      if (printedYear != null) 'printed_year': printedYear,
      if (printedMonth != null) 'printed_month': printedMonth,
      if (printedDay != null) 'printed_day': printedDay,
      if (printedHour != null) 'printed_hour': printedHour,
      if (printedMinute != null) 'printed_minute': printedMinute,
      if (printedSecond != null) 'printed_second': printedSecond,
      if (datePrecision != null) 'date_precision': datePrecision,
      if (timezoneId != null) 'timezone_id': timezoneId,
      if (utcInstantMs != null) 'utc_instant_ms': utcInstantMs,
      if (currency != null) 'currency': currency,
      if (totalAmountCents != null) 'total_amount_cents': totalAmountCents,
      if (reviewedAtMs != null) 'reviewed_at_ms': reviewedAtMs,
      if (currentRevisionOrigin != null)
        'current_revision_origin': currentRevisionOrigin,
      if (currentRevisionSeq != null)
        'current_revision_seq': currentRevisionSeq,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptsCompanion copyWith({
    Value<String>? id,
    Value<int>? isDeleted,
    Value<String?>? storeId,
    Value<int?>? printedYear,
    Value<int?>? printedMonth,
    Value<int?>? printedDay,
    Value<int?>? printedHour,
    Value<int?>? printedMinute,
    Value<int?>? printedSecond,
    Value<String?>? datePrecision,
    Value<String?>? timezoneId,
    Value<int?>? utcInstantMs,
    Value<String?>? currency,
    Value<int?>? totalAmountCents,
    Value<int?>? reviewedAtMs,
    Value<String>? currentRevisionOrigin,
    Value<int>? currentRevisionSeq,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ReceiptsCompanion(
      id: id ?? this.id,
      isDeleted: isDeleted ?? this.isDeleted,
      storeId: storeId ?? this.storeId,
      printedYear: printedYear ?? this.printedYear,
      printedMonth: printedMonth ?? this.printedMonth,
      printedDay: printedDay ?? this.printedDay,
      printedHour: printedHour ?? this.printedHour,
      printedMinute: printedMinute ?? this.printedMinute,
      printedSecond: printedSecond ?? this.printedSecond,
      datePrecision: datePrecision ?? this.datePrecision,
      timezoneId: timezoneId ?? this.timezoneId,
      utcInstantMs: utcInstantMs ?? this.utcInstantMs,
      currency: currency ?? this.currency,
      totalAmountCents: totalAmountCents ?? this.totalAmountCents,
      reviewedAtMs: reviewedAtMs ?? this.reviewedAtMs,
      currentRevisionOrigin:
          currentRevisionOrigin ?? this.currentRevisionOrigin,
      currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<int>(isDeleted.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (printedYear.present) {
      map['printed_year'] = Variable<int>(printedYear.value);
    }
    if (printedMonth.present) {
      map['printed_month'] = Variable<int>(printedMonth.value);
    }
    if (printedDay.present) {
      map['printed_day'] = Variable<int>(printedDay.value);
    }
    if (printedHour.present) {
      map['printed_hour'] = Variable<int>(printedHour.value);
    }
    if (printedMinute.present) {
      map['printed_minute'] = Variable<int>(printedMinute.value);
    }
    if (printedSecond.present) {
      map['printed_second'] = Variable<int>(printedSecond.value);
    }
    if (datePrecision.present) {
      map['date_precision'] = Variable<String>(datePrecision.value);
    }
    if (timezoneId.present) {
      map['timezone_id'] = Variable<String>(timezoneId.value);
    }
    if (utcInstantMs.present) {
      map['utc_instant_ms'] = Variable<int>(utcInstantMs.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (totalAmountCents.present) {
      map['total_amount_cents'] = Variable<int>(totalAmountCents.value);
    }
    if (reviewedAtMs.present) {
      map['reviewed_at_ms'] = Variable<int>(reviewedAtMs.value);
    }
    if (currentRevisionOrigin.present) {
      map['current_revision_origin'] = Variable<String>(
        currentRevisionOrigin.value,
      );
    }
    if (currentRevisionSeq.present) {
      map['current_revision_seq'] = Variable<int>(currentRevisionSeq.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptsCompanion(')
          ..write('id: $id, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('storeId: $storeId, ')
          ..write('printedYear: $printedYear, ')
          ..write('printedMonth: $printedMonth, ')
          ..write('printedDay: $printedDay, ')
          ..write('printedHour: $printedHour, ')
          ..write('printedMinute: $printedMinute, ')
          ..write('printedSecond: $printedSecond, ')
          ..write('datePrecision: $datePrecision, ')
          ..write('timezoneId: $timezoneId, ')
          ..write('utcInstantMs: $utcInstantMs, ')
          ..write('currency: $currency, ')
          ..write('totalAmountCents: $totalAmountCents, ')
          ..write('reviewedAtMs: $reviewedAtMs, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class RowIdentities extends Table with TableInfo<RowIdentities, RowIdentity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RowIdentities(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(row_id) = 36 AND row_id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(row_id, \'-\', \'\')) = 32 AND "replace"(row_id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES receipts(id)',
  );
  static const VerificationMeta _firstOriginMeta = const VerificationMeta(
    'firstOrigin',
  );
  late final GeneratedColumn<String> firstOrigin = GeneratedColumn<String>(
    'first_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _firstSeqMeta = const VerificationMeta(
    'firstSeq',
  );
  late final GeneratedColumn<int> firstSeq = GeneratedColumn<int>(
    'first_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowId,
    receiptId,
    firstOrigin,
    firstSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'row_identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<RowIdentity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('first_origin')) {
      context.handle(
        _firstOriginMeta,
        firstOrigin.isAcceptableOrUnknown(
          data['first_origin']!,
          _firstOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstOriginMeta);
    }
    if (data.containsKey('first_seq')) {
      context.handle(
        _firstSeqMeta,
        firstSeq.isAcceptableOrUnknown(data['first_seq']!, _firstSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {receiptId, rowId},
  ];
  @override
  RowIdentity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RowIdentity(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      firstOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_origin'],
      )!,
      firstSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seq'],
      )!,
    );
  }

  @override
  RowIdentities createAlias(String alias) {
    return RowIdentities(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'UNIQUE(receipt_id, row_id)',
    'FOREIGN KEY(first_origin, first_seq)REFERENCES change_log(origin_device_id, origin_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class RowIdentity extends DataClass implements Insertable<RowIdentity> {
  final String rowId;
  final String receiptId;
  final String firstOrigin;
  final int firstSeq;
  const RowIdentity({
    required this.rowId,
    required this.receiptId,
    required this.firstOrigin,
    required this.firstSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<String>(rowId);
    map['receipt_id'] = Variable<String>(receiptId);
    map['first_origin'] = Variable<String>(firstOrigin);
    map['first_seq'] = Variable<int>(firstSeq);
    return map;
  }

  RowIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return RowIdentitiesCompanion(
      rowId: Value(rowId),
      receiptId: Value(receiptId),
      firstOrigin: Value(firstOrigin),
      firstSeq: Value(firstSeq),
    );
  }

  factory RowIdentity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RowIdentity(
      rowId: serializer.fromJson<String>(json['row_id']),
      receiptId: serializer.fromJson<String>(json['receipt_id']),
      firstOrigin: serializer.fromJson<String>(json['first_origin']),
      firstSeq: serializer.fromJson<int>(json['first_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'row_id': serializer.toJson<String>(rowId),
      'receipt_id': serializer.toJson<String>(receiptId),
      'first_origin': serializer.toJson<String>(firstOrigin),
      'first_seq': serializer.toJson<int>(firstSeq),
    };
  }

  RowIdentity copyWith({
    String? rowId,
    String? receiptId,
    String? firstOrigin,
    int? firstSeq,
  }) => RowIdentity(
    rowId: rowId ?? this.rowId,
    receiptId: receiptId ?? this.receiptId,
    firstOrigin: firstOrigin ?? this.firstOrigin,
    firstSeq: firstSeq ?? this.firstSeq,
  );
  RowIdentity copyWithCompanion(RowIdentitiesCompanion data) {
    return RowIdentity(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      firstOrigin: data.firstOrigin.present
          ? data.firstOrigin.value
          : this.firstOrigin,
      firstSeq: data.firstSeq.present ? data.firstSeq.value : this.firstSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RowIdentity(')
          ..write('rowId: $rowId, ')
          ..write('receiptId: $receiptId, ')
          ..write('firstOrigin: $firstOrigin, ')
          ..write('firstSeq: $firstSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rowId, receiptId, firstOrigin, firstSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RowIdentity &&
          other.rowId == this.rowId &&
          other.receiptId == this.receiptId &&
          other.firstOrigin == this.firstOrigin &&
          other.firstSeq == this.firstSeq);
}

class RowIdentitiesCompanion extends UpdateCompanion<RowIdentity> {
  final Value<String> rowId;
  final Value<String> receiptId;
  final Value<String> firstOrigin;
  final Value<int> firstSeq;
  final Value<int> rowid;
  const RowIdentitiesCompanion({
    this.rowId = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.firstOrigin = const Value.absent(),
    this.firstSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RowIdentitiesCompanion.insert({
    required String rowId,
    required String receiptId,
    required String firstOrigin,
    required int firstSeq,
    this.rowid = const Value.absent(),
  }) : rowId = Value(rowId),
       receiptId = Value(receiptId),
       firstOrigin = Value(firstOrigin),
       firstSeq = Value(firstSeq);
  static Insertable<RowIdentity> custom({
    Expression<String>? rowId,
    Expression<String>? receiptId,
    Expression<String>? firstOrigin,
    Expression<int>? firstSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (receiptId != null) 'receipt_id': receiptId,
      if (firstOrigin != null) 'first_origin': firstOrigin,
      if (firstSeq != null) 'first_seq': firstSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RowIdentitiesCompanion copyWith({
    Value<String>? rowId,
    Value<String>? receiptId,
    Value<String>? firstOrigin,
    Value<int>? firstSeq,
    Value<int>? rowid,
  }) {
    return RowIdentitiesCompanion(
      rowId: rowId ?? this.rowId,
      receiptId: receiptId ?? this.receiptId,
      firstOrigin: firstOrigin ?? this.firstOrigin,
      firstSeq: firstSeq ?? this.firstSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (firstOrigin.present) {
      map['first_origin'] = Variable<String>(firstOrigin.value);
    }
    if (firstSeq.present) {
      map['first_seq'] = Variable<int>(firstSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RowIdentitiesCompanion(')
          ..write('rowId: $rowId, ')
          ..write('receiptId: $receiptId, ')
          ..write('firstOrigin: $firstOrigin, ')
          ..write('firstSeq: $firstSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Products extends Table with TableInfo<Products, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Products(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES stores(id)',
  );
  static const VerificationMeta _canonicalNameMeta = const VerificationMeta(
    'canonicalName',
  );
  late final GeneratedColumn<String> canonicalName = GeneratedColumn<String>(
    'canonical_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(canonical_name)) > 0 AND canonical_name = trim(canonical_name))',
  );
  static const VerificationMeta _packageValueMeta = const VerificationMeta(
    'packageValue',
  );
  late final GeneratedColumn<int> packageValue = GeneratedColumn<int>(
    'package_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _packageScaleMeta = const VerificationMeta(
    'packageScale',
  );
  late final GeneratedColumn<int> packageScale = GeneratedColumn<int>(
    'package_scale',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _packageUnitMeta = const VerificationMeta(
    'packageUnit',
  );
  late final GeneratedColumn<String> packageUnit = GeneratedColumn<String>(
    'package_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _currentRevisionOriginMeta =
      const VerificationMeta('currentRevisionOrigin');
  late final GeneratedColumn<String> currentRevisionOrigin =
      GeneratedColumn<String>(
        'current_revision_origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _currentRevisionSeqMeta =
      const VerificationMeta('currentRevisionSeq');
  late final GeneratedColumn<int> currentRevisionSeq = GeneratedColumn<int>(
    'current_revision_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (created_at_ms >= 0)',
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (updated_at_ms >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    storeId,
    canonicalName,
    packageValue,
    packageScale,
    packageUnit,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('canonical_name')) {
      context.handle(
        _canonicalNameMeta,
        canonicalName.isAcceptableOrUnknown(
          data['canonical_name']!,
          _canonicalNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalNameMeta);
    }
    if (data.containsKey('package_value')) {
      context.handle(
        _packageValueMeta,
        packageValue.isAcceptableOrUnknown(
          data['package_value']!,
          _packageValueMeta,
        ),
      );
    }
    if (data.containsKey('package_scale')) {
      context.handle(
        _packageScaleMeta,
        packageScale.isAcceptableOrUnknown(
          data['package_scale']!,
          _packageScaleMeta,
        ),
      );
    }
    if (data.containsKey('package_unit')) {
      context.handle(
        _packageUnitMeta,
        packageUnit.isAcceptableOrUnknown(
          data['package_unit']!,
          _packageUnitMeta,
        ),
      );
    }
    if (data.containsKey('current_revision_origin')) {
      context.handle(
        _currentRevisionOriginMeta,
        currentRevisionOrigin.isAcceptableOrUnknown(
          data['current_revision_origin']!,
          _currentRevisionOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionOriginMeta);
    }
    if (data.containsKey('current_revision_seq')) {
      context.handle(
        _currentRevisionSeqMeta,
        currentRevisionSeq.isAcceptableOrUnknown(
          data['current_revision_seq']!,
          _currentRevisionSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionSeqMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {storeId, id},
  ];
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      canonicalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_name'],
      )!,
      packageValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}package_value'],
      ),
      packageScale: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}package_scale'],
      ),
      packageUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_unit'],
      ),
      currentRevisionOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_origin'],
      )!,
      currentRevisionSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision_seq'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  Products createAlias(String alias) {
    return Products(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'UNIQUE(store_id, id)',
    'FOREIGN KEY(current_revision_origin, current_revision_seq)REFERENCES change_log(origin_device_id, origin_seq)',
    'CHECK((package_value IS NULL AND package_scale IS NULL AND package_unit IS NULL)OR(package_value IS NOT NULL AND package_value > 0 AND package_scale IS NOT NULL AND package_scale BETWEEN 0 AND 6 AND package_unit IS NOT NULL AND package_unit IN (\'piece\', \'kg\', \'litre\')))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String storeId;
  final String canonicalName;
  final int? packageValue;
  final int? packageScale;
  final String? packageUnit;
  final String currentRevisionOrigin;
  final int currentRevisionSeq;
  final int createdAtMs;
  final int updatedAtMs;
  const Product({
    required this.id,
    required this.storeId,
    required this.canonicalName,
    this.packageValue,
    this.packageScale,
    this.packageUnit,
    required this.currentRevisionOrigin,
    required this.currentRevisionSeq,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['store_id'] = Variable<String>(storeId);
    map['canonical_name'] = Variable<String>(canonicalName);
    if (!nullToAbsent || packageValue != null) {
      map['package_value'] = Variable<int>(packageValue);
    }
    if (!nullToAbsent || packageScale != null) {
      map['package_scale'] = Variable<int>(packageScale);
    }
    if (!nullToAbsent || packageUnit != null) {
      map['package_unit'] = Variable<String>(packageUnit);
    }
    map['current_revision_origin'] = Variable<String>(currentRevisionOrigin);
    map['current_revision_seq'] = Variable<int>(currentRevisionSeq);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      storeId: Value(storeId),
      canonicalName: Value(canonicalName),
      packageValue: packageValue == null && nullToAbsent
          ? const Value.absent()
          : Value(packageValue),
      packageScale: packageScale == null && nullToAbsent
          ? const Value.absent()
          : Value(packageScale),
      packageUnit: packageUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(packageUnit),
      currentRevisionOrigin: Value(currentRevisionOrigin),
      currentRevisionSeq: Value(currentRevisionSeq),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      storeId: serializer.fromJson<String>(json['store_id']),
      canonicalName: serializer.fromJson<String>(json['canonical_name']),
      packageValue: serializer.fromJson<int?>(json['package_value']),
      packageScale: serializer.fromJson<int?>(json['package_scale']),
      packageUnit: serializer.fromJson<String?>(json['package_unit']),
      currentRevisionOrigin: serializer.fromJson<String>(
        json['current_revision_origin'],
      ),
      currentRevisionSeq: serializer.fromJson<int>(
        json['current_revision_seq'],
      ),
      createdAtMs: serializer.fromJson<int>(json['created_at_ms']),
      updatedAtMs: serializer.fromJson<int>(json['updated_at_ms']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'store_id': serializer.toJson<String>(storeId),
      'canonical_name': serializer.toJson<String>(canonicalName),
      'package_value': serializer.toJson<int?>(packageValue),
      'package_scale': serializer.toJson<int?>(packageScale),
      'package_unit': serializer.toJson<String?>(packageUnit),
      'current_revision_origin': serializer.toJson<String>(
        currentRevisionOrigin,
      ),
      'current_revision_seq': serializer.toJson<int>(currentRevisionSeq),
      'created_at_ms': serializer.toJson<int>(createdAtMs),
      'updated_at_ms': serializer.toJson<int>(updatedAtMs),
    };
  }

  Product copyWith({
    String? id,
    String? storeId,
    String? canonicalName,
    Value<int?> packageValue = const Value.absent(),
    Value<int?> packageScale = const Value.absent(),
    Value<String?> packageUnit = const Value.absent(),
    String? currentRevisionOrigin,
    int? currentRevisionSeq,
    int? createdAtMs,
    int? updatedAtMs,
  }) => Product(
    id: id ?? this.id,
    storeId: storeId ?? this.storeId,
    canonicalName: canonicalName ?? this.canonicalName,
    packageValue: packageValue.present ? packageValue.value : this.packageValue,
    packageScale: packageScale.present ? packageScale.value : this.packageScale,
    packageUnit: packageUnit.present ? packageUnit.value : this.packageUnit,
    currentRevisionOrigin: currentRevisionOrigin ?? this.currentRevisionOrigin,
    currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      canonicalName: data.canonicalName.present
          ? data.canonicalName.value
          : this.canonicalName,
      packageValue: data.packageValue.present
          ? data.packageValue.value
          : this.packageValue,
      packageScale: data.packageScale.present
          ? data.packageScale.value
          : this.packageScale,
      packageUnit: data.packageUnit.present
          ? data.packageUnit.value
          : this.packageUnit,
      currentRevisionOrigin: data.currentRevisionOrigin.present
          ? data.currentRevisionOrigin.value
          : this.currentRevisionOrigin,
      currentRevisionSeq: data.currentRevisionSeq.present
          ? data.currentRevisionSeq.value
          : this.currentRevisionSeq,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('storeId: $storeId, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('packageValue: $packageValue, ')
          ..write('packageScale: $packageScale, ')
          ..write('packageUnit: $packageUnit, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    storeId,
    canonicalName,
    packageValue,
    packageScale,
    packageUnit,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.storeId == this.storeId &&
          other.canonicalName == this.canonicalName &&
          other.packageValue == this.packageValue &&
          other.packageScale == this.packageScale &&
          other.packageUnit == this.packageUnit &&
          other.currentRevisionOrigin == this.currentRevisionOrigin &&
          other.currentRevisionSeq == this.currentRevisionSeq &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> storeId;
  final Value<String> canonicalName;
  final Value<int?> packageValue;
  final Value<int?> packageScale;
  final Value<String?> packageUnit;
  final Value<String> currentRevisionOrigin;
  final Value<int> currentRevisionSeq;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.storeId = const Value.absent(),
    this.canonicalName = const Value.absent(),
    this.packageValue = const Value.absent(),
    this.packageScale = const Value.absent(),
    this.packageUnit = const Value.absent(),
    this.currentRevisionOrigin = const Value.absent(),
    this.currentRevisionSeq = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String storeId,
    required String canonicalName,
    this.packageValue = const Value.absent(),
    this.packageScale = const Value.absent(),
    this.packageUnit = const Value.absent(),
    required String currentRevisionOrigin,
    required int currentRevisionSeq,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       storeId = Value(storeId),
       canonicalName = Value(canonicalName),
       currentRevisionOrigin = Value(currentRevisionOrigin),
       currentRevisionSeq = Value(currentRevisionSeq),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? storeId,
    Expression<String>? canonicalName,
    Expression<int>? packageValue,
    Expression<int>? packageScale,
    Expression<String>? packageUnit,
    Expression<String>? currentRevisionOrigin,
    Expression<int>? currentRevisionSeq,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (storeId != null) 'store_id': storeId,
      if (canonicalName != null) 'canonical_name': canonicalName,
      if (packageValue != null) 'package_value': packageValue,
      if (packageScale != null) 'package_scale': packageScale,
      if (packageUnit != null) 'package_unit': packageUnit,
      if (currentRevisionOrigin != null)
        'current_revision_origin': currentRevisionOrigin,
      if (currentRevisionSeq != null)
        'current_revision_seq': currentRevisionSeq,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? storeId,
    Value<String>? canonicalName,
    Value<int?>? packageValue,
    Value<int?>? packageScale,
    Value<String?>? packageUnit,
    Value<String>? currentRevisionOrigin,
    Value<int>? currentRevisionSeq,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      canonicalName: canonicalName ?? this.canonicalName,
      packageValue: packageValue ?? this.packageValue,
      packageScale: packageScale ?? this.packageScale,
      packageUnit: packageUnit ?? this.packageUnit,
      currentRevisionOrigin:
          currentRevisionOrigin ?? this.currentRevisionOrigin,
      currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (canonicalName.present) {
      map['canonical_name'] = Variable<String>(canonicalName.value);
    }
    if (packageValue.present) {
      map['package_value'] = Variable<int>(packageValue.value);
    }
    if (packageScale.present) {
      map['package_scale'] = Variable<int>(packageScale.value);
    }
    if (packageUnit.present) {
      map['package_unit'] = Variable<String>(packageUnit.value);
    }
    if (currentRevisionOrigin.present) {
      map['current_revision_origin'] = Variable<String>(
        currentRevisionOrigin.value,
      );
    }
    if (currentRevisionSeq.present) {
      map['current_revision_seq'] = Variable<int>(currentRevisionSeq.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('storeId: $storeId, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('packageValue: $packageValue, ')
          ..write('packageScale: $packageScale, ')
          ..write('packageUnit: $packageUnit, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ReceiptItems extends Table with TableInfo<ReceiptItems, ReceiptItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ReceiptItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (position >= 0)',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (kind IN (\'product\', \'discount\', \'deposit\', \'adjustment\'))',
  );
  static const VerificationMeta _parentItemIdMeta = const VerificationMeta(
    'parentItemId',
  );
  late final GeneratedColumn<String> parentItemId = GeneratedColumn<String>(
    'parent_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _discountScopeMeta = const VerificationMeta(
    'discountScope',
  );
  late final GeneratedColumn<String> discountScope = GeneratedColumn<String>(
    'discount_scope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (discount_scope IS NULL OR discount_scope IN (\'item\', \'receipt\'))',
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _rawNameMeta = const VerificationMeta(
    'rawName',
  );
  late final GeneratedColumn<String> rawName = GeneratedColumn<String>(
    'raw_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (raw_name IS NULL OR(length(trim(raw_name)) > 0 AND raw_name = trim(raw_name)))',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (length(trim(name)) > 0 AND name = trim(name))',
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(normalized_name) > 0)',
  );
  static const VerificationMeta _normalizerVersionMeta = const VerificationMeta(
    'normalizerVersion',
  );
  late final GeneratedColumn<int> normalizerVersion = GeneratedColumn<int>(
    'normalizer_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (normalizer_version = 1)',
  );
  static const VerificationMeta _quantityValueMeta = const VerificationMeta(
    'quantityValue',
  );
  late final GeneratedColumn<int> quantityValue = GeneratedColumn<int>(
    'quantity_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _quantityScaleMeta = const VerificationMeta(
    'quantityScale',
  );
  late final GeneratedColumn<int> quantityScale = GeneratedColumn<int>(
    'quantity_scale',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints:
        'CHECK (quantity_scale IS NULL OR quantity_scale BETWEEN 0 AND 6)',
  );
  static const VerificationMeta _quantityUnitMeta = const VerificationMeta(
    'quantityUnit',
  );
  late final GeneratedColumn<String> quantityUnit = GeneratedColumn<String>(
    'quantity_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (quantity_unit IS NULL OR quantity_unit IN (\'piece\', \'kg\', \'litre\'))',
  );
  static const VerificationMeta _rateMicrosMeta = const VerificationMeta(
    'rateMicros',
  );
  late final GeneratedColumn<int> rateMicros = GeneratedColumn<int>(
    'rate_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (rate_micros IS NULL OR rate_micros >= 0)',
  );
  static const VerificationMeta _lineTotalCentsMeta = const VerificationMeta(
    'lineTotalCents',
  );
  late final GeneratedColumn<int> lineTotalCents = GeneratedColumn<int>(
    'line_total_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _adjustmentReasonMeta = const VerificationMeta(
    'adjustmentReason',
  );
  late final GeneratedColumn<String> adjustmentReason = GeneratedColumn<String>(
    'adjustment_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'CHECK (adjustment_reason IS NULL OR(length(trim(adjustment_reason)) > 0 AND adjustment_reason = trim(adjustment_reason)))',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    receiptId,
    storeId,
    position,
    kind,
    parentItemId,
    discountScope,
    productId,
    rawName,
    name,
    normalizedName,
    normalizerVersion,
    quantityValue,
    quantityScale,
    quantityUnit,
    rateMicros,
    lineTotalCents,
    adjustmentReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipt_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('parent_item_id')) {
      context.handle(
        _parentItemIdMeta,
        parentItemId.isAcceptableOrUnknown(
          data['parent_item_id']!,
          _parentItemIdMeta,
        ),
      );
    }
    if (data.containsKey('discount_scope')) {
      context.handle(
        _discountScopeMeta,
        discountScope.isAcceptableOrUnknown(
          data['discount_scope']!,
          _discountScopeMeta,
        ),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('raw_name')) {
      context.handle(
        _rawNameMeta,
        rawName.isAcceptableOrUnknown(data['raw_name']!, _rawNameMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('normalizer_version')) {
      context.handle(
        _normalizerVersionMeta,
        normalizerVersion.isAcceptableOrUnknown(
          data['normalizer_version']!,
          _normalizerVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizerVersionMeta);
    }
    if (data.containsKey('quantity_value')) {
      context.handle(
        _quantityValueMeta,
        quantityValue.isAcceptableOrUnknown(
          data['quantity_value']!,
          _quantityValueMeta,
        ),
      );
    }
    if (data.containsKey('quantity_scale')) {
      context.handle(
        _quantityScaleMeta,
        quantityScale.isAcceptableOrUnknown(
          data['quantity_scale']!,
          _quantityScaleMeta,
        ),
      );
    }
    if (data.containsKey('quantity_unit')) {
      context.handle(
        _quantityUnitMeta,
        quantityUnit.isAcceptableOrUnknown(
          data['quantity_unit']!,
          _quantityUnitMeta,
        ),
      );
    }
    if (data.containsKey('rate_micros')) {
      context.handle(
        _rateMicrosMeta,
        rateMicros.isAcceptableOrUnknown(data['rate_micros']!, _rateMicrosMeta),
      );
    }
    if (data.containsKey('line_total_cents')) {
      context.handle(
        _lineTotalCentsMeta,
        lineTotalCents.isAcceptableOrUnknown(
          data['line_total_cents']!,
          _lineTotalCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineTotalCentsMeta);
    }
    if (data.containsKey('adjustment_reason')) {
      context.handle(
        _adjustmentReasonMeta,
        adjustmentReason.isAcceptableOrUnknown(
          data['adjustment_reason']!,
          _adjustmentReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {receiptId, position},
    {receiptId, id},
  ];
  @override
  ReceiptItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      parentItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_item_id'],
      ),
      discountScope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}discount_scope'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      rawName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_name'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      normalizerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}normalizer_version'],
      )!,
      quantityValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_value'],
      ),
      quantityScale: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_scale'],
      ),
      quantityUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quantity_unit'],
      ),
      rateMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rate_micros'],
      ),
      lineTotalCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_cents'],
      )!,
      adjustmentReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}adjustment_reason'],
      ),
    );
  }

  @override
  ReceiptItems createAlias(String alias) {
    return ReceiptItems(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'UNIQUE(receipt_id, position)',
    'UNIQUE(receipt_id, id)',
    'FOREIGN KEY(receipt_id, store_id)REFERENCES receipts(id, store_id)',
    'FOREIGN KEY(store_id, product_id)REFERENCES products(store_id, id)',
    'CHECK(product_id IS NULL OR kind = \'product\')',
    'FOREIGN KEY(receipt_id, id)REFERENCES row_identities(receipt_id, row_id)',
    'FOREIGN KEY(receipt_id, parent_item_id)REFERENCES receipt_items(receipt_id, id)DEFERRABLE INITIALLY DEFERRED',
    'CHECK(parent_item_id IS NULL OR(parent_item_id <> id AND kind IN (\'discount\', \'deposit\')))',
    'CHECK((kind = \'discount\' AND line_total_cents < 0 AND discount_scope IS NOT NULL AND((discount_scope = \'item\' AND parent_item_id IS NOT NULL)OR(discount_scope = \'receipt\' AND parent_item_id IS NULL)))OR(kind <> \'discount\' AND discount_scope IS NULL))',
    'CHECK((kind = \'adjustment\' AND adjustment_reason IS NOT NULL)OR(kind <> \'adjustment\' AND adjustment_reason IS NULL))',
    'CHECK((quantity_value IS NULL AND quantity_scale IS NULL AND quantity_unit IS NULL AND rate_micros IS NULL)OR(quantity_value IS NOT NULL AND quantity_value <> 0 AND quantity_scale IS NOT NULL AND quantity_unit IS NOT NULL AND rate_micros IS NOT NULL))',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ReceiptItem extends DataClass implements Insertable<ReceiptItem> {
  final String id;
  final String receiptId;
  final String storeId;
  final int position;
  final String kind;
  final String? parentItemId;
  final String? discountScope;
  final String? productId;
  final String? rawName;
  final String name;
  final String normalizedName;
  final int normalizerVersion;
  final int? quantityValue;
  final int? quantityScale;
  final String? quantityUnit;
  final int? rateMicros;
  final int lineTotalCents;
  final String? adjustmentReason;
  const ReceiptItem({
    required this.id,
    required this.receiptId,
    required this.storeId,
    required this.position,
    required this.kind,
    this.parentItemId,
    this.discountScope,
    this.productId,
    this.rawName,
    required this.name,
    required this.normalizedName,
    required this.normalizerVersion,
    this.quantityValue,
    this.quantityScale,
    this.quantityUnit,
    this.rateMicros,
    required this.lineTotalCents,
    this.adjustmentReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['receipt_id'] = Variable<String>(receiptId);
    map['store_id'] = Variable<String>(storeId);
    map['position'] = Variable<int>(position);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || parentItemId != null) {
      map['parent_item_id'] = Variable<String>(parentItemId);
    }
    if (!nullToAbsent || discountScope != null) {
      map['discount_scope'] = Variable<String>(discountScope);
    }
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || rawName != null) {
      map['raw_name'] = Variable<String>(rawName);
    }
    map['name'] = Variable<String>(name);
    map['normalized_name'] = Variable<String>(normalizedName);
    map['normalizer_version'] = Variable<int>(normalizerVersion);
    if (!nullToAbsent || quantityValue != null) {
      map['quantity_value'] = Variable<int>(quantityValue);
    }
    if (!nullToAbsent || quantityScale != null) {
      map['quantity_scale'] = Variable<int>(quantityScale);
    }
    if (!nullToAbsent || quantityUnit != null) {
      map['quantity_unit'] = Variable<String>(quantityUnit);
    }
    if (!nullToAbsent || rateMicros != null) {
      map['rate_micros'] = Variable<int>(rateMicros);
    }
    map['line_total_cents'] = Variable<int>(lineTotalCents);
    if (!nullToAbsent || adjustmentReason != null) {
      map['adjustment_reason'] = Variable<String>(adjustmentReason);
    }
    return map;
  }

  ReceiptItemsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptItemsCompanion(
      id: Value(id),
      receiptId: Value(receiptId),
      storeId: Value(storeId),
      position: Value(position),
      kind: Value(kind),
      parentItemId: parentItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentItemId),
      discountScope: discountScope == null && nullToAbsent
          ? const Value.absent()
          : Value(discountScope),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      rawName: rawName == null && nullToAbsent
          ? const Value.absent()
          : Value(rawName),
      name: Value(name),
      normalizedName: Value(normalizedName),
      normalizerVersion: Value(normalizerVersion),
      quantityValue: quantityValue == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityValue),
      quantityScale: quantityScale == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityScale),
      quantityUnit: quantityUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(quantityUnit),
      rateMicros: rateMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(rateMicros),
      lineTotalCents: Value(lineTotalCents),
      adjustmentReason: adjustmentReason == null && nullToAbsent
          ? const Value.absent()
          : Value(adjustmentReason),
    );
  }

  factory ReceiptItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptItem(
      id: serializer.fromJson<String>(json['id']),
      receiptId: serializer.fromJson<String>(json['receipt_id']),
      storeId: serializer.fromJson<String>(json['store_id']),
      position: serializer.fromJson<int>(json['position']),
      kind: serializer.fromJson<String>(json['kind']),
      parentItemId: serializer.fromJson<String?>(json['parent_item_id']),
      discountScope: serializer.fromJson<String?>(json['discount_scope']),
      productId: serializer.fromJson<String?>(json['product_id']),
      rawName: serializer.fromJson<String?>(json['raw_name']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalized_name']),
      normalizerVersion: serializer.fromJson<int>(json['normalizer_version']),
      quantityValue: serializer.fromJson<int?>(json['quantity_value']),
      quantityScale: serializer.fromJson<int?>(json['quantity_scale']),
      quantityUnit: serializer.fromJson<String?>(json['quantity_unit']),
      rateMicros: serializer.fromJson<int?>(json['rate_micros']),
      lineTotalCents: serializer.fromJson<int>(json['line_total_cents']),
      adjustmentReason: serializer.fromJson<String?>(json['adjustment_reason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'receipt_id': serializer.toJson<String>(receiptId),
      'store_id': serializer.toJson<String>(storeId),
      'position': serializer.toJson<int>(position),
      'kind': serializer.toJson<String>(kind),
      'parent_item_id': serializer.toJson<String?>(parentItemId),
      'discount_scope': serializer.toJson<String?>(discountScope),
      'product_id': serializer.toJson<String?>(productId),
      'raw_name': serializer.toJson<String?>(rawName),
      'name': serializer.toJson<String>(name),
      'normalized_name': serializer.toJson<String>(normalizedName),
      'normalizer_version': serializer.toJson<int>(normalizerVersion),
      'quantity_value': serializer.toJson<int?>(quantityValue),
      'quantity_scale': serializer.toJson<int?>(quantityScale),
      'quantity_unit': serializer.toJson<String?>(quantityUnit),
      'rate_micros': serializer.toJson<int?>(rateMicros),
      'line_total_cents': serializer.toJson<int>(lineTotalCents),
      'adjustment_reason': serializer.toJson<String?>(adjustmentReason),
    };
  }

  ReceiptItem copyWith({
    String? id,
    String? receiptId,
    String? storeId,
    int? position,
    String? kind,
    Value<String?> parentItemId = const Value.absent(),
    Value<String?> discountScope = const Value.absent(),
    Value<String?> productId = const Value.absent(),
    Value<String?> rawName = const Value.absent(),
    String? name,
    String? normalizedName,
    int? normalizerVersion,
    Value<int?> quantityValue = const Value.absent(),
    Value<int?> quantityScale = const Value.absent(),
    Value<String?> quantityUnit = const Value.absent(),
    Value<int?> rateMicros = const Value.absent(),
    int? lineTotalCents,
    Value<String?> adjustmentReason = const Value.absent(),
  }) => ReceiptItem(
    id: id ?? this.id,
    receiptId: receiptId ?? this.receiptId,
    storeId: storeId ?? this.storeId,
    position: position ?? this.position,
    kind: kind ?? this.kind,
    parentItemId: parentItemId.present ? parentItemId.value : this.parentItemId,
    discountScope: discountScope.present
        ? discountScope.value
        : this.discountScope,
    productId: productId.present ? productId.value : this.productId,
    rawName: rawName.present ? rawName.value : this.rawName,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    normalizerVersion: normalizerVersion ?? this.normalizerVersion,
    quantityValue: quantityValue.present
        ? quantityValue.value
        : this.quantityValue,
    quantityScale: quantityScale.present
        ? quantityScale.value
        : this.quantityScale,
    quantityUnit: quantityUnit.present ? quantityUnit.value : this.quantityUnit,
    rateMicros: rateMicros.present ? rateMicros.value : this.rateMicros,
    lineTotalCents: lineTotalCents ?? this.lineTotalCents,
    adjustmentReason: adjustmentReason.present
        ? adjustmentReason.value
        : this.adjustmentReason,
  );
  ReceiptItem copyWithCompanion(ReceiptItemsCompanion data) {
    return ReceiptItem(
      id: data.id.present ? data.id.value : this.id,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      position: data.position.present ? data.position.value : this.position,
      kind: data.kind.present ? data.kind.value : this.kind,
      parentItemId: data.parentItemId.present
          ? data.parentItemId.value
          : this.parentItemId,
      discountScope: data.discountScope.present
          ? data.discountScope.value
          : this.discountScope,
      productId: data.productId.present ? data.productId.value : this.productId,
      rawName: data.rawName.present ? data.rawName.value : this.rawName,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      normalizerVersion: data.normalizerVersion.present
          ? data.normalizerVersion.value
          : this.normalizerVersion,
      quantityValue: data.quantityValue.present
          ? data.quantityValue.value
          : this.quantityValue,
      quantityScale: data.quantityScale.present
          ? data.quantityScale.value
          : this.quantityScale,
      quantityUnit: data.quantityUnit.present
          ? data.quantityUnit.value
          : this.quantityUnit,
      rateMicros: data.rateMicros.present
          ? data.rateMicros.value
          : this.rateMicros,
      lineTotalCents: data.lineTotalCents.present
          ? data.lineTotalCents.value
          : this.lineTotalCents,
      adjustmentReason: data.adjustmentReason.present
          ? data.adjustmentReason.value
          : this.adjustmentReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptItem(')
          ..write('id: $id, ')
          ..write('receiptId: $receiptId, ')
          ..write('storeId: $storeId, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('parentItemId: $parentItemId, ')
          ..write('discountScope: $discountScope, ')
          ..write('productId: $productId, ')
          ..write('rawName: $rawName, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('normalizerVersion: $normalizerVersion, ')
          ..write('quantityValue: $quantityValue, ')
          ..write('quantityScale: $quantityScale, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('rateMicros: $rateMicros, ')
          ..write('lineTotalCents: $lineTotalCents, ')
          ..write('adjustmentReason: $adjustmentReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    receiptId,
    storeId,
    position,
    kind,
    parentItemId,
    discountScope,
    productId,
    rawName,
    name,
    normalizedName,
    normalizerVersion,
    quantityValue,
    quantityScale,
    quantityUnit,
    rateMicros,
    lineTotalCents,
    adjustmentReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptItem &&
          other.id == this.id &&
          other.receiptId == this.receiptId &&
          other.storeId == this.storeId &&
          other.position == this.position &&
          other.kind == this.kind &&
          other.parentItemId == this.parentItemId &&
          other.discountScope == this.discountScope &&
          other.productId == this.productId &&
          other.rawName == this.rawName &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.normalizerVersion == this.normalizerVersion &&
          other.quantityValue == this.quantityValue &&
          other.quantityScale == this.quantityScale &&
          other.quantityUnit == this.quantityUnit &&
          other.rateMicros == this.rateMicros &&
          other.lineTotalCents == this.lineTotalCents &&
          other.adjustmentReason == this.adjustmentReason);
}

class ReceiptItemsCompanion extends UpdateCompanion<ReceiptItem> {
  final Value<String> id;
  final Value<String> receiptId;
  final Value<String> storeId;
  final Value<int> position;
  final Value<String> kind;
  final Value<String?> parentItemId;
  final Value<String?> discountScope;
  final Value<String?> productId;
  final Value<String?> rawName;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<int> normalizerVersion;
  final Value<int?> quantityValue;
  final Value<int?> quantityScale;
  final Value<String?> quantityUnit;
  final Value<int?> rateMicros;
  final Value<int> lineTotalCents;
  final Value<String?> adjustmentReason;
  final Value<int> rowid;
  const ReceiptItemsCompanion({
    this.id = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.position = const Value.absent(),
    this.kind = const Value.absent(),
    this.parentItemId = const Value.absent(),
    this.discountScope = const Value.absent(),
    this.productId = const Value.absent(),
    this.rawName = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.normalizerVersion = const Value.absent(),
    this.quantityValue = const Value.absent(),
    this.quantityScale = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.rateMicros = const Value.absent(),
    this.lineTotalCents = const Value.absent(),
    this.adjustmentReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptItemsCompanion.insert({
    required String id,
    required String receiptId,
    required String storeId,
    required int position,
    required String kind,
    this.parentItemId = const Value.absent(),
    this.discountScope = const Value.absent(),
    this.productId = const Value.absent(),
    this.rawName = const Value.absent(),
    required String name,
    required String normalizedName,
    required int normalizerVersion,
    this.quantityValue = const Value.absent(),
    this.quantityScale = const Value.absent(),
    this.quantityUnit = const Value.absent(),
    this.rateMicros = const Value.absent(),
    required int lineTotalCents,
    this.adjustmentReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       receiptId = Value(receiptId),
       storeId = Value(storeId),
       position = Value(position),
       kind = Value(kind),
       name = Value(name),
       normalizedName = Value(normalizedName),
       normalizerVersion = Value(normalizerVersion),
       lineTotalCents = Value(lineTotalCents);
  static Insertable<ReceiptItem> custom({
    Expression<String>? id,
    Expression<String>? receiptId,
    Expression<String>? storeId,
    Expression<int>? position,
    Expression<String>? kind,
    Expression<String>? parentItemId,
    Expression<String>? discountScope,
    Expression<String>? productId,
    Expression<String>? rawName,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<int>? normalizerVersion,
    Expression<int>? quantityValue,
    Expression<int>? quantityScale,
    Expression<String>? quantityUnit,
    Expression<int>? rateMicros,
    Expression<int>? lineTotalCents,
    Expression<String>? adjustmentReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (receiptId != null) 'receipt_id': receiptId,
      if (storeId != null) 'store_id': storeId,
      if (position != null) 'position': position,
      if (kind != null) 'kind': kind,
      if (parentItemId != null) 'parent_item_id': parentItemId,
      if (discountScope != null) 'discount_scope': discountScope,
      if (productId != null) 'product_id': productId,
      if (rawName != null) 'raw_name': rawName,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (normalizerVersion != null) 'normalizer_version': normalizerVersion,
      if (quantityValue != null) 'quantity_value': quantityValue,
      if (quantityScale != null) 'quantity_scale': quantityScale,
      if (quantityUnit != null) 'quantity_unit': quantityUnit,
      if (rateMicros != null) 'rate_micros': rateMicros,
      if (lineTotalCents != null) 'line_total_cents': lineTotalCents,
      if (adjustmentReason != null) 'adjustment_reason': adjustmentReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? receiptId,
    Value<String>? storeId,
    Value<int>? position,
    Value<String>? kind,
    Value<String?>? parentItemId,
    Value<String?>? discountScope,
    Value<String?>? productId,
    Value<String?>? rawName,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<int>? normalizerVersion,
    Value<int?>? quantityValue,
    Value<int?>? quantityScale,
    Value<String?>? quantityUnit,
    Value<int?>? rateMicros,
    Value<int>? lineTotalCents,
    Value<String?>? adjustmentReason,
    Value<int>? rowid,
  }) {
    return ReceiptItemsCompanion(
      id: id ?? this.id,
      receiptId: receiptId ?? this.receiptId,
      storeId: storeId ?? this.storeId,
      position: position ?? this.position,
      kind: kind ?? this.kind,
      parentItemId: parentItemId ?? this.parentItemId,
      discountScope: discountScope ?? this.discountScope,
      productId: productId ?? this.productId,
      rawName: rawName ?? this.rawName,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      normalizerVersion: normalizerVersion ?? this.normalizerVersion,
      quantityValue: quantityValue ?? this.quantityValue,
      quantityScale: quantityScale ?? this.quantityScale,
      quantityUnit: quantityUnit ?? this.quantityUnit,
      rateMicros: rateMicros ?? this.rateMicros,
      lineTotalCents: lineTotalCents ?? this.lineTotalCents,
      adjustmentReason: adjustmentReason ?? this.adjustmentReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (parentItemId.present) {
      map['parent_item_id'] = Variable<String>(parentItemId.value);
    }
    if (discountScope.present) {
      map['discount_scope'] = Variable<String>(discountScope.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (rawName.present) {
      map['raw_name'] = Variable<String>(rawName.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (normalizerVersion.present) {
      map['normalizer_version'] = Variable<int>(normalizerVersion.value);
    }
    if (quantityValue.present) {
      map['quantity_value'] = Variable<int>(quantityValue.value);
    }
    if (quantityScale.present) {
      map['quantity_scale'] = Variable<int>(quantityScale.value);
    }
    if (quantityUnit.present) {
      map['quantity_unit'] = Variable<String>(quantityUnit.value);
    }
    if (rateMicros.present) {
      map['rate_micros'] = Variable<int>(rateMicros.value);
    }
    if (lineTotalCents.present) {
      map['line_total_cents'] = Variable<int>(lineTotalCents.value);
    }
    if (adjustmentReason.present) {
      map['adjustment_reason'] = Variable<String>(adjustmentReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptItemsCompanion(')
          ..write('id: $id, ')
          ..write('receiptId: $receiptId, ')
          ..write('storeId: $storeId, ')
          ..write('position: $position, ')
          ..write('kind: $kind, ')
          ..write('parentItemId: $parentItemId, ')
          ..write('discountScope: $discountScope, ')
          ..write('productId: $productId, ')
          ..write('rawName: $rawName, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('normalizerVersion: $normalizerVersion, ')
          ..write('quantityValue: $quantityValue, ')
          ..write('quantityScale: $quantityScale, ')
          ..write('quantityUnit: $quantityUnit, ')
          ..write('rateMicros: $rateMicros, ')
          ..write('lineTotalCents: $lineTotalCents, ')
          ..write('adjustmentReason: $adjustmentReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ReceiptReviews extends Table
    with TableInfo<ReceiptReviews, ReceiptReview> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ReceiptReviews(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY REFERENCES receipts(id)',
  );
  static const VerificationMeta _payloadVersionMeta = const VerificationMeta(
    'payloadVersion',
  );
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
    'payload_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (payload_version = 1)',
  );
  static const VerificationMeta _policyVersionMeta = const VerificationMeta(
    'policyVersion',
  );
  late final GeneratedColumn<int> policyVersion = GeneratedColumn<int>(
    'policy_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (policy_version IN (1, 2))',
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK ((source = \'manual\' AND policy_version = 1)OR(source = \'ocr\' AND policy_version = 2))',
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(trim(app_version)) > 0 AND app_version = trim(app_version))',
  );
  static const VerificationMeta _timezoneRulesVersionMeta =
      const VerificationMeta('timezoneRulesVersion');
  late final GeneratedColumn<String> timezoneRulesVersion =
      GeneratedColumn<String>(
        'timezone_rules_version',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _rowCountMeta = const VerificationMeta(
    'rowCount',
  );
  late final GeneratedColumn<int> rowCount = GeneratedColumn<int>(
    'row_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (row_count > 0)',
  );
  static const VerificationMeta _approvedSha256Meta = const VerificationMeta(
    'approvedSha256',
  );
  late final GeneratedColumn<String> approvedSha256 = GeneratedColumn<String>(
    'approved_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(approved_sha256) = 64 AND approved_sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _canonicalDocumentMeta = const VerificationMeta(
    'canonicalDocument',
  );
  late final GeneratedColumn<String> canonicalDocument =
      GeneratedColumn<String>(
        'canonical_document',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL CHECK (json_valid(canonical_document))',
      );
  @override
  List<GeneratedColumn> get $columns => [
    receiptId,
    payloadVersion,
    policyVersion,
    source,
    appVersion,
    timezoneRulesVersion,
    rowCount,
    approvedSha256,
    canonicalDocument,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receipt_reviews';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceiptReview> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('payload_version')) {
      context.handle(
        _payloadVersionMeta,
        payloadVersion.isAcceptableOrUnknown(
          data['payload_version']!,
          _payloadVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadVersionMeta);
    }
    if (data.containsKey('policy_version')) {
      context.handle(
        _policyVersionMeta,
        policyVersion.isAcceptableOrUnknown(
          data['policy_version']!,
          _policyVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_policyVersionMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_appVersionMeta);
    }
    if (data.containsKey('timezone_rules_version')) {
      context.handle(
        _timezoneRulesVersionMeta,
        timezoneRulesVersion.isAcceptableOrUnknown(
          data['timezone_rules_version']!,
          _timezoneRulesVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timezoneRulesVersionMeta);
    }
    if (data.containsKey('row_count')) {
      context.handle(
        _rowCountMeta,
        rowCount.isAcceptableOrUnknown(data['row_count']!, _rowCountMeta),
      );
    } else if (isInserting) {
      context.missing(_rowCountMeta);
    }
    if (data.containsKey('approved_sha256')) {
      context.handle(
        _approvedSha256Meta,
        approvedSha256.isAcceptableOrUnknown(
          data['approved_sha256']!,
          _approvedSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_approvedSha256Meta);
    }
    if (data.containsKey('canonical_document')) {
      context.handle(
        _canonicalDocumentMeta,
        canonicalDocument.isAcceptableOrUnknown(
          data['canonical_document']!,
          _canonicalDocumentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalDocumentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {receiptId};
  @override
  ReceiptReview map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceiptReview(
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      payloadVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_version'],
      )!,
      policyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}policy_version'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      )!,
      timezoneRulesVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone_rules_version'],
      )!,
      rowCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_count'],
      )!,
      approvedSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}approved_sha256'],
      )!,
      canonicalDocument: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_document'],
      )!,
    );
  }

  @override
  ReceiptReviews createAlias(String alias) {
    return ReceiptReviews(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  bool get dontWriteConstraints => true;
}

class ReceiptReview extends DataClass implements Insertable<ReceiptReview> {
  final String receiptId;
  final int payloadVersion;
  final int policyVersion;
  final String source;
  final String appVersion;
  final String timezoneRulesVersion;
  final int rowCount;
  final String approvedSha256;
  final String canonicalDocument;
  const ReceiptReview({
    required this.receiptId,
    required this.payloadVersion,
    required this.policyVersion,
    required this.source,
    required this.appVersion,
    required this.timezoneRulesVersion,
    required this.rowCount,
    required this.approvedSha256,
    required this.canonicalDocument,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['receipt_id'] = Variable<String>(receiptId);
    map['payload_version'] = Variable<int>(payloadVersion);
    map['policy_version'] = Variable<int>(policyVersion);
    map['source'] = Variable<String>(source);
    map['app_version'] = Variable<String>(appVersion);
    map['timezone_rules_version'] = Variable<String>(timezoneRulesVersion);
    map['row_count'] = Variable<int>(rowCount);
    map['approved_sha256'] = Variable<String>(approvedSha256);
    map['canonical_document'] = Variable<String>(canonicalDocument);
    return map;
  }

  ReceiptReviewsCompanion toCompanion(bool nullToAbsent) {
    return ReceiptReviewsCompanion(
      receiptId: Value(receiptId),
      payloadVersion: Value(payloadVersion),
      policyVersion: Value(policyVersion),
      source: Value(source),
      appVersion: Value(appVersion),
      timezoneRulesVersion: Value(timezoneRulesVersion),
      rowCount: Value(rowCount),
      approvedSha256: Value(approvedSha256),
      canonicalDocument: Value(canonicalDocument),
    );
  }

  factory ReceiptReview.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceiptReview(
      receiptId: serializer.fromJson<String>(json['receipt_id']),
      payloadVersion: serializer.fromJson<int>(json['payload_version']),
      policyVersion: serializer.fromJson<int>(json['policy_version']),
      source: serializer.fromJson<String>(json['source']),
      appVersion: serializer.fromJson<String>(json['app_version']),
      timezoneRulesVersion: serializer.fromJson<String>(
        json['timezone_rules_version'],
      ),
      rowCount: serializer.fromJson<int>(json['row_count']),
      approvedSha256: serializer.fromJson<String>(json['approved_sha256']),
      canonicalDocument: serializer.fromJson<String>(
        json['canonical_document'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'receipt_id': serializer.toJson<String>(receiptId),
      'payload_version': serializer.toJson<int>(payloadVersion),
      'policy_version': serializer.toJson<int>(policyVersion),
      'source': serializer.toJson<String>(source),
      'app_version': serializer.toJson<String>(appVersion),
      'timezone_rules_version': serializer.toJson<String>(timezoneRulesVersion),
      'row_count': serializer.toJson<int>(rowCount),
      'approved_sha256': serializer.toJson<String>(approvedSha256),
      'canonical_document': serializer.toJson<String>(canonicalDocument),
    };
  }

  ReceiptReview copyWith({
    String? receiptId,
    int? payloadVersion,
    int? policyVersion,
    String? source,
    String? appVersion,
    String? timezoneRulesVersion,
    int? rowCount,
    String? approvedSha256,
    String? canonicalDocument,
  }) => ReceiptReview(
    receiptId: receiptId ?? this.receiptId,
    payloadVersion: payloadVersion ?? this.payloadVersion,
    policyVersion: policyVersion ?? this.policyVersion,
    source: source ?? this.source,
    appVersion: appVersion ?? this.appVersion,
    timezoneRulesVersion: timezoneRulesVersion ?? this.timezoneRulesVersion,
    rowCount: rowCount ?? this.rowCount,
    approvedSha256: approvedSha256 ?? this.approvedSha256,
    canonicalDocument: canonicalDocument ?? this.canonicalDocument,
  );
  ReceiptReview copyWithCompanion(ReceiptReviewsCompanion data) {
    return ReceiptReview(
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      policyVersion: data.policyVersion.present
          ? data.policyVersion.value
          : this.policyVersion,
      source: data.source.present ? data.source.value : this.source,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      timezoneRulesVersion: data.timezoneRulesVersion.present
          ? data.timezoneRulesVersion.value
          : this.timezoneRulesVersion,
      rowCount: data.rowCount.present ? data.rowCount.value : this.rowCount,
      approvedSha256: data.approvedSha256.present
          ? data.approvedSha256.value
          : this.approvedSha256,
      canonicalDocument: data.canonicalDocument.present
          ? data.canonicalDocument.value
          : this.canonicalDocument,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptReview(')
          ..write('receiptId: $receiptId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('policyVersion: $policyVersion, ')
          ..write('source: $source, ')
          ..write('appVersion: $appVersion, ')
          ..write('timezoneRulesVersion: $timezoneRulesVersion, ')
          ..write('rowCount: $rowCount, ')
          ..write('approvedSha256: $approvedSha256, ')
          ..write('canonicalDocument: $canonicalDocument')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    receiptId,
    payloadVersion,
    policyVersion,
    source,
    appVersion,
    timezoneRulesVersion,
    rowCount,
    approvedSha256,
    canonicalDocument,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceiptReview &&
          other.receiptId == this.receiptId &&
          other.payloadVersion == this.payloadVersion &&
          other.policyVersion == this.policyVersion &&
          other.source == this.source &&
          other.appVersion == this.appVersion &&
          other.timezoneRulesVersion == this.timezoneRulesVersion &&
          other.rowCount == this.rowCount &&
          other.approvedSha256 == this.approvedSha256 &&
          other.canonicalDocument == this.canonicalDocument);
}

class ReceiptReviewsCompanion extends UpdateCompanion<ReceiptReview> {
  final Value<String> receiptId;
  final Value<int> payloadVersion;
  final Value<int> policyVersion;
  final Value<String> source;
  final Value<String> appVersion;
  final Value<String> timezoneRulesVersion;
  final Value<int> rowCount;
  final Value<String> approvedSha256;
  final Value<String> canonicalDocument;
  final Value<int> rowid;
  const ReceiptReviewsCompanion({
    this.receiptId = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.policyVersion = const Value.absent(),
    this.source = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.timezoneRulesVersion = const Value.absent(),
    this.rowCount = const Value.absent(),
    this.approvedSha256 = const Value.absent(),
    this.canonicalDocument = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceiptReviewsCompanion.insert({
    required String receiptId,
    required int payloadVersion,
    required int policyVersion,
    required String source,
    required String appVersion,
    required String timezoneRulesVersion,
    required int rowCount,
    required String approvedSha256,
    required String canonicalDocument,
    this.rowid = const Value.absent(),
  }) : receiptId = Value(receiptId),
       payloadVersion = Value(payloadVersion),
       policyVersion = Value(policyVersion),
       source = Value(source),
       appVersion = Value(appVersion),
       timezoneRulesVersion = Value(timezoneRulesVersion),
       rowCount = Value(rowCount),
       approvedSha256 = Value(approvedSha256),
       canonicalDocument = Value(canonicalDocument);
  static Insertable<ReceiptReview> custom({
    Expression<String>? receiptId,
    Expression<int>? payloadVersion,
    Expression<int>? policyVersion,
    Expression<String>? source,
    Expression<String>? appVersion,
    Expression<String>? timezoneRulesVersion,
    Expression<int>? rowCount,
    Expression<String>? approvedSha256,
    Expression<String>? canonicalDocument,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (receiptId != null) 'receipt_id': receiptId,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (policyVersion != null) 'policy_version': policyVersion,
      if (source != null) 'source': source,
      if (appVersion != null) 'app_version': appVersion,
      if (timezoneRulesVersion != null)
        'timezone_rules_version': timezoneRulesVersion,
      if (rowCount != null) 'row_count': rowCount,
      if (approvedSha256 != null) 'approved_sha256': approvedSha256,
      if (canonicalDocument != null) 'canonical_document': canonicalDocument,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceiptReviewsCompanion copyWith({
    Value<String>? receiptId,
    Value<int>? payloadVersion,
    Value<int>? policyVersion,
    Value<String>? source,
    Value<String>? appVersion,
    Value<String>? timezoneRulesVersion,
    Value<int>? rowCount,
    Value<String>? approvedSha256,
    Value<String>? canonicalDocument,
    Value<int>? rowid,
  }) {
    return ReceiptReviewsCompanion(
      receiptId: receiptId ?? this.receiptId,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      policyVersion: policyVersion ?? this.policyVersion,
      source: source ?? this.source,
      appVersion: appVersion ?? this.appVersion,
      timezoneRulesVersion: timezoneRulesVersion ?? this.timezoneRulesVersion,
      rowCount: rowCount ?? this.rowCount,
      approvedSha256: approvedSha256 ?? this.approvedSha256,
      canonicalDocument: canonicalDocument ?? this.canonicalDocument,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (policyVersion.present) {
      map['policy_version'] = Variable<int>(policyVersion.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (timezoneRulesVersion.present) {
      map['timezone_rules_version'] = Variable<String>(
        timezoneRulesVersion.value,
      );
    }
    if (rowCount.present) {
      map['row_count'] = Variable<int>(rowCount.value);
    }
    if (approvedSha256.present) {
      map['approved_sha256'] = Variable<String>(approvedSha256.value);
    }
    if (canonicalDocument.present) {
      map['canonical_document'] = Variable<String>(canonicalDocument.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceiptReviewsCompanion(')
          ..write('receiptId: $receiptId, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('policyVersion: $policyVersion, ')
          ..write('source: $source, ')
          ..write('appVersion: $appVersion, ')
          ..write('timezoneRulesVersion: $timezoneRulesVersion, ')
          ..write('rowCount: $rowCount, ')
          ..write('approvedSha256: $approvedSha256, ')
          ..write('canonicalDocument: $canonicalDocument, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ReceivedCursors extends Table
    with TableInfo<ReceivedCursors, ReceivedCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ReceivedCursors(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originDeviceIdMeta = const VerificationMeta(
    'originDeviceId',
  );
  late final GeneratedColumn<String> originDeviceId = GeneratedColumn<String>(
    'origin_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _committedSeqMeta = const VerificationMeta(
    'committedSeq',
  );
  late final GeneratedColumn<int> committedSeq = GeneratedColumn<int>(
    'committed_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (committed_seq >= 0 AND committed_seq < 9223372036854775807)',
  );
  @override
  List<GeneratedColumn> get $columns => [originDeviceId, committedSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'received_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceivedCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('origin_device_id')) {
      context.handle(
        _originDeviceIdMeta,
        originDeviceId.isAcceptableOrUnknown(
          data['origin_device_id']!,
          _originDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originDeviceIdMeta);
    }
    if (data.containsKey('committed_seq')) {
      context.handle(
        _committedSeqMeta,
        committedSeq.isAcceptableOrUnknown(
          data['committed_seq']!,
          _committedSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_committedSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {originDeviceId};
  @override
  ReceivedCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceivedCursor(
      originDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_device_id'],
      )!,
      committedSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}committed_seq'],
      )!,
    );
  }

  @override
  ReceivedCursors createAlias(String alias) {
    return ReceivedCursors(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  bool get dontWriteConstraints => true;
}

class ReceivedCursor extends DataClass implements Insertable<ReceivedCursor> {
  final String originDeviceId;
  final int committedSeq;
  const ReceivedCursor({
    required this.originDeviceId,
    required this.committedSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['origin_device_id'] = Variable<String>(originDeviceId);
    map['committed_seq'] = Variable<int>(committedSeq);
    return map;
  }

  ReceivedCursorsCompanion toCompanion(bool nullToAbsent) {
    return ReceivedCursorsCompanion(
      originDeviceId: Value(originDeviceId),
      committedSeq: Value(committedSeq),
    );
  }

  factory ReceivedCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceivedCursor(
      originDeviceId: serializer.fromJson<String>(json['origin_device_id']),
      committedSeq: serializer.fromJson<int>(json['committed_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'origin_device_id': serializer.toJson<String>(originDeviceId),
      'committed_seq': serializer.toJson<int>(committedSeq),
    };
  }

  ReceivedCursor copyWith({String? originDeviceId, int? committedSeq}) =>
      ReceivedCursor(
        originDeviceId: originDeviceId ?? this.originDeviceId,
        committedSeq: committedSeq ?? this.committedSeq,
      );
  ReceivedCursor copyWithCompanion(ReceivedCursorsCompanion data) {
    return ReceivedCursor(
      originDeviceId: data.originDeviceId.present
          ? data.originDeviceId.value
          : this.originDeviceId,
      committedSeq: data.committedSeq.present
          ? data.committedSeq.value
          : this.committedSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceivedCursor(')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('committedSeq: $committedSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(originDeviceId, committedSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceivedCursor &&
          other.originDeviceId == this.originDeviceId &&
          other.committedSeq == this.committedSeq);
}

class ReceivedCursorsCompanion extends UpdateCompanion<ReceivedCursor> {
  final Value<String> originDeviceId;
  final Value<int> committedSeq;
  final Value<int> rowid;
  const ReceivedCursorsCompanion({
    this.originDeviceId = const Value.absent(),
    this.committedSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceivedCursorsCompanion.insert({
    required String originDeviceId,
    required int committedSeq,
    this.rowid = const Value.absent(),
  }) : originDeviceId = Value(originDeviceId),
       committedSeq = Value(committedSeq);
  static Insertable<ReceivedCursor> custom({
    Expression<String>? originDeviceId,
    Expression<int>? committedSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
      if (committedSeq != null) 'committed_seq': committedSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceivedCursorsCompanion copyWith({
    Value<String>? originDeviceId,
    Value<int>? committedSeq,
    Value<int>? rowid,
  }) {
    return ReceivedCursorsCompanion(
      originDeviceId: originDeviceId ?? this.originDeviceId,
      committedSeq: committedSeq ?? this.committedSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originDeviceId.present) {
      map['origin_device_id'] = Variable<String>(originDeviceId.value);
    }
    if (committedSeq.present) {
      map['committed_seq'] = Variable<int>(committedSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceivedCursorsCompanion(')
          ..write('originDeviceId: $originDeviceId, ')
          ..write('committedSeq: $committedSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LocalMutations extends Table
    with TableInfo<LocalMutations, LocalMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LocalMutations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _commandSha256Meta = const VerificationMeta(
    'commandSha256',
  );
  late final GeneratedColumn<String> commandSha256 = GeneratedColumn<String>(
    'command_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(command_sha256) = 64 AND command_sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _receiptIdMeta = const VerificationMeta(
    'receiptId',
  );
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
    'receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL REFERENCES receipts(id)',
  );
  static const VerificationMeta _resultOriginMeta = const VerificationMeta(
    'resultOrigin',
  );
  late final GeneratedColumn<String> resultOrigin = GeneratedColumn<String>(
    'result_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _resultSeqMeta = const VerificationMeta(
    'resultSeq',
  );
  late final GeneratedColumn<int> resultSeq = GeneratedColumn<int>(
    'result_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    mutationId,
    commandSha256,
    receiptId,
    resultOrigin,
    resultSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('command_sha256')) {
      context.handle(
        _commandSha256Meta,
        commandSha256.isAcceptableOrUnknown(
          data['command_sha256']!,
          _commandSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandSha256Meta);
    }
    if (data.containsKey('receipt_id')) {
      context.handle(
        _receiptIdMeta,
        receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('result_origin')) {
      context.handle(
        _resultOriginMeta,
        resultOrigin.isAcceptableOrUnknown(
          data['result_origin']!,
          _resultOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resultOriginMeta);
    }
    if (data.containsKey('result_seq')) {
      context.handle(
        _resultSeqMeta,
        resultSeq.isAcceptableOrUnknown(data['result_seq']!, _resultSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_resultSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mutationId};
  @override
  LocalMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMutation(
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      commandSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_sha256'],
      )!,
      receiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_id'],
      )!,
      resultOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_origin'],
      )!,
      resultSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_seq'],
      )!,
    );
  }

  @override
  LocalMutations createAlias(String alias) {
    return LocalMutations(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(result_origin, result_seq)REFERENCES change_log(origin_device_id, origin_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class LocalMutation extends DataClass implements Insertable<LocalMutation> {
  final String mutationId;
  final String commandSha256;
  final String receiptId;
  final String resultOrigin;
  final int resultSeq;
  const LocalMutation({
    required this.mutationId,
    required this.commandSha256,
    required this.receiptId,
    required this.resultOrigin,
    required this.resultSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mutation_id'] = Variable<String>(mutationId);
    map['command_sha256'] = Variable<String>(commandSha256);
    map['receipt_id'] = Variable<String>(receiptId);
    map['result_origin'] = Variable<String>(resultOrigin);
    map['result_seq'] = Variable<int>(resultSeq);
    return map;
  }

  LocalMutationsCompanion toCompanion(bool nullToAbsent) {
    return LocalMutationsCompanion(
      mutationId: Value(mutationId),
      commandSha256: Value(commandSha256),
      receiptId: Value(receiptId),
      resultOrigin: Value(resultOrigin),
      resultSeq: Value(resultSeq),
    );
  }

  factory LocalMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMutation(
      mutationId: serializer.fromJson<String>(json['mutation_id']),
      commandSha256: serializer.fromJson<String>(json['command_sha256']),
      receiptId: serializer.fromJson<String>(json['receipt_id']),
      resultOrigin: serializer.fromJson<String>(json['result_origin']),
      resultSeq: serializer.fromJson<int>(json['result_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mutation_id': serializer.toJson<String>(mutationId),
      'command_sha256': serializer.toJson<String>(commandSha256),
      'receipt_id': serializer.toJson<String>(receiptId),
      'result_origin': serializer.toJson<String>(resultOrigin),
      'result_seq': serializer.toJson<int>(resultSeq),
    };
  }

  LocalMutation copyWith({
    String? mutationId,
    String? commandSha256,
    String? receiptId,
    String? resultOrigin,
    int? resultSeq,
  }) => LocalMutation(
    mutationId: mutationId ?? this.mutationId,
    commandSha256: commandSha256 ?? this.commandSha256,
    receiptId: receiptId ?? this.receiptId,
    resultOrigin: resultOrigin ?? this.resultOrigin,
    resultSeq: resultSeq ?? this.resultSeq,
  );
  LocalMutation copyWithCompanion(LocalMutationsCompanion data) {
    return LocalMutation(
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      commandSha256: data.commandSha256.present
          ? data.commandSha256.value
          : this.commandSha256,
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      resultOrigin: data.resultOrigin.present
          ? data.resultOrigin.value
          : this.resultOrigin,
      resultSeq: data.resultSeq.present ? data.resultSeq.value : this.resultSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMutation(')
          ..write('mutationId: $mutationId, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('receiptId: $receiptId, ')
          ..write('resultOrigin: $resultOrigin, ')
          ..write('resultSeq: $resultSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    commandSha256,
    receiptId,
    resultOrigin,
    resultSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMutation &&
          other.mutationId == this.mutationId &&
          other.commandSha256 == this.commandSha256 &&
          other.receiptId == this.receiptId &&
          other.resultOrigin == this.resultOrigin &&
          other.resultSeq == this.resultSeq);
}

class LocalMutationsCompanion extends UpdateCompanion<LocalMutation> {
  final Value<String> mutationId;
  final Value<String> commandSha256;
  final Value<String> receiptId;
  final Value<String> resultOrigin;
  final Value<int> resultSeq;
  final Value<int> rowid;
  const LocalMutationsCompanion({
    this.mutationId = const Value.absent(),
    this.commandSha256 = const Value.absent(),
    this.receiptId = const Value.absent(),
    this.resultOrigin = const Value.absent(),
    this.resultSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMutationsCompanion.insert({
    required String mutationId,
    required String commandSha256,
    required String receiptId,
    required String resultOrigin,
    required int resultSeq,
    this.rowid = const Value.absent(),
  }) : mutationId = Value(mutationId),
       commandSha256 = Value(commandSha256),
       receiptId = Value(receiptId),
       resultOrigin = Value(resultOrigin),
       resultSeq = Value(resultSeq);
  static Insertable<LocalMutation> custom({
    Expression<String>? mutationId,
    Expression<String>? commandSha256,
    Expression<String>? receiptId,
    Expression<String>? resultOrigin,
    Expression<int>? resultSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mutationId != null) 'mutation_id': mutationId,
      if (commandSha256 != null) 'command_sha256': commandSha256,
      if (receiptId != null) 'receipt_id': receiptId,
      if (resultOrigin != null) 'result_origin': resultOrigin,
      if (resultSeq != null) 'result_seq': resultSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMutationsCompanion copyWith({
    Value<String>? mutationId,
    Value<String>? commandSha256,
    Value<String>? receiptId,
    Value<String>? resultOrigin,
    Value<int>? resultSeq,
    Value<int>? rowid,
  }) {
    return LocalMutationsCompanion(
      mutationId: mutationId ?? this.mutationId,
      commandSha256: commandSha256 ?? this.commandSha256,
      receiptId: receiptId ?? this.receiptId,
      resultOrigin: resultOrigin ?? this.resultOrigin,
      resultSeq: resultSeq ?? this.resultSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (commandSha256.present) {
      map['command_sha256'] = Variable<String>(commandSha256.value);
    }
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (resultOrigin.present) {
      map['result_origin'] = Variable<String>(resultOrigin.value);
    }
    if (resultSeq.present) {
      map['result_seq'] = Variable<int>(resultSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMutationsCompanion(')
          ..write('mutationId: $mutationId, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('receiptId: $receiptId, ')
          ..write('resultOrigin: $resultOrigin, ')
          ..write('resultSeq: $resultSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ProductAliases extends Table
    with TableInfo<ProductAliases, ProductAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ProductAliases(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY CHECK (length(id) = 36 AND id GLOB \'????????-????-4???-[89ab]???-????????????\' AND length("replace"(id, \'-\', \'\')) = 32 AND "replace"(id, \'-\', \'\') NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(normalized_name) > 0)',
  );
  static const VerificationMeta _normalizerVersionMeta = const VerificationMeta(
    'normalizerVersion',
  );
  late final GeneratedColumn<int> normalizerVersion = GeneratedColumn<int>(
    'normalizer_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (normalizer_version = 1)',
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  late final GeneratedColumn<int> isActive = GeneratedColumn<int>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (is_active IN (0, 1))',
  );
  static const VerificationMeta _currentRevisionOriginMeta =
      const VerificationMeta('currentRevisionOrigin');
  late final GeneratedColumn<String> currentRevisionOrigin =
      GeneratedColumn<String>(
        'current_revision_origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        $customConstraints: 'NOT NULL',
      );
  static const VerificationMeta _currentRevisionSeqMeta =
      const VerificationMeta('currentRevisionSeq');
  late final GeneratedColumn<int> currentRevisionSeq = GeneratedColumn<int>(
    'current_revision_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (created_at_ms >= 0)',
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (updated_at_ms >= 0)',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    storeId,
    normalizedName,
    normalizerVersion,
    productId,
    isActive,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductAliase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('normalizer_version')) {
      context.handle(
        _normalizerVersionMeta,
        normalizerVersion.isAcceptableOrUnknown(
          data['normalizer_version']!,
          _normalizerVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizerVersionMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    if (data.containsKey('current_revision_origin')) {
      context.handle(
        _currentRevisionOriginMeta,
        currentRevisionOrigin.isAcceptableOrUnknown(
          data['current_revision_origin']!,
          _currentRevisionOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionOriginMeta);
    }
    if (data.containsKey('current_revision_seq')) {
      context.handle(
        _currentRevisionSeqMeta,
        currentRevisionSeq.isAcceptableOrUnknown(
          data['current_revision_seq']!,
          _currentRevisionSeqMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionSeqMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductAliase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      normalizerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}normalizer_version'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_active'],
      )!,
      currentRevisionOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_origin'],
      )!,
      currentRevisionSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision_seq'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
    );
  }

  @override
  ProductAliases createAlias(String alias) {
    return ProductAliases(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(store_id, product_id)REFERENCES products(store_id, id)',
    'FOREIGN KEY(current_revision_origin, current_revision_seq)REFERENCES change_log(origin_device_id, origin_seq)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ProductAliase extends DataClass implements Insertable<ProductAliase> {
  final String id;
  final String storeId;
  final String normalizedName;
  final int normalizerVersion;
  final String productId;
  final int isActive;
  final String currentRevisionOrigin;
  final int currentRevisionSeq;
  final int createdAtMs;
  final int updatedAtMs;
  const ProductAliase({
    required this.id,
    required this.storeId,
    required this.normalizedName,
    required this.normalizerVersion,
    required this.productId,
    required this.isActive,
    required this.currentRevisionOrigin,
    required this.currentRevisionSeq,
    required this.createdAtMs,
    required this.updatedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['store_id'] = Variable<String>(storeId);
    map['normalized_name'] = Variable<String>(normalizedName);
    map['normalizer_version'] = Variable<int>(normalizerVersion);
    map['product_id'] = Variable<String>(productId);
    map['is_active'] = Variable<int>(isActive);
    map['current_revision_origin'] = Variable<String>(currentRevisionOrigin);
    map['current_revision_seq'] = Variable<int>(currentRevisionSeq);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    return map;
  }

  ProductAliasesCompanion toCompanion(bool nullToAbsent) {
    return ProductAliasesCompanion(
      id: Value(id),
      storeId: Value(storeId),
      normalizedName: Value(normalizedName),
      normalizerVersion: Value(normalizerVersion),
      productId: Value(productId),
      isActive: Value(isActive),
      currentRevisionOrigin: Value(currentRevisionOrigin),
      currentRevisionSeq: Value(currentRevisionSeq),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
    );
  }

  factory ProductAliase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductAliase(
      id: serializer.fromJson<String>(json['id']),
      storeId: serializer.fromJson<String>(json['store_id']),
      normalizedName: serializer.fromJson<String>(json['normalized_name']),
      normalizerVersion: serializer.fromJson<int>(json['normalizer_version']),
      productId: serializer.fromJson<String>(json['product_id']),
      isActive: serializer.fromJson<int>(json['is_active']),
      currentRevisionOrigin: serializer.fromJson<String>(
        json['current_revision_origin'],
      ),
      currentRevisionSeq: serializer.fromJson<int>(
        json['current_revision_seq'],
      ),
      createdAtMs: serializer.fromJson<int>(json['created_at_ms']),
      updatedAtMs: serializer.fromJson<int>(json['updated_at_ms']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'store_id': serializer.toJson<String>(storeId),
      'normalized_name': serializer.toJson<String>(normalizedName),
      'normalizer_version': serializer.toJson<int>(normalizerVersion),
      'product_id': serializer.toJson<String>(productId),
      'is_active': serializer.toJson<int>(isActive),
      'current_revision_origin': serializer.toJson<String>(
        currentRevisionOrigin,
      ),
      'current_revision_seq': serializer.toJson<int>(currentRevisionSeq),
      'created_at_ms': serializer.toJson<int>(createdAtMs),
      'updated_at_ms': serializer.toJson<int>(updatedAtMs),
    };
  }

  ProductAliase copyWith({
    String? id,
    String? storeId,
    String? normalizedName,
    int? normalizerVersion,
    String? productId,
    int? isActive,
    String? currentRevisionOrigin,
    int? currentRevisionSeq,
    int? createdAtMs,
    int? updatedAtMs,
  }) => ProductAliase(
    id: id ?? this.id,
    storeId: storeId ?? this.storeId,
    normalizedName: normalizedName ?? this.normalizedName,
    normalizerVersion: normalizerVersion ?? this.normalizerVersion,
    productId: productId ?? this.productId,
    isActive: isActive ?? this.isActive,
    currentRevisionOrigin: currentRevisionOrigin ?? this.currentRevisionOrigin,
    currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
  ProductAliase copyWithCompanion(ProductAliasesCompanion data) {
    return ProductAliase(
      id: data.id.present ? data.id.value : this.id,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      normalizerVersion: data.normalizerVersion.present
          ? data.normalizerVersion.value
          : this.normalizerVersion,
      productId: data.productId.present ? data.productId.value : this.productId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      currentRevisionOrigin: data.currentRevisionOrigin.present
          ? data.currentRevisionOrigin.value
          : this.currentRevisionOrigin,
      currentRevisionSeq: data.currentRevisionSeq.present
          ? data.currentRevisionSeq.value
          : this.currentRevisionSeq,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductAliase(')
          ..write('id: $id, ')
          ..write('storeId: $storeId, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('normalizerVersion: $normalizerVersion, ')
          ..write('productId: $productId, ')
          ..write('isActive: $isActive, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    storeId,
    normalizedName,
    normalizerVersion,
    productId,
    isActive,
    currentRevisionOrigin,
    currentRevisionSeq,
    createdAtMs,
    updatedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductAliase &&
          other.id == this.id &&
          other.storeId == this.storeId &&
          other.normalizedName == this.normalizedName &&
          other.normalizerVersion == this.normalizerVersion &&
          other.productId == this.productId &&
          other.isActive == this.isActive &&
          other.currentRevisionOrigin == this.currentRevisionOrigin &&
          other.currentRevisionSeq == this.currentRevisionSeq &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs);
}

class ProductAliasesCompanion extends UpdateCompanion<ProductAliase> {
  final Value<String> id;
  final Value<String> storeId;
  final Value<String> normalizedName;
  final Value<int> normalizerVersion;
  final Value<String> productId;
  final Value<int> isActive;
  final Value<String> currentRevisionOrigin;
  final Value<int> currentRevisionSeq;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<int> rowid;
  const ProductAliasesCompanion({
    this.id = const Value.absent(),
    this.storeId = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.normalizerVersion = const Value.absent(),
    this.productId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.currentRevisionOrigin = const Value.absent(),
    this.currentRevisionSeq = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductAliasesCompanion.insert({
    required String id,
    required String storeId,
    required String normalizedName,
    required int normalizerVersion,
    required String productId,
    required int isActive,
    required String currentRevisionOrigin,
    required int currentRevisionSeq,
    required int createdAtMs,
    required int updatedAtMs,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       storeId = Value(storeId),
       normalizedName = Value(normalizedName),
       normalizerVersion = Value(normalizerVersion),
       productId = Value(productId),
       isActive = Value(isActive),
       currentRevisionOrigin = Value(currentRevisionOrigin),
       currentRevisionSeq = Value(currentRevisionSeq),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<ProductAliase> custom({
    Expression<String>? id,
    Expression<String>? storeId,
    Expression<String>? normalizedName,
    Expression<int>? normalizerVersion,
    Expression<String>? productId,
    Expression<int>? isActive,
    Expression<String>? currentRevisionOrigin,
    Expression<int>? currentRevisionSeq,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (storeId != null) 'store_id': storeId,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (normalizerVersion != null) 'normalizer_version': normalizerVersion,
      if (productId != null) 'product_id': productId,
      if (isActive != null) 'is_active': isActive,
      if (currentRevisionOrigin != null)
        'current_revision_origin': currentRevisionOrigin,
      if (currentRevisionSeq != null)
        'current_revision_seq': currentRevisionSeq,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductAliasesCompanion copyWith({
    Value<String>? id,
    Value<String>? storeId,
    Value<String>? normalizedName,
    Value<int>? normalizerVersion,
    Value<String>? productId,
    Value<int>? isActive,
    Value<String>? currentRevisionOrigin,
    Value<int>? currentRevisionSeq,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<int>? rowid,
  }) {
    return ProductAliasesCompanion(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      normalizedName: normalizedName ?? this.normalizedName,
      normalizerVersion: normalizerVersion ?? this.normalizerVersion,
      productId: productId ?? this.productId,
      isActive: isActive ?? this.isActive,
      currentRevisionOrigin:
          currentRevisionOrigin ?? this.currentRevisionOrigin,
      currentRevisionSeq: currentRevisionSeq ?? this.currentRevisionSeq,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (normalizerVersion.present) {
      map['normalizer_version'] = Variable<int>(normalizerVersion.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<int>(isActive.value);
    }
    if (currentRevisionOrigin.present) {
      map['current_revision_origin'] = Variable<String>(
        currentRevisionOrigin.value,
      );
    }
    if (currentRevisionSeq.present) {
      map['current_revision_seq'] = Variable<int>(currentRevisionSeq.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductAliasesCompanion(')
          ..write('id: $id, ')
          ..write('storeId: $storeId, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('normalizerVersion: $normalizerVersion, ')
          ..write('productId: $productId, ')
          ..write('isActive: $isActive, ')
          ..write('currentRevisionOrigin: $currentRevisionOrigin, ')
          ..write('currentRevisionSeq: $currentRevisionSeq, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class CatalogMutations extends Table
    with TableInfo<CatalogMutations, CatalogMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  CatalogMutations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _commandSha256Meta = const VerificationMeta(
    'commandSha256',
  );
  late final GeneratedColumn<String> commandSha256 = GeneratedColumn<String>(
    'command_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (length(command_sha256) = 64 AND command_sha256 NOT GLOB \'*[^0-9a-f]*\')',
  );
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (entity_kind IN (\'product\', \'alias\'))',
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _resultOriginMeta = const VerificationMeta(
    'resultOrigin',
  );
  late final GeneratedColumn<String> resultOrigin = GeneratedColumn<String>(
    'result_origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _resultSeqMeta = const VerificationMeta(
    'resultSeq',
  );
  late final GeneratedColumn<int> resultSeq = GeneratedColumn<int>(
    'result_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    mutationId,
    commandSha256,
    entityKind,
    entityId,
    resultOrigin,
    resultSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('command_sha256')) {
      context.handle(
        _commandSha256Meta,
        commandSha256.isAcceptableOrUnknown(
          data['command_sha256']!,
          _commandSha256Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandSha256Meta);
    }
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('result_origin')) {
      context.handle(
        _resultOriginMeta,
        resultOrigin.isAcceptableOrUnknown(
          data['result_origin']!,
          _resultOriginMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resultOriginMeta);
    }
    if (data.containsKey('result_seq')) {
      context.handle(
        _resultSeqMeta,
        resultSeq.isAcceptableOrUnknown(data['result_seq']!, _resultSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_resultSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mutationId};
  @override
  CatalogMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogMutation(
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      commandSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_sha256'],
      )!,
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      resultOrigin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_origin'],
      )!,
      resultSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}result_seq'],
      )!,
    );
  }

  @override
  CatalogMutations createAlias(String alias) {
    return CatalogMutations(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(result_origin, result_seq, entity_kind, entity_id)REFERENCES change_log(origin_device_id, origin_seq, entity_kind, entity_id)',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class CatalogMutation extends DataClass implements Insertable<CatalogMutation> {
  final String mutationId;
  final String commandSha256;
  final String entityKind;
  final String entityId;
  final String resultOrigin;
  final int resultSeq;
  const CatalogMutation({
    required this.mutationId,
    required this.commandSha256,
    required this.entityKind,
    required this.entityId,
    required this.resultOrigin,
    required this.resultSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['mutation_id'] = Variable<String>(mutationId);
    map['command_sha256'] = Variable<String>(commandSha256);
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    map['result_origin'] = Variable<String>(resultOrigin);
    map['result_seq'] = Variable<int>(resultSeq);
    return map;
  }

  CatalogMutationsCompanion toCompanion(bool nullToAbsent) {
    return CatalogMutationsCompanion(
      mutationId: Value(mutationId),
      commandSha256: Value(commandSha256),
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      resultOrigin: Value(resultOrigin),
      resultSeq: Value(resultSeq),
    );
  }

  factory CatalogMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogMutation(
      mutationId: serializer.fromJson<String>(json['mutation_id']),
      commandSha256: serializer.fromJson<String>(json['command_sha256']),
      entityKind: serializer.fromJson<String>(json['entity_kind']),
      entityId: serializer.fromJson<String>(json['entity_id']),
      resultOrigin: serializer.fromJson<String>(json['result_origin']),
      resultSeq: serializer.fromJson<int>(json['result_seq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mutation_id': serializer.toJson<String>(mutationId),
      'command_sha256': serializer.toJson<String>(commandSha256),
      'entity_kind': serializer.toJson<String>(entityKind),
      'entity_id': serializer.toJson<String>(entityId),
      'result_origin': serializer.toJson<String>(resultOrigin),
      'result_seq': serializer.toJson<int>(resultSeq),
    };
  }

  CatalogMutation copyWith({
    String? mutationId,
    String? commandSha256,
    String? entityKind,
    String? entityId,
    String? resultOrigin,
    int? resultSeq,
  }) => CatalogMutation(
    mutationId: mutationId ?? this.mutationId,
    commandSha256: commandSha256 ?? this.commandSha256,
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    resultOrigin: resultOrigin ?? this.resultOrigin,
    resultSeq: resultSeq ?? this.resultSeq,
  );
  CatalogMutation copyWithCompanion(CatalogMutationsCompanion data) {
    return CatalogMutation(
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      commandSha256: data.commandSha256.present
          ? data.commandSha256.value
          : this.commandSha256,
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      resultOrigin: data.resultOrigin.present
          ? data.resultOrigin.value
          : this.resultOrigin,
      resultSeq: data.resultSeq.present ? data.resultSeq.value : this.resultSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogMutation(')
          ..write('mutationId: $mutationId, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('resultOrigin: $resultOrigin, ')
          ..write('resultSeq: $resultSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    mutationId,
    commandSha256,
    entityKind,
    entityId,
    resultOrigin,
    resultSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogMutation &&
          other.mutationId == this.mutationId &&
          other.commandSha256 == this.commandSha256 &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.resultOrigin == this.resultOrigin &&
          other.resultSeq == this.resultSeq);
}

class CatalogMutationsCompanion extends UpdateCompanion<CatalogMutation> {
  final Value<String> mutationId;
  final Value<String> commandSha256;
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<String> resultOrigin;
  final Value<int> resultSeq;
  final Value<int> rowid;
  const CatalogMutationsCompanion({
    this.mutationId = const Value.absent(),
    this.commandSha256 = const Value.absent(),
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.resultOrigin = const Value.absent(),
    this.resultSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogMutationsCompanion.insert({
    required String mutationId,
    required String commandSha256,
    required String entityKind,
    required String entityId,
    required String resultOrigin,
    required int resultSeq,
    this.rowid = const Value.absent(),
  }) : mutationId = Value(mutationId),
       commandSha256 = Value(commandSha256),
       entityKind = Value(entityKind),
       entityId = Value(entityId),
       resultOrigin = Value(resultOrigin),
       resultSeq = Value(resultSeq);
  static Insertable<CatalogMutation> custom({
    Expression<String>? mutationId,
    Expression<String>? commandSha256,
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<String>? resultOrigin,
    Expression<int>? resultSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mutationId != null) 'mutation_id': mutationId,
      if (commandSha256 != null) 'command_sha256': commandSha256,
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (resultOrigin != null) 'result_origin': resultOrigin,
      if (resultSeq != null) 'result_seq': resultSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogMutationsCompanion copyWith({
    Value<String>? mutationId,
    Value<String>? commandSha256,
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<String>? resultOrigin,
    Value<int>? resultSeq,
    Value<int>? rowid,
  }) {
    return CatalogMutationsCompanion(
      mutationId: mutationId ?? this.mutationId,
      commandSha256: commandSha256 ?? this.commandSha256,
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      resultOrigin: resultOrigin ?? this.resultOrigin,
      resultSeq: resultSeq ?? this.resultSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (commandSha256.present) {
      map['command_sha256'] = Variable<String>(commandSha256.value);
    }
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (resultOrigin.present) {
      map['result_origin'] = Variable<String>(resultOrigin.value);
    }
    if (resultSeq.present) {
      map['result_seq'] = Variable<int>(resultSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogMutationsCompanion(')
          ..write('mutationId: $mutationId, ')
          ..write('commandSha256: $commandSha256, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('resultOrigin: $resultOrigin, ')
          ..write('resultSeq: $resultSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ReceiptDatabase extends GeneratedDatabase {
  _$ReceiptDatabase(QueryExecutor e) : super(e);
  late final DatasetState datasetState = DatasetState(this);
  late final ChangeLog changeLog = ChangeLog(this);
  late final Trigger changeLogNoUpdate = Trigger(
    'CREATE TRIGGER change_log_no_update BEFORE UPDATE ON change_log BEGIN SELECT RAISE (ABORT, \'immutable_event\');END',
    'change_log_no_update',
  );
  late final Trigger changeLogNoDelete = Trigger(
    'CREATE TRIGGER change_log_no_delete BEFORE DELETE ON change_log BEGIN SELECT RAISE (ABORT, \'immutable_event\');END',
    'change_log_no_delete',
  );
  late final RevisionParents revisionParents = RevisionParents(this);
  late final Index revisionParentsParent = Index(
    'revision_parents_parent',
    'CREATE INDEX revision_parents_parent ON revision_parents (parent_origin, parent_seq)',
  );
  late final Trigger revisionParentsNoUpdate = Trigger(
    'CREATE TRIGGER revision_parents_no_update BEFORE UPDATE ON revision_parents BEGIN SELECT RAISE (ABORT, \'immutable_parent\');END',
    'revision_parents_no_update',
  );
  late final Trigger revisionParentsNoDelete = Trigger(
    'CREATE TRIGGER revision_parents_no_delete BEFORE DELETE ON revision_parents BEGIN SELECT RAISE (ABORT, \'immutable_parent\');END',
    'revision_parents_no_delete',
  );
  late final EventDependencies eventDependencies = EventDependencies(this);
  late final Index eventDependenciesTarget = Index(
    'event_dependencies_target',
    'CREATE INDEX event_dependencies_target ON event_dependencies (dependency_origin, dependency_seq)',
  );
  late final Trigger eventDependenciesNoUpdate = Trigger(
    'CREATE TRIGGER event_dependencies_no_update BEFORE UPDATE ON event_dependencies BEGIN SELECT RAISE (ABORT, \'immutable_dependency\');END',
    'event_dependencies_no_update',
  );
  late final Trigger eventDependenciesNoDelete = Trigger(
    'CREATE TRIGGER event_dependencies_no_delete BEFORE DELETE ON event_dependencies BEGIN SELECT RAISE (ABORT, \'immutable_dependency\');END',
    'event_dependencies_no_delete',
  );
  late final EntityHeads entityHeads = EntityHeads(this);
  late final Index entityHeadsRevision = Index(
    'entity_heads_revision',
    'CREATE INDEX entity_heads_revision ON entity_heads (origin_device_id, origin_seq)',
  );
  late final Stores stores = Stores(this);
  late final Index storesRevision = Index(
    'stores_revision',
    'CREATE INDEX stores_revision ON stores (current_revision_origin, current_revision_seq)',
  );
  late final Receipts receipts = Receipts(this);
  late final Index receiptsBranchDate = Index(
    'receipts_branch_date',
    'CREATE INDEX receipts_branch_date ON receipts (store_id, printed_year, printed_month, printed_day, id)',
  );
  late final Index receiptsRevision = Index(
    'receipts_revision',
    'CREATE INDEX receipts_revision ON receipts (current_revision_origin, current_revision_seq)',
  );
  late final RowIdentities rowIdentities = RowIdentities(this);
  late final Index rowIdentitiesRevision = Index(
    'row_identities_revision',
    'CREATE INDEX row_identities_revision ON row_identities (first_origin, first_seq)',
  );
  late final Trigger rowIdentitiesNoUpdate = Trigger(
    'CREATE TRIGGER row_identities_no_update BEFORE UPDATE ON row_identities BEGIN SELECT RAISE (ABORT, \'immutable_row_identity\');END',
    'row_identities_no_update',
  );
  late final Trigger rowIdentitiesNoDelete = Trigger(
    'CREATE TRIGGER row_identities_no_delete BEFORE DELETE ON row_identities BEGIN SELECT RAISE (ABORT, \'immutable_row_identity\');END',
    'row_identities_no_delete',
  );
  late final Products products = Products(this);
  late final ReceiptItems receiptItems = ReceiptItems(this);
  late final Index receiptItemsParent = Index(
    'receipt_items_parent',
    'CREATE INDEX receipt_items_parent ON receipt_items (receipt_id, parent_item_id)',
  );
  late final ReceiptReviews receiptReviews = ReceiptReviews(this);
  late final ReceivedCursors receivedCursors = ReceivedCursors(this);
  late final LocalMutations localMutations = LocalMutations(this);
  late final Index localMutationsRevision = Index(
    'local_mutations_revision',
    'CREATE INDEX local_mutations_revision ON local_mutations (result_origin, result_seq)',
  );
  late final Index localMutationsReceipt = Index(
    'local_mutations_receipt',
    'CREATE INDEX local_mutations_receipt ON local_mutations (receipt_id)',
  );
  late final Trigger localMutationsNoUpdate = Trigger(
    'CREATE TRIGGER local_mutations_no_update BEFORE UPDATE ON local_mutations BEGIN SELECT RAISE (ABORT, \'immutable_mutation\');END',
    'local_mutations_no_update',
  );
  late final Trigger localMutationsNoDelete = Trigger(
    'CREATE TRIGGER local_mutations_no_delete BEFORE DELETE ON local_mutations BEGIN SELECT RAISE (ABORT, \'immutable_mutation\');END',
    'local_mutations_no_delete',
  );
  late final Index productsBranchName = Index(
    'products_branch_name',
    'CREATE INDEX products_branch_name ON products (store_id, canonical_name, id)',
  );
  late final Index productsRevision = Index(
    'products_revision',
    'CREATE INDEX products_revision ON products (current_revision_origin, current_revision_seq)',
  );
  late final ProductAliases productAliases = ProductAliases(this);
  late final Index productAliasesActiveName = Index(
    'product_aliases_active_name',
    'CREATE UNIQUE INDEX product_aliases_active_name ON product_aliases (store_id, normalized_name) WHERE is_active = 1',
  );
  late final Index productAliasesProduct = Index(
    'product_aliases_product',
    'CREATE INDEX product_aliases_product ON product_aliases (store_id, product_id)',
  );
  late final Index productAliasesRevision = Index(
    'product_aliases_revision',
    'CREATE INDEX product_aliases_revision ON product_aliases (current_revision_origin, current_revision_seq)',
  );
  late final CatalogMutations catalogMutations = CatalogMutations(this);
  late final Index catalogMutationsRevision = Index(
    'catalog_mutations_revision',
    'CREATE INDEX catalog_mutations_revision ON catalog_mutations (result_origin, result_seq)',
  );
  late final Trigger catalogMutationsNoUpdate = Trigger(
    'CREATE TRIGGER catalog_mutations_no_update BEFORE UPDATE ON catalog_mutations BEGIN SELECT RAISE (ABORT, \'immutable_mutation\');END',
    'catalog_mutations_no_update',
  );
  late final Trigger catalogMutationsNoDelete = Trigger(
    'CREATE TRIGGER catalog_mutations_no_delete BEFORE DELETE ON catalog_mutations BEGIN SELECT RAISE (ABORT, \'immutable_mutation\');END',
    'catalog_mutations_no_delete',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    datasetState,
    changeLog,
    changeLogNoUpdate,
    changeLogNoDelete,
    revisionParents,
    revisionParentsParent,
    revisionParentsNoUpdate,
    revisionParentsNoDelete,
    eventDependencies,
    eventDependenciesTarget,
    eventDependenciesNoUpdate,
    eventDependenciesNoDelete,
    entityHeads,
    entityHeadsRevision,
    stores,
    storesRevision,
    receipts,
    receiptsBranchDate,
    receiptsRevision,
    rowIdentities,
    rowIdentitiesRevision,
    rowIdentitiesNoUpdate,
    rowIdentitiesNoDelete,
    products,
    receiptItems,
    receiptItemsParent,
    receiptReviews,
    receivedCursors,
    localMutations,
    localMutationsRevision,
    localMutationsReceipt,
    localMutationsNoUpdate,
    localMutationsNoDelete,
    productsBranchName,
    productsRevision,
    productAliases,
    productAliasesActiveName,
    productAliasesProduct,
    productAliasesRevision,
    catalogMutations,
    catalogMutationsRevision,
    catalogMutationsNoUpdate,
    catalogMutationsNoDelete,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'change_log',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'change_log',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'revision_parents',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'revision_parents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'event_dependencies',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'event_dependencies',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'row_identities',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'row_identities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_mutations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_mutations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'catalog_mutations',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'catalog_mutations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}
