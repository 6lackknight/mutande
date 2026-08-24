// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mailbox_database.dart';

// ignore_for_file: type=lint
class $ThreadListSnapshotsTable extends ThreadListSnapshots
    with TableInfo<$ThreadListSnapshotsTable, ThreadListSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreadListSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _filterKeyMeta = const VerificationMeta(
    'filterKey',
  );
  @override
  late final GeneratedColumn<String> filterKey = GeneratedColumn<String>(
    'filter_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [filterKey, savedAt, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'thread_list_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThreadListSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('filter_key')) {
      context.handle(
        _filterKeyMeta,
        filterKey.isAcceptableOrUnknown(data['filter_key']!, _filterKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_filterKeyMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {filterKey};
  @override
  ThreadListSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreadListSnapshot(
      filterKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter_key'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_at'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $ThreadListSnapshotsTable createAlias(String alias) {
    return $ThreadListSnapshotsTable(attachedDatabase, alias);
  }
}

class ThreadListSnapshot extends DataClass
    implements Insertable<ThreadListSnapshot> {
  final String filterKey;
  final String savedAt;
  final String json;
  const ThreadListSnapshot({
    required this.filterKey,
    required this.savedAt,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['filter_key'] = Variable<String>(filterKey);
    map['saved_at'] = Variable<String>(savedAt);
    map['json'] = Variable<String>(json);
    return map;
  }

  ThreadListSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return ThreadListSnapshotsCompanion(
      filterKey: Value(filterKey),
      savedAt: Value(savedAt),
      json: Value(json),
    );
  }

  factory ThreadListSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreadListSnapshot(
      filterKey: serializer.fromJson<String>(json['filterKey']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'filterKey': serializer.toJson<String>(filterKey),
      'savedAt': serializer.toJson<String>(savedAt),
      'json': serializer.toJson<String>(json),
    };
  }

  ThreadListSnapshot copyWith({
    String? filterKey,
    String? savedAt,
    String? json,
  }) => ThreadListSnapshot(
    filterKey: filterKey ?? this.filterKey,
    savedAt: savedAt ?? this.savedAt,
    json: json ?? this.json,
  );
  ThreadListSnapshot copyWithCompanion(ThreadListSnapshotsCompanion data) {
    return ThreadListSnapshot(
      filterKey: data.filterKey.present ? data.filterKey.value : this.filterKey,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreadListSnapshot(')
          ..write('filterKey: $filterKey, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(filterKey, savedAt, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreadListSnapshot &&
          other.filterKey == this.filterKey &&
          other.savedAt == this.savedAt &&
          other.json == this.json);
}

class ThreadListSnapshotsCompanion extends UpdateCompanion<ThreadListSnapshot> {
  final Value<String> filterKey;
  final Value<String> savedAt;
  final Value<String> json;
  final Value<int> rowid;
  const ThreadListSnapshotsCompanion({
    this.filterKey = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThreadListSnapshotsCompanion.insert({
    required String filterKey,
    required String savedAt,
    required String json,
    this.rowid = const Value.absent(),
  }) : filterKey = Value(filterKey),
       savedAt = Value(savedAt),
       json = Value(json);
  static Insertable<ThreadListSnapshot> custom({
    Expression<String>? filterKey,
    Expression<String>? savedAt,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (filterKey != null) 'filter_key': filterKey,
      if (savedAt != null) 'saved_at': savedAt,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThreadListSnapshotsCompanion copyWith({
    Value<String>? filterKey,
    Value<String>? savedAt,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return ThreadListSnapshotsCompanion(
      filterKey: filterKey ?? this.filterKey,
      savedAt: savedAt ?? this.savedAt,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (filterKey.present) {
      map['filter_key'] = Variable<String>(filterKey.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreadListSnapshotsCompanion(')
          ..write('filterKey: $filterKey, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedThreadDetailsTable extends CachedThreadDetails
    with TableInfo<$CachedThreadDetailsTable, CachedThreadDetail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedThreadDetailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hubUpdatedAtMeta = const VerificationMeta(
    'hubUpdatedAt',
  );
  @override
  late final GeneratedColumn<String> hubUpdatedAt = GeneratedColumn<String>(
    'hub_updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<String> cachedAt = GeneratedColumn<String>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, hubUpdatedAt, json, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_thread_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedThreadDetail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hub_updated_at')) {
      context.handle(
        _hubUpdatedAtMeta,
        hubUpdatedAt.isAcceptableOrUnknown(
          data['hub_updated_at']!,
          _hubUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedThreadDetail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedThreadDetail(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hubUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hub_updated_at'],
      ),
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedThreadDetailsTable createAlias(String alias) {
    return $CachedThreadDetailsTable(attachedDatabase, alias);
  }
}

class CachedThreadDetail extends DataClass
    implements Insertable<CachedThreadDetail> {
  final String id;
  final String? hubUpdatedAt;
  final String json;
  final String cachedAt;
  const CachedThreadDetail({
    required this.id,
    this.hubUpdatedAt,
    required this.json,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || hubUpdatedAt != null) {
      map['hub_updated_at'] = Variable<String>(hubUpdatedAt);
    }
    map['json'] = Variable<String>(json);
    map['cached_at'] = Variable<String>(cachedAt);
    return map;
  }

  CachedThreadDetailsCompanion toCompanion(bool nullToAbsent) {
    return CachedThreadDetailsCompanion(
      id: Value(id),
      hubUpdatedAt: hubUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hubUpdatedAt),
      json: Value(json),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedThreadDetail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedThreadDetail(
      id: serializer.fromJson<String>(json['id']),
      hubUpdatedAt: serializer.fromJson<String?>(json['hubUpdatedAt']),
      json: serializer.fromJson<String>(json['json']),
      cachedAt: serializer.fromJson<String>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hubUpdatedAt': serializer.toJson<String?>(hubUpdatedAt),
      'json': serializer.toJson<String>(json),
      'cachedAt': serializer.toJson<String>(cachedAt),
    };
  }

  CachedThreadDetail copyWith({
    String? id,
    Value<String?> hubUpdatedAt = const Value.absent(),
    String? json,
    String? cachedAt,
  }) => CachedThreadDetail(
    id: id ?? this.id,
    hubUpdatedAt: hubUpdatedAt.present ? hubUpdatedAt.value : this.hubUpdatedAt,
    json: json ?? this.json,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedThreadDetail copyWithCompanion(CachedThreadDetailsCompanion data) {
    return CachedThreadDetail(
      id: data.id.present ? data.id.value : this.id,
      hubUpdatedAt: data.hubUpdatedAt.present
          ? data.hubUpdatedAt.value
          : this.hubUpdatedAt,
      json: data.json.present ? data.json.value : this.json,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedThreadDetail(')
          ..write('id: $id, ')
          ..write('hubUpdatedAt: $hubUpdatedAt, ')
          ..write('json: $json, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, hubUpdatedAt, json, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedThreadDetail &&
          other.id == this.id &&
          other.hubUpdatedAt == this.hubUpdatedAt &&
          other.json == this.json &&
          other.cachedAt == this.cachedAt);
}

class CachedThreadDetailsCompanion extends UpdateCompanion<CachedThreadDetail> {
  final Value<String> id;
  final Value<String?> hubUpdatedAt;
  final Value<String> json;
  final Value<String> cachedAt;
  final Value<int> rowid;
  const CachedThreadDetailsCompanion({
    this.id = const Value.absent(),
    this.hubUpdatedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedThreadDetailsCompanion.insert({
    required String id,
    this.hubUpdatedAt = const Value.absent(),
    required String json,
    required String cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       json = Value(json),
       cachedAt = Value(cachedAt);
  static Insertable<CachedThreadDetail> custom({
    Expression<String>? id,
    Expression<String>? hubUpdatedAt,
    Expression<String>? json,
    Expression<String>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hubUpdatedAt != null) 'hub_updated_at': hubUpdatedAt,
      if (json != null) 'json': json,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedThreadDetailsCompanion copyWith({
    Value<String>? id,
    Value<String?>? hubUpdatedAt,
    Value<String>? json,
    Value<String>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedThreadDetailsCompanion(
      id: id ?? this.id,
      hubUpdatedAt: hubUpdatedAt ?? this.hubUpdatedAt,
      json: json ?? this.json,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hubUpdatedAt.present) {
      map['hub_updated_at'] = Variable<String>(hubUpdatedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<String>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedThreadDetailsCompanion(')
          ..write('id: $id, ')
          ..write('hubUpdatedAt: $hubUpdatedAt, ')
          ..write('json: $json, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollabListSnapshotsTable extends CollabListSnapshots
    with TableInfo<$CollabListSnapshotsTable, CollabListSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollabListSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _archiveKeyMeta = const VerificationMeta(
    'archiveKey',
  );
  @override
  late final GeneratedColumn<String> archiveKey = GeneratedColumn<String>(
    'archive_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [archiveKey, savedAt, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collab_list_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollabListSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('archive_key')) {
      context.handle(
        _archiveKeyMeta,
        archiveKey.isAcceptableOrUnknown(data['archive_key']!, _archiveKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_archiveKeyMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {archiveKey};
  @override
  CollabListSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollabListSnapshot(
      archiveKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}archive_key'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_at'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $CollabListSnapshotsTable createAlias(String alias) {
    return $CollabListSnapshotsTable(attachedDatabase, alias);
  }
}

class CollabListSnapshot extends DataClass
    implements Insertable<CollabListSnapshot> {
  final String archiveKey;
  final String savedAt;
  final String json;
  const CollabListSnapshot({
    required this.archiveKey,
    required this.savedAt,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['archive_key'] = Variable<String>(archiveKey);
    map['saved_at'] = Variable<String>(savedAt);
    map['json'] = Variable<String>(json);
    return map;
  }

  CollabListSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return CollabListSnapshotsCompanion(
      archiveKey: Value(archiveKey),
      savedAt: Value(savedAt),
      json: Value(json),
    );
  }

  factory CollabListSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollabListSnapshot(
      archiveKey: serializer.fromJson<String>(json['archiveKey']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'archiveKey': serializer.toJson<String>(archiveKey),
      'savedAt': serializer.toJson<String>(savedAt),
      'json': serializer.toJson<String>(json),
    };
  }

  CollabListSnapshot copyWith({
    String? archiveKey,
    String? savedAt,
    String? json,
  }) => CollabListSnapshot(
    archiveKey: archiveKey ?? this.archiveKey,
    savedAt: savedAt ?? this.savedAt,
    json: json ?? this.json,
  );
  CollabListSnapshot copyWithCompanion(CollabListSnapshotsCompanion data) {
    return CollabListSnapshot(
      archiveKey: data.archiveKey.present
          ? data.archiveKey.value
          : this.archiveKey,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollabListSnapshot(')
          ..write('archiveKey: $archiveKey, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(archiveKey, savedAt, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollabListSnapshot &&
          other.archiveKey == this.archiveKey &&
          other.savedAt == this.savedAt &&
          other.json == this.json);
}

class CollabListSnapshotsCompanion extends UpdateCompanion<CollabListSnapshot> {
  final Value<String> archiveKey;
  final Value<String> savedAt;
  final Value<String> json;
  final Value<int> rowid;
  const CollabListSnapshotsCompanion({
    this.archiveKey = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollabListSnapshotsCompanion.insert({
    required String archiveKey,
    required String savedAt,
    required String json,
    this.rowid = const Value.absent(),
  }) : archiveKey = Value(archiveKey),
       savedAt = Value(savedAt),
       json = Value(json);
  static Insertable<CollabListSnapshot> custom({
    Expression<String>? archiveKey,
    Expression<String>? savedAt,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (archiveKey != null) 'archive_key': archiveKey,
      if (savedAt != null) 'saved_at': savedAt,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollabListSnapshotsCompanion copyWith({
    Value<String>? archiveKey,
    Value<String>? savedAt,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return CollabListSnapshotsCompanion(
      archiveKey: archiveKey ?? this.archiveKey,
      savedAt: savedAt ?? this.savedAt,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (archiveKey.present) {
      map['archive_key'] = Variable<String>(archiveKey.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollabListSnapshotsCompanion(')
          ..write('archiveKey: $archiveKey, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCollabDetailsTable extends CachedCollabDetails
    with TableInfo<$CachedCollabDetailsTable, CachedCollabDetail> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCollabDetailsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hubUpdatedAtMeta = const VerificationMeta(
    'hubUpdatedAt',
  );
  @override
  late final GeneratedColumn<String> hubUpdatedAt = GeneratedColumn<String>(
    'hub_updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<String> cachedAt = GeneratedColumn<String>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, hubUpdatedAt, json, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_collab_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCollabDetail> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hub_updated_at')) {
      context.handle(
        _hubUpdatedAtMeta,
        hubUpdatedAt.isAcceptableOrUnknown(
          data['hub_updated_at']!,
          _hubUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedCollabDetail map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCollabDetail(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hubUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hub_updated_at'],
      ),
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedCollabDetailsTable createAlias(String alias) {
    return $CachedCollabDetailsTable(attachedDatabase, alias);
  }
}

class CachedCollabDetail extends DataClass
    implements Insertable<CachedCollabDetail> {
  final String id;
  final String? hubUpdatedAt;
  final String json;
  final String cachedAt;
  const CachedCollabDetail({
    required this.id,
    this.hubUpdatedAt,
    required this.json,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || hubUpdatedAt != null) {
      map['hub_updated_at'] = Variable<String>(hubUpdatedAt);
    }
    map['json'] = Variable<String>(json);
    map['cached_at'] = Variable<String>(cachedAt);
    return map;
  }

  CachedCollabDetailsCompanion toCompanion(bool nullToAbsent) {
    return CachedCollabDetailsCompanion(
      id: Value(id),
      hubUpdatedAt: hubUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hubUpdatedAt),
      json: Value(json),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedCollabDetail.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCollabDetail(
      id: serializer.fromJson<String>(json['id']),
      hubUpdatedAt: serializer.fromJson<String?>(json['hubUpdatedAt']),
      json: serializer.fromJson<String>(json['json']),
      cachedAt: serializer.fromJson<String>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hubUpdatedAt': serializer.toJson<String?>(hubUpdatedAt),
      'json': serializer.toJson<String>(json),
      'cachedAt': serializer.toJson<String>(cachedAt),
    };
  }

  CachedCollabDetail copyWith({
    String? id,
    Value<String?> hubUpdatedAt = const Value.absent(),
    String? json,
    String? cachedAt,
  }) => CachedCollabDetail(
    id: id ?? this.id,
    hubUpdatedAt: hubUpdatedAt.present ? hubUpdatedAt.value : this.hubUpdatedAt,
    json: json ?? this.json,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedCollabDetail copyWithCompanion(CachedCollabDetailsCompanion data) {
    return CachedCollabDetail(
      id: data.id.present ? data.id.value : this.id,
      hubUpdatedAt: data.hubUpdatedAt.present
          ? data.hubUpdatedAt.value
          : this.hubUpdatedAt,
      json: data.json.present ? data.json.value : this.json,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCollabDetail(')
          ..write('id: $id, ')
          ..write('hubUpdatedAt: $hubUpdatedAt, ')
          ..write('json: $json, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, hubUpdatedAt, json, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCollabDetail &&
          other.id == this.id &&
          other.hubUpdatedAt == this.hubUpdatedAt &&
          other.json == this.json &&
          other.cachedAt == this.cachedAt);
}

class CachedCollabDetailsCompanion extends UpdateCompanion<CachedCollabDetail> {
  final Value<String> id;
  final Value<String?> hubUpdatedAt;
  final Value<String> json;
  final Value<String> cachedAt;
  final Value<int> rowid;
  const CachedCollabDetailsCompanion({
    this.id = const Value.absent(),
    this.hubUpdatedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCollabDetailsCompanion.insert({
    required String id,
    this.hubUpdatedAt = const Value.absent(),
    required String json,
    required String cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       json = Value(json),
       cachedAt = Value(cachedAt);
  static Insertable<CachedCollabDetail> custom({
    Expression<String>? id,
    Expression<String>? hubUpdatedAt,
    Expression<String>? json,
    Expression<String>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hubUpdatedAt != null) 'hub_updated_at': hubUpdatedAt,
      if (json != null) 'json': json,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCollabDetailsCompanion copyWith({
    Value<String>? id,
    Value<String?>? hubUpdatedAt,
    Value<String>? json,
    Value<String>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedCollabDetailsCompanion(
      id: id ?? this.id,
      hubUpdatedAt: hubUpdatedAt ?? this.hubUpdatedAt,
      json: json ?? this.json,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hubUpdatedAt.present) {
      map['hub_updated_at'] = Variable<String>(hubUpdatedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<String>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCollabDetailsCompanion(')
          ..write('id: $id, ')
          ..write('hubUpdatedAt: $hubUpdatedAt, ')
          ..write('json: $json, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaEntriesTable extends MediaEntries
    with TableInfo<$MediaEntriesTable, MediaEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _threadIdMeta = const VerificationMeta(
    'threadId',
  );
  @override
  late final GeneratedColumn<String> threadId = GeneratedColumn<String>(
    'thread_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptedPathMeta = const VerificationMeta(
    'encryptedPath',
  );
  @override
  late final GeneratedColumn<String> encryptedPath = GeneratedColumn<String>(
    'encrypted_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<String> cachedAt = GeneratedColumn<String>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sha256,
    threadId,
    messageId,
    name,
    mime,
    size,
    encryptedPath,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('thread_id')) {
      context.handle(
        _threadIdMeta,
        threadId.isAcceptableOrUnknown(data['thread_id']!, _threadIdMeta),
      );
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
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
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('encrypted_path')) {
      context.handle(
        _encryptedPathMeta,
        encryptedPath.isAcceptableOrUnknown(
          data['encrypted_path']!,
          _encryptedPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPathMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      threadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thread_id'],
      ),
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      ),
      encryptedPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_path'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $MediaEntriesTable createAlias(String alias) {
    return $MediaEntriesTable(attachedDatabase, alias);
  }
}

class MediaEntry extends DataClass implements Insertable<MediaEntry> {
  final String id;
  final String sha256;
  final String? threadId;
  final String? messageId;
  final String name;
  final String mime;
  final int? size;
  final String encryptedPath;
  final String cachedAt;
  const MediaEntry({
    required this.id,
    required this.sha256,
    this.threadId,
    this.messageId,
    required this.name,
    required this.mime,
    this.size,
    required this.encryptedPath,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || threadId != null) {
      map['thread_id'] = Variable<String>(threadId);
    }
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    map['name'] = Variable<String>(name);
    map['mime'] = Variable<String>(mime);
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<int>(size);
    }
    map['encrypted_path'] = Variable<String>(encryptedPath);
    map['cached_at'] = Variable<String>(cachedAt);
    return map;
  }

  MediaEntriesCompanion toCompanion(bool nullToAbsent) {
    return MediaEntriesCompanion(
      id: Value(id),
      sha256: Value(sha256),
      threadId: threadId == null && nullToAbsent
          ? const Value.absent()
          : Value(threadId),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      name: Value(name),
      mime: Value(mime),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      encryptedPath: Value(encryptedPath),
      cachedAt: Value(cachedAt),
    );
  }

  factory MediaEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaEntry(
      id: serializer.fromJson<String>(json['id']),
      sha256: serializer.fromJson<String>(json['sha256']),
      threadId: serializer.fromJson<String?>(json['threadId']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      name: serializer.fromJson<String>(json['name']),
      mime: serializer.fromJson<String>(json['mime']),
      size: serializer.fromJson<int?>(json['size']),
      encryptedPath: serializer.fromJson<String>(json['encryptedPath']),
      cachedAt: serializer.fromJson<String>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sha256': serializer.toJson<String>(sha256),
      'threadId': serializer.toJson<String?>(threadId),
      'messageId': serializer.toJson<String?>(messageId),
      'name': serializer.toJson<String>(name),
      'mime': serializer.toJson<String>(mime),
      'size': serializer.toJson<int?>(size),
      'encryptedPath': serializer.toJson<String>(encryptedPath),
      'cachedAt': serializer.toJson<String>(cachedAt),
    };
  }

  MediaEntry copyWith({
    String? id,
    String? sha256,
    Value<String?> threadId = const Value.absent(),
    Value<String?> messageId = const Value.absent(),
    String? name,
    String? mime,
    Value<int?> size = const Value.absent(),
    String? encryptedPath,
    String? cachedAt,
  }) => MediaEntry(
    id: id ?? this.id,
    sha256: sha256 ?? this.sha256,
    threadId: threadId.present ? threadId.value : this.threadId,
    messageId: messageId.present ? messageId.value : this.messageId,
    name: name ?? this.name,
    mime: mime ?? this.mime,
    size: size.present ? size.value : this.size,
    encryptedPath: encryptedPath ?? this.encryptedPath,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  MediaEntry copyWithCompanion(MediaEntriesCompanion data) {
    return MediaEntry(
      id: data.id.present ? data.id.value : this.id,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      threadId: data.threadId.present ? data.threadId.value : this.threadId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      name: data.name.present ? data.name.value : this.name,
      mime: data.mime.present ? data.mime.value : this.mime,
      size: data.size.present ? data.size.value : this.size,
      encryptedPath: data.encryptedPath.present
          ? data.encryptedPath.value
          : this.encryptedPath,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaEntry(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('threadId: $threadId, ')
          ..write('messageId: $messageId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('encryptedPath: $encryptedPath, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sha256,
    threadId,
    messageId,
    name,
    mime,
    size,
    encryptedPath,
    cachedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaEntry &&
          other.id == this.id &&
          other.sha256 == this.sha256 &&
          other.threadId == this.threadId &&
          other.messageId == this.messageId &&
          other.name == this.name &&
          other.mime == this.mime &&
          other.size == this.size &&
          other.encryptedPath == this.encryptedPath &&
          other.cachedAt == this.cachedAt);
}

class MediaEntriesCompanion extends UpdateCompanion<MediaEntry> {
  final Value<String> id;
  final Value<String> sha256;
  final Value<String?> threadId;
  final Value<String?> messageId;
  final Value<String> name;
  final Value<String> mime;
  final Value<int?> size;
  final Value<String> encryptedPath;
  final Value<String> cachedAt;
  final Value<int> rowid;
  const MediaEntriesCompanion({
    this.id = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.threadId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.name = const Value.absent(),
    this.mime = const Value.absent(),
    this.size = const Value.absent(),
    this.encryptedPath = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaEntriesCompanion.insert({
    required String id,
    required String sha256,
    this.threadId = const Value.absent(),
    this.messageId = const Value.absent(),
    required String name,
    required String mime,
    this.size = const Value.absent(),
    required String encryptedPath,
    required String cachedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sha256 = Value(sha256),
       name = Value(name),
       mime = Value(mime),
       encryptedPath = Value(encryptedPath),
       cachedAt = Value(cachedAt);
  static Insertable<MediaEntry> custom({
    Expression<String>? id,
    Expression<String>? sha256,
    Expression<String>? threadId,
    Expression<String>? messageId,
    Expression<String>? name,
    Expression<String>? mime,
    Expression<int>? size,
    Expression<String>? encryptedPath,
    Expression<String>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sha256 != null) 'sha256': sha256,
      if (threadId != null) 'thread_id': threadId,
      if (messageId != null) 'message_id': messageId,
      if (name != null) 'name': name,
      if (mime != null) 'mime': mime,
      if (size != null) 'size': size,
      if (encryptedPath != null) 'encrypted_path': encryptedPath,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sha256,
    Value<String?>? threadId,
    Value<String?>? messageId,
    Value<String>? name,
    Value<String>? mime,
    Value<int?>? size,
    Value<String>? encryptedPath,
    Value<String>? cachedAt,
    Value<int>? rowid,
  }) {
    return MediaEntriesCompanion(
      id: id ?? this.id,
      sha256: sha256 ?? this.sha256,
      threadId: threadId ?? this.threadId,
      messageId: messageId ?? this.messageId,
      name: name ?? this.name,
      mime: mime ?? this.mime,
      size: size ?? this.size,
      encryptedPath: encryptedPath ?? this.encryptedPath,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (threadId.present) {
      map['thread_id'] = Variable<String>(threadId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (encryptedPath.present) {
      map['encrypted_path'] = Variable<String>(encryptedPath.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<String>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('threadId: $threadId, ')
          ..write('messageId: $messageId, ')
          ..write('name: $name, ')
          ..write('mime: $mime, ')
          ..write('size: $size, ')
          ..write('encryptedPath: $encryptedPath, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NetworkSnapshotsTable extends NetworkSnapshots
    with TableInfo<$NetworkSnapshotsTable, NetworkSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NetworkSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<String> savedAt = GeneratedColumn<String>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, savedAt, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'network_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<NetworkSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind};
  @override
  NetworkSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NetworkSnapshot(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}saved_at'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $NetworkSnapshotsTable createAlias(String alias) {
    return $NetworkSnapshotsTable(attachedDatabase, alias);
  }
}

class NetworkSnapshot extends DataClass implements Insertable<NetworkSnapshot> {
  final String kind;
  final String savedAt;
  final String json;
  const NetworkSnapshot({
    required this.kind,
    required this.savedAt,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['saved_at'] = Variable<String>(savedAt);
    map['json'] = Variable<String>(json);
    return map;
  }

  NetworkSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return NetworkSnapshotsCompanion(
      kind: Value(kind),
      savedAt: Value(savedAt),
      json: Value(json),
    );
  }

  factory NetworkSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NetworkSnapshot(
      kind: serializer.fromJson<String>(json['kind']),
      savedAt: serializer.fromJson<String>(json['savedAt']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'savedAt': serializer.toJson<String>(savedAt),
      'json': serializer.toJson<String>(json),
    };
  }

  NetworkSnapshot copyWith({String? kind, String? savedAt, String? json}) =>
      NetworkSnapshot(
        kind: kind ?? this.kind,
        savedAt: savedAt ?? this.savedAt,
        json: json ?? this.json,
      );
  NetworkSnapshot copyWithCompanion(NetworkSnapshotsCompanion data) {
    return NetworkSnapshot(
      kind: data.kind.present ? data.kind.value : this.kind,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSnapshot(')
          ..write('kind: $kind, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, savedAt, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkSnapshot &&
          other.kind == this.kind &&
          other.savedAt == this.savedAt &&
          other.json == this.json);
}

class NetworkSnapshotsCompanion extends UpdateCompanion<NetworkSnapshot> {
  final Value<String> kind;
  final Value<String> savedAt;
  final Value<String> json;
  final Value<int> rowid;
  const NetworkSnapshotsCompanion({
    this.kind = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NetworkSnapshotsCompanion.insert({
    required String kind,
    required String savedAt,
    required String json,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       savedAt = Value(savedAt),
       json = Value(json);
  static Insertable<NetworkSnapshot> custom({
    Expression<String>? kind,
    Expression<String>? savedAt,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (savedAt != null) 'saved_at': savedAt,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NetworkSnapshotsCompanion copyWith({
    Value<String>? kind,
    Value<String>? savedAt,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return NetworkSnapshotsCompanion(
      kind: kind ?? this.kind,
      savedAt: savedAt ?? this.savedAt,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<String>(savedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSnapshotsCompanion(')
          ..write('kind: $kind, ')
          ..write('savedAt: $savedAt, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MailboxDatabase extends GeneratedDatabase {
  _$MailboxDatabase(QueryExecutor e) : super(e);
  $MailboxDatabaseManager get managers => $MailboxDatabaseManager(this);
  late final $ThreadListSnapshotsTable threadListSnapshots =
      $ThreadListSnapshotsTable(this);
  late final $CachedThreadDetailsTable cachedThreadDetails =
      $CachedThreadDetailsTable(this);
  late final $CollabListSnapshotsTable collabListSnapshots =
      $CollabListSnapshotsTable(this);
  late final $CachedCollabDetailsTable cachedCollabDetails =
      $CachedCollabDetailsTable(this);
  late final $MediaEntriesTable mediaEntries = $MediaEntriesTable(this);
  late final $NetworkSnapshotsTable networkSnapshots = $NetworkSnapshotsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    threadListSnapshots,
    cachedThreadDetails,
    collabListSnapshots,
    cachedCollabDetails,
    mediaEntries,
    networkSnapshots,
  ];
}

typedef $$ThreadListSnapshotsTableCreateCompanionBuilder =
    ThreadListSnapshotsCompanion Function({
      required String filterKey,
      required String savedAt,
      required String json,
      Value<int> rowid,
    });
typedef $$ThreadListSnapshotsTableUpdateCompanionBuilder =
    ThreadListSnapshotsCompanion Function({
      Value<String> filterKey,
      Value<String> savedAt,
      Value<String> json,
      Value<int> rowid,
    });

class $$ThreadListSnapshotsTableFilterComposer
    extends Composer<_$MailboxDatabase, $ThreadListSnapshotsTable> {
  $$ThreadListSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get filterKey => $composableBuilder(
    column: $table.filterKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ThreadListSnapshotsTableOrderingComposer
    extends Composer<_$MailboxDatabase, $ThreadListSnapshotsTable> {
  $$ThreadListSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get filterKey => $composableBuilder(
    column: $table.filterKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThreadListSnapshotsTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $ThreadListSnapshotsTable> {
  $$ThreadListSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get filterKey =>
      $composableBuilder(column: $table.filterKey, builder: (column) => column);

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$ThreadListSnapshotsTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $ThreadListSnapshotsTable,
          ThreadListSnapshot,
          $$ThreadListSnapshotsTableFilterComposer,
          $$ThreadListSnapshotsTableOrderingComposer,
          $$ThreadListSnapshotsTableAnnotationComposer,
          $$ThreadListSnapshotsTableCreateCompanionBuilder,
          $$ThreadListSnapshotsTableUpdateCompanionBuilder,
          (
            ThreadListSnapshot,
            BaseReferences<
              _$MailboxDatabase,
              $ThreadListSnapshotsTable,
              ThreadListSnapshot
            >,
          ),
          ThreadListSnapshot,
          PrefetchHooks Function()
        > {
  $$ThreadListSnapshotsTableTableManager(
    _$MailboxDatabase db,
    $ThreadListSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreadListSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreadListSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ThreadListSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> filterKey = const Value.absent(),
                Value<String> savedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreadListSnapshotsCompanion(
                filterKey: filterKey,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String filterKey,
                required String savedAt,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => ThreadListSnapshotsCompanion.insert(
                filterKey: filterKey,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ThreadListSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $ThreadListSnapshotsTable,
      ThreadListSnapshot,
      $$ThreadListSnapshotsTableFilterComposer,
      $$ThreadListSnapshotsTableOrderingComposer,
      $$ThreadListSnapshotsTableAnnotationComposer,
      $$ThreadListSnapshotsTableCreateCompanionBuilder,
      $$ThreadListSnapshotsTableUpdateCompanionBuilder,
      (
        ThreadListSnapshot,
        BaseReferences<
          _$MailboxDatabase,
          $ThreadListSnapshotsTable,
          ThreadListSnapshot
        >,
      ),
      ThreadListSnapshot,
      PrefetchHooks Function()
    >;
typedef $$CachedThreadDetailsTableCreateCompanionBuilder =
    CachedThreadDetailsCompanion Function({
      required String id,
      Value<String?> hubUpdatedAt,
      required String json,
      required String cachedAt,
      Value<int> rowid,
    });
typedef $$CachedThreadDetailsTableUpdateCompanionBuilder =
    CachedThreadDetailsCompanion Function({
      Value<String> id,
      Value<String?> hubUpdatedAt,
      Value<String> json,
      Value<String> cachedAt,
      Value<int> rowid,
    });

class $$CachedThreadDetailsTableFilterComposer
    extends Composer<_$MailboxDatabase, $CachedThreadDetailsTable> {
  $$CachedThreadDetailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedThreadDetailsTableOrderingComposer
    extends Composer<_$MailboxDatabase, $CachedThreadDetailsTable> {
  $$CachedThreadDetailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedThreadDetailsTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $CachedThreadDetailsTable> {
  $$CachedThreadDetailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedThreadDetailsTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $CachedThreadDetailsTable,
          CachedThreadDetail,
          $$CachedThreadDetailsTableFilterComposer,
          $$CachedThreadDetailsTableOrderingComposer,
          $$CachedThreadDetailsTableAnnotationComposer,
          $$CachedThreadDetailsTableCreateCompanionBuilder,
          $$CachedThreadDetailsTableUpdateCompanionBuilder,
          (
            CachedThreadDetail,
            BaseReferences<
              _$MailboxDatabase,
              $CachedThreadDetailsTable,
              CachedThreadDetail
            >,
          ),
          CachedThreadDetail,
          PrefetchHooks Function()
        > {
  $$CachedThreadDetailsTableTableManager(
    _$MailboxDatabase db,
    $CachedThreadDetailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedThreadDetailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedThreadDetailsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedThreadDetailsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> hubUpdatedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<String> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedThreadDetailsCompanion(
                id: id,
                hubUpdatedAt: hubUpdatedAt,
                json: json,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> hubUpdatedAt = const Value.absent(),
                required String json,
                required String cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedThreadDetailsCompanion.insert(
                id: id,
                hubUpdatedAt: hubUpdatedAt,
                json: json,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedThreadDetailsTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $CachedThreadDetailsTable,
      CachedThreadDetail,
      $$CachedThreadDetailsTableFilterComposer,
      $$CachedThreadDetailsTableOrderingComposer,
      $$CachedThreadDetailsTableAnnotationComposer,
      $$CachedThreadDetailsTableCreateCompanionBuilder,
      $$CachedThreadDetailsTableUpdateCompanionBuilder,
      (
        CachedThreadDetail,
        BaseReferences<
          _$MailboxDatabase,
          $CachedThreadDetailsTable,
          CachedThreadDetail
        >,
      ),
      CachedThreadDetail,
      PrefetchHooks Function()
    >;
typedef $$CollabListSnapshotsTableCreateCompanionBuilder =
    CollabListSnapshotsCompanion Function({
      required String archiveKey,
      required String savedAt,
      required String json,
      Value<int> rowid,
    });
typedef $$CollabListSnapshotsTableUpdateCompanionBuilder =
    CollabListSnapshotsCompanion Function({
      Value<String> archiveKey,
      Value<String> savedAt,
      Value<String> json,
      Value<int> rowid,
    });

class $$CollabListSnapshotsTableFilterComposer
    extends Composer<_$MailboxDatabase, $CollabListSnapshotsTable> {
  $$CollabListSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get archiveKey => $composableBuilder(
    column: $table.archiveKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollabListSnapshotsTableOrderingComposer
    extends Composer<_$MailboxDatabase, $CollabListSnapshotsTable> {
  $$CollabListSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get archiveKey => $composableBuilder(
    column: $table.archiveKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollabListSnapshotsTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $CollabListSnapshotsTable> {
  $$CollabListSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get archiveKey => $composableBuilder(
    column: $table.archiveKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$CollabListSnapshotsTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $CollabListSnapshotsTable,
          CollabListSnapshot,
          $$CollabListSnapshotsTableFilterComposer,
          $$CollabListSnapshotsTableOrderingComposer,
          $$CollabListSnapshotsTableAnnotationComposer,
          $$CollabListSnapshotsTableCreateCompanionBuilder,
          $$CollabListSnapshotsTableUpdateCompanionBuilder,
          (
            CollabListSnapshot,
            BaseReferences<
              _$MailboxDatabase,
              $CollabListSnapshotsTable,
              CollabListSnapshot
            >,
          ),
          CollabListSnapshot,
          PrefetchHooks Function()
        > {
  $$CollabListSnapshotsTableTableManager(
    _$MailboxDatabase db,
    $CollabListSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollabListSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollabListSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CollabListSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> archiveKey = const Value.absent(),
                Value<String> savedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollabListSnapshotsCompanion(
                archiveKey: archiveKey,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String archiveKey,
                required String savedAt,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => CollabListSnapshotsCompanion.insert(
                archiveKey: archiveKey,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollabListSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $CollabListSnapshotsTable,
      CollabListSnapshot,
      $$CollabListSnapshotsTableFilterComposer,
      $$CollabListSnapshotsTableOrderingComposer,
      $$CollabListSnapshotsTableAnnotationComposer,
      $$CollabListSnapshotsTableCreateCompanionBuilder,
      $$CollabListSnapshotsTableUpdateCompanionBuilder,
      (
        CollabListSnapshot,
        BaseReferences<
          _$MailboxDatabase,
          $CollabListSnapshotsTable,
          CollabListSnapshot
        >,
      ),
      CollabListSnapshot,
      PrefetchHooks Function()
    >;
typedef $$CachedCollabDetailsTableCreateCompanionBuilder =
    CachedCollabDetailsCompanion Function({
      required String id,
      Value<String?> hubUpdatedAt,
      required String json,
      required String cachedAt,
      Value<int> rowid,
    });
typedef $$CachedCollabDetailsTableUpdateCompanionBuilder =
    CachedCollabDetailsCompanion Function({
      Value<String> id,
      Value<String?> hubUpdatedAt,
      Value<String> json,
      Value<String> cachedAt,
      Value<int> rowid,
    });

class $$CachedCollabDetailsTableFilterComposer
    extends Composer<_$MailboxDatabase, $CachedCollabDetailsTable> {
  $$CachedCollabDetailsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCollabDetailsTableOrderingComposer
    extends Composer<_$MailboxDatabase, $CachedCollabDetailsTable> {
  $$CachedCollabDetailsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCollabDetailsTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $CachedCollabDetailsTable> {
  $$CachedCollabDetailsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hubUpdatedAt => $composableBuilder(
    column: $table.hubUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedCollabDetailsTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $CachedCollabDetailsTable,
          CachedCollabDetail,
          $$CachedCollabDetailsTableFilterComposer,
          $$CachedCollabDetailsTableOrderingComposer,
          $$CachedCollabDetailsTableAnnotationComposer,
          $$CachedCollabDetailsTableCreateCompanionBuilder,
          $$CachedCollabDetailsTableUpdateCompanionBuilder,
          (
            CachedCollabDetail,
            BaseReferences<
              _$MailboxDatabase,
              $CachedCollabDetailsTable,
              CachedCollabDetail
            >,
          ),
          CachedCollabDetail,
          PrefetchHooks Function()
        > {
  $$CachedCollabDetailsTableTableManager(
    _$MailboxDatabase db,
    $CachedCollabDetailsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCollabDetailsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCollabDetailsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedCollabDetailsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> hubUpdatedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<String> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCollabDetailsCompanion(
                id: id,
                hubUpdatedAt: hubUpdatedAt,
                json: json,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> hubUpdatedAt = const Value.absent(),
                required String json,
                required String cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedCollabDetailsCompanion.insert(
                id: id,
                hubUpdatedAt: hubUpdatedAt,
                json: json,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCollabDetailsTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $CachedCollabDetailsTable,
      CachedCollabDetail,
      $$CachedCollabDetailsTableFilterComposer,
      $$CachedCollabDetailsTableOrderingComposer,
      $$CachedCollabDetailsTableAnnotationComposer,
      $$CachedCollabDetailsTableCreateCompanionBuilder,
      $$CachedCollabDetailsTableUpdateCompanionBuilder,
      (
        CachedCollabDetail,
        BaseReferences<
          _$MailboxDatabase,
          $CachedCollabDetailsTable,
          CachedCollabDetail
        >,
      ),
      CachedCollabDetail,
      PrefetchHooks Function()
    >;
typedef $$MediaEntriesTableCreateCompanionBuilder =
    MediaEntriesCompanion Function({
      required String id,
      required String sha256,
      Value<String?> threadId,
      Value<String?> messageId,
      required String name,
      required String mime,
      Value<int?> size,
      required String encryptedPath,
      required String cachedAt,
      Value<int> rowid,
    });
typedef $$MediaEntriesTableUpdateCompanionBuilder =
    MediaEntriesCompanion Function({
      Value<String> id,
      Value<String> sha256,
      Value<String?> threadId,
      Value<String?> messageId,
      Value<String> name,
      Value<String> mime,
      Value<int?> size,
      Value<String> encryptedPath,
      Value<String> cachedAt,
      Value<int> rowid,
    });

class $$MediaEntriesTableFilterComposer
    extends Composer<_$MailboxDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaEntriesTableOrderingComposer
    extends Composer<_$MailboxDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get threadId => $composableBuilder(
    column: $table.threadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaEntriesTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get threadId =>
      $composableBuilder(column: $table.threadId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get encryptedPath => $composableBuilder(
    column: $table.encryptedPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$MediaEntriesTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $MediaEntriesTable,
          MediaEntry,
          $$MediaEntriesTableFilterComposer,
          $$MediaEntriesTableOrderingComposer,
          $$MediaEntriesTableAnnotationComposer,
          $$MediaEntriesTableCreateCompanionBuilder,
          $$MediaEntriesTableUpdateCompanionBuilder,
          (
            MediaEntry,
            BaseReferences<_$MailboxDatabase, $MediaEntriesTable, MediaEntry>,
          ),
          MediaEntry,
          PrefetchHooks Function()
        > {
  $$MediaEntriesTableTableManager(
    _$MailboxDatabase db,
    $MediaEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> threadId = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<String> encryptedPath = const Value.absent(),
                Value<String> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaEntriesCompanion(
                id: id,
                sha256: sha256,
                threadId: threadId,
                messageId: messageId,
                name: name,
                mime: mime,
                size: size,
                encryptedPath: encryptedPath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sha256,
                Value<String?> threadId = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                required String name,
                required String mime,
                Value<int?> size = const Value.absent(),
                required String encryptedPath,
                required String cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => MediaEntriesCompanion.insert(
                id: id,
                sha256: sha256,
                threadId: threadId,
                messageId: messageId,
                name: name,
                mime: mime,
                size: size,
                encryptedPath: encryptedPath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $MediaEntriesTable,
      MediaEntry,
      $$MediaEntriesTableFilterComposer,
      $$MediaEntriesTableOrderingComposer,
      $$MediaEntriesTableAnnotationComposer,
      $$MediaEntriesTableCreateCompanionBuilder,
      $$MediaEntriesTableUpdateCompanionBuilder,
      (
        MediaEntry,
        BaseReferences<_$MailboxDatabase, $MediaEntriesTable, MediaEntry>,
      ),
      MediaEntry,
      PrefetchHooks Function()
    >;
typedef $$NetworkSnapshotsTableCreateCompanionBuilder =
    NetworkSnapshotsCompanion Function({
      required String kind,
      required String savedAt,
      required String json,
      Value<int> rowid,
    });
typedef $$NetworkSnapshotsTableUpdateCompanionBuilder =
    NetworkSnapshotsCompanion Function({
      Value<String> kind,
      Value<String> savedAt,
      Value<String> json,
      Value<int> rowid,
    });

class $$NetworkSnapshotsTableFilterComposer
    extends Composer<_$MailboxDatabase, $NetworkSnapshotsTable> {
  $$NetworkSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NetworkSnapshotsTableOrderingComposer
    extends Composer<_$MailboxDatabase, $NetworkSnapshotsTable> {
  $$NetworkSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NetworkSnapshotsTableAnnotationComposer
    extends Composer<_$MailboxDatabase, $NetworkSnapshotsTable> {
  $$NetworkSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$NetworkSnapshotsTableTableManager
    extends
        RootTableManager<
          _$MailboxDatabase,
          $NetworkSnapshotsTable,
          NetworkSnapshot,
          $$NetworkSnapshotsTableFilterComposer,
          $$NetworkSnapshotsTableOrderingComposer,
          $$NetworkSnapshotsTableAnnotationComposer,
          $$NetworkSnapshotsTableCreateCompanionBuilder,
          $$NetworkSnapshotsTableUpdateCompanionBuilder,
          (
            NetworkSnapshot,
            BaseReferences<
              _$MailboxDatabase,
              $NetworkSnapshotsTable,
              NetworkSnapshot
            >,
          ),
          NetworkSnapshot,
          PrefetchHooks Function()
        > {
  $$NetworkSnapshotsTableTableManager(
    _$MailboxDatabase db,
    $NetworkSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NetworkSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NetworkSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NetworkSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<String> savedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NetworkSnapshotsCompanion(
                kind: kind,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required String savedAt,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => NetworkSnapshotsCompanion.insert(
                kind: kind,
                savedAt: savedAt,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NetworkSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$MailboxDatabase,
      $NetworkSnapshotsTable,
      NetworkSnapshot,
      $$NetworkSnapshotsTableFilterComposer,
      $$NetworkSnapshotsTableOrderingComposer,
      $$NetworkSnapshotsTableAnnotationComposer,
      $$NetworkSnapshotsTableCreateCompanionBuilder,
      $$NetworkSnapshotsTableUpdateCompanionBuilder,
      (
        NetworkSnapshot,
        BaseReferences<
          _$MailboxDatabase,
          $NetworkSnapshotsTable,
          NetworkSnapshot
        >,
      ),
      NetworkSnapshot,
      PrefetchHooks Function()
    >;

class $MailboxDatabaseManager {
  final _$MailboxDatabase _db;
  $MailboxDatabaseManager(this._db);
  $$ThreadListSnapshotsTableTableManager get threadListSnapshots =>
      $$ThreadListSnapshotsTableTableManager(_db, _db.threadListSnapshots);
  $$CachedThreadDetailsTableTableManager get cachedThreadDetails =>
      $$CachedThreadDetailsTableTableManager(_db, _db.cachedThreadDetails);
  $$CollabListSnapshotsTableTableManager get collabListSnapshots =>
      $$CollabListSnapshotsTableTableManager(_db, _db.collabListSnapshots);
  $$CachedCollabDetailsTableTableManager get cachedCollabDetails =>
      $$CachedCollabDetailsTableTableManager(_db, _db.cachedCollabDetails);
  $$MediaEntriesTableTableManager get mediaEntries =>
      $$MediaEntriesTableTableManager(_db, _db.mediaEntries);
  $$NetworkSnapshotsTableTableManager get networkSnapshots =>
      $$NetworkSnapshotsTableTableManager(_db, _db.networkSnapshots);
}
