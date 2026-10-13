// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ServersTable extends Servers with TableInfo<$ServersTable, Server> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requiresPasswordMeta = const VerificationMeta(
    'requiresPassword',
  );
  @override
  late final GeneratedColumn<bool> requiresPassword = GeneratedColumn<bool>(
    'requires_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_password" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _allowSelfSignedMeta = const VerificationMeta(
    'allowSelfSigned',
  );
  @override
  late final GeneratedColumn<bool> allowSelfSigned = GeneratedColumn<bool>(
    'allow_self_signed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_self_signed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _usesAccessTokenMeta = const VerificationMeta(
    'usesAccessToken',
  );
  @override
  late final GeneratedColumn<bool> usesAccessToken = GeneratedColumn<bool>(
    'uses_access_token',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("uses_access_token" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverVersionMeta = const VerificationMeta(
    'serverVersion',
  );
  @override
  late final GeneratedColumn<String> serverVersion = GeneratedColumn<String>(
    'server_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capabilitiesJsonMeta = const VerificationMeta(
    'capabilitiesJson',
  );
  @override
  late final GeneratedColumn<String> capabilitiesJson = GeneratedColumn<String>(
    'capabilities_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _probedAtMeta = const VerificationMeta(
    'probedAt',
  );
  @override
  late final GeneratedColumn<DateTime> probedAt = GeneratedColumn<DateTime>(
    'probed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastConnectedAt =
      GeneratedColumn<DateTime>(
        'last_connected_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    baseUrl,
    label,
    requiresPassword,
    allowSelfSigned,
    usesAccessToken,
    serverVersion,
    capabilitiesJson,
    probedAt,
    lastConnectedAt,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Server> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('requires_password')) {
      context.handle(
        _requiresPasswordMeta,
        requiresPassword.isAcceptableOrUnknown(
          data['requires_password']!,
          _requiresPasswordMeta,
        ),
      );
    }
    if (data.containsKey('allow_self_signed')) {
      context.handle(
        _allowSelfSignedMeta,
        allowSelfSigned.isAcceptableOrUnknown(
          data['allow_self_signed']!,
          _allowSelfSignedMeta,
        ),
      );
    }
    if (data.containsKey('uses_access_token')) {
      context.handle(
        _usesAccessTokenMeta,
        usesAccessToken.isAcceptableOrUnknown(
          data['uses_access_token']!,
          _usesAccessTokenMeta,
        ),
      );
    }
    if (data.containsKey('server_version')) {
      context.handle(
        _serverVersionMeta,
        serverVersion.isAcceptableOrUnknown(
          data['server_version']!,
          _serverVersionMeta,
        ),
      );
    }
    if (data.containsKey('capabilities_json')) {
      context.handle(
        _capabilitiesJsonMeta,
        capabilitiesJson.isAcceptableOrUnknown(
          data['capabilities_json']!,
          _capabilitiesJsonMeta,
        ),
      );
    }
    if (data.containsKey('probed_at')) {
      context.handle(
        _probedAtMeta,
        probedAt.isAcceptableOrUnknown(data['probed_at']!, _probedAtMeta),
      );
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Server map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Server(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      requiresPassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_password'],
      )!,
      allowSelfSigned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_self_signed'],
      )!,
      usesAccessToken: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}uses_access_token'],
      )!,
      serverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_version'],
      ),
      capabilitiesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}capabilities_json'],
      )!,
      probedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}probed_at'],
      ),
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_connected_at'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ServersTable createAlias(String alias) {
    return $ServersTable(attachedDatabase, alias);
  }
}

class Server extends DataClass implements Insertable<Server> {
  final String id;
  final String baseUrl;
  final String label;
  final bool requiresPassword;
  final bool allowSelfSigned;

  /// Whether a Cloudflare Access service token is stored for this server. The
  /// token itself is in the keystore; this only drives what the UI shows.
  final bool usesAccessToken;

  /// What `/api/status` last reported, for display. Never used to gate a
  /// feature.
  final String? serverVersion;

  /// Probe results, stored as the JSON list of capability names so a new
  /// capability in a later build does not need a schema migration.
  final String capabilitiesJson;
  final DateTime? probedAt;
  final DateTime? lastConnectedAt;

  /// Ordering in the server switcher.
  final int position;
  const Server({
    required this.id,
    required this.baseUrl,
    required this.label,
    required this.requiresPassword,
    required this.allowSelfSigned,
    required this.usesAccessToken,
    this.serverVersion,
    required this.capabilitiesJson,
    this.probedAt,
    this.lastConnectedAt,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['base_url'] = Variable<String>(baseUrl);
    map['label'] = Variable<String>(label);
    map['requires_password'] = Variable<bool>(requiresPassword);
    map['allow_self_signed'] = Variable<bool>(allowSelfSigned);
    map['uses_access_token'] = Variable<bool>(usesAccessToken);
    if (!nullToAbsent || serverVersion != null) {
      map['server_version'] = Variable<String>(serverVersion);
    }
    map['capabilities_json'] = Variable<String>(capabilitiesJson);
    if (!nullToAbsent || probedAt != null) {
      map['probed_at'] = Variable<DateTime>(probedAt);
    }
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  ServersCompanion toCompanion(bool nullToAbsent) {
    return ServersCompanion(
      id: Value(id),
      baseUrl: Value(baseUrl),
      label: Value(label),
      requiresPassword: Value(requiresPassword),
      allowSelfSigned: Value(allowSelfSigned),
      usesAccessToken: Value(usesAccessToken),
      serverVersion: serverVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(serverVersion),
      capabilitiesJson: Value(capabilitiesJson),
      probedAt: probedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(probedAt),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      position: Value(position),
    );
  }

  factory Server.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Server(
      id: serializer.fromJson<String>(json['id']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      label: serializer.fromJson<String>(json['label']),
      requiresPassword: serializer.fromJson<bool>(json['requiresPassword']),
      allowSelfSigned: serializer.fromJson<bool>(json['allowSelfSigned']),
      usesAccessToken: serializer.fromJson<bool>(json['usesAccessToken']),
      serverVersion: serializer.fromJson<String?>(json['serverVersion']),
      capabilitiesJson: serializer.fromJson<String>(json['capabilitiesJson']),
      probedAt: serializer.fromJson<DateTime?>(json['probedAt']),
      lastConnectedAt: serializer.fromJson<DateTime?>(json['lastConnectedAt']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'label': serializer.toJson<String>(label),
      'requiresPassword': serializer.toJson<bool>(requiresPassword),
      'allowSelfSigned': serializer.toJson<bool>(allowSelfSigned),
      'usesAccessToken': serializer.toJson<bool>(usesAccessToken),
      'serverVersion': serializer.toJson<String?>(serverVersion),
      'capabilitiesJson': serializer.toJson<String>(capabilitiesJson),
      'probedAt': serializer.toJson<DateTime?>(probedAt),
      'lastConnectedAt': serializer.toJson<DateTime?>(lastConnectedAt),
      'position': serializer.toJson<int>(position),
    };
  }

  Server copyWith({
    String? id,
    String? baseUrl,
    String? label,
    bool? requiresPassword,
    bool? allowSelfSigned,
    bool? usesAccessToken,
    Value<String?> serverVersion = const Value.absent(),
    String? capabilitiesJson,
    Value<DateTime?> probedAt = const Value.absent(),
    Value<DateTime?> lastConnectedAt = const Value.absent(),
    int? position,
  }) => Server(
    id: id ?? this.id,
    baseUrl: baseUrl ?? this.baseUrl,
    label: label ?? this.label,
    requiresPassword: requiresPassword ?? this.requiresPassword,
    allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
    usesAccessToken: usesAccessToken ?? this.usesAccessToken,
    serverVersion: serverVersion.present
        ? serverVersion.value
        : this.serverVersion,
    capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
    probedAt: probedAt.present ? probedAt.value : this.probedAt,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
    position: position ?? this.position,
  );
  Server copyWithCompanion(ServersCompanion data) {
    return Server(
      id: data.id.present ? data.id.value : this.id,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      label: data.label.present ? data.label.value : this.label,
      requiresPassword: data.requiresPassword.present
          ? data.requiresPassword.value
          : this.requiresPassword,
      allowSelfSigned: data.allowSelfSigned.present
          ? data.allowSelfSigned.value
          : this.allowSelfSigned,
      usesAccessToken: data.usesAccessToken.present
          ? data.usesAccessToken.value
          : this.usesAccessToken,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      capabilitiesJson: data.capabilitiesJson.present
          ? data.capabilitiesJson.value
          : this.capabilitiesJson,
      probedAt: data.probedAt.present ? data.probedAt.value : this.probedAt,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Server(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('label: $label, ')
          ..write('requiresPassword: $requiresPassword, ')
          ..write('allowSelfSigned: $allowSelfSigned, ')
          ..write('usesAccessToken: $usesAccessToken, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('probedAt: $probedAt, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    baseUrl,
    label,
    requiresPassword,
    allowSelfSigned,
    usesAccessToken,
    serverVersion,
    capabilitiesJson,
    probedAt,
    lastConnectedAt,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Server &&
          other.id == this.id &&
          other.baseUrl == this.baseUrl &&
          other.label == this.label &&
          other.requiresPassword == this.requiresPassword &&
          other.allowSelfSigned == this.allowSelfSigned &&
          other.usesAccessToken == this.usesAccessToken &&
          other.serverVersion == this.serverVersion &&
          other.capabilitiesJson == this.capabilitiesJson &&
          other.probedAt == this.probedAt &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.position == this.position);
}

class ServersCompanion extends UpdateCompanion<Server> {
  final Value<String> id;
  final Value<String> baseUrl;
  final Value<String> label;
  final Value<bool> requiresPassword;
  final Value<bool> allowSelfSigned;
  final Value<bool> usesAccessToken;
  final Value<String?> serverVersion;
  final Value<String> capabilitiesJson;
  final Value<DateTime?> probedAt;
  final Value<DateTime?> lastConnectedAt;
  final Value<int> position;
  final Value<int> rowid;
  const ServersCompanion({
    this.id = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.label = const Value.absent(),
    this.requiresPassword = const Value.absent(),
    this.allowSelfSigned = const Value.absent(),
    this.usesAccessToken = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.probedAt = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServersCompanion.insert({
    required String id,
    required String baseUrl,
    required String label,
    this.requiresPassword = const Value.absent(),
    this.allowSelfSigned = const Value.absent(),
    this.usesAccessToken = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.capabilitiesJson = const Value.absent(),
    this.probedAt = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       baseUrl = Value(baseUrl),
       label = Value(label);
  static Insertable<Server> custom({
    Expression<String>? id,
    Expression<String>? baseUrl,
    Expression<String>? label,
    Expression<bool>? requiresPassword,
    Expression<bool>? allowSelfSigned,
    Expression<bool>? usesAccessToken,
    Expression<String>? serverVersion,
    Expression<String>? capabilitiesJson,
    Expression<DateTime>? probedAt,
    Expression<DateTime>? lastConnectedAt,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baseUrl != null) 'base_url': baseUrl,
      if (label != null) 'label': label,
      if (requiresPassword != null) 'requires_password': requiresPassword,
      if (allowSelfSigned != null) 'allow_self_signed': allowSelfSigned,
      if (usesAccessToken != null) 'uses_access_token': usesAccessToken,
      if (serverVersion != null) 'server_version': serverVersion,
      if (capabilitiesJson != null) 'capabilities_json': capabilitiesJson,
      if (probedAt != null) 'probed_at': probedAt,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServersCompanion copyWith({
    Value<String>? id,
    Value<String>? baseUrl,
    Value<String>? label,
    Value<bool>? requiresPassword,
    Value<bool>? allowSelfSigned,
    Value<bool>? usesAccessToken,
    Value<String?>? serverVersion,
    Value<String>? capabilitiesJson,
    Value<DateTime?>? probedAt,
    Value<DateTime?>? lastConnectedAt,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ServersCompanion(
      id: id ?? this.id,
      baseUrl: baseUrl ?? this.baseUrl,
      label: label ?? this.label,
      requiresPassword: requiresPassword ?? this.requiresPassword,
      allowSelfSigned: allowSelfSigned ?? this.allowSelfSigned,
      usesAccessToken: usesAccessToken ?? this.usesAccessToken,
      serverVersion: serverVersion ?? this.serverVersion,
      capabilitiesJson: capabilitiesJson ?? this.capabilitiesJson,
      probedAt: probedAt ?? this.probedAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (requiresPassword.present) {
      map['requires_password'] = Variable<bool>(requiresPassword.value);
    }
    if (allowSelfSigned.present) {
      map['allow_self_signed'] = Variable<bool>(allowSelfSigned.value);
    }
    if (usesAccessToken.present) {
      map['uses_access_token'] = Variable<bool>(usesAccessToken.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<String>(serverVersion.value);
    }
    if (capabilitiesJson.present) {
      map['capabilities_json'] = Variable<String>(capabilitiesJson.value);
    }
    if (probedAt.present) {
      map['probed_at'] = Variable<DateTime>(probedAt.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<DateTime>(lastConnectedAt.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServersCompanion(')
          ..write('id: $id, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('label: $label, ')
          ..write('requiresPassword: $requiresPassword, ')
          ..write('allowSelfSigned: $allowSelfSigned, ')
          ..write('usesAccessToken: $usesAccessToken, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('capabilitiesJson: $capabilitiesJson, ')
          ..write('probedAt: $probedAt, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedSessionsTable extends CachedSessions
    with TableInfo<$CachedSessionsTable, CachedSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES servers (id)',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _workspaceMeta = const VerificationMeta(
    'workspace',
  );
  @override
  late final GeneratedColumn<String> workspace = GeneratedColumn<String>(
    'workspace',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _hasFullHistoryMeta = const VerificationMeta(
    'hasFullHistory',
  );
  @override
  late final GeneratedColumn<bool> hasFullHistory = GeneratedColumn<bool>(
    'has_full_history',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_full_history" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    sessionId,
    title,
    workspace,
    model,
    projectId,
    createdAt,
    updatedAt,
    pinned,
    archived,
    tagsJson,
    hasFullHistory,
    syncedAt,
    rawJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('workspace')) {
      context.handle(
        _workspaceMeta,
        workspace.isAcceptableOrUnknown(data['workspace']!, _workspaceMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('has_full_history')) {
      context.handle(
        _hasFullHistoryMeta,
        hasFullHistory.isAcceptableOrUnknown(
          data['has_full_history']!,
          _hasFullHistoryMeta,
        ),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId, sessionId};
  @override
  CachedSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSession(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      workspace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      hasFullHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_full_history'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
    );
  }

  @override
  $CachedSessionsTable createAlias(String alias) {
    return $CachedSessionsTable(attachedDatabase, alias);
  }
}

class CachedSession extends DataClass implements Insertable<CachedSession> {
  final String serverId;
  final String sessionId;
  final String title;
  final String? workspace;
  final String? model;
  final String? projectId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool pinned;
  final bool archived;
  final String tagsJson;

  /// Whether the message history has been fetched, as opposed to just the
  /// list row. Distinguishes "no messages" from "not loaded yet".
  final bool hasFullHistory;
  final DateTime? syncedAt;
  final String rawJson;
  const CachedSession({
    required this.serverId,
    required this.sessionId,
    required this.title,
    this.workspace,
    this.model,
    this.projectId,
    this.createdAt,
    this.updatedAt,
    required this.pinned,
    required this.archived,
    required this.tagsJson,
    required this.hasFullHistory,
    this.syncedAt,
    required this.rawJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<String>(serverId);
    map['session_id'] = Variable<String>(sessionId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || workspace != null) {
      map['workspace'] = Variable<String>(workspace);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    map['pinned'] = Variable<bool>(pinned);
    map['archived'] = Variable<bool>(archived);
    map['tags_json'] = Variable<String>(tagsJson);
    map['has_full_history'] = Variable<bool>(hasFullHistory);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['raw_json'] = Variable<String>(rawJson);
    return map;
  }

  CachedSessionsCompanion toCompanion(bool nullToAbsent) {
    return CachedSessionsCompanion(
      serverId: Value(serverId),
      sessionId: Value(sessionId),
      title: Value(title),
      workspace: workspace == null && nullToAbsent
          ? const Value.absent()
          : Value(workspace),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      pinned: Value(pinned),
      archived: Value(archived),
      tagsJson: Value(tagsJson),
      hasFullHistory: Value(hasFullHistory),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      rawJson: Value(rawJson),
    );
  }

  factory CachedSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSession(
      serverId: serializer.fromJson<String>(json['serverId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      title: serializer.fromJson<String>(json['title']),
      workspace: serializer.fromJson<String?>(json['workspace']),
      model: serializer.fromJson<String?>(json['model']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      archived: serializer.fromJson<bool>(json['archived']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      hasFullHistory: serializer.fromJson<bool>(json['hasFullHistory']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<String>(serverId),
      'sessionId': serializer.toJson<String>(sessionId),
      'title': serializer.toJson<String>(title),
      'workspace': serializer.toJson<String?>(workspace),
      'model': serializer.toJson<String?>(model),
      'projectId': serializer.toJson<String?>(projectId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'pinned': serializer.toJson<bool>(pinned),
      'archived': serializer.toJson<bool>(archived),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'hasFullHistory': serializer.toJson<bool>(hasFullHistory),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'rawJson': serializer.toJson<String>(rawJson),
    };
  }

  CachedSession copyWith({
    String? serverId,
    String? sessionId,
    String? title,
    Value<String?> workspace = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<String?> projectId = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    bool? pinned,
    bool? archived,
    String? tagsJson,
    bool? hasFullHistory,
    Value<DateTime?> syncedAt = const Value.absent(),
    String? rawJson,
  }) => CachedSession(
    serverId: serverId ?? this.serverId,
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    workspace: workspace.present ? workspace.value : this.workspace,
    model: model.present ? model.value : this.model,
    projectId: projectId.present ? projectId.value : this.projectId,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
    tagsJson: tagsJson ?? this.tagsJson,
    hasFullHistory: hasFullHistory ?? this.hasFullHistory,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    rawJson: rawJson ?? this.rawJson,
  );
  CachedSession copyWithCompanion(CachedSessionsCompanion data) {
    return CachedSession(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      title: data.title.present ? data.title.value : this.title,
      workspace: data.workspace.present ? data.workspace.value : this.workspace,
      model: data.model.present ? data.model.value : this.model,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      archived: data.archived.present ? data.archived.value : this.archived,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      hasFullHistory: data.hasFullHistory.present
          ? data.hasFullHistory.value
          : this.hasFullHistory,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSession(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('workspace: $workspace, ')
          ..write('model: $model, ')
          ..write('projectId: $projectId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('archived: $archived, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('hasFullHistory: $hasFullHistory, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rawJson: $rawJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    serverId,
    sessionId,
    title,
    workspace,
    model,
    projectId,
    createdAt,
    updatedAt,
    pinned,
    archived,
    tagsJson,
    hasFullHistory,
    syncedAt,
    rawJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSession &&
          other.serverId == this.serverId &&
          other.sessionId == this.sessionId &&
          other.title == this.title &&
          other.workspace == this.workspace &&
          other.model == this.model &&
          other.projectId == this.projectId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.pinned == this.pinned &&
          other.archived == this.archived &&
          other.tagsJson == this.tagsJson &&
          other.hasFullHistory == this.hasFullHistory &&
          other.syncedAt == this.syncedAt &&
          other.rawJson == this.rawJson);
}

class CachedSessionsCompanion extends UpdateCompanion<CachedSession> {
  final Value<String> serverId;
  final Value<String> sessionId;
  final Value<String> title;
  final Value<String?> workspace;
  final Value<String?> model;
  final Value<String?> projectId;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<bool> pinned;
  final Value<bool> archived;
  final Value<String> tagsJson;
  final Value<bool> hasFullHistory;
  final Value<DateTime?> syncedAt;
  final Value<String> rawJson;
  final Value<int> rowid;
  const CachedSessionsCompanion({
    this.serverId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.title = const Value.absent(),
    this.workspace = const Value.absent(),
    this.model = const Value.absent(),
    this.projectId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pinned = const Value.absent(),
    this.archived = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.hasFullHistory = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSessionsCompanion.insert({
    required String serverId,
    required String sessionId,
    this.title = const Value.absent(),
    this.workspace = const Value.absent(),
    this.model = const Value.absent(),
    this.projectId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.pinned = const Value.absent(),
    this.archived = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.hasFullHistory = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       sessionId = Value(sessionId);
  static Insertable<CachedSession> custom({
    Expression<String>? serverId,
    Expression<String>? sessionId,
    Expression<String>? title,
    Expression<String>? workspace,
    Expression<String>? model,
    Expression<String>? projectId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? pinned,
    Expression<bool>? archived,
    Expression<String>? tagsJson,
    Expression<bool>? hasFullHistory,
    Expression<DateTime>? syncedAt,
    Expression<String>? rawJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (sessionId != null) 'session_id': sessionId,
      if (title != null) 'title': title,
      if (workspace != null) 'workspace': workspace,
      if (model != null) 'model': model,
      if (projectId != null) 'project_id': projectId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (pinned != null) 'pinned': pinned,
      if (archived != null) 'archived': archived,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (hasFullHistory != null) 'has_full_history': hasFullHistory,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rawJson != null) 'raw_json': rawJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSessionsCompanion copyWith({
    Value<String>? serverId,
    Value<String>? sessionId,
    Value<String>? title,
    Value<String?>? workspace,
    Value<String?>? model,
    Value<String?>? projectId,
    Value<DateTime?>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<bool>? pinned,
    Value<bool>? archived,
    Value<String>? tagsJson,
    Value<bool>? hasFullHistory,
    Value<DateTime?>? syncedAt,
    Value<String>? rawJson,
    Value<int>? rowid,
  }) {
    return CachedSessionsCompanion(
      serverId: serverId ?? this.serverId,
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      workspace: workspace ?? this.workspace,
      model: model ?? this.model,
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      tagsJson: tagsJson ?? this.tagsJson,
      hasFullHistory: hasFullHistory ?? this.hasFullHistory,
      syncedAt: syncedAt ?? this.syncedAt,
      rawJson: rawJson ?? this.rawJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (workspace.present) {
      map['workspace'] = Variable<String>(workspace.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (hasFullHistory.present) {
      map['has_full_history'] = Variable<bool>(hasFullHistory.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedSessionsCompanion(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('workspace: $workspace, ')
          ..write('model: $model, ')
          ..write('projectId: $projectId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('pinned: $pinned, ')
          ..write('archived: $archived, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('hasFullHistory: $hasFullHistory, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rawJson: $rawJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMessagesTable extends CachedMessages
    with TableInfo<$CachedMessagesTable, CachedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _reasoningMeta = const VerificationMeta(
    'reasoning',
  );
  @override
  late final GeneratedColumn<String> reasoning = GeneratedColumn<String>(
    'reasoning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _toolCallsJsonMeta = const VerificationMeta(
    'toolCallsJson',
  );
  @override
  late final GeneratedColumn<String> toolCallsJson = GeneratedColumn<String>(
    'tool_calls_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    sessionId,
    ordinal,
    role,
    content,
    reasoning,
    attachmentsJson,
    toolCallsJson,
    createdAt,
    rawJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('reasoning')) {
      context.handle(
        _reasoningMeta,
        reasoning.isAcceptableOrUnknown(data['reasoning']!, _reasoningMeta),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('tool_calls_json')) {
      context.handle(
        _toolCallsJsonMeta,
        toolCallsJson.isAcceptableOrUnknown(
          data['tool_calls_json']!,
          _toolCallsJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId, sessionId, ordinal};
  @override
  CachedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMessage(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      reasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      toolCallsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_calls_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      )!,
    );
  }

  @override
  $CachedMessagesTable createAlias(String alias) {
    return $CachedMessagesTable(attachedDatabase, alias);
  }
}

class CachedMessage extends DataClass implements Insertable<CachedMessage> {
  final String serverId;
  final String sessionId;
  final int ordinal;
  final String role;
  final String content;
  final String? reasoning;
  final String attachmentsJson;
  final String toolCallsJson;
  final DateTime? createdAt;
  final String rawJson;
  const CachedMessage({
    required this.serverId,
    required this.sessionId,
    required this.ordinal,
    required this.role,
    required this.content,
    this.reasoning,
    required this.attachmentsJson,
    required this.toolCallsJson,
    this.createdAt,
    required this.rawJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<String>(serverId);
    map['session_id'] = Variable<String>(sessionId);
    map['ordinal'] = Variable<int>(ordinal);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || reasoning != null) {
      map['reasoning'] = Variable<String>(reasoning);
    }
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['tool_calls_json'] = Variable<String>(toolCallsJson);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    map['raw_json'] = Variable<String>(rawJson);
    return map;
  }

  CachedMessagesCompanion toCompanion(bool nullToAbsent) {
    return CachedMessagesCompanion(
      serverId: Value(serverId),
      sessionId: Value(sessionId),
      ordinal: Value(ordinal),
      role: Value(role),
      content: Value(content),
      reasoning: reasoning == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoning),
      attachmentsJson: Value(attachmentsJson),
      toolCallsJson: Value(toolCallsJson),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      rawJson: Value(rawJson),
    );
  }

  factory CachedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMessage(
      serverId: serializer.fromJson<String>(json['serverId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      reasoning: serializer.fromJson<String?>(json['reasoning']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      toolCallsJson: serializer.fromJson<String>(json['toolCallsJson']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      rawJson: serializer.fromJson<String>(json['rawJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<String>(serverId),
      'sessionId': serializer.toJson<String>(sessionId),
      'ordinal': serializer.toJson<int>(ordinal),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'reasoning': serializer.toJson<String?>(reasoning),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'toolCallsJson': serializer.toJson<String>(toolCallsJson),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'rawJson': serializer.toJson<String>(rawJson),
    };
  }

  CachedMessage copyWith({
    String? serverId,
    String? sessionId,
    int? ordinal,
    String? role,
    String? content,
    Value<String?> reasoning = const Value.absent(),
    String? attachmentsJson,
    String? toolCallsJson,
    Value<DateTime?> createdAt = const Value.absent(),
    String? rawJson,
  }) => CachedMessage(
    serverId: serverId ?? this.serverId,
    sessionId: sessionId ?? this.sessionId,
    ordinal: ordinal ?? this.ordinal,
    role: role ?? this.role,
    content: content ?? this.content,
    reasoning: reasoning.present ? reasoning.value : this.reasoning,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    toolCallsJson: toolCallsJson ?? this.toolCallsJson,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    rawJson: rawJson ?? this.rawJson,
  );
  CachedMessage copyWithCompanion(CachedMessagesCompanion data) {
    return CachedMessage(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      reasoning: data.reasoning.present ? data.reasoning.value : this.reasoning,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      toolCallsJson: data.toolCallsJson.present
          ? data.toolCallsJson.value
          : this.toolCallsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessage(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rawJson: $rawJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    serverId,
    sessionId,
    ordinal,
    role,
    content,
    reasoning,
    attachmentsJson,
    toolCallsJson,
    createdAt,
    rawJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMessage &&
          other.serverId == this.serverId &&
          other.sessionId == this.sessionId &&
          other.ordinal == this.ordinal &&
          other.role == this.role &&
          other.content == this.content &&
          other.reasoning == this.reasoning &&
          other.attachmentsJson == this.attachmentsJson &&
          other.toolCallsJson == this.toolCallsJson &&
          other.createdAt == this.createdAt &&
          other.rawJson == this.rawJson);
}

class CachedMessagesCompanion extends UpdateCompanion<CachedMessage> {
  final Value<String> serverId;
  final Value<String> sessionId;
  final Value<int> ordinal;
  final Value<String> role;
  final Value<String> content;
  final Value<String?> reasoning;
  final Value<String> attachmentsJson;
  final Value<String> toolCallsJson;
  final Value<DateTime?> createdAt;
  final Value<String> rawJson;
  final Value<int> rowid;
  const CachedMessagesCompanion({
    this.serverId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMessagesCompanion.insert({
    required String serverId,
    required String sessionId,
    required int ordinal,
    required String role,
    this.content = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       sessionId = Value(sessionId),
       ordinal = Value(ordinal),
       role = Value(role);
  static Insertable<CachedMessage> custom({
    Expression<String>? serverId,
    Expression<String>? sessionId,
    Expression<int>? ordinal,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? reasoning,
    Expression<String>? attachmentsJson,
    Expression<String>? toolCallsJson,
    Expression<DateTime>? createdAt,
    Expression<String>? rawJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (sessionId != null) 'session_id': sessionId,
      if (ordinal != null) 'ordinal': ordinal,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (reasoning != null) 'reasoning': reasoning,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (toolCallsJson != null) 'tool_calls_json': toolCallsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rawJson != null) 'raw_json': rawJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMessagesCompanion copyWith({
    Value<String>? serverId,
    Value<String>? sessionId,
    Value<int>? ordinal,
    Value<String>? role,
    Value<String>? content,
    Value<String?>? reasoning,
    Value<String>? attachmentsJson,
    Value<String>? toolCallsJson,
    Value<DateTime?>? createdAt,
    Value<String>? rawJson,
    Value<int>? rowid,
  }) {
    return CachedMessagesCompanion(
      serverId: serverId ?? this.serverId,
      sessionId: sessionId ?? this.sessionId,
      ordinal: ordinal ?? this.ordinal,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      createdAt: createdAt ?? this.createdAt,
      rawJson: rawJson ?? this.rawJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (reasoning.present) {
      map['reasoning'] = Variable<String>(reasoning.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (toolCallsJson.present) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessagesCompanion(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('ordinal: $ordinal, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('reasoning: $reasoning, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rawJson: $rawJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<OutboxKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<OutboxKind>($OutboxTable.$converterkind);
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    sessionId,
    kind,
    payloadJson,
    localId,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      kind: $OutboxTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<OutboxKind, String, String> $converterkind =
      const EnumNameConverter<OutboxKind>(OutboxKind.values);
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int id;
  final String serverId;
  final String? sessionId;
  final OutboxKind kind;

  /// The request body, verbatim, ready to POST.
  final String payloadJson;

  /// Correlates with the optimistic row already shown in the transcript, so a
  /// flush updates that message rather than appending a duplicate.
  final String localId;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;

  /// The last failure, kept so the UI can explain why something is stuck
  /// instead of silently retrying forever.
  final String? lastError;
  const OutboxData({
    required this.id,
    required this.serverId,
    this.sessionId,
    required this.kind,
    required this.payloadJson,
    required this.localId,
    required this.createdAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_id'] = Variable<String>(serverId);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    {
      map['kind'] = Variable<String>($OutboxTable.$converterkind.toSql(kind));
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['local_id'] = Variable<String>(localId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      serverId: Value(serverId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      kind: Value(kind),
      payloadJson: Value(payloadJson),
      localId: Value(localId),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<String>(json['serverId']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      kind: $OutboxTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      localId: serializer.fromJson<String>(json['localId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<String>(serverId),
      'sessionId': serializer.toJson<String?>(sessionId),
      'kind': serializer.toJson<String>(
        $OutboxTable.$converterkind.toJson(kind),
      ),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'localId': serializer.toJson<String>(localId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxData copyWith({
    int? id,
    String? serverId,
    Value<String?> sessionId = const Value.absent(),
    OutboxKind? kind,
    String? payloadJson,
    String? localId,
    DateTime? createdAt,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => OutboxData(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    kind: kind ?? this.kind,
    payloadJson: payloadJson ?? this.payloadJson,
    localId: localId ?? this.localId,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      localId: data.localId.present ? data.localId.value : this.localId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('localId: $localId, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    sessionId,
    kind,
    payloadJson,
    localId,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.sessionId == this.sessionId &&
          other.kind == this.kind &&
          other.payloadJson == this.payloadJson &&
          other.localId == this.localId &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> id;
  final Value<String> serverId;
  final Value<String?> sessionId;
  final Value<OutboxKind> kind;
  final Value<String> payloadJson;
  final Value<String> localId;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.localId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String serverId,
    this.sessionId = const Value.absent(),
    required OutboxKind kind,
    required String payloadJson,
    required String localId,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : serverId = Value(serverId),
       kind = Value(kind),
       payloadJson = Value(payloadJson),
       localId = Value(localId),
       createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<int>? id,
    Expression<String>? serverId,
    Expression<String>? sessionId,
    Expression<String>? kind,
    Expression<String>? payloadJson,
    Expression<String>? localId,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (sessionId != null) 'session_id': sessionId,
      if (kind != null) 'kind': kind,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (localId != null) 'local_id': localId,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? serverId,
    Value<String?>? sessionId,
    Value<OutboxKind>? kind,
    Value<String>? payloadJson,
    Value<String>? localId,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
  }) {
    return OutboxCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      sessionId: sessionId ?? this.sessionId,
      kind: kind ?? this.kind,
      payloadJson: payloadJson ?? this.payloadJson,
      localId: localId ?? this.localId,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $OutboxTable.$converterkind.toSql(kind.value),
      );
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('localId: $localId, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $StreamCursorsTable extends StreamCursors
    with TableInfo<$StreamCursorsTable, StreamCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StreamCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastEventIdMeta = const VerificationMeta(
    'lastEventId',
  );
  @override
  late final GeneratedColumn<String> lastEventId = GeneratedColumn<String>(
    'last_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streamIdMeta = const VerificationMeta(
    'streamId',
  );
  @override
  late final GeneratedColumn<String> streamId = GeneratedColumn<String>(
    'stream_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    sessionId,
    lastEventId,
    streamId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stream_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<StreamCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('last_event_id')) {
      context.handle(
        _lastEventIdMeta,
        lastEventId.isAcceptableOrUnknown(
          data['last_event_id']!,
          _lastEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastEventIdMeta);
    }
    if (data.containsKey('stream_id')) {
      context.handle(
        _streamIdMeta,
        streamId.isAcceptableOrUnknown(data['stream_id']!, _streamIdMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId, sessionId};
  @override
  StreamCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StreamCursor(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      lastEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_event_id'],
      )!,
      streamId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stream_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StreamCursorsTable createAlias(String alias) {
    return $StreamCursorsTable(attachedDatabase, alias);
  }
}

class StreamCursor extends DataClass implements Insertable<StreamCursor> {
  final String serverId;
  final String sessionId;

  /// Opaque `Last-Event-ID`. Never parsed.
  final String lastEventId;

  /// The `stream_id` of the run this cursor belongs to, so a cursor from a
  /// previous run is not replayed against a new one.
  final String? streamId;
  final DateTime updatedAt;
  const StreamCursor({
    required this.serverId,
    required this.sessionId,
    required this.lastEventId,
    this.streamId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<String>(serverId);
    map['session_id'] = Variable<String>(sessionId);
    map['last_event_id'] = Variable<String>(lastEventId);
    if (!nullToAbsent || streamId != null) {
      map['stream_id'] = Variable<String>(streamId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StreamCursorsCompanion toCompanion(bool nullToAbsent) {
    return StreamCursorsCompanion(
      serverId: Value(serverId),
      sessionId: Value(sessionId),
      lastEventId: Value(lastEventId),
      streamId: streamId == null && nullToAbsent
          ? const Value.absent()
          : Value(streamId),
      updatedAt: Value(updatedAt),
    );
  }

  factory StreamCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StreamCursor(
      serverId: serializer.fromJson<String>(json['serverId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      lastEventId: serializer.fromJson<String>(json['lastEventId']),
      streamId: serializer.fromJson<String?>(json['streamId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<String>(serverId),
      'sessionId': serializer.toJson<String>(sessionId),
      'lastEventId': serializer.toJson<String>(lastEventId),
      'streamId': serializer.toJson<String?>(streamId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StreamCursor copyWith({
    String? serverId,
    String? sessionId,
    String? lastEventId,
    Value<String?> streamId = const Value.absent(),
    DateTime? updatedAt,
  }) => StreamCursor(
    serverId: serverId ?? this.serverId,
    sessionId: sessionId ?? this.sessionId,
    lastEventId: lastEventId ?? this.lastEventId,
    streamId: streamId.present ? streamId.value : this.streamId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StreamCursor copyWithCompanion(StreamCursorsCompanion data) {
    return StreamCursor(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      lastEventId: data.lastEventId.present
          ? data.lastEventId.value
          : this.lastEventId,
      streamId: data.streamId.present ? data.streamId.value : this.streamId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StreamCursor(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('streamId: $streamId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(serverId, sessionId, lastEventId, streamId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreamCursor &&
          other.serverId == this.serverId &&
          other.sessionId == this.sessionId &&
          other.lastEventId == this.lastEventId &&
          other.streamId == this.streamId &&
          other.updatedAt == this.updatedAt);
}

class StreamCursorsCompanion extends UpdateCompanion<StreamCursor> {
  final Value<String> serverId;
  final Value<String> sessionId;
  final Value<String> lastEventId;
  final Value<String?> streamId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StreamCursorsCompanion({
    this.serverId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.streamId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StreamCursorsCompanion.insert({
    required String serverId,
    required String sessionId,
    required String lastEventId,
    this.streamId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       sessionId = Value(sessionId),
       lastEventId = Value(lastEventId),
       updatedAt = Value(updatedAt);
  static Insertable<StreamCursor> custom({
    Expression<String>? serverId,
    Expression<String>? sessionId,
    Expression<String>? lastEventId,
    Expression<String>? streamId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (sessionId != null) 'session_id': sessionId,
      if (lastEventId != null) 'last_event_id': lastEventId,
      if (streamId != null) 'stream_id': streamId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StreamCursorsCompanion copyWith({
    Value<String>? serverId,
    Value<String>? sessionId,
    Value<String>? lastEventId,
    Value<String?>? streamId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StreamCursorsCompanion(
      serverId: serverId ?? this.serverId,
      sessionId: sessionId ?? this.sessionId,
      lastEventId: lastEventId ?? this.lastEventId,
      streamId: streamId ?? this.streamId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (lastEventId.present) {
      map['last_event_id'] = Variable<String>(lastEventId.value);
    }
    if (streamId.present) {
      map['stream_id'] = Variable<String>(streamId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StreamCursorsCompanion(')
          ..write('serverId: $serverId, ')
          ..write('sessionId: $sessionId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('streamId: $streamId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDocumentsTable extends CachedDocuments
    with TableInfo<$CachedDocumentsTable, CachedDocument> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [serverId, key, bodyJson, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDocument> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId, key};
  @override
  CachedDocument map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDocument(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CachedDocumentsTable createAlias(String alias) {
    return $CachedDocumentsTable(attachedDatabase, alias);
  }
}

class CachedDocument extends DataClass implements Insertable<CachedDocument> {
  final String serverId;

  /// The API path this came from, which is a natural unique key.
  final String key;
  final String bodyJson;
  final DateTime fetchedAt;
  const CachedDocument({
    required this.serverId,
    required this.key,
    required this.bodyJson,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<String>(serverId);
    map['key'] = Variable<String>(key);
    map['body_json'] = Variable<String>(bodyJson);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CachedDocumentsCompanion toCompanion(bool nullToAbsent) {
    return CachedDocumentsCompanion(
      serverId: Value(serverId),
      key: Value(key),
      bodyJson: Value(bodyJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedDocument.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDocument(
      serverId: serializer.fromJson<String>(json['serverId']),
      key: serializer.fromJson<String>(json['key']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<String>(serverId),
      'key': serializer.toJson<String>(key),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CachedDocument copyWith({
    String? serverId,
    String? key,
    String? bodyJson,
    DateTime? fetchedAt,
  }) => CachedDocument(
    serverId: serverId ?? this.serverId,
    key: key ?? this.key,
    bodyJson: bodyJson ?? this.bodyJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CachedDocument copyWithCompanion(CachedDocumentsCompanion data) {
    return CachedDocument(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      key: data.key.present ? data.key.value : this.key,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocument(')
          ..write('serverId: $serverId, ')
          ..write('key: $key, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(serverId, key, bodyJson, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDocument &&
          other.serverId == this.serverId &&
          other.key == this.key &&
          other.bodyJson == this.bodyJson &&
          other.fetchedAt == this.fetchedAt);
}

class CachedDocumentsCompanion extends UpdateCompanion<CachedDocument> {
  final Value<String> serverId;
  final Value<String> key;
  final Value<String> bodyJson;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CachedDocumentsCompanion({
    this.serverId = const Value.absent(),
    this.key = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDocumentsCompanion.insert({
    required String serverId,
    required String key,
    required String bodyJson,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : serverId = Value(serverId),
       key = Value(key),
       bodyJson = Value(bodyJson),
       fetchedAt = Value(fetchedAt);
  static Insertable<CachedDocument> custom({
    Expression<String>? serverId,
    Expression<String>? key,
    Expression<String>? bodyJson,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (key != null) 'key': key,
      if (bodyJson != null) 'body_json': bodyJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDocumentsCompanion copyWith({
    Value<String>? serverId,
    Value<String>? key,
    Value<String>? bodyJson,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CachedDocumentsCompanion(
      serverId: serverId ?? this.serverId,
      key: key ?? this.key,
      bodyJson: bodyJson ?? this.bodyJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocumentsCompanion(')
          ..write('serverId: $serverId, ')
          ..write('key: $key, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$IrisDatabase extends GeneratedDatabase {
  _$IrisDatabase(QueryExecutor e) : super(e);
  $IrisDatabaseManager get managers => $IrisDatabaseManager(this);
  late final $ServersTable servers = $ServersTable(this);
  late final $CachedSessionsTable cachedSessions = $CachedSessionsTable(this);
  late final $CachedMessagesTable cachedMessages = $CachedMessagesTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $StreamCursorsTable streamCursors = $StreamCursorsTable(this);
  late final $CachedDocumentsTable cachedDocuments = $CachedDocumentsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    servers,
    cachedSessions,
    cachedMessages,
    outbox,
    streamCursors,
    cachedDocuments,
  ];
}

typedef $$ServersTableCreateCompanionBuilder =
    ServersCompanion Function({
      required String id,
      required String baseUrl,
      required String label,
      Value<bool> requiresPassword,
      Value<bool> allowSelfSigned,
      Value<bool> usesAccessToken,
      Value<String?> serverVersion,
      Value<String> capabilitiesJson,
      Value<DateTime?> probedAt,
      Value<DateTime?> lastConnectedAt,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$ServersTableUpdateCompanionBuilder =
    ServersCompanion Function({
      Value<String> id,
      Value<String> baseUrl,
      Value<String> label,
      Value<bool> requiresPassword,
      Value<bool> allowSelfSigned,
      Value<bool> usesAccessToken,
      Value<String?> serverVersion,
      Value<String> capabilitiesJson,
      Value<DateTime?> probedAt,
      Value<DateTime?> lastConnectedAt,
      Value<int> position,
      Value<int> rowid,
    });

final class $$ServersTableReferences
    extends BaseReferences<_$IrisDatabase, $ServersTable, Server> {
  $$ServersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CachedSessionsTable, List<CachedSession>>
  _cachedSessionsRefsTable(_$IrisDatabase db) => MultiTypedResultKey.fromTable(
    db.cachedSessions,
    aliasName: 'servers__id__cached_sessions__server_id',
  );

  $$CachedSessionsTableProcessedTableManager get cachedSessionsRefs {
    final manager = $$CachedSessionsTableTableManager(
      $_db,
      $_db.cachedSessions,
    ).filter((f) => f.serverId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cachedSessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ServersTableFilterComposer
    extends Composer<_$IrisDatabase, $ServersTable> {
  $$ServersTableFilterComposer({
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

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresPassword => $composableBuilder(
    column: $table.requiresPassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowSelfSigned => $composableBuilder(
    column: $table.allowSelfSigned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usesAccessToken => $composableBuilder(
    column: $table.usesAccessToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get probedAt => $composableBuilder(
    column: $table.probedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> cachedSessionsRefs(
    Expression<bool> Function($$CachedSessionsTableFilterComposer f) f,
  ) {
    final $$CachedSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cachedSessions,
      getReferencedColumn: (t) => t.serverId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CachedSessionsTableFilterComposer(
            $db: $db,
            $table: $db.cachedSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServersTableOrderingComposer
    extends Composer<_$IrisDatabase, $ServersTable> {
  $$ServersTableOrderingComposer({
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

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresPassword => $composableBuilder(
    column: $table.requiresPassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowSelfSigned => $composableBuilder(
    column: $table.allowSelfSigned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usesAccessToken => $composableBuilder(
    column: $table.usesAccessToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get probedAt => $composableBuilder(
    column: $table.probedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServersTableAnnotationComposer
    extends Composer<_$IrisDatabase, $ServersTable> {
  $$ServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<bool> get requiresPassword => $composableBuilder(
    column: $table.requiresPassword,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowSelfSigned => $composableBuilder(
    column: $table.allowSelfSigned,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get usesAccessToken => $composableBuilder(
    column: $table.usesAccessToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverVersion => $composableBuilder(
    column: $table.serverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get capabilitiesJson => $composableBuilder(
    column: $table.capabilitiesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get probedAt =>
      $composableBuilder(column: $table.probedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  Expression<T> cachedSessionsRefs<T extends Object>(
    Expression<T> Function($$CachedSessionsTableAnnotationComposer a) f,
  ) {
    final $$CachedSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cachedSessions,
      getReferencedColumn: (t) => t.serverId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CachedSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.cachedSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ServersTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $ServersTable,
          Server,
          $$ServersTableFilterComposer,
          $$ServersTableOrderingComposer,
          $$ServersTableAnnotationComposer,
          $$ServersTableCreateCompanionBuilder,
          $$ServersTableUpdateCompanionBuilder,
          (Server, $$ServersTableReferences),
          Server,
          PrefetchHooks Function({bool cachedSessionsRefs})
        > {
  $$ServersTableTableManager(_$IrisDatabase db, $ServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<bool> requiresPassword = const Value.absent(),
                Value<bool> allowSelfSigned = const Value.absent(),
                Value<bool> usesAccessToken = const Value.absent(),
                Value<String?> serverVersion = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<DateTime?> probedAt = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServersCompanion(
                id: id,
                baseUrl: baseUrl,
                label: label,
                requiresPassword: requiresPassword,
                allowSelfSigned: allowSelfSigned,
                usesAccessToken: usesAccessToken,
                serverVersion: serverVersion,
                capabilitiesJson: capabilitiesJson,
                probedAt: probedAt,
                lastConnectedAt: lastConnectedAt,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String baseUrl,
                required String label,
                Value<bool> requiresPassword = const Value.absent(),
                Value<bool> allowSelfSigned = const Value.absent(),
                Value<bool> usesAccessToken = const Value.absent(),
                Value<String?> serverVersion = const Value.absent(),
                Value<String> capabilitiesJson = const Value.absent(),
                Value<DateTime?> probedAt = const Value.absent(),
                Value<DateTime?> lastConnectedAt = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServersCompanion.insert(
                id: id,
                baseUrl: baseUrl,
                label: label,
                requiresPassword: requiresPassword,
                allowSelfSigned: allowSelfSigned,
                usesAccessToken: usesAccessToken,
                serverVersion: serverVersion,
                capabilitiesJson: capabilitiesJson,
                probedAt: probedAt,
                lastConnectedAt: lastConnectedAt,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ServersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cachedSessionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (cachedSessionsRefs) db.cachedSessions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cachedSessionsRefs)
                    await $_getPrefetchedData<
                      Server,
                      $ServersTable,
                      CachedSession
                    >(
                      currentTable: table,
                      referencedTable: $$ServersTableReferences
                          ._cachedSessionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ServersTableReferences(
                        db,
                        table,
                        p0,
                      ).cachedSessionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.serverId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ServersTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $ServersTable,
      Server,
      $$ServersTableFilterComposer,
      $$ServersTableOrderingComposer,
      $$ServersTableAnnotationComposer,
      $$ServersTableCreateCompanionBuilder,
      $$ServersTableUpdateCompanionBuilder,
      (Server, $$ServersTableReferences),
      Server,
      PrefetchHooks Function({bool cachedSessionsRefs})
    >;
typedef $$CachedSessionsTableCreateCompanionBuilder =
    CachedSessionsCompanion Function({
      required String serverId,
      required String sessionId,
      Value<String> title,
      Value<String?> workspace,
      Value<String?> model,
      Value<String?> projectId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<bool> pinned,
      Value<bool> archived,
      Value<String> tagsJson,
      Value<bool> hasFullHistory,
      Value<DateTime?> syncedAt,
      Value<String> rawJson,
      Value<int> rowid,
    });
typedef $$CachedSessionsTableUpdateCompanionBuilder =
    CachedSessionsCompanion Function({
      Value<String> serverId,
      Value<String> sessionId,
      Value<String> title,
      Value<String?> workspace,
      Value<String?> model,
      Value<String?> projectId,
      Value<DateTime?> createdAt,
      Value<DateTime?> updatedAt,
      Value<bool> pinned,
      Value<bool> archived,
      Value<String> tagsJson,
      Value<bool> hasFullHistory,
      Value<DateTime?> syncedAt,
      Value<String> rawJson,
      Value<int> rowid,
    });

final class $$CachedSessionsTableReferences
    extends
        BaseReferences<_$IrisDatabase, $CachedSessionsTable, CachedSession> {
  $$CachedSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ServersTable _serverIdTable(_$IrisDatabase db) =>
      db.servers.createAlias('cached_sessions__server_id__servers__id');

  $$ServersTableProcessedTableManager get serverId {
    final $_column = $_itemColumn<String>('server_id')!;

    final manager = $$ServersTableTableManager(
      $_db,
      $_db.servers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_serverIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CachedSessionsTableFilterComposer
    extends Composer<_$IrisDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspace => $composableBuilder(
    column: $table.workspace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasFullHistory => $composableBuilder(
    column: $table.hasFullHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  $$ServersTableFilterComposer get serverId {
    final $$ServersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverId,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableFilterComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CachedSessionsTableOrderingComposer
    extends Composer<_$IrisDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspace => $composableBuilder(
    column: $table.workspace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasFullHistory => $composableBuilder(
    column: $table.hasFullHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$ServersTableOrderingComposer get serverId {
    final $$ServersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverId,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableOrderingComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CachedSessionsTableAnnotationComposer
    extends Composer<_$IrisDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get workspace =>
      $composableBuilder(column: $table.workspace, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<bool> get hasFullHistory => $composableBuilder(
    column: $table.hasFullHistory,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  $$ServersTableAnnotationComposer get serverId {
    final $$ServersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.serverId,
      referencedTable: $db.servers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ServersTableAnnotationComposer(
            $db: $db,
            $table: $db.servers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CachedSessionsTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $CachedSessionsTable,
          CachedSession,
          $$CachedSessionsTableFilterComposer,
          $$CachedSessionsTableOrderingComposer,
          $$CachedSessionsTableAnnotationComposer,
          $$CachedSessionsTableCreateCompanionBuilder,
          $$CachedSessionsTableUpdateCompanionBuilder,
          (CachedSession, $$CachedSessionsTableReferences),
          CachedSession,
          PrefetchHooks Function({bool serverId})
        > {
  $$CachedSessionsTableTableManager(
    _$IrisDatabase db,
    $CachedSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> serverId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> workspace = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<bool> hasFullHistory = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion(
                serverId: serverId,
                sessionId: sessionId,
                title: title,
                workspace: workspace,
                model: model,
                projectId: projectId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pinned: pinned,
                archived: archived,
                tagsJson: tagsJson,
                hasFullHistory: hasFullHistory,
                syncedAt: syncedAt,
                rawJson: rawJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverId,
                required String sessionId,
                Value<String> title = const Value.absent(),
                Value<String?> workspace = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<bool> hasFullHistory = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion.insert(
                serverId: serverId,
                sessionId: sessionId,
                title: title,
                workspace: workspace,
                model: model,
                projectId: projectId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pinned: pinned,
                archived: archived,
                tagsJson: tagsJson,
                hasFullHistory: hasFullHistory,
                syncedAt: syncedAt,
                rawJson: rawJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CachedSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({serverId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (serverId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.serverId,
                                referencedTable: $$CachedSessionsTableReferences
                                    ._serverIdTable(db),
                                referencedColumn:
                                    $$CachedSessionsTableReferences
                                        ._serverIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CachedSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $CachedSessionsTable,
      CachedSession,
      $$CachedSessionsTableFilterComposer,
      $$CachedSessionsTableOrderingComposer,
      $$CachedSessionsTableAnnotationComposer,
      $$CachedSessionsTableCreateCompanionBuilder,
      $$CachedSessionsTableUpdateCompanionBuilder,
      (CachedSession, $$CachedSessionsTableReferences),
      CachedSession,
      PrefetchHooks Function({bool serverId})
    >;
typedef $$CachedMessagesTableCreateCompanionBuilder =
    CachedMessagesCompanion Function({
      required String serverId,
      required String sessionId,
      required int ordinal,
      required String role,
      Value<String> content,
      Value<String?> reasoning,
      Value<String> attachmentsJson,
      Value<String> toolCallsJson,
      Value<DateTime?> createdAt,
      Value<String> rawJson,
      Value<int> rowid,
    });
typedef $$CachedMessagesTableUpdateCompanionBuilder =
    CachedMessagesCompanion Function({
      Value<String> serverId,
      Value<String> sessionId,
      Value<int> ordinal,
      Value<String> role,
      Value<String> content,
      Value<String?> reasoning,
      Value<String> attachmentsJson,
      Value<String> toolCallsJson,
      Value<DateTime?> createdAt,
      Value<String> rawJson,
      Value<int> rowid,
    });

class $$CachedMessagesTableFilterComposer
    extends Composer<_$IrisDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMessagesTableOrderingComposer
    extends Composer<_$IrisDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMessagesTableAnnotationComposer
    extends Composer<_$IrisDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get reasoning =>
      $composableBuilder(column: $table.reasoning, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);
}

class $$CachedMessagesTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $CachedMessagesTable,
          CachedMessage,
          $$CachedMessagesTableFilterComposer,
          $$CachedMessagesTableOrderingComposer,
          $$CachedMessagesTableAnnotationComposer,
          $$CachedMessagesTableCreateCompanionBuilder,
          $$CachedMessagesTableUpdateCompanionBuilder,
          (
            CachedMessage,
            BaseReferences<_$IrisDatabase, $CachedMessagesTable, CachedMessage>,
          ),
          CachedMessage,
          PrefetchHooks Function()
        > {
  $$CachedMessagesTableTableManager(
    _$IrisDatabase db,
    $CachedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> serverId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> toolCallsJson = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion(
                serverId: serverId,
                sessionId: sessionId,
                ordinal: ordinal,
                role: role,
                content: content,
                reasoning: reasoning,
                attachmentsJson: attachmentsJson,
                toolCallsJson: toolCallsJson,
                createdAt: createdAt,
                rawJson: rawJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverId,
                required String sessionId,
                required int ordinal,
                required String role,
                Value<String> content = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<String> toolCallsJson = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<String> rawJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion.insert(
                serverId: serverId,
                sessionId: sessionId,
                ordinal: ordinal,
                role: role,
                content: content,
                reasoning: reasoning,
                attachmentsJson: attachmentsJson,
                toolCallsJson: toolCallsJson,
                createdAt: createdAt,
                rawJson: rawJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $CachedMessagesTable,
      CachedMessage,
      $$CachedMessagesTableFilterComposer,
      $$CachedMessagesTableOrderingComposer,
      $$CachedMessagesTableAnnotationComposer,
      $$CachedMessagesTableCreateCompanionBuilder,
      $$CachedMessagesTableUpdateCompanionBuilder,
      (
        CachedMessage,
        BaseReferences<_$IrisDatabase, $CachedMessagesTable, CachedMessage>,
      ),
      CachedMessage,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      required String serverId,
      Value<String?> sessionId,
      required OutboxKind kind,
      required String payloadJson,
      required String localId,
      required DateTime createdAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
    });
typedef $$OutboxTableUpdateCompanionBuilder =
    OutboxCompanion Function({
      Value<int> id,
      Value<String> serverId,
      Value<String?> sessionId,
      Value<OutboxKind> kind,
      Value<String> payloadJson,
      Value<String> localId,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
    });

class $$OutboxTableFilterComposer
    extends Composer<_$IrisDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<OutboxKind, OutboxKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$IrisDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$IrisDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<OutboxKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (
            OutboxData,
            BaseReferences<_$IrisDatabase, $OutboxTable, OutboxData>,
          ),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$IrisDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<OutboxKind> kind = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> localId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion(
                id: id,
                serverId: serverId,
                sessionId: sessionId,
                kind: kind,
                payloadJson: payloadJson,
                localId: localId,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String serverId,
                Value<String?> sessionId = const Value.absent(),
                required OutboxKind kind,
                required String payloadJson,
                required String localId,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxCompanion.insert(
                id: id,
                serverId: serverId,
                sessionId: sessionId,
                kind: kind,
                payloadJson: payloadJson,
                localId: localId,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$IrisDatabase, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;
typedef $$StreamCursorsTableCreateCompanionBuilder =
    StreamCursorsCompanion Function({
      required String serverId,
      required String sessionId,
      required String lastEventId,
      Value<String?> streamId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$StreamCursorsTableUpdateCompanionBuilder =
    StreamCursorsCompanion Function({
      Value<String> serverId,
      Value<String> sessionId,
      Value<String> lastEventId,
      Value<String?> streamId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$StreamCursorsTableFilterComposer
    extends Composer<_$IrisDatabase, $StreamCursorsTable> {
  $$StreamCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StreamCursorsTableOrderingComposer
    extends Composer<_$IrisDatabase, $StreamCursorsTable> {
  $$StreamCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streamId => $composableBuilder(
    column: $table.streamId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StreamCursorsTableAnnotationComposer
    extends Composer<_$IrisDatabase, $StreamCursorsTable> {
  $$StreamCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get streamId =>
      $composableBuilder(column: $table.streamId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StreamCursorsTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $StreamCursorsTable,
          StreamCursor,
          $$StreamCursorsTableFilterComposer,
          $$StreamCursorsTableOrderingComposer,
          $$StreamCursorsTableAnnotationComposer,
          $$StreamCursorsTableCreateCompanionBuilder,
          $$StreamCursorsTableUpdateCompanionBuilder,
          (
            StreamCursor,
            BaseReferences<_$IrisDatabase, $StreamCursorsTable, StreamCursor>,
          ),
          StreamCursor,
          PrefetchHooks Function()
        > {
  $$StreamCursorsTableTableManager(_$IrisDatabase db, $StreamCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StreamCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StreamCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StreamCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> serverId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> lastEventId = const Value.absent(),
                Value<String?> streamId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreamCursorsCompanion(
                serverId: serverId,
                sessionId: sessionId,
                lastEventId: lastEventId,
                streamId: streamId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverId,
                required String sessionId,
                required String lastEventId,
                Value<String?> streamId = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StreamCursorsCompanion.insert(
                serverId: serverId,
                sessionId: sessionId,
                lastEventId: lastEventId,
                streamId: streamId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StreamCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $StreamCursorsTable,
      StreamCursor,
      $$StreamCursorsTableFilterComposer,
      $$StreamCursorsTableOrderingComposer,
      $$StreamCursorsTableAnnotationComposer,
      $$StreamCursorsTableCreateCompanionBuilder,
      $$StreamCursorsTableUpdateCompanionBuilder,
      (
        StreamCursor,
        BaseReferences<_$IrisDatabase, $StreamCursorsTable, StreamCursor>,
      ),
      StreamCursor,
      PrefetchHooks Function()
    >;
typedef $$CachedDocumentsTableCreateCompanionBuilder =
    CachedDocumentsCompanion Function({
      required String serverId,
      required String key,
      required String bodyJson,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CachedDocumentsTableUpdateCompanionBuilder =
    CachedDocumentsCompanion Function({
      Value<String> serverId,
      Value<String> key,
      Value<String> bodyJson,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CachedDocumentsTableFilterComposer
    extends Composer<_$IrisDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDocumentsTableOrderingComposer
    extends Composer<_$IrisDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDocumentsTableAnnotationComposer
    extends Composer<_$IrisDatabase, $CachedDocumentsTable> {
  $$CachedDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CachedDocumentsTableTableManager
    extends
        RootTableManager<
          _$IrisDatabase,
          $CachedDocumentsTable,
          CachedDocument,
          $$CachedDocumentsTableFilterComposer,
          $$CachedDocumentsTableOrderingComposer,
          $$CachedDocumentsTableAnnotationComposer,
          $$CachedDocumentsTableCreateCompanionBuilder,
          $$CachedDocumentsTableUpdateCompanionBuilder,
          (
            CachedDocument,
            BaseReferences<
              _$IrisDatabase,
              $CachedDocumentsTable,
              CachedDocument
            >,
          ),
          CachedDocument,
          PrefetchHooks Function()
        > {
  $$CachedDocumentsTableTableManager(
    _$IrisDatabase db,
    $CachedDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> serverId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDocumentsCompanion(
                serverId: serverId,
                key: key,
                bodyJson: bodyJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String serverId,
                required String key,
                required String bodyJson,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedDocumentsCompanion.insert(
                serverId: serverId,
                key: key,
                bodyJson: bodyJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$IrisDatabase,
      $CachedDocumentsTable,
      CachedDocument,
      $$CachedDocumentsTableFilterComposer,
      $$CachedDocumentsTableOrderingComposer,
      $$CachedDocumentsTableAnnotationComposer,
      $$CachedDocumentsTableCreateCompanionBuilder,
      $$CachedDocumentsTableUpdateCompanionBuilder,
      (
        CachedDocument,
        BaseReferences<_$IrisDatabase, $CachedDocumentsTable, CachedDocument>,
      ),
      CachedDocument,
      PrefetchHooks Function()
    >;

class $IrisDatabaseManager {
  final _$IrisDatabase _db;
  $IrisDatabaseManager(this._db);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db, _db.servers);
  $$CachedSessionsTableTableManager get cachedSessions =>
      $$CachedSessionsTableTableManager(_db, _db.cachedSessions);
  $$CachedMessagesTableTableManager get cachedMessages =>
      $$CachedMessagesTableTableManager(_db, _db.cachedMessages);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$StreamCursorsTableTableManager get streamCursors =>
      $$StreamCursorsTableTableManager(_db, _db.streamCursors);
  $$CachedDocumentsTableTableManager get cachedDocuments =>
      $$CachedDocumentsTableTableManager(_db, _db.cachedDocuments);
}
