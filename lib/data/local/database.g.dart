// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, FolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, createdAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      color:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}color'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRow extends DataClass implements Insertable<FolderRow> {
  final int id;
  final String name;
  final String color;
  final DateTime createdAt;
  final DateTime? deletedAt;
  const FolderRow({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<String>(color);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      createdAt: Value(createdAt),
      deletedAt:
          deletedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(deletedAt),
    );
  }

  factory FolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String>(json['color']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String>(color),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  FolderRow copyWith({
    int? id,
    String? name,
    String? color,
    DateTime? createdAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => FolderRow(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  FolderRow copyWithCompanion(FoldersCompanion data) {
    return FolderRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, createdAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> color;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deletedAt;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String color,
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : name = Value(name),
       color = Value(color);
  static Insertable<FolderRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? color,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deletedAt,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trashedAtMeta = const VerificationMeta(
    'trashedAt',
  );
  @override
  late final GeneratedColumn<DateTime> trashedAt = GeneratedColumn<DateTime>(
    'trashed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    content,
    status,
    folderId,
    createdAt,
    expiresAt,
    trashedAt,
    dueDate,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('trashed_at')) {
      context.handle(
        _trashedAtMeta,
        trashedAt.isAcceptableOrUnknown(data['trashed_at']!, _trashedAtMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      content:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}content'],
          )!,
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}status'],
          )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      expiresAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}expires_at'],
          )!,
      trashedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trashed_at'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final int id;
  final String content;
  final String status;
  final int? folderId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? trashedAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  const TaskRow({
    required this.id,
    required this.content,
    required this.status,
    this.folderId,
    required this.createdAt,
    required this.expiresAt,
    this.trashedAt,
    this.dueDate,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['content'] = Variable<String>(content);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    if (!nullToAbsent || trashedAt != null) {
      map['trashed_at'] = Variable<DateTime>(trashedAt);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      content: Value(content),
      status: Value(status),
      folderId:
          folderId == null && nullToAbsent
              ? const Value.absent()
              : Value(folderId),
      createdAt: Value(createdAt),
      expiresAt: Value(expiresAt),
      trashedAt:
          trashedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(trashedAt),
      dueDate:
          dueDate == null && nullToAbsent
              ? const Value.absent()
              : Value(dueDate),
      completedAt:
          completedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(completedAt),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<int>(json['id']),
      content: serializer.fromJson<String>(json['content']),
      status: serializer.fromJson<String>(json['status']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      trashedAt: serializer.fromJson<DateTime?>(json['trashedAt']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'content': serializer.toJson<String>(content),
      'status': serializer.toJson<String>(status),
      'folderId': serializer.toJson<int?>(folderId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'trashedAt': serializer.toJson<DateTime?>(trashedAt),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  TaskRow copyWith({
    int? id,
    String? content,
    String? status,
    Value<int?> folderId = const Value.absent(),
    DateTime? createdAt,
    DateTime? expiresAt,
    Value<DateTime?> trashedAt = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
  }) => TaskRow(
    id: id ?? this.id,
    content: content ?? this.content,
    status: status ?? this.status,
    folderId: folderId.present ? folderId.value : this.folderId,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    trashedAt: trashedAt.present ? trashedAt.value : this.trashedAt,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      content: data.content.present ? data.content.value : this.content,
      status: data.status.present ? data.status.value : this.status,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      trashedAt: data.trashedAt.present ? data.trashedAt.value : this.trashedAt,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('folderId: $folderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    status,
    folderId,
    createdAt,
    expiresAt,
    trashedAt,
    dueDate,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.content == this.content &&
          other.status == this.status &&
          other.folderId == this.folderId &&
          other.createdAt == this.createdAt &&
          other.expiresAt == this.expiresAt &&
          other.trashedAt == this.trashedAt &&
          other.dueDate == this.dueDate &&
          other.completedAt == this.completedAt);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<int> id;
  final Value<String> content;
  final Value<String> status;
  final Value<int?> folderId;
  final Value<DateTime> createdAt;
  final Value<DateTime> expiresAt;
  final Value<DateTime?> trashedAt;
  final Value<DateTime?> dueDate;
  final Value<DateTime?> completedAt;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.folderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.completedAt = const Value.absent(),
  });
  TasksCompanion.insert({
    this.id = const Value.absent(),
    required String content,
    required String status,
    this.folderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    required DateTime expiresAt,
    this.trashedAt = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.completedAt = const Value.absent(),
  }) : content = Value(content),
       status = Value(status),
       expiresAt = Value(expiresAt);
  static Insertable<TaskRow> custom({
    Expression<int>? id,
    Expression<String>? content,
    Expression<String>? status,
    Expression<int>? folderId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? trashedAt,
    Expression<DateTime>? dueDate,
    Expression<DateTime>? completedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
      if (folderId != null) 'folder_id': folderId,
      if (createdAt != null) 'created_at': createdAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (trashedAt != null) 'trashed_at': trashedAt,
      if (dueDate != null) 'due_date': dueDate,
      if (completedAt != null) 'completed_at': completedAt,
    });
  }

  TasksCompanion copyWith({
    Value<int>? id,
    Value<String>? content,
    Value<String>? status,
    Value<int?>? folderId,
    Value<DateTime>? createdAt,
    Value<DateTime>? expiresAt,
    Value<DateTime?>? trashedAt,
    Value<DateTime?>? dueDate,
    Value<DateTime?>? completedAt,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      content: content ?? this.content,
      status: status ?? this.status,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      trashedAt: trashedAt ?? this.trashedAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (trashedAt.present) {
      map['trashed_at'] = Variable<DateTime>(trashedAt.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('folderId: $folderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawMarkdownMeta = const VerificationMeta(
    'rawMarkdown',
  );
  @override
  late final GeneratedColumn<String> rawMarkdown = GeneratedColumn<String>(
    'raw_markdown',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('block'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    folderId,
    title,
    rawMarkdown,
    sizeBytes,
    createdAt,
    updatedAt,
    deletedAt,
    color,
    kind,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('raw_markdown')) {
      context.handle(
        _rawMarkdownMeta,
        rawMarkdown.isAcceptableOrUnknown(
          data['raw_markdown']!,
          _rawMarkdownMeta,
        ),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
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
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      folderId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}folder_id'],
          )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      rawMarkdown:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}raw_markdown'],
          )!,
      sizeBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}size_bytes'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      kind:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final int id;
  final int folderId;
  final String? title;
  final String rawMarkdown;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? color;

  /// Note variant. 'block' = block-based editor (default). 'whiteboard' =
  /// infinite canvas, drawing-only.
  final String kind;
  const NoteRow({
    required this.id,
    required this.folderId,
    this.title,
    required this.rawMarkdown,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.color,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['folder_id'] = Variable<int>(folderId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['raw_markdown'] = Variable<String>(rawMarkdown);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['kind'] = Variable<String>(kind);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      folderId: Value(folderId),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      rawMarkdown: Value(rawMarkdown),
      sizeBytes: Value(sizeBytes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt:
          deletedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(deletedAt),
      color:
          color == null && nullToAbsent ? const Value.absent() : Value(color),
      kind: Value(kind),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<int>(json['id']),
      folderId: serializer.fromJson<int>(json['folderId']),
      title: serializer.fromJson<String?>(json['title']),
      rawMarkdown: serializer.fromJson<String>(json['rawMarkdown']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      color: serializer.fromJson<String?>(json['color']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'folderId': serializer.toJson<int>(folderId),
      'title': serializer.toJson<String?>(title),
      'rawMarkdown': serializer.toJson<String>(rawMarkdown),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'color': serializer.toJson<String?>(color),
      'kind': serializer.toJson<String>(kind),
    };
  }

  NoteRow copyWith({
    int? id,
    int? folderId,
    Value<String?> title = const Value.absent(),
    String? rawMarkdown,
    int? sizeBytes,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> color = const Value.absent(),
    String? kind,
  }) => NoteRow(
    id: id ?? this.id,
    folderId: folderId ?? this.folderId,
    title: title.present ? title.value : this.title,
    rawMarkdown: rawMarkdown ?? this.rawMarkdown,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    color: color.present ? color.value : this.color,
    kind: kind ?? this.kind,
  );
  NoteRow copyWithCompanion(NotesCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      title: data.title.present ? data.title.value : this.title,
      rawMarkdown:
          data.rawMarkdown.present ? data.rawMarkdown.value : this.rawMarkdown,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      color: data.color.present ? data.color.value : this.color,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('color: $color, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    title,
    rawMarkdown,
    sizeBytes,
    createdAt,
    updatedAt,
    deletedAt,
    color,
    kind,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.folderId == this.folderId &&
          other.title == this.title &&
          other.rawMarkdown == this.rawMarkdown &&
          other.sizeBytes == this.sizeBytes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.color == this.color &&
          other.kind == this.kind);
}

class NotesCompanion extends UpdateCompanion<NoteRow> {
  final Value<int> id;
  final Value<int> folderId;
  final Value<String?> title;
  final Value<String> rawMarkdown;
  final Value<int> sizeBytes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String?> color;
  final Value<String> kind;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    this.title = const Value.absent(),
    this.rawMarkdown = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.color = const Value.absent(),
    this.kind = const Value.absent(),
  });
  NotesCompanion.insert({
    this.id = const Value.absent(),
    required int folderId,
    this.title = const Value.absent(),
    this.rawMarkdown = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.color = const Value.absent(),
    this.kind = const Value.absent(),
  }) : folderId = Value(folderId);
  static Insertable<NoteRow> custom({
    Expression<int>? id,
    Expression<int>? folderId,
    Expression<String>? title,
    Expression<String>? rawMarkdown,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? color,
    Expression<String>? kind,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderId != null) 'folder_id': folderId,
      if (title != null) 'title': title,
      if (rawMarkdown != null) 'raw_markdown': rawMarkdown,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (color != null) 'color': color,
      if (kind != null) 'kind': kind,
    });
  }

  NotesCompanion copyWith({
    Value<int>? id,
    Value<int>? folderId,
    Value<String?>? title,
    Value<String>? rawMarkdown,
    Value<int>? sizeBytes,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String?>? color,
    Value<String>? kind,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      color: color ?? this.color,
      kind: kind ?? this.kind,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rawMarkdown.present) {
      map['raw_markdown'] = Variable<String>(rawMarkdown.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('color: $color, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }
}

class $NoteImagesTable extends NoteImages
    with TableInfo<$NoteImagesTable, NoteImageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteImagesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _filenameMeta = const VerificationMeta(
    'filename',
  );
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
    'filename',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    filename,
    filePath,
    sizeBytes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteImageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(
        _filenameMeta,
        filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta),
      );
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteImageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteImageRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      noteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}note_id'],
          )!,
      filename:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}filename'],
          )!,
      filePath:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}file_path'],
          )!,
      sizeBytes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}size_bytes'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $NoteImagesTable createAlias(String alias) {
    return $NoteImagesTable(attachedDatabase, alias);
  }
}

class NoteImageRow extends DataClass implements Insertable<NoteImageRow> {
  final int id;
  final int noteId;
  final String filename;
  final String filePath;
  final int sizeBytes;
  final DateTime createdAt;
  const NoteImageRow({
    required this.id,
    required this.noteId,
    required this.filename,
    required this.filePath,
    required this.sizeBytes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['note_id'] = Variable<int>(noteId);
    map['filename'] = Variable<String>(filename);
    map['file_path'] = Variable<String>(filePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NoteImagesCompanion toCompanion(bool nullToAbsent) {
    return NoteImagesCompanion(
      id: Value(id),
      noteId: Value(noteId),
      filename: Value(filename),
      filePath: Value(filePath),
      sizeBytes: Value(sizeBytes),
      createdAt: Value(createdAt),
    );
  }

  factory NoteImageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteImageRow(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<int>(json['noteId']),
      filename: serializer.fromJson<String>(json['filename']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<int>(noteId),
      'filename': serializer.toJson<String>(filename),
      'filePath': serializer.toJson<String>(filePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NoteImageRow copyWith({
    int? id,
    int? noteId,
    String? filename,
    String? filePath,
    int? sizeBytes,
    DateTime? createdAt,
  }) => NoteImageRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    filename: filename ?? this.filename,
    filePath: filePath ?? this.filePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdAt: createdAt ?? this.createdAt,
  );
  NoteImageRow copyWithCompanion(NoteImagesCompanion data) {
    return NoteImageRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      filename: data.filename.present ? data.filename.value : this.filename,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteImageRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('filename: $filename, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, noteId, filename, filePath, sizeBytes, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteImageRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.filename == this.filename &&
          other.filePath == this.filePath &&
          other.sizeBytes == this.sizeBytes &&
          other.createdAt == this.createdAt);
}

class NoteImagesCompanion extends UpdateCompanion<NoteImageRow> {
  final Value<int> id;
  final Value<int> noteId;
  final Value<String> filename;
  final Value<String> filePath;
  final Value<int> sizeBytes;
  final Value<DateTime> createdAt;
  const NoteImagesCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.filename = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NoteImagesCompanion.insert({
    this.id = const Value.absent(),
    required int noteId,
    required String filename,
    required String filePath,
    required int sizeBytes,
    this.createdAt = const Value.absent(),
  }) : noteId = Value(noteId),
       filename = Value(filename),
       filePath = Value(filePath),
       sizeBytes = Value(sizeBytes);
  static Insertable<NoteImageRow> custom({
    Expression<int>? id,
    Expression<int>? noteId,
    Expression<String>? filename,
    Expression<String>? filePath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (filename != null) 'filename': filename,
      if (filePath != null) 'file_path': filePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NoteImagesCompanion copyWith({
    Value<int>? id,
    Value<int>? noteId,
    Value<String>? filename,
    Value<String>? filePath,
    Value<int>? sizeBytes,
    Value<DateTime>? createdAt,
  }) {
    return NoteImagesCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      filename: filename ?? this.filename,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteImagesCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('filename: $filename, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $NoteVersionsTable extends NoteVersions
    with TableInfo<$NoteVersionsTable, NoteVersionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteVersionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _rawMarkdownMeta = const VerificationMeta(
    'rawMarkdown',
  );
  @override
  late final GeneratedColumn<String> rawMarkdown = GeneratedColumn<String>(
    'raw_markdown',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, noteId, rawMarkdown, savedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteVersionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('raw_markdown')) {
      context.handle(
        _rawMarkdownMeta,
        rawMarkdown.isAcceptableOrUnknown(
          data['raw_markdown']!,
          _rawMarkdownMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rawMarkdownMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteVersionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteVersionRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      noteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}note_id'],
          )!,
      rawMarkdown:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}raw_markdown'],
          )!,
      savedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}saved_at'],
          )!,
    );
  }

  @override
  $NoteVersionsTable createAlias(String alias) {
    return $NoteVersionsTable(attachedDatabase, alias);
  }
}

class NoteVersionRow extends DataClass implements Insertable<NoteVersionRow> {
  final int id;
  final int noteId;
  final String rawMarkdown;
  final DateTime savedAt;
  const NoteVersionRow({
    required this.id,
    required this.noteId,
    required this.rawMarkdown,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['note_id'] = Variable<int>(noteId);
    map['raw_markdown'] = Variable<String>(rawMarkdown);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  NoteVersionsCompanion toCompanion(bool nullToAbsent) {
    return NoteVersionsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      rawMarkdown: Value(rawMarkdown),
      savedAt: Value(savedAt),
    );
  }

  factory NoteVersionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteVersionRow(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<int>(json['noteId']),
      rawMarkdown: serializer.fromJson<String>(json['rawMarkdown']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<int>(noteId),
      'rawMarkdown': serializer.toJson<String>(rawMarkdown),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  NoteVersionRow copyWith({
    int? id,
    int? noteId,
    String? rawMarkdown,
    DateTime? savedAt,
  }) => NoteVersionRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    rawMarkdown: rawMarkdown ?? this.rawMarkdown,
    savedAt: savedAt ?? this.savedAt,
  );
  NoteVersionRow copyWithCompanion(NoteVersionsCompanion data) {
    return NoteVersionRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      rawMarkdown:
          data.rawMarkdown.present ? data.rawMarkdown.value : this.rawMarkdown,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteVersionRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, noteId, rawMarkdown, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteVersionRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.rawMarkdown == this.rawMarkdown &&
          other.savedAt == this.savedAt);
}

class NoteVersionsCompanion extends UpdateCompanion<NoteVersionRow> {
  final Value<int> id;
  final Value<int> noteId;
  final Value<String> rawMarkdown;
  final Value<DateTime> savedAt;
  const NoteVersionsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.rawMarkdown = const Value.absent(),
    this.savedAt = const Value.absent(),
  });
  NoteVersionsCompanion.insert({
    this.id = const Value.absent(),
    required int noteId,
    required String rawMarkdown,
    this.savedAt = const Value.absent(),
  }) : noteId = Value(noteId),
       rawMarkdown = Value(rawMarkdown);
  static Insertable<NoteVersionRow> custom({
    Expression<int>? id,
    Expression<int>? noteId,
    Expression<String>? rawMarkdown,
    Expression<DateTime>? savedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (rawMarkdown != null) 'raw_markdown': rawMarkdown,
      if (savedAt != null) 'saved_at': savedAt,
    });
  }

  NoteVersionsCompanion copyWith({
    Value<int>? id,
    Value<int>? noteId,
    Value<String>? rawMarkdown,
    Value<DateTime>? savedAt,
  }) {
    return NoteVersionsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (rawMarkdown.present) {
      map['raw_markdown'] = Variable<String>(rawMarkdown.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteVersionsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('rawMarkdown: $rawMarkdown, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }
}

class $NoteTaskLinksTable extends NoteTaskLinks
    with TableInfo<$NoteTaskLinksTable, NoteTaskLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteTaskLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<int> taskId = GeneratedColumn<int>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [noteId, taskId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_task_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteTaskLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {noteId, taskId};
  @override
  NoteTaskLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteTaskLinkRow(
      noteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}note_id'],
          )!,
      taskId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}task_id'],
          )!,
    );
  }

  @override
  $NoteTaskLinksTable createAlias(String alias) {
    return $NoteTaskLinksTable(attachedDatabase, alias);
  }
}

class NoteTaskLinkRow extends DataClass implements Insertable<NoteTaskLinkRow> {
  final int noteId;
  final int taskId;
  const NoteTaskLinkRow({required this.noteId, required this.taskId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['note_id'] = Variable<int>(noteId);
    map['task_id'] = Variable<int>(taskId);
    return map;
  }

  NoteTaskLinksCompanion toCompanion(bool nullToAbsent) {
    return NoteTaskLinksCompanion(noteId: Value(noteId), taskId: Value(taskId));
  }

  factory NoteTaskLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteTaskLinkRow(
      noteId: serializer.fromJson<int>(json['noteId']),
      taskId: serializer.fromJson<int>(json['taskId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'noteId': serializer.toJson<int>(noteId),
      'taskId': serializer.toJson<int>(taskId),
    };
  }

  NoteTaskLinkRow copyWith({int? noteId, int? taskId}) => NoteTaskLinkRow(
    noteId: noteId ?? this.noteId,
    taskId: taskId ?? this.taskId,
  );
  NoteTaskLinkRow copyWithCompanion(NoteTaskLinksCompanion data) {
    return NoteTaskLinkRow(
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteTaskLinkRow(')
          ..write('noteId: $noteId, ')
          ..write('taskId: $taskId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(noteId, taskId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteTaskLinkRow &&
          other.noteId == this.noteId &&
          other.taskId == this.taskId);
}

class NoteTaskLinksCompanion extends UpdateCompanion<NoteTaskLinkRow> {
  final Value<int> noteId;
  final Value<int> taskId;
  final Value<int> rowid;
  const NoteTaskLinksCompanion({
    this.noteId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteTaskLinksCompanion.insert({
    required int noteId,
    required int taskId,
    this.rowid = const Value.absent(),
  }) : noteId = Value(noteId),
       taskId = Value(taskId);
  static Insertable<NoteTaskLinkRow> custom({
    Expression<int>? noteId,
    Expression<int>? taskId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (noteId != null) 'note_id': noteId,
      if (taskId != null) 'task_id': taskId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteTaskLinksCompanion copyWith({
    Value<int>? noteId,
    Value<int>? taskId,
    Value<int>? rowid,
  }) {
    return NoteTaskLinksCompanion(
      noteId: noteId ?? this.noteId,
      taskId: taskId ?? this.taskId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<int>(taskId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteTaskLinksCompanion(')
          ..write('noteId: $noteId, ')
          ..write('taskId: $taskId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteBlocksTable extends NoteBlocks
    with TableInfo<$NoteBlocksTable, NoteBlockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteBlocksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id) ON DELETE CASCADE',
    ),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    position,
    type,
    payload,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteBlockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteBlockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteBlockRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      noteId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}note_id'],
          )!,
      position:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}position'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}type'],
          )!,
      payload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}payload'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
    );
  }

  @override
  $NoteBlocksTable createAlias(String alias) {
    return $NoteBlocksTable(attachedDatabase, alias);
  }
}

class NoteBlockRow extends DataClass implements Insertable<NoteBlockRow> {
  final int id;
  final int noteId;
  final int position;
  final String type;
  final String payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NoteBlockRow({
    required this.id,
    required this.noteId,
    required this.position,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['note_id'] = Variable<int>(noteId);
    map['position'] = Variable<int>(position);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NoteBlocksCompanion toCompanion(bool nullToAbsent) {
    return NoteBlocksCompanion(
      id: Value(id),
      noteId: Value(noteId),
      position: Value(position),
      type: Value(type),
      payload: Value(payload),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteBlockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteBlockRow(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<int>(json['noteId']),
      position: serializer.fromJson<int>(json['position']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<int>(noteId),
      'position': serializer.toJson<int>(position),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NoteBlockRow copyWith({
    int? id,
    int? noteId,
    int? position,
    String? type,
    String? payload,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteBlockRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    position: position ?? this.position,
    type: type ?? this.type,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NoteBlockRow copyWithCompanion(NoteBlocksCompanion data) {
    return NoteBlockRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      position: data.position.present ? data.position.value : this.position,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteBlockRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('position: $position, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, noteId, position, type, payload, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteBlockRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.position == this.position &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NoteBlocksCompanion extends UpdateCompanion<NoteBlockRow> {
  final Value<int> id;
  final Value<int> noteId;
  final Value<int> position;
  final Value<String> type;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const NoteBlocksCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.position = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NoteBlocksCompanion.insert({
    this.id = const Value.absent(),
    required int noteId,
    required int position,
    required String type,
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : noteId = Value(noteId),
       position = Value(position),
       type = Value(type);
  static Insertable<NoteBlockRow> custom({
    Expression<int>? id,
    Expression<int>? noteId,
    Expression<int>? position,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (position != null) 'position': position,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NoteBlocksCompanion copyWith({
    Value<int>? id,
    Value<int>? noteId,
    Value<int>? position,
    Value<String>? type,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return NoteBlocksCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      position: position ?? this.position,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteBlocksCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('position: $position, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $LabSpacesTable extends LabSpaces
    with TableInfo<$LabSpacesTable, LabSpaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LabSpacesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accentColorMeta = const VerificationMeta(
    'accentColor',
  );
  @override
  late final GeneratedColumn<String> accentColor = GeneratedColumn<String>(
    'accent_color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    accentColor,
    status,
    startDate,
    dueDate,
    createdAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lab_spaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<LabSpaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('accent_color')) {
      context.handle(
        _accentColorMeta,
        accentColor.isAcceptableOrUnknown(
          data['accent_color']!,
          _accentColorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accentColorMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LabSpaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LabSpaceRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      accentColor:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}accent_color'],
          )!,
      status:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}status'],
          )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $LabSpacesTable createAlias(String alias) {
    return $LabSpacesTable(attachedDatabase, alias);
  }
}

class LabSpaceRow extends DataClass implements Insertable<LabSpaceRow> {
  final int id;
  final String name;
  final String accentColor;
  final String status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? deletedAt;
  const LabSpaceRow({
    required this.id,
    required this.name,
    required this.accentColor,
    required this.status,
    this.startDate,
    this.dueDate,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['accent_color'] = Variable<String>(accentColor);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || startDate != null) {
      map['start_date'] = Variable<DateTime>(startDate);
    }
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  LabSpacesCompanion toCompanion(bool nullToAbsent) {
    return LabSpacesCompanion(
      id: Value(id),
      name: Value(name),
      accentColor: Value(accentColor),
      status: Value(status),
      startDate:
          startDate == null && nullToAbsent
              ? const Value.absent()
              : Value(startDate),
      dueDate:
          dueDate == null && nullToAbsent
              ? const Value.absent()
              : Value(dueDate),
      createdAt: Value(createdAt),
      deletedAt:
          deletedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(deletedAt),
    );
  }

  factory LabSpaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LabSpaceRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      accentColor: serializer.fromJson<String>(json['accentColor']),
      status: serializer.fromJson<String>(json['status']),
      startDate: serializer.fromJson<DateTime?>(json['startDate']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'accentColor': serializer.toJson<String>(accentColor),
      'status': serializer.toJson<String>(status),
      'startDate': serializer.toJson<DateTime?>(startDate),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  LabSpaceRow copyWith({
    int? id,
    String? name,
    String? accentColor,
    String? status,
    Value<DateTime?> startDate = const Value.absent(),
    Value<DateTime?> dueDate = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => LabSpaceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    accentColor: accentColor ?? this.accentColor,
    status: status ?? this.status,
    startDate: startDate.present ? startDate.value : this.startDate,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  LabSpaceRow copyWithCompanion(LabSpacesCompanion data) {
    return LabSpaceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      accentColor:
          data.accentColor.present ? data.accentColor.value : this.accentColor,
      status: data.status.present ? data.status.value : this.status,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LabSpaceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('accentColor: $accentColor, ')
          ..write('status: $status, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    accentColor,
    status,
    startDate,
    dueDate,
    createdAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LabSpaceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.accentColor == this.accentColor &&
          other.status == this.status &&
          other.startDate == this.startDate &&
          other.dueDate == this.dueDate &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class LabSpacesCompanion extends UpdateCompanion<LabSpaceRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> accentColor;
  final Value<String> status;
  final Value<DateTime?> startDate;
  final Value<DateTime?> dueDate;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deletedAt;
  const LabSpacesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.accentColor = const Value.absent(),
    this.status = const Value.absent(),
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  LabSpacesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String accentColor,
    this.status = const Value.absent(),
    this.startDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
  }) : name = Value(name),
       accentColor = Value(accentColor);
  static Insertable<LabSpaceRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? accentColor,
    Expression<String>? status,
    Expression<DateTime>? startDate,
    Expression<DateTime>? dueDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (accentColor != null) 'accent_color': accentColor,
      if (status != null) 'status': status,
      if (startDate != null) 'start_date': startDate,
      if (dueDate != null) 'due_date': dueDate,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  LabSpacesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? accentColor,
    Value<String>? status,
    Value<DateTime?>? startDate,
    Value<DateTime?>? dueDate,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deletedAt,
  }) {
    return LabSpacesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      accentColor: accentColor ?? this.accentColor,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (accentColor.present) {
      map['accent_color'] = Variable<String>(accentColor.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LabSpacesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('accentColor: $accentColor, ')
          ..write('status: $status, ')
          ..write('startDate: $startDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $KanbanColumnsTable extends KanbanColumns
    with TableInfo<$KanbanColumnsTable, KanbanColumnRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KanbanColumnsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
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
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    labSpaceId,
    name,
    position,
    isDefault,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kanban_columns';
  @override
  VerificationContext validateIntegrity(
    Insertable<KanbanColumnRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labSpaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KanbanColumnRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KanbanColumnRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      position:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}position'],
          )!,
      isDefault:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_default'],
          )!,
    );
  }

  @override
  $KanbanColumnsTable createAlias(String alias) {
    return $KanbanColumnsTable(attachedDatabase, alias);
  }
}

class KanbanColumnRow extends DataClass implements Insertable<KanbanColumnRow> {
  final int id;
  final int labSpaceId;
  final String name;
  final int position;
  final bool isDefault;
  const KanbanColumnRow({
    required this.id,
    required this.labSpaceId,
    required this.name,
    required this.position,
    required this.isDefault,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lab_space_id'] = Variable<int>(labSpaceId);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    map['is_default'] = Variable<bool>(isDefault);
    return map;
  }

  KanbanColumnsCompanion toCompanion(bool nullToAbsent) {
    return KanbanColumnsCompanion(
      id: Value(id),
      labSpaceId: Value(labSpaceId),
      name: Value(name),
      position: Value(position),
      isDefault: Value(isDefault),
    );
  }

  factory KanbanColumnRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KanbanColumnRow(
      id: serializer.fromJson<int>(json['id']),
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'isDefault': serializer.toJson<bool>(isDefault),
    };
  }

  KanbanColumnRow copyWith({
    int? id,
    int? labSpaceId,
    String? name,
    int? position,
    bool? isDefault,
  }) => KanbanColumnRow(
    id: id ?? this.id,
    labSpaceId: labSpaceId ?? this.labSpaceId,
    name: name ?? this.name,
    position: position ?? this.position,
    isDefault: isDefault ?? this.isDefault,
  );
  KanbanColumnRow copyWithCompanion(KanbanColumnsCompanion data) {
    return KanbanColumnRow(
      id: data.id.present ? data.id.value : this.id,
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KanbanColumnRow(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('isDefault: $isDefault')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, labSpaceId, name, position, isDefault);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KanbanColumnRow &&
          other.id == this.id &&
          other.labSpaceId == this.labSpaceId &&
          other.name == this.name &&
          other.position == this.position &&
          other.isDefault == this.isDefault);
}

class KanbanColumnsCompanion extends UpdateCompanion<KanbanColumnRow> {
  final Value<int> id;
  final Value<int> labSpaceId;
  final Value<String> name;
  final Value<int> position;
  final Value<bool> isDefault;
  const KanbanColumnsCompanion({
    this.id = const Value.absent(),
    this.labSpaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.isDefault = const Value.absent(),
  });
  KanbanColumnsCompanion.insert({
    this.id = const Value.absent(),
    required int labSpaceId,
    required String name,
    required int position,
    this.isDefault = const Value.absent(),
  }) : labSpaceId = Value(labSpaceId),
       name = Value(name),
       position = Value(position);
  static Insertable<KanbanColumnRow> custom({
    Expression<int>? id,
    Expression<int>? labSpaceId,
    Expression<String>? name,
    Expression<int>? position,
    Expression<bool>? isDefault,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (isDefault != null) 'is_default': isDefault,
    });
  }

  KanbanColumnsCompanion copyWith({
    Value<int>? id,
    Value<int>? labSpaceId,
    Value<String>? name,
    Value<int>? position,
    Value<bool>? isDefault,
  }) {
    return KanbanColumnsCompanion(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      name: name ?? this.name,
      position: position ?? this.position,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KanbanColumnsCompanion(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('isDefault: $isDefault')
          ..write(')'))
        .toString();
  }
}

class $KanbanCardsTable extends KanbanCards
    with TableInfo<$KanbanCardsTable, KanbanCardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KanbanCardsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
  );
  static const VerificationMeta _columnIdMeta = const VerificationMeta(
    'columnId',
  );
  @override
  late final GeneratedColumn<int> columnId = GeneratedColumn<int>(
    'column_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES kanban_columns (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceNoteIdMeta = const VerificationMeta(
    'sourceNoteId',
  );
  @override
  late final GeneratedColumn<int> sourceNoteId = GeneratedColumn<int>(
    'source_note_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _sourceAnchorMeta = const VerificationMeta(
    'sourceAnchor',
  );
  @override
  late final GeneratedColumn<String> sourceAnchor = GeneratedColumn<String>(
    'source_anchor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originTaskIdMeta = const VerificationMeta(
    'originTaskId',
  );
  @override
  late final GeneratedColumn<int> originTaskId = GeneratedColumn<int>(
    'origin_task_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tasks (id)',
    ),
  );
  static const VerificationMeta _originFolderColorMeta = const VerificationMeta(
    'originFolderColor',
  );
  @override
  late final GeneratedColumn<int> originFolderColor = GeneratedColumn<int>(
    'origin_folder_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originTaskDoneAtMeta = const VerificationMeta(
    'originTaskDoneAt',
  );
  @override
  late final GeneratedColumn<DateTime> originTaskDoneAt =
      GeneratedColumn<DateTime>(
        'origin_task_done_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    labSpaceId,
    columnId,
    title,
    description,
    priority,
    position,
    dueDate,
    sourceNoteId,
    sourceAnchor,
    originTaskId,
    originFolderColor,
    originTaskDoneAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kanban_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<KanbanCardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labSpaceIdMeta);
    }
    if (data.containsKey('column_id')) {
      context.handle(
        _columnIdMeta,
        columnId.isAcceptableOrUnknown(data['column_id']!, _columnIdMeta),
      );
    } else if (isInserting) {
      context.missing(_columnIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('source_note_id')) {
      context.handle(
        _sourceNoteIdMeta,
        sourceNoteId.isAcceptableOrUnknown(
          data['source_note_id']!,
          _sourceNoteIdMeta,
        ),
      );
    }
    if (data.containsKey('source_anchor')) {
      context.handle(
        _sourceAnchorMeta,
        sourceAnchor.isAcceptableOrUnknown(
          data['source_anchor']!,
          _sourceAnchorMeta,
        ),
      );
    }
    if (data.containsKey('origin_task_id')) {
      context.handle(
        _originTaskIdMeta,
        originTaskId.isAcceptableOrUnknown(
          data['origin_task_id']!,
          _originTaskIdMeta,
        ),
      );
    }
    if (data.containsKey('origin_folder_color')) {
      context.handle(
        _originFolderColorMeta,
        originFolderColor.isAcceptableOrUnknown(
          data['origin_folder_color']!,
          _originFolderColorMeta,
        ),
      );
    }
    if (data.containsKey('origin_task_done_at')) {
      context.handle(
        _originTaskDoneAtMeta,
        originTaskDoneAt.isAcceptableOrUnknown(
          data['origin_task_done_at']!,
          _originTaskDoneAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KanbanCardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KanbanCardRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      columnId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}column_id'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      priority:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}priority'],
          )!,
      position:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}position'],
          )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      sourceNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_note_id'],
      ),
      sourceAnchor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_anchor'],
      ),
      originTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}origin_task_id'],
      ),
      originFolderColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}origin_folder_color'],
      ),
      originTaskDoneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}origin_task_done_at'],
      ),
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $KanbanCardsTable createAlias(String alias) {
    return $KanbanCardsTable(attachedDatabase, alias);
  }
}

class KanbanCardRow extends DataClass implements Insertable<KanbanCardRow> {
  final int id;
  final int labSpaceId;
  final int columnId;
  final String title;
  final String? description;
  final String priority;
  final int position;
  final DateTime? dueDate;
  final int? sourceNoteId;
  final String? sourceAnchor;
  final int? originTaskId;
  final int? originFolderColor;
  final DateTime? originTaskDoneAt;
  final DateTime createdAt;
  const KanbanCardRow({
    required this.id,
    required this.labSpaceId,
    required this.columnId,
    required this.title,
    this.description,
    required this.priority,
    required this.position,
    this.dueDate,
    this.sourceNoteId,
    this.sourceAnchor,
    this.originTaskId,
    this.originFolderColor,
    this.originTaskDoneAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lab_space_id'] = Variable<int>(labSpaceId);
    map['column_id'] = Variable<int>(columnId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['priority'] = Variable<String>(priority);
    map['position'] = Variable<int>(position);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || sourceNoteId != null) {
      map['source_note_id'] = Variable<int>(sourceNoteId);
    }
    if (!nullToAbsent || sourceAnchor != null) {
      map['source_anchor'] = Variable<String>(sourceAnchor);
    }
    if (!nullToAbsent || originTaskId != null) {
      map['origin_task_id'] = Variable<int>(originTaskId);
    }
    if (!nullToAbsent || originFolderColor != null) {
      map['origin_folder_color'] = Variable<int>(originFolderColor);
    }
    if (!nullToAbsent || originTaskDoneAt != null) {
      map['origin_task_done_at'] = Variable<DateTime>(originTaskDoneAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  KanbanCardsCompanion toCompanion(bool nullToAbsent) {
    return KanbanCardsCompanion(
      id: Value(id),
      labSpaceId: Value(labSpaceId),
      columnId: Value(columnId),
      title: Value(title),
      description:
          description == null && nullToAbsent
              ? const Value.absent()
              : Value(description),
      priority: Value(priority),
      position: Value(position),
      dueDate:
          dueDate == null && nullToAbsent
              ? const Value.absent()
              : Value(dueDate),
      sourceNoteId:
          sourceNoteId == null && nullToAbsent
              ? const Value.absent()
              : Value(sourceNoteId),
      sourceAnchor:
          sourceAnchor == null && nullToAbsent
              ? const Value.absent()
              : Value(sourceAnchor),
      originTaskId:
          originTaskId == null && nullToAbsent
              ? const Value.absent()
              : Value(originTaskId),
      originFolderColor:
          originFolderColor == null && nullToAbsent
              ? const Value.absent()
              : Value(originFolderColor),
      originTaskDoneAt:
          originTaskDoneAt == null && nullToAbsent
              ? const Value.absent()
              : Value(originTaskDoneAt),
      createdAt: Value(createdAt),
    );
  }

  factory KanbanCardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KanbanCardRow(
      id: serializer.fromJson<int>(json['id']),
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      columnId: serializer.fromJson<int>(json['columnId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      priority: serializer.fromJson<String>(json['priority']),
      position: serializer.fromJson<int>(json['position']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      sourceNoteId: serializer.fromJson<int?>(json['sourceNoteId']),
      sourceAnchor: serializer.fromJson<String?>(json['sourceAnchor']),
      originTaskId: serializer.fromJson<int?>(json['originTaskId']),
      originFolderColor: serializer.fromJson<int?>(json['originFolderColor']),
      originTaskDoneAt: serializer.fromJson<DateTime?>(
        json['originTaskDoneAt'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'columnId': serializer.toJson<int>(columnId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'priority': serializer.toJson<String>(priority),
      'position': serializer.toJson<int>(position),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'sourceNoteId': serializer.toJson<int?>(sourceNoteId),
      'sourceAnchor': serializer.toJson<String?>(sourceAnchor),
      'originTaskId': serializer.toJson<int?>(originTaskId),
      'originFolderColor': serializer.toJson<int?>(originFolderColor),
      'originTaskDoneAt': serializer.toJson<DateTime?>(originTaskDoneAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  KanbanCardRow copyWith({
    int? id,
    int? labSpaceId,
    int? columnId,
    String? title,
    Value<String?> description = const Value.absent(),
    String? priority,
    int? position,
    Value<DateTime?> dueDate = const Value.absent(),
    Value<int?> sourceNoteId = const Value.absent(),
    Value<String?> sourceAnchor = const Value.absent(),
    Value<int?> originTaskId = const Value.absent(),
    Value<int?> originFolderColor = const Value.absent(),
    Value<DateTime?> originTaskDoneAt = const Value.absent(),
    DateTime? createdAt,
  }) => KanbanCardRow(
    id: id ?? this.id,
    labSpaceId: labSpaceId ?? this.labSpaceId,
    columnId: columnId ?? this.columnId,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    priority: priority ?? this.priority,
    position: position ?? this.position,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    sourceNoteId: sourceNoteId.present ? sourceNoteId.value : this.sourceNoteId,
    sourceAnchor: sourceAnchor.present ? sourceAnchor.value : this.sourceAnchor,
    originTaskId: originTaskId.present ? originTaskId.value : this.originTaskId,
    originFolderColor:
        originFolderColor.present
            ? originFolderColor.value
            : this.originFolderColor,
    originTaskDoneAt:
        originTaskDoneAt.present
            ? originTaskDoneAt.value
            : this.originTaskDoneAt,
    createdAt: createdAt ?? this.createdAt,
  );
  KanbanCardRow copyWithCompanion(KanbanCardsCompanion data) {
    return KanbanCardRow(
      id: data.id.present ? data.id.value : this.id,
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      columnId: data.columnId.present ? data.columnId.value : this.columnId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      priority: data.priority.present ? data.priority.value : this.priority,
      position: data.position.present ? data.position.value : this.position,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      sourceNoteId:
          data.sourceNoteId.present
              ? data.sourceNoteId.value
              : this.sourceNoteId,
      sourceAnchor:
          data.sourceAnchor.present
              ? data.sourceAnchor.value
              : this.sourceAnchor,
      originTaskId:
          data.originTaskId.present
              ? data.originTaskId.value
              : this.originTaskId,
      originFolderColor:
          data.originFolderColor.present
              ? data.originFolderColor.value
              : this.originFolderColor,
      originTaskDoneAt:
          data.originTaskDoneAt.present
              ? data.originTaskDoneAt.value
              : this.originTaskDoneAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KanbanCardRow(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('columnId: $columnId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('priority: $priority, ')
          ..write('position: $position, ')
          ..write('dueDate: $dueDate, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('sourceAnchor: $sourceAnchor, ')
          ..write('originTaskId: $originTaskId, ')
          ..write('originFolderColor: $originFolderColor, ')
          ..write('originTaskDoneAt: $originTaskDoneAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    labSpaceId,
    columnId,
    title,
    description,
    priority,
    position,
    dueDate,
    sourceNoteId,
    sourceAnchor,
    originTaskId,
    originFolderColor,
    originTaskDoneAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KanbanCardRow &&
          other.id == this.id &&
          other.labSpaceId == this.labSpaceId &&
          other.columnId == this.columnId &&
          other.title == this.title &&
          other.description == this.description &&
          other.priority == this.priority &&
          other.position == this.position &&
          other.dueDate == this.dueDate &&
          other.sourceNoteId == this.sourceNoteId &&
          other.sourceAnchor == this.sourceAnchor &&
          other.originTaskId == this.originTaskId &&
          other.originFolderColor == this.originFolderColor &&
          other.originTaskDoneAt == this.originTaskDoneAt &&
          other.createdAt == this.createdAt);
}

class KanbanCardsCompanion extends UpdateCompanion<KanbanCardRow> {
  final Value<int> id;
  final Value<int> labSpaceId;
  final Value<int> columnId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> priority;
  final Value<int> position;
  final Value<DateTime?> dueDate;
  final Value<int?> sourceNoteId;
  final Value<String?> sourceAnchor;
  final Value<int?> originTaskId;
  final Value<int?> originFolderColor;
  final Value<DateTime?> originTaskDoneAt;
  final Value<DateTime> createdAt;
  const KanbanCardsCompanion({
    this.id = const Value.absent(),
    this.labSpaceId = const Value.absent(),
    this.columnId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.priority = const Value.absent(),
    this.position = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.sourceAnchor = const Value.absent(),
    this.originTaskId = const Value.absent(),
    this.originFolderColor = const Value.absent(),
    this.originTaskDoneAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  KanbanCardsCompanion.insert({
    this.id = const Value.absent(),
    required int labSpaceId,
    required int columnId,
    required String title,
    this.description = const Value.absent(),
    this.priority = const Value.absent(),
    required int position,
    this.dueDate = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.sourceAnchor = const Value.absent(),
    this.originTaskId = const Value.absent(),
    this.originFolderColor = const Value.absent(),
    this.originTaskDoneAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : labSpaceId = Value(labSpaceId),
       columnId = Value(columnId),
       title = Value(title),
       position = Value(position);
  static Insertable<KanbanCardRow> custom({
    Expression<int>? id,
    Expression<int>? labSpaceId,
    Expression<int>? columnId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? priority,
    Expression<int>? position,
    Expression<DateTime>? dueDate,
    Expression<int>? sourceNoteId,
    Expression<String>? sourceAnchor,
    Expression<int>? originTaskId,
    Expression<int>? originFolderColor,
    Expression<DateTime>? originTaskDoneAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (columnId != null) 'column_id': columnId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (priority != null) 'priority': priority,
      if (position != null) 'position': position,
      if (dueDate != null) 'due_date': dueDate,
      if (sourceNoteId != null) 'source_note_id': sourceNoteId,
      if (sourceAnchor != null) 'source_anchor': sourceAnchor,
      if (originTaskId != null) 'origin_task_id': originTaskId,
      if (originFolderColor != null) 'origin_folder_color': originFolderColor,
      if (originTaskDoneAt != null) 'origin_task_done_at': originTaskDoneAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  KanbanCardsCompanion copyWith({
    Value<int>? id,
    Value<int>? labSpaceId,
    Value<int>? columnId,
    Value<String>? title,
    Value<String?>? description,
    Value<String>? priority,
    Value<int>? position,
    Value<DateTime?>? dueDate,
    Value<int?>? sourceNoteId,
    Value<String?>? sourceAnchor,
    Value<int?>? originTaskId,
    Value<int?>? originFolderColor,
    Value<DateTime?>? originTaskDoneAt,
    Value<DateTime>? createdAt,
  }) {
    return KanbanCardsCompanion(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      columnId: columnId ?? this.columnId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      position: position ?? this.position,
      dueDate: dueDate ?? this.dueDate,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      sourceAnchor: sourceAnchor ?? this.sourceAnchor,
      originTaskId: originTaskId ?? this.originTaskId,
      originFolderColor: originFolderColor ?? this.originFolderColor,
      originTaskDoneAt: originTaskDoneAt ?? this.originTaskDoneAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (columnId.present) {
      map['column_id'] = Variable<int>(columnId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (sourceNoteId.present) {
      map['source_note_id'] = Variable<int>(sourceNoteId.value);
    }
    if (sourceAnchor.present) {
      map['source_anchor'] = Variable<String>(sourceAnchor.value);
    }
    if (originTaskId.present) {
      map['origin_task_id'] = Variable<int>(originTaskId.value);
    }
    if (originFolderColor.present) {
      map['origin_folder_color'] = Variable<int>(originFolderColor.value);
    }
    if (originTaskDoneAt.present) {
      map['origin_task_done_at'] = Variable<DateTime>(originTaskDoneAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KanbanCardsCompanion(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('columnId: $columnId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('priority: $priority, ')
          ..write('position: $position, ')
          ..write('dueDate: $dueDate, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('sourceAnchor: $sourceAnchor, ')
          ..write('originTaskId: $originTaskId, ')
          ..write('originFolderColor: $originFolderColor, ')
          ..write('originTaskDoneAt: $originTaskDoneAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SpaceFolderLinksTable extends SpaceFolderLinks
    with TableInfo<$SpaceFolderLinksTable, SpaceFolderLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SpaceFolderLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [labSpaceId, folderId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'space_folder_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<SpaceFolderLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labSpaceIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {labSpaceId, folderId};
  @override
  SpaceFolderLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SpaceFolderLinkRow(
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      folderId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}folder_id'],
          )!,
    );
  }

  @override
  $SpaceFolderLinksTable createAlias(String alias) {
    return $SpaceFolderLinksTable(attachedDatabase, alias);
  }
}

class SpaceFolderLinkRow extends DataClass
    implements Insertable<SpaceFolderLinkRow> {
  final int labSpaceId;
  final int folderId;
  const SpaceFolderLinkRow({required this.labSpaceId, required this.folderId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['lab_space_id'] = Variable<int>(labSpaceId);
    map['folder_id'] = Variable<int>(folderId);
    return map;
  }

  SpaceFolderLinksCompanion toCompanion(bool nullToAbsent) {
    return SpaceFolderLinksCompanion(
      labSpaceId: Value(labSpaceId),
      folderId: Value(folderId),
    );
  }

  factory SpaceFolderLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SpaceFolderLinkRow(
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      folderId: serializer.fromJson<int>(json['folderId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'folderId': serializer.toJson<int>(folderId),
    };
  }

  SpaceFolderLinkRow copyWith({int? labSpaceId, int? folderId}) =>
      SpaceFolderLinkRow(
        labSpaceId: labSpaceId ?? this.labSpaceId,
        folderId: folderId ?? this.folderId,
      );
  SpaceFolderLinkRow copyWithCompanion(SpaceFolderLinksCompanion data) {
    return SpaceFolderLinkRow(
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SpaceFolderLinkRow(')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('folderId: $folderId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(labSpaceId, folderId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SpaceFolderLinkRow &&
          other.labSpaceId == this.labSpaceId &&
          other.folderId == this.folderId);
}

class SpaceFolderLinksCompanion extends UpdateCompanion<SpaceFolderLinkRow> {
  final Value<int> labSpaceId;
  final Value<int> folderId;
  final Value<int> rowid;
  const SpaceFolderLinksCompanion({
    this.labSpaceId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SpaceFolderLinksCompanion.insert({
    required int labSpaceId,
    required int folderId,
    this.rowid = const Value.absent(),
  }) : labSpaceId = Value(labSpaceId),
       folderId = Value(folderId);
  static Insertable<SpaceFolderLinkRow> custom({
    Expression<int>? labSpaceId,
    Expression<int>? folderId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (folderId != null) 'folder_id': folderId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SpaceFolderLinksCompanion copyWith({
    Value<int>? labSpaceId,
    Value<int>? folderId,
    Value<int>? rowid,
  }) {
    return SpaceFolderLinksCompanion(
      labSpaceId: labSpaceId ?? this.labSpaceId,
      folderId: folderId ?? this.folderId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SpaceFolderLinksCompanion(')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('folderId: $folderId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OnboardingFlagsTable extends OnboardingFlags
    with TableInfo<$OnboardingFlagsTable, OnboardingFlagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OnboardingFlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<DateTime> seenAt = GeneratedColumn<DateTime>(
    'seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, seenAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'onboarding_flags';
  @override
  VerificationContext validateIntegrity(
    Insertable<OnboardingFlagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_seenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  OnboardingFlagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OnboardingFlagRow(
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      seenAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}seen_at'],
          )!,
    );
  }

  @override
  $OnboardingFlagsTable createAlias(String alias) {
    return $OnboardingFlagsTable(attachedDatabase, alias);
  }
}

class OnboardingFlagRow extends DataClass
    implements Insertable<OnboardingFlagRow> {
  final String key;
  final DateTime seenAt;
  const OnboardingFlagRow({required this.key, required this.seenAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['seen_at'] = Variable<DateTime>(seenAt);
    return map;
  }

  OnboardingFlagsCompanion toCompanion(bool nullToAbsent) {
    return OnboardingFlagsCompanion(key: Value(key), seenAt: Value(seenAt));
  }

  factory OnboardingFlagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OnboardingFlagRow(
      key: serializer.fromJson<String>(json['key']),
      seenAt: serializer.fromJson<DateTime>(json['seenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'seenAt': serializer.toJson<DateTime>(seenAt),
    };
  }

  OnboardingFlagRow copyWith({String? key, DateTime? seenAt}) =>
      OnboardingFlagRow(key: key ?? this.key, seenAt: seenAt ?? this.seenAt);
  OnboardingFlagRow copyWithCompanion(OnboardingFlagsCompanion data) {
    return OnboardingFlagRow(
      key: data.key.present ? data.key.value : this.key,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OnboardingFlagRow(')
          ..write('key: $key, ')
          ..write('seenAt: $seenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, seenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OnboardingFlagRow &&
          other.key == this.key &&
          other.seenAt == this.seenAt);
}

class OnboardingFlagsCompanion extends UpdateCompanion<OnboardingFlagRow> {
  final Value<String> key;
  final Value<DateTime> seenAt;
  final Value<int> rowid;
  const OnboardingFlagsCompanion({
    this.key = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OnboardingFlagsCompanion.insert({
    required String key,
    required DateTime seenAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       seenAt = Value(seenAt);
  static Insertable<OnboardingFlagRow> custom({
    Expression<String>? key,
    Expression<DateTime>? seenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (seenAt != null) 'seen_at': seenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OnboardingFlagsCompanion copyWith({
    Value<String>? key,
    Value<DateTime>? seenAt,
    Value<int>? rowid,
  }) {
    return OnboardingFlagsCompanion(
      key: key ?? this.key,
      seenAt: seenAt ?? this.seenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<DateTime>(seenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OnboardingFlagsCompanion(')
          ..write('key: $key, ')
          ..write('seenAt: $seenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotificationsTable extends Notifications
    with TableInfo<$NotificationsTable, NotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, message, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      message:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}message'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $NotificationsTable createAlias(String alias) {
    return $NotificationsTable(attachedDatabase, alias);
  }
}

class NotificationRow extends DataClass implements Insertable<NotificationRow> {
  final int id;
  final String message;
  final DateTime createdAt;
  const NotificationRow({
    required this.id,
    required this.message,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message'] = Variable<String>(message);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NotificationsCompanion toCompanion(bool nullToAbsent) {
    return NotificationsCompanion(
      id: Value(id),
      message: Value(message),
      createdAt: Value(createdAt),
    );
  }

  factory NotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationRow(
      id: serializer.fromJson<int>(json['id']),
      message: serializer.fromJson<String>(json['message']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'message': serializer.toJson<String>(message),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NotificationRow copyWith({int? id, String? message, DateTime? createdAt}) =>
      NotificationRow(
        id: id ?? this.id,
        message: message ?? this.message,
        createdAt: createdAt ?? this.createdAt,
      );
  NotificationRow copyWithCompanion(NotificationsCompanion data) {
    return NotificationRow(
      id: data.id.present ? data.id.value : this.id,
      message: data.message.present ? data.message.value : this.message,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationRow(')
          ..write('id: $id, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, message, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationRow &&
          other.id == this.id &&
          other.message == this.message &&
          other.createdAt == this.createdAt);
}

class NotificationsCompanion extends UpdateCompanion<NotificationRow> {
  final Value<int> id;
  final Value<String> message;
  final Value<DateTime> createdAt;
  const NotificationsCompanion({
    this.id = const Value.absent(),
    this.message = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NotificationsCompanion.insert({
    this.id = const Value.absent(),
    required String message,
    this.createdAt = const Value.absent(),
  }) : message = Value(message);
  static Insertable<NotificationRow> custom({
    Expression<int>? id,
    Expression<String>? message,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (message != null) 'message': message,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NotificationsCompanion copyWith({
    Value<int>? id,
    Value<String>? message,
    Value<DateTime>? createdAt,
  }) {
    return NotificationsCompanion(
      id: id ?? this.id,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationsCompanion(')
          ..write('id: $id, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ScheduleBlocksTable extends ScheduleBlocks
    with TableInfo<$ScheduleBlocksTable, ScheduleBlockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleBlocksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _daysMeta = const VerificationMeta('days');
  @override
  late final GeneratedColumn<String> days = GeneratedColumn<String>(
    'days',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _useFolderColorMeta = const VerificationMeta(
    'useFolderColor',
  );
  @override
  late final GeneratedColumn<int> useFolderColor = GeneratedColumn<int>(
    'use_folder_color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    labSpaceId,
    folderId,
    title,
    location,
    startTime,
    endTime,
    days,
    color,
    useFolderColor,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_blocks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleBlockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labSpaceIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('days')) {
      context.handle(
        _daysMeta,
        days.isAcceptableOrUnknown(data['days']!, _daysMeta),
      );
    } else if (isInserting) {
      context.missing(_daysMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('use_folder_color')) {
      context.handle(
        _useFolderColorMeta,
        useFolderColor.isAcceptableOrUnknown(
          data['use_folder_color']!,
          _useFolderColorMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleBlockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleBlockRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      startTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}start_time'],
          )!,
      endTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}end_time'],
          )!,
      days:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}days'],
          )!,
      color:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}color'],
          )!,
      useFolderColor:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}use_folder_color'],
          )!,
      createdAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}created_at'],
          )!,
    );
  }

  @override
  $ScheduleBlocksTable createAlias(String alias) {
    return $ScheduleBlocksTable(attachedDatabase, alias);
  }
}

class ScheduleBlockRow extends DataClass
    implements Insertable<ScheduleBlockRow> {
  final int id;
  final int labSpaceId;
  final int? folderId;
  final String title;
  final String? location;
  final String startTime;
  final String endTime;
  final String days;
  final String color;
  final int useFolderColor;
  final DateTime createdAt;
  const ScheduleBlockRow({
    required this.id,
    required this.labSpaceId,
    this.folderId,
    required this.title,
    this.location,
    required this.startTime,
    required this.endTime,
    required this.days,
    required this.color,
    required this.useFolderColor,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lab_space_id'] = Variable<int>(labSpaceId);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    map['start_time'] = Variable<String>(startTime);
    map['end_time'] = Variable<String>(endTime);
    map['days'] = Variable<String>(days);
    map['color'] = Variable<String>(color);
    map['use_folder_color'] = Variable<int>(useFolderColor);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ScheduleBlocksCompanion toCompanion(bool nullToAbsent) {
    return ScheduleBlocksCompanion(
      id: Value(id),
      labSpaceId: Value(labSpaceId),
      folderId:
          folderId == null && nullToAbsent
              ? const Value.absent()
              : Value(folderId),
      title: Value(title),
      location:
          location == null && nullToAbsent
              ? const Value.absent()
              : Value(location),
      startTime: Value(startTime),
      endTime: Value(endTime),
      days: Value(days),
      color: Value(color),
      useFolderColor: Value(useFolderColor),
      createdAt: Value(createdAt),
    );
  }

  factory ScheduleBlockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleBlockRow(
      id: serializer.fromJson<int>(json['id']),
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      title: serializer.fromJson<String>(json['title']),
      location: serializer.fromJson<String?>(json['location']),
      startTime: serializer.fromJson<String>(json['startTime']),
      endTime: serializer.fromJson<String>(json['endTime']),
      days: serializer.fromJson<String>(json['days']),
      color: serializer.fromJson<String>(json['color']),
      useFolderColor: serializer.fromJson<int>(json['useFolderColor']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'folderId': serializer.toJson<int?>(folderId),
      'title': serializer.toJson<String>(title),
      'location': serializer.toJson<String?>(location),
      'startTime': serializer.toJson<String>(startTime),
      'endTime': serializer.toJson<String>(endTime),
      'days': serializer.toJson<String>(days),
      'color': serializer.toJson<String>(color),
      'useFolderColor': serializer.toJson<int>(useFolderColor),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ScheduleBlockRow copyWith({
    int? id,
    int? labSpaceId,
    Value<int?> folderId = const Value.absent(),
    String? title,
    Value<String?> location = const Value.absent(),
    String? startTime,
    String? endTime,
    String? days,
    String? color,
    int? useFolderColor,
    DateTime? createdAt,
  }) => ScheduleBlockRow(
    id: id ?? this.id,
    labSpaceId: labSpaceId ?? this.labSpaceId,
    folderId: folderId.present ? folderId.value : this.folderId,
    title: title ?? this.title,
    location: location.present ? location.value : this.location,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    days: days ?? this.days,
    color: color ?? this.color,
    useFolderColor: useFolderColor ?? this.useFolderColor,
    createdAt: createdAt ?? this.createdAt,
  );
  ScheduleBlockRow copyWithCompanion(ScheduleBlocksCompanion data) {
    return ScheduleBlockRow(
      id: data.id.present ? data.id.value : this.id,
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      title: data.title.present ? data.title.value : this.title,
      location: data.location.present ? data.location.value : this.location,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      days: data.days.present ? data.days.value : this.days,
      color: data.color.present ? data.color.value : this.color,
      useFolderColor:
          data.useFolderColor.present
              ? data.useFolderColor.value
              : this.useFolderColor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleBlockRow(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('days: $days, ')
          ..write('color: $color, ')
          ..write('useFolderColor: $useFolderColor, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    labSpaceId,
    folderId,
    title,
    location,
    startTime,
    endTime,
    days,
    color,
    useFolderColor,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleBlockRow &&
          other.id == this.id &&
          other.labSpaceId == this.labSpaceId &&
          other.folderId == this.folderId &&
          other.title == this.title &&
          other.location == this.location &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.days == this.days &&
          other.color == this.color &&
          other.useFolderColor == this.useFolderColor &&
          other.createdAt == this.createdAt);
}

class ScheduleBlocksCompanion extends UpdateCompanion<ScheduleBlockRow> {
  final Value<int> id;
  final Value<int> labSpaceId;
  final Value<int?> folderId;
  final Value<String> title;
  final Value<String?> location;
  final Value<String> startTime;
  final Value<String> endTime;
  final Value<String> days;
  final Value<String> color;
  final Value<int> useFolderColor;
  final Value<DateTime> createdAt;
  const ScheduleBlocksCompanion({
    this.id = const Value.absent(),
    this.labSpaceId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.title = const Value.absent(),
    this.location = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.days = const Value.absent(),
    this.color = const Value.absent(),
    this.useFolderColor = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ScheduleBlocksCompanion.insert({
    this.id = const Value.absent(),
    required int labSpaceId,
    this.folderId = const Value.absent(),
    required String title,
    this.location = const Value.absent(),
    required String startTime,
    required String endTime,
    required String days,
    required String color,
    this.useFolderColor = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : labSpaceId = Value(labSpaceId),
       title = Value(title),
       startTime = Value(startTime),
       endTime = Value(endTime),
       days = Value(days),
       color = Value(color);
  static Insertable<ScheduleBlockRow> custom({
    Expression<int>? id,
    Expression<int>? labSpaceId,
    Expression<int>? folderId,
    Expression<String>? title,
    Expression<String>? location,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<String>? days,
    Expression<String>? color,
    Expression<int>? useFolderColor,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (folderId != null) 'folder_id': folderId,
      if (title != null) 'title': title,
      if (location != null) 'location': location,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (days != null) 'days': days,
      if (color != null) 'color': color,
      if (useFolderColor != null) 'use_folder_color': useFolderColor,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ScheduleBlocksCompanion copyWith({
    Value<int>? id,
    Value<int>? labSpaceId,
    Value<int?>? folderId,
    Value<String>? title,
    Value<String?>? location,
    Value<String>? startTime,
    Value<String>? endTime,
    Value<String>? days,
    Value<String>? color,
    Value<int>? useFolderColor,
    Value<DateTime>? createdAt,
  }) {
    return ScheduleBlocksCompanion(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      days: days ?? this.days,
      color: color ?? this.color,
      useFolderColor: useFolderColor ?? this.useFolderColor,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (days.present) {
      map['days'] = Variable<String>(days.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (useFolderColor.present) {
      map['use_folder_color'] = Variable<int>(useFolderColor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleBlocksCompanion(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('location: $location, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('days: $days, ')
          ..write('color: $color, ')
          ..write('useFolderColor: $useFolderColor, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ScheduleSettingsTable extends ScheduleSettings
    with TableInfo<$ScheduleSettingsTable, ScheduleSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
  );
  static const VerificationMeta _showSaturdayMeta = const VerificationMeta(
    'showSaturday',
  );
  @override
  late final GeneratedColumn<int> showSaturday = GeneratedColumn<int>(
    'show_saturday',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _showSundayMeta = const VerificationMeta(
    'showSunday',
  );
  @override
  late final GeneratedColumn<int> showSunday = GeneratedColumn<int>(
    'show_sunday',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayStartTimeMeta = const VerificationMeta(
    'dayStartTime',
  );
  @override
  late final GeneratedColumn<String> dayStartTime = GeneratedColumn<String>(
    'day_start_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('07:00'),
  );
  static const VerificationMeta _dayEndTimeMeta = const VerificationMeta(
    'dayEndTime',
  );
  @override
  late final GeneratedColumn<String> dayEndTime = GeneratedColumn<String>(
    'day_end_time',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('22:00'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    labSpaceId,
    showSaturday,
    showSunday,
    dayStartTime,
    dayEndTime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    }
    if (data.containsKey('show_saturday')) {
      context.handle(
        _showSaturdayMeta,
        showSaturday.isAcceptableOrUnknown(
          data['show_saturday']!,
          _showSaturdayMeta,
        ),
      );
    }
    if (data.containsKey('show_sunday')) {
      context.handle(
        _showSundayMeta,
        showSunday.isAcceptableOrUnknown(data['show_sunday']!, _showSundayMeta),
      );
    }
    if (data.containsKey('day_start_time')) {
      context.handle(
        _dayStartTimeMeta,
        dayStartTime.isAcceptableOrUnknown(
          data['day_start_time']!,
          _dayStartTimeMeta,
        ),
      );
    }
    if (data.containsKey('day_end_time')) {
      context.handle(
        _dayEndTimeMeta,
        dayEndTime.isAcceptableOrUnknown(
          data['day_end_time']!,
          _dayEndTimeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {labSpaceId};
  @override
  ScheduleSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleSettingsRow(
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      showSaturday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}show_saturday'],
      ),
      showSunday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}show_sunday'],
      ),
      dayStartTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}day_start_time'],
          )!,
      dayEndTime:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}day_end_time'],
          )!,
    );
  }

  @override
  $ScheduleSettingsTable createAlias(String alias) {
    return $ScheduleSettingsTable(attachedDatabase, alias);
  }
}

class ScheduleSettingsRow extends DataClass
    implements Insertable<ScheduleSettingsRow> {
  final int labSpaceId;
  final int? showSaturday;
  final int? showSunday;
  final String dayStartTime;
  final String dayEndTime;
  const ScheduleSettingsRow({
    required this.labSpaceId,
    this.showSaturday,
    this.showSunday,
    required this.dayStartTime,
    required this.dayEndTime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['lab_space_id'] = Variable<int>(labSpaceId);
    if (!nullToAbsent || showSaturday != null) {
      map['show_saturday'] = Variable<int>(showSaturday);
    }
    if (!nullToAbsent || showSunday != null) {
      map['show_sunday'] = Variable<int>(showSunday);
    }
    map['day_start_time'] = Variable<String>(dayStartTime);
    map['day_end_time'] = Variable<String>(dayEndTime);
    return map;
  }

  ScheduleSettingsCompanion toCompanion(bool nullToAbsent) {
    return ScheduleSettingsCompanion(
      labSpaceId: Value(labSpaceId),
      showSaturday:
          showSaturday == null && nullToAbsent
              ? const Value.absent()
              : Value(showSaturday),
      showSunday:
          showSunday == null && nullToAbsent
              ? const Value.absent()
              : Value(showSunday),
      dayStartTime: Value(dayStartTime),
      dayEndTime: Value(dayEndTime),
    );
  }

  factory ScheduleSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleSettingsRow(
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      showSaturday: serializer.fromJson<int?>(json['showSaturday']),
      showSunday: serializer.fromJson<int?>(json['showSunday']),
      dayStartTime: serializer.fromJson<String>(json['dayStartTime']),
      dayEndTime: serializer.fromJson<String>(json['dayEndTime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'showSaturday': serializer.toJson<int?>(showSaturday),
      'showSunday': serializer.toJson<int?>(showSunday),
      'dayStartTime': serializer.toJson<String>(dayStartTime),
      'dayEndTime': serializer.toJson<String>(dayEndTime),
    };
  }

  ScheduleSettingsRow copyWith({
    int? labSpaceId,
    Value<int?> showSaturday = const Value.absent(),
    Value<int?> showSunday = const Value.absent(),
    String? dayStartTime,
    String? dayEndTime,
  }) => ScheduleSettingsRow(
    labSpaceId: labSpaceId ?? this.labSpaceId,
    showSaturday: showSaturday.present ? showSaturday.value : this.showSaturday,
    showSunday: showSunday.present ? showSunday.value : this.showSunday,
    dayStartTime: dayStartTime ?? this.dayStartTime,
    dayEndTime: dayEndTime ?? this.dayEndTime,
  );
  ScheduleSettingsRow copyWithCompanion(ScheduleSettingsCompanion data) {
    return ScheduleSettingsRow(
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      showSaturday:
          data.showSaturday.present
              ? data.showSaturday.value
              : this.showSaturday,
      showSunday:
          data.showSunday.present ? data.showSunday.value : this.showSunday,
      dayStartTime:
          data.dayStartTime.present
              ? data.dayStartTime.value
              : this.dayStartTime,
      dayEndTime:
          data.dayEndTime.present ? data.dayEndTime.value : this.dayEndTime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleSettingsRow(')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('showSaturday: $showSaturday, ')
          ..write('showSunday: $showSunday, ')
          ..write('dayStartTime: $dayStartTime, ')
          ..write('dayEndTime: $dayEndTime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    labSpaceId,
    showSaturday,
    showSunday,
    dayStartTime,
    dayEndTime,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleSettingsRow &&
          other.labSpaceId == this.labSpaceId &&
          other.showSaturday == this.showSaturday &&
          other.showSunday == this.showSunday &&
          other.dayStartTime == this.dayStartTime &&
          other.dayEndTime == this.dayEndTime);
}

class ScheduleSettingsCompanion extends UpdateCompanion<ScheduleSettingsRow> {
  final Value<int> labSpaceId;
  final Value<int?> showSaturday;
  final Value<int?> showSunday;
  final Value<String> dayStartTime;
  final Value<String> dayEndTime;
  const ScheduleSettingsCompanion({
    this.labSpaceId = const Value.absent(),
    this.showSaturday = const Value.absent(),
    this.showSunday = const Value.absent(),
    this.dayStartTime = const Value.absent(),
    this.dayEndTime = const Value.absent(),
  });
  ScheduleSettingsCompanion.insert({
    this.labSpaceId = const Value.absent(),
    this.showSaturday = const Value.absent(),
    this.showSunday = const Value.absent(),
    this.dayStartTime = const Value.absent(),
    this.dayEndTime = const Value.absent(),
  });
  static Insertable<ScheduleSettingsRow> custom({
    Expression<int>? labSpaceId,
    Expression<int>? showSaturday,
    Expression<int>? showSunday,
    Expression<String>? dayStartTime,
    Expression<String>? dayEndTime,
  }) {
    return RawValuesInsertable({
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (showSaturday != null) 'show_saturday': showSaturday,
      if (showSunday != null) 'show_sunday': showSunday,
      if (dayStartTime != null) 'day_start_time': dayStartTime,
      if (dayEndTime != null) 'day_end_time': dayEndTime,
    });
  }

  ScheduleSettingsCompanion copyWith({
    Value<int>? labSpaceId,
    Value<int?>? showSaturday,
    Value<int?>? showSunday,
    Value<String>? dayStartTime,
    Value<String>? dayEndTime,
  }) {
    return ScheduleSettingsCompanion(
      labSpaceId: labSpaceId ?? this.labSpaceId,
      showSaturday: showSaturday ?? this.showSaturday,
      showSunday: showSunday ?? this.showSunday,
      dayStartTime: dayStartTime ?? this.dayStartTime,
      dayEndTime: dayEndTime ?? this.dayEndTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (showSaturday.present) {
      map['show_saturday'] = Variable<int>(showSaturday.value);
    }
    if (showSunday.present) {
      map['show_sunday'] = Variable<int>(showSunday.value);
    }
    if (dayStartTime.present) {
      map['day_start_time'] = Variable<String>(dayStartTime.value);
    }
    if (dayEndTime.present) {
      map['day_end_time'] = Variable<String>(dayEndTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleSettingsCompanion(')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('showSaturday: $showSaturday, ')
          ..write('showSunday: $showSunday, ')
          ..write('dayStartTime: $dayStartTime, ')
          ..write('dayEndTime: $dayEndTime')
          ..write(')'))
        .toString();
  }
}

class $ScheduleWeekNotesTable extends ScheduleWeekNotes
    with TableInfo<$ScheduleWeekNotesTable, ScheduleWeekNoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduleWeekNotesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _labSpaceIdMeta = const VerificationMeta(
    'labSpaceId',
  );
  @override
  late final GeneratedColumn<int> labSpaceId = GeneratedColumn<int>(
    'lab_space_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lab_spaces (id)',
    ),
  );
  static const VerificationMeta _weekStartDateMeta = const VerificationMeta(
    'weekStartDate',
  );
  @override
  late final GeneratedColumn<String> weekStartDate = GeneratedColumn<String>(
    'week_start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, labSpaceId, weekStartDate, note];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedule_week_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduleWeekNoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lab_space_id')) {
      context.handle(
        _labSpaceIdMeta,
        labSpaceId.isAcceptableOrUnknown(
          data['lab_space_id']!,
          _labSpaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_labSpaceIdMeta);
    }
    if (data.containsKey('week_start_date')) {
      context.handle(
        _weekStartDateMeta,
        weekStartDate.isAcceptableOrUnknown(
          data['week_start_date']!,
          _weekStartDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekStartDateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduleWeekNoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduleWeekNoteRow(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      labSpaceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}lab_space_id'],
          )!,
      weekStartDate:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}week_start_date'],
          )!,
      note:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}note'],
          )!,
    );
  }

  @override
  $ScheduleWeekNotesTable createAlias(String alias) {
    return $ScheduleWeekNotesTable(attachedDatabase, alias);
  }
}

class ScheduleWeekNoteRow extends DataClass
    implements Insertable<ScheduleWeekNoteRow> {
  final int id;
  final int labSpaceId;
  final String weekStartDate;
  final String note;
  const ScheduleWeekNoteRow({
    required this.id,
    required this.labSpaceId,
    required this.weekStartDate,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lab_space_id'] = Variable<int>(labSpaceId);
    map['week_start_date'] = Variable<String>(weekStartDate);
    map['note'] = Variable<String>(note);
    return map;
  }

  ScheduleWeekNotesCompanion toCompanion(bool nullToAbsent) {
    return ScheduleWeekNotesCompanion(
      id: Value(id),
      labSpaceId: Value(labSpaceId),
      weekStartDate: Value(weekStartDate),
      note: Value(note),
    );
  }

  factory ScheduleWeekNoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduleWeekNoteRow(
      id: serializer.fromJson<int>(json['id']),
      labSpaceId: serializer.fromJson<int>(json['labSpaceId']),
      weekStartDate: serializer.fromJson<String>(json['weekStartDate']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'labSpaceId': serializer.toJson<int>(labSpaceId),
      'weekStartDate': serializer.toJson<String>(weekStartDate),
      'note': serializer.toJson<String>(note),
    };
  }

  ScheduleWeekNoteRow copyWith({
    int? id,
    int? labSpaceId,
    String? weekStartDate,
    String? note,
  }) => ScheduleWeekNoteRow(
    id: id ?? this.id,
    labSpaceId: labSpaceId ?? this.labSpaceId,
    weekStartDate: weekStartDate ?? this.weekStartDate,
    note: note ?? this.note,
  );
  ScheduleWeekNoteRow copyWithCompanion(ScheduleWeekNotesCompanion data) {
    return ScheduleWeekNoteRow(
      id: data.id.present ? data.id.value : this.id,
      labSpaceId:
          data.labSpaceId.present ? data.labSpaceId.value : this.labSpaceId,
      weekStartDate:
          data.weekStartDate.present
              ? data.weekStartDate.value
              : this.weekStartDate,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleWeekNoteRow(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, labSpaceId, weekStartDate, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleWeekNoteRow &&
          other.id == this.id &&
          other.labSpaceId == this.labSpaceId &&
          other.weekStartDate == this.weekStartDate &&
          other.note == this.note);
}

class ScheduleWeekNotesCompanion extends UpdateCompanion<ScheduleWeekNoteRow> {
  final Value<int> id;
  final Value<int> labSpaceId;
  final Value<String> weekStartDate;
  final Value<String> note;
  const ScheduleWeekNotesCompanion({
    this.id = const Value.absent(),
    this.labSpaceId = const Value.absent(),
    this.weekStartDate = const Value.absent(),
    this.note = const Value.absent(),
  });
  ScheduleWeekNotesCompanion.insert({
    this.id = const Value.absent(),
    required int labSpaceId,
    required String weekStartDate,
    required String note,
  }) : labSpaceId = Value(labSpaceId),
       weekStartDate = Value(weekStartDate),
       note = Value(note);
  static Insertable<ScheduleWeekNoteRow> custom({
    Expression<int>? id,
    Expression<int>? labSpaceId,
    Expression<String>? weekStartDate,
    Expression<String>? note,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (labSpaceId != null) 'lab_space_id': labSpaceId,
      if (weekStartDate != null) 'week_start_date': weekStartDate,
      if (note != null) 'note': note,
    });
  }

  ScheduleWeekNotesCompanion copyWith({
    Value<int>? id,
    Value<int>? labSpaceId,
    Value<String>? weekStartDate,
    Value<String>? note,
  }) {
    return ScheduleWeekNotesCompanion(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      weekStartDate: weekStartDate ?? this.weekStartDate,
      note: note ?? this.note,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (labSpaceId.present) {
      map['lab_space_id'] = Variable<int>(labSpaceId.value);
    }
    if (weekStartDate.present) {
      map['week_start_date'] = Variable<String>(weekStartDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduleWeekNotesCompanion(')
          ..write('id: $id, ')
          ..write('labSpaceId: $labSpaceId, ')
          ..write('weekStartDate: $weekStartDate, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $NoteImagesTable noteImages = $NoteImagesTable(this);
  late final $NoteVersionsTable noteVersions = $NoteVersionsTable(this);
  late final $NoteTaskLinksTable noteTaskLinks = $NoteTaskLinksTable(this);
  late final $NoteBlocksTable noteBlocks = $NoteBlocksTable(this);
  late final $LabSpacesTable labSpaces = $LabSpacesTable(this);
  late final $KanbanColumnsTable kanbanColumns = $KanbanColumnsTable(this);
  late final $KanbanCardsTable kanbanCards = $KanbanCardsTable(this);
  late final $SpaceFolderLinksTable spaceFolderLinks = $SpaceFolderLinksTable(
    this,
  );
  late final $OnboardingFlagsTable onboardingFlags = $OnboardingFlagsTable(
    this,
  );
  late final $NotificationsTable notifications = $NotificationsTable(this);
  late final $ScheduleBlocksTable scheduleBlocks = $ScheduleBlocksTable(this);
  late final $ScheduleSettingsTable scheduleSettings = $ScheduleSettingsTable(
    this,
  );
  late final $ScheduleWeekNotesTable scheduleWeekNotes =
      $ScheduleWeekNotesTable(this);
  late final TasksDao tasksDao = TasksDao(this as AppDatabase);
  late final NotesDao notesDao = NotesDao(this as AppDatabase);
  late final NoteBlocksDao noteBlocksDao = NoteBlocksDao(this as AppDatabase);
  late final FoldersDao foldersDao = FoldersDao(this as AppDatabase);
  late final LabSpacesDao labSpacesDao = LabSpacesDao(this as AppDatabase);
  late final KanbanDao kanbanDao = KanbanDao(this as AppDatabase);
  late final NotificationsDao notificationsDao = NotificationsDao(
    this as AppDatabase,
  );
  late final ScheduleDao scheduleDao = ScheduleDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    folders,
    tasks,
    notes,
    noteImages,
    noteVersions,
    noteTaskLinks,
    noteBlocks,
    labSpaces,
    kanbanColumns,
    kanbanCards,
    spaceFolderLinks,
    onboardingFlags,
    notifications,
    scheduleBlocks,
    scheduleSettings,
    scheduleWeekNotes,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'notes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('note_blocks', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      required String name,
      required String color,
      Value<DateTime> createdAt,
      Value<DateTime?> deletedAt,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> color,
      Value<DateTime> createdAt,
      Value<DateTime?> deletedAt,
    });

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, FolderRow> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TasksTable, List<TaskRow>> _tasksRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tasks,
    aliasName: $_aliasNameGenerator(db.folders.id, db.tasks.folderId),
  );

  $$TasksTableProcessedTableManager get tasksRefs {
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tasksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NotesTable, List<NoteRow>> _notesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.notes,
    aliasName: $_aliasNameGenerator(db.folders.id, db.notes.folderId),
  );

  $$NotesTableProcessedTableManager get notesRefs {
    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_notesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpaceFolderLinksTable, List<SpaceFolderLinkRow>>
  _spaceFolderLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.spaceFolderLinks,
    aliasName: $_aliasNameGenerator(
      db.folders.id,
      db.spaceFolderLinks.folderId,
    ),
  );

  $$SpaceFolderLinksTableProcessedTableManager get spaceFolderLinksRefs {
    final manager = $$SpaceFolderLinksTableTableManager(
      $_db,
      $_db.spaceFolderLinks,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _spaceFolderLinksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> tasksRefs(
    Expression<bool> Function($$TasksTableFilterComposer f) f,
  ) {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> notesRefs(
    Expression<bool> Function($$NotesTableFilterComposer f) f,
  ) {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> spaceFolderLinksRefs(
    Expression<bool> Function($$SpaceFolderLinksTableFilterComposer f) f,
  ) {
    final $$SpaceFolderLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spaceFolderLinks,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpaceFolderLinksTableFilterComposer(
            $db: $db,
            $table: $db.spaceFolderLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> tasksRefs<T extends Object>(
    Expression<T> Function($$TasksTableAnnotationComposer a) f,
  ) {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> notesRefs<T extends Object>(
    Expression<T> Function($$NotesTableAnnotationComposer a) f,
  ) {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> spaceFolderLinksRefs<T extends Object>(
    Expression<T> Function($$SpaceFolderLinksTableAnnotationComposer a) f,
  ) {
    final $$SpaceFolderLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spaceFolderLinks,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpaceFolderLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.spaceFolderLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          FolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (FolderRow, $$FoldersTableReferences),
          FolderRow,
          PrefetchHooks Function({
            bool tasksRefs,
            bool notesRefs,
            bool spaceFolderLinksRefs,
          })
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                name: name,
                color: color,
                createdAt: createdAt,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String color,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                name: name,
                color: color,
                createdAt: createdAt,
                deletedAt: deletedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$FoldersTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            tasksRefs = false,
            notesRefs = false,
            spaceFolderLinksRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (tasksRefs) db.tasks,
                if (notesRefs) db.notes,
                if (spaceFolderLinksRefs) db.spaceFolderLinks,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tasksRefs)
                    await $_getPrefetchedData<
                      FolderRow,
                      $FoldersTable,
                      TaskRow
                    >(
                      currentTable: table,
                      referencedTable: $$FoldersTableReferences._tasksRefsTable(
                        db,
                      ),
                      managerFromTypedResult:
                          (p0) =>
                              $$FoldersTableReferences(db, table, p0).tasksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.folderId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (notesRefs)
                    await $_getPrefetchedData<
                      FolderRow,
                      $FoldersTable,
                      NoteRow
                    >(
                      currentTable: table,
                      referencedTable: $$FoldersTableReferences._notesRefsTable(
                        db,
                      ),
                      managerFromTypedResult:
                          (p0) =>
                              $$FoldersTableReferences(db, table, p0).notesRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.folderId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (spaceFolderLinksRefs)
                    await $_getPrefetchedData<
                      FolderRow,
                      $FoldersTable,
                      SpaceFolderLinkRow
                    >(
                      currentTable: table,
                      referencedTable: $$FoldersTableReferences
                          ._spaceFolderLinksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$FoldersTableReferences(
                                db,
                                table,
                                p0,
                              ).spaceFolderLinksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.folderId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      FolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRow, $$FoldersTableReferences),
      FolderRow,
      PrefetchHooks Function({
        bool tasksRefs,
        bool notesRefs,
        bool spaceFolderLinksRefs,
      })
    >;
typedef $$TasksTableCreateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      required String content,
      required String status,
      Value<int?> folderId,
      Value<DateTime> createdAt,
      required DateTime expiresAt,
      Value<DateTime?> trashedAt,
      Value<DateTime?> dueDate,
      Value<DateTime?> completedAt,
    });
typedef $$TasksTableUpdateCompanionBuilder =
    TasksCompanion Function({
      Value<int> id,
      Value<String> content,
      Value<String> status,
      Value<int?> folderId,
      Value<DateTime> createdAt,
      Value<DateTime> expiresAt,
      Value<DateTime?> trashedAt,
      Value<DateTime?> dueDate,
      Value<DateTime?> completedAt,
    });

final class $$TasksTableReferences
    extends BaseReferences<_$AppDatabase, $TasksTable, TaskRow> {
  $$TasksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _folderIdTable(_$AppDatabase db) => db.folders
      .createAlias($_aliasNameGenerator(db.tasks.folderId, db.folders.id));

  $$FoldersTableProcessedTableManager? get folderId {
    final $_column = $_itemColumn<int>('folder_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$NoteTaskLinksTable, List<NoteTaskLinkRow>>
  _noteTaskLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.noteTaskLinks,
    aliasName: $_aliasNameGenerator(db.tasks.id, db.noteTaskLinks.taskId),
  );

  $$NoteTaskLinksTableProcessedTableManager get noteTaskLinksRefs {
    final manager = $$NoteTaskLinksTableTableManager(
      $_db,
      $_db.noteTaskLinks,
    ).filter((f) => f.taskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteTaskLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$KanbanCardsTable, List<KanbanCardRow>>
  _kanbanCardsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.kanbanCards,
    aliasName: $_aliasNameGenerator(db.tasks.id, db.kanbanCards.originTaskId),
  );

  $$KanbanCardsTableProcessedTableManager get kanbanCardsRefs {
    final manager = $$KanbanCardsTableTableManager(
      $_db,
      $_db.kanbanCards,
    ).filter((f) => f.originTaskId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_kanbanCardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
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

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> noteTaskLinksRefs(
    Expression<bool> Function($$NoteTaskLinksTableFilterComposer f) f,
  ) {
    final $$NoteTaskLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTaskLinks,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTaskLinksTableFilterComposer(
            $db: $db,
            $table: $db.noteTaskLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> kanbanCardsRefs(
    Expression<bool> Function($$KanbanCardsTableFilterComposer f) f,
  ) {
    final $$KanbanCardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.originTaskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
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

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get trashedAt =>
      $composableBuilder(column: $table.trashedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> noteTaskLinksRefs<T extends Object>(
    Expression<T> Function($$NoteTaskLinksTableAnnotationComposer a) f,
  ) {
    final $$NoteTaskLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTaskLinks,
      getReferencedColumn: (t) => t.taskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTaskLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.noteTaskLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> kanbanCardsRefs<T extends Object>(
    Expression<T> Function($$KanbanCardsTableAnnotationComposer a) f,
  ) {
    final $$KanbanCardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.originTaskId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, $$TasksTableReferences),
          TaskRow,
          PrefetchHooks Function({
            bool folderId,
            bool noteTaskLinksRefs,
            bool kanbanCardsRefs,
          })
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                content: content,
                status: status,
                folderId: folderId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                trashedAt: trashedAt,
                dueDate: dueDate,
                completedAt: completedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String content,
                required String status,
                Value<int?> folderId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                required DateTime expiresAt,
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                content: content,
                status: status,
                folderId: folderId,
                createdAt: createdAt,
                expiresAt: expiresAt,
                trashedAt: trashedAt,
                dueDate: dueDate,
                completedAt: completedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$TasksTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            folderId = false,
            noteTaskLinksRefs = false,
            kanbanCardsRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (noteTaskLinksRefs) db.noteTaskLinks,
                if (kanbanCardsRefs) db.kanbanCards,
              ],
              addJoins: <
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
                if (folderId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.folderId,
                            referencedTable: $$TasksTableReferences
                                ._folderIdTable(db),
                            referencedColumn:
                                $$TasksTableReferences._folderIdTable(db).id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (noteTaskLinksRefs)
                    await $_getPrefetchedData<
                      TaskRow,
                      $TasksTable,
                      NoteTaskLinkRow
                    >(
                      currentTable: table,
                      referencedTable: $$TasksTableReferences
                          ._noteTaskLinksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).noteTaskLinksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.taskId == item.id),
                      typedResults: items,
                    ),
                  if (kanbanCardsRefs)
                    await $_getPrefetchedData<
                      TaskRow,
                      $TasksTable,
                      KanbanCardRow
                    >(
                      currentTable: table,
                      referencedTable: $$TasksTableReferences
                          ._kanbanCardsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$TasksTableReferences(
                                db,
                                table,
                                p0,
                              ).kanbanCardsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.originTaskId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, $$TasksTableReferences),
      TaskRow,
      PrefetchHooks Function({
        bool folderId,
        bool noteTaskLinksRefs,
        bool kanbanCardsRefs,
      })
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      required int folderId,
      Value<String?> title,
      Value<String> rawMarkdown,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> color,
      Value<String> kind,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<int> id,
      Value<int> folderId,
      Value<String?> title,
      Value<String> rawMarkdown,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> color,
      Value<String> kind,
    });

final class $$NotesTableReferences
    extends BaseReferences<_$AppDatabase, $NotesTable, NoteRow> {
  $$NotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _folderIdTable(_$AppDatabase db) => db.folders
      .createAlias($_aliasNameGenerator(db.notes.folderId, db.folders.id));

  $$FoldersTableProcessedTableManager get folderId {
    final $_column = $_itemColumn<int>('folder_id')!;

    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$NoteImagesTable, List<NoteImageRow>>
  _noteImagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.noteImages,
    aliasName: $_aliasNameGenerator(db.notes.id, db.noteImages.noteId),
  );

  $$NoteImagesTableProcessedTableManager get noteImagesRefs {
    final manager = $$NoteImagesTableTableManager(
      $_db,
      $_db.noteImages,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteImagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NoteVersionsTable, List<NoteVersionRow>>
  _noteVersionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.noteVersions,
    aliasName: $_aliasNameGenerator(db.notes.id, db.noteVersions.noteId),
  );

  $$NoteVersionsTableProcessedTableManager get noteVersionsRefs {
    final manager = $$NoteVersionsTableTableManager(
      $_db,
      $_db.noteVersions,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteVersionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NoteTaskLinksTable, List<NoteTaskLinkRow>>
  _noteTaskLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.noteTaskLinks,
    aliasName: $_aliasNameGenerator(db.notes.id, db.noteTaskLinks.noteId),
  );

  $$NoteTaskLinksTableProcessedTableManager get noteTaskLinksRefs {
    final manager = $$NoteTaskLinksTableTableManager(
      $_db,
      $_db.noteTaskLinks,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteTaskLinksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$NoteBlocksTable, List<NoteBlockRow>>
  _noteBlocksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.noteBlocks,
    aliasName: $_aliasNameGenerator(db.notes.id, db.noteBlocks.noteId),
  );

  $$NoteBlocksTableProcessedTableManager get noteBlocksRefs {
    final manager = $$NoteBlocksTableTableManager(
      $_db,
      $_db.noteBlocks,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_noteBlocksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$KanbanCardsTable, List<KanbanCardRow>>
  _kanbanCardsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.kanbanCards,
    aliasName: $_aliasNameGenerator(db.notes.id, db.kanbanCards.sourceNoteId),
  );

  $$KanbanCardsTableProcessedTableManager get kanbanCardsRefs {
    final manager = $$KanbanCardsTableTableManager(
      $_db,
      $_db.kanbanCards,
    ).filter((f) => f.sourceNoteId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_kanbanCardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
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

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> noteImagesRefs(
    Expression<bool> Function($$NoteImagesTableFilterComposer f) f,
  ) {
    final $$NoteImagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteImages,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteImagesTableFilterComposer(
            $db: $db,
            $table: $db.noteImages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> noteVersionsRefs(
    Expression<bool> Function($$NoteVersionsTableFilterComposer f) f,
  ) {
    final $$NoteVersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteVersions,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteVersionsTableFilterComposer(
            $db: $db,
            $table: $db.noteVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> noteTaskLinksRefs(
    Expression<bool> Function($$NoteTaskLinksTableFilterComposer f) f,
  ) {
    final $$NoteTaskLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTaskLinks,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTaskLinksTableFilterComposer(
            $db: $db,
            $table: $db.noteTaskLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> noteBlocksRefs(
    Expression<bool> Function($$NoteBlocksTableFilterComposer f) f,
  ) {
    final $$NoteBlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteBlocks,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteBlocksTableFilterComposer(
            $db: $db,
            $table: $db.noteBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> kanbanCardsRefs(
    Expression<bool> Function($$KanbanCardsTableFilterComposer f) f,
  ) {
    final $$KanbanCardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.sourceNoteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
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

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> noteImagesRefs<T extends Object>(
    Expression<T> Function($$NoteImagesTableAnnotationComposer a) f,
  ) {
    final $$NoteImagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteImages,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteImagesTableAnnotationComposer(
            $db: $db,
            $table: $db.noteImages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> noteVersionsRefs<T extends Object>(
    Expression<T> Function($$NoteVersionsTableAnnotationComposer a) f,
  ) {
    final $$NoteVersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteVersions,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteVersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.noteVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> noteTaskLinksRefs<T extends Object>(
    Expression<T> Function($$NoteTaskLinksTableAnnotationComposer a) f,
  ) {
    final $$NoteTaskLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteTaskLinks,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteTaskLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.noteTaskLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> noteBlocksRefs<T extends Object>(
    Expression<T> Function($$NoteBlocksTableAnnotationComposer a) f,
  ) {
    final $$NoteBlocksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.noteBlocks,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NoteBlocksTableAnnotationComposer(
            $db: $db,
            $table: $db.noteBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> kanbanCardsRefs<T extends Object>(
    Expression<T> Function($$KanbanCardsTableAnnotationComposer a) f,
  ) {
    final $$KanbanCardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.sourceNoteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          NoteRow,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteRow, $$NotesTableReferences),
          NoteRow,
          PrefetchHooks Function({
            bool folderId,
            bool noteImagesRefs,
            bool noteVersionsRefs,
            bool noteTaskLinksRefs,
            bool noteBlocksRefs,
            bool kanbanCardsRefs,
          })
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> folderId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> rawMarkdown = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String> kind = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                folderId: folderId,
                title: title,
                rawMarkdown: rawMarkdown,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                color: color,
                kind: kind,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int folderId,
                Value<String?> title = const Value.absent(),
                Value<String> rawMarkdown = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String> kind = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                folderId: folderId,
                title: title,
                rawMarkdown: rawMarkdown,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                color: color,
                kind: kind,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NotesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            folderId = false,
            noteImagesRefs = false,
            noteVersionsRefs = false,
            noteTaskLinksRefs = false,
            noteBlocksRefs = false,
            kanbanCardsRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (noteImagesRefs) db.noteImages,
                if (noteVersionsRefs) db.noteVersions,
                if (noteTaskLinksRefs) db.noteTaskLinks,
                if (noteBlocksRefs) db.noteBlocks,
                if (kanbanCardsRefs) db.kanbanCards,
              ],
              addJoins: <
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
                if (folderId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.folderId,
                            referencedTable: $$NotesTableReferences
                                ._folderIdTable(db),
                            referencedColumn:
                                $$NotesTableReferences._folderIdTable(db).id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (noteImagesRefs)
                    await $_getPrefetchedData<
                      NoteRow,
                      $NotesTable,
                      NoteImageRow
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._noteImagesRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).noteImagesRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                  if (noteVersionsRefs)
                    await $_getPrefetchedData<
                      NoteRow,
                      $NotesTable,
                      NoteVersionRow
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._noteVersionsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).noteVersionsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                  if (noteTaskLinksRefs)
                    await $_getPrefetchedData<
                      NoteRow,
                      $NotesTable,
                      NoteTaskLinkRow
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._noteTaskLinksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).noteTaskLinksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                  if (noteBlocksRefs)
                    await $_getPrefetchedData<
                      NoteRow,
                      $NotesTable,
                      NoteBlockRow
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._noteBlocksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).noteBlocksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.noteId == item.id),
                      typedResults: items,
                    ),
                  if (kanbanCardsRefs)
                    await $_getPrefetchedData<
                      NoteRow,
                      $NotesTable,
                      KanbanCardRow
                    >(
                      currentTable: table,
                      referencedTable: $$NotesTableReferences
                          ._kanbanCardsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).kanbanCardsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.sourceNoteId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      NoteRow,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteRow, $$NotesTableReferences),
      NoteRow,
      PrefetchHooks Function({
        bool folderId,
        bool noteImagesRefs,
        bool noteVersionsRefs,
        bool noteTaskLinksRefs,
        bool noteBlocksRefs,
        bool kanbanCardsRefs,
      })
    >;
typedef $$NoteImagesTableCreateCompanionBuilder =
    NoteImagesCompanion Function({
      Value<int> id,
      required int noteId,
      required String filename,
      required String filePath,
      required int sizeBytes,
      Value<DateTime> createdAt,
    });
typedef $$NoteImagesTableUpdateCompanionBuilder =
    NoteImagesCompanion Function({
      Value<int> id,
      Value<int> noteId,
      Value<String> filename,
      Value<String> filePath,
      Value<int> sizeBytes,
      Value<DateTime> createdAt,
    });

final class $$NoteImagesTableReferences
    extends BaseReferences<_$AppDatabase, $NoteImagesTable, NoteImageRow> {
  $$NoteImagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _noteIdTable(_$AppDatabase db) => db.notes.createAlias(
    $_aliasNameGenerator(db.noteImages.noteId, db.notes.id),
  );

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<int>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteImagesTableFilterComposer
    extends Composer<_$AppDatabase, $NoteImagesTable> {
  $$NoteImagesTableFilterComposer({
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

  ColumnFilters<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteImagesTable> {
  $$NoteImagesTableOrderingComposer({
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

  ColumnOrderings<String> get filename => $composableBuilder(
    column: $table.filename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteImagesTable> {
  $$NoteImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteImagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteImagesTable,
          NoteImageRow,
          $$NoteImagesTableFilterComposer,
          $$NoteImagesTableOrderingComposer,
          $$NoteImagesTableAnnotationComposer,
          $$NoteImagesTableCreateCompanionBuilder,
          $$NoteImagesTableUpdateCompanionBuilder,
          (NoteImageRow, $$NoteImagesTableReferences),
          NoteImageRow,
          PrefetchHooks Function({bool noteId})
        > {
  $$NoteImagesTableTableManager(_$AppDatabase db, $NoteImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NoteImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NoteImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NoteImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> noteId = const Value.absent(),
                Value<String> filename = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteImagesCompanion(
                id: id,
                noteId: noteId,
                filename: filename,
                filePath: filePath,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int noteId,
                required String filename,
                required String filePath,
                required int sizeBytes,
                Value<DateTime> createdAt = const Value.absent(),
              }) => NoteImagesCompanion.insert(
                id: id,
                noteId: noteId,
                filename: filename,
                filePath: filePath,
                sizeBytes: sizeBytes,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NoteImagesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({noteId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (noteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.noteId,
                            referencedTable: $$NoteImagesTableReferences
                                ._noteIdTable(db),
                            referencedColumn:
                                $$NoteImagesTableReferences._noteIdTable(db).id,
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

typedef $$NoteImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteImagesTable,
      NoteImageRow,
      $$NoteImagesTableFilterComposer,
      $$NoteImagesTableOrderingComposer,
      $$NoteImagesTableAnnotationComposer,
      $$NoteImagesTableCreateCompanionBuilder,
      $$NoteImagesTableUpdateCompanionBuilder,
      (NoteImageRow, $$NoteImagesTableReferences),
      NoteImageRow,
      PrefetchHooks Function({bool noteId})
    >;
typedef $$NoteVersionsTableCreateCompanionBuilder =
    NoteVersionsCompanion Function({
      Value<int> id,
      required int noteId,
      required String rawMarkdown,
      Value<DateTime> savedAt,
    });
typedef $$NoteVersionsTableUpdateCompanionBuilder =
    NoteVersionsCompanion Function({
      Value<int> id,
      Value<int> noteId,
      Value<String> rawMarkdown,
      Value<DateTime> savedAt,
    });

final class $$NoteVersionsTableReferences
    extends BaseReferences<_$AppDatabase, $NoteVersionsTable, NoteVersionRow> {
  $$NoteVersionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _noteIdTable(_$AppDatabase db) => db.notes.createAlias(
    $_aliasNameGenerator(db.noteVersions.noteId, db.notes.id),
  );

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<int>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableFilterComposer({
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

  ColumnFilters<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableOrderingComposer({
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

  ColumnOrderings<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteVersionsTable> {
  $$NoteVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rawMarkdown => $composableBuilder(
    column: $table.rawMarkdown,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteVersionsTable,
          NoteVersionRow,
          $$NoteVersionsTableFilterComposer,
          $$NoteVersionsTableOrderingComposer,
          $$NoteVersionsTableAnnotationComposer,
          $$NoteVersionsTableCreateCompanionBuilder,
          $$NoteVersionsTableUpdateCompanionBuilder,
          (NoteVersionRow, $$NoteVersionsTableReferences),
          NoteVersionRow,
          PrefetchHooks Function({bool noteId})
        > {
  $$NoteVersionsTableTableManager(_$AppDatabase db, $NoteVersionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NoteVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NoteVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$NoteVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> noteId = const Value.absent(),
                Value<String> rawMarkdown = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
              }) => NoteVersionsCompanion(
                id: id,
                noteId: noteId,
                rawMarkdown: rawMarkdown,
                savedAt: savedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int noteId,
                required String rawMarkdown,
                Value<DateTime> savedAt = const Value.absent(),
              }) => NoteVersionsCompanion.insert(
                id: id,
                noteId: noteId,
                rawMarkdown: rawMarkdown,
                savedAt: savedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NoteVersionsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({noteId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (noteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.noteId,
                            referencedTable: $$NoteVersionsTableReferences
                                ._noteIdTable(db),
                            referencedColumn:
                                $$NoteVersionsTableReferences
                                    ._noteIdTable(db)
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

typedef $$NoteVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteVersionsTable,
      NoteVersionRow,
      $$NoteVersionsTableFilterComposer,
      $$NoteVersionsTableOrderingComposer,
      $$NoteVersionsTableAnnotationComposer,
      $$NoteVersionsTableCreateCompanionBuilder,
      $$NoteVersionsTableUpdateCompanionBuilder,
      (NoteVersionRow, $$NoteVersionsTableReferences),
      NoteVersionRow,
      PrefetchHooks Function({bool noteId})
    >;
typedef $$NoteTaskLinksTableCreateCompanionBuilder =
    NoteTaskLinksCompanion Function({
      required int noteId,
      required int taskId,
      Value<int> rowid,
    });
typedef $$NoteTaskLinksTableUpdateCompanionBuilder =
    NoteTaskLinksCompanion Function({
      Value<int> noteId,
      Value<int> taskId,
      Value<int> rowid,
    });

final class $$NoteTaskLinksTableReferences
    extends
        BaseReferences<_$AppDatabase, $NoteTaskLinksTable, NoteTaskLinkRow> {
  $$NoteTaskLinksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NotesTable _noteIdTable(_$AppDatabase db) => db.notes.createAlias(
    $_aliasNameGenerator(db.noteTaskLinks.noteId, db.notes.id),
  );

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<int>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _taskIdTable(_$AppDatabase db) => db.tasks.createAlias(
    $_aliasNameGenerator(db.noteTaskLinks.taskId, db.tasks.id),
  );

  $$TasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<int>('task_id')!;

    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteTaskLinksTableFilterComposer
    extends Composer<_$AppDatabase, $NoteTaskLinksTable> {
  $$NoteTaskLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get taskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTaskLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteTaskLinksTable> {
  $$NoteTaskLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get taskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTaskLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteTaskLinksTable> {
  $$NoteTaskLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get taskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.taskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteTaskLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteTaskLinksTable,
          NoteTaskLinkRow,
          $$NoteTaskLinksTableFilterComposer,
          $$NoteTaskLinksTableOrderingComposer,
          $$NoteTaskLinksTableAnnotationComposer,
          $$NoteTaskLinksTableCreateCompanionBuilder,
          $$NoteTaskLinksTableUpdateCompanionBuilder,
          (NoteTaskLinkRow, $$NoteTaskLinksTableReferences),
          NoteTaskLinkRow,
          PrefetchHooks Function({bool noteId, bool taskId})
        > {
  $$NoteTaskLinksTableTableManager(_$AppDatabase db, $NoteTaskLinksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NoteTaskLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$NoteTaskLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NoteTaskLinksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> noteId = const Value.absent(),
                Value<int> taskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteTaskLinksCompanion(
                noteId: noteId,
                taskId: taskId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int noteId,
                required int taskId,
                Value<int> rowid = const Value.absent(),
              }) => NoteTaskLinksCompanion.insert(
                noteId: noteId,
                taskId: taskId,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NoteTaskLinksTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({noteId = false, taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (noteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.noteId,
                            referencedTable: $$NoteTaskLinksTableReferences
                                ._noteIdTable(db),
                            referencedColumn:
                                $$NoteTaskLinksTableReferences
                                    ._noteIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (taskId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.taskId,
                            referencedTable: $$NoteTaskLinksTableReferences
                                ._taskIdTable(db),
                            referencedColumn:
                                $$NoteTaskLinksTableReferences
                                    ._taskIdTable(db)
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

typedef $$NoteTaskLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteTaskLinksTable,
      NoteTaskLinkRow,
      $$NoteTaskLinksTableFilterComposer,
      $$NoteTaskLinksTableOrderingComposer,
      $$NoteTaskLinksTableAnnotationComposer,
      $$NoteTaskLinksTableCreateCompanionBuilder,
      $$NoteTaskLinksTableUpdateCompanionBuilder,
      (NoteTaskLinkRow, $$NoteTaskLinksTableReferences),
      NoteTaskLinkRow,
      PrefetchHooks Function({bool noteId, bool taskId})
    >;
typedef $$NoteBlocksTableCreateCompanionBuilder =
    NoteBlocksCompanion Function({
      Value<int> id,
      required int noteId,
      required int position,
      required String type,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$NoteBlocksTableUpdateCompanionBuilder =
    NoteBlocksCompanion Function({
      Value<int> id,
      Value<int> noteId,
      Value<int> position,
      Value<String> type,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$NoteBlocksTableReferences
    extends BaseReferences<_$AppDatabase, $NoteBlocksTable, NoteBlockRow> {
  $$NoteBlocksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _noteIdTable(_$AppDatabase db) => db.notes.createAlias(
    $_aliasNameGenerator(db.noteBlocks.noteId, db.notes.id),
  );

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<int>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NoteBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
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

  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
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

  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteBlocksTable> {
  $$NoteBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NoteBlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteBlocksTable,
          NoteBlockRow,
          $$NoteBlocksTableFilterComposer,
          $$NoteBlocksTableOrderingComposer,
          $$NoteBlocksTableAnnotationComposer,
          $$NoteBlocksTableCreateCompanionBuilder,
          $$NoteBlocksTableUpdateCompanionBuilder,
          (NoteBlockRow, $$NoteBlocksTableReferences),
          NoteBlockRow,
          PrefetchHooks Function({bool noteId})
        > {
  $$NoteBlocksTableTableManager(_$AppDatabase db, $NoteBlocksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NoteBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NoteBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NoteBlocksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> noteId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NoteBlocksCompanion(
                id: id,
                noteId: noteId,
                position: position,
                type: type,
                payload: payload,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int noteId,
                required int position,
                required String type,
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NoteBlocksCompanion.insert(
                id: id,
                noteId: noteId,
                position: position,
                type: type,
                payload: payload,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NoteBlocksTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({noteId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (noteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.noteId,
                            referencedTable: $$NoteBlocksTableReferences
                                ._noteIdTable(db),
                            referencedColumn:
                                $$NoteBlocksTableReferences._noteIdTable(db).id,
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

typedef $$NoteBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteBlocksTable,
      NoteBlockRow,
      $$NoteBlocksTableFilterComposer,
      $$NoteBlocksTableOrderingComposer,
      $$NoteBlocksTableAnnotationComposer,
      $$NoteBlocksTableCreateCompanionBuilder,
      $$NoteBlocksTableUpdateCompanionBuilder,
      (NoteBlockRow, $$NoteBlocksTableReferences),
      NoteBlockRow,
      PrefetchHooks Function({bool noteId})
    >;
typedef $$LabSpacesTableCreateCompanionBuilder =
    LabSpacesCompanion Function({
      Value<int> id,
      required String name,
      required String accentColor,
      Value<String> status,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<DateTime> createdAt,
      Value<DateTime?> deletedAt,
    });
typedef $$LabSpacesTableUpdateCompanionBuilder =
    LabSpacesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> accentColor,
      Value<String> status,
      Value<DateTime?> startDate,
      Value<DateTime?> dueDate,
      Value<DateTime> createdAt,
      Value<DateTime?> deletedAt,
    });

final class $$LabSpacesTableReferences
    extends BaseReferences<_$AppDatabase, $LabSpacesTable, LabSpaceRow> {
  $$LabSpacesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$KanbanColumnsTable, List<KanbanColumnRow>>
  _kanbanColumnsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.kanbanColumns,
    aliasName: $_aliasNameGenerator(
      db.labSpaces.id,
      db.kanbanColumns.labSpaceId,
    ),
  );

  $$KanbanColumnsTableProcessedTableManager get kanbanColumnsRefs {
    final manager = $$KanbanColumnsTableTableManager(
      $_db,
      $_db.kanbanColumns,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_kanbanColumnsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$KanbanCardsTable, List<KanbanCardRow>>
  _kanbanCardsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.kanbanCards,
    aliasName: $_aliasNameGenerator(db.labSpaces.id, db.kanbanCards.labSpaceId),
  );

  $$KanbanCardsTableProcessedTableManager get kanbanCardsRefs {
    final manager = $$KanbanCardsTableTableManager(
      $_db,
      $_db.kanbanCards,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_kanbanCardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SpaceFolderLinksTable, List<SpaceFolderLinkRow>>
  _spaceFolderLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.spaceFolderLinks,
    aliasName: $_aliasNameGenerator(
      db.labSpaces.id,
      db.spaceFolderLinks.labSpaceId,
    ),
  );

  $$SpaceFolderLinksTableProcessedTableManager get spaceFolderLinksRefs {
    final manager = $$SpaceFolderLinksTableTableManager(
      $_db,
      $_db.spaceFolderLinks,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _spaceFolderLinksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleBlocksTable, List<ScheduleBlockRow>>
  _scheduleBlocksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleBlocks,
    aliasName: $_aliasNameGenerator(
      db.labSpaces.id,
      db.scheduleBlocks.labSpaceId,
    ),
  );

  $$ScheduleBlocksTableProcessedTableManager get scheduleBlocksRefs {
    final manager = $$ScheduleBlocksTableTableManager(
      $_db,
      $_db.scheduleBlocks,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_scheduleBlocksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleSettingsTable, List<ScheduleSettingsRow>>
  _scheduleSettingsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scheduleSettings,
    aliasName: $_aliasNameGenerator(
      db.labSpaces.id,
      db.scheduleSettings.labSpaceId,
    ),
  );

  $$ScheduleSettingsTableProcessedTableManager get scheduleSettingsRefs {
    final manager = $$ScheduleSettingsTableTableManager(
      $_db,
      $_db.scheduleSettings,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleSettingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ScheduleWeekNotesTable, List<ScheduleWeekNoteRow>>
  _scheduleWeekNotesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.scheduleWeekNotes,
        aliasName: $_aliasNameGenerator(
          db.labSpaces.id,
          db.scheduleWeekNotes.labSpaceId,
        ),
      );

  $$ScheduleWeekNotesTableProcessedTableManager get scheduleWeekNotesRefs {
    final manager = $$ScheduleWeekNotesTableTableManager(
      $_db,
      $_db.scheduleWeekNotes,
    ).filter((f) => f.labSpaceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _scheduleWeekNotesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LabSpacesTableFilterComposer
    extends Composer<_$AppDatabase, $LabSpacesTable> {
  $$LabSpacesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> kanbanColumnsRefs(
    Expression<bool> Function($$KanbanColumnsTableFilterComposer f) f,
  ) {
    final $$KanbanColumnsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanColumns,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanColumnsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanColumns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> kanbanCardsRefs(
    Expression<bool> Function($$KanbanCardsTableFilterComposer f) f,
  ) {
    final $$KanbanCardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> spaceFolderLinksRefs(
    Expression<bool> Function($$SpaceFolderLinksTableFilterComposer f) f,
  ) {
    final $$SpaceFolderLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spaceFolderLinks,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpaceFolderLinksTableFilterComposer(
            $db: $db,
            $table: $db.spaceFolderLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleBlocksRefs(
    Expression<bool> Function($$ScheduleBlocksTableFilterComposer f) f,
  ) {
    final $$ScheduleBlocksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleBlocks,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleBlocksTableFilterComposer(
            $db: $db,
            $table: $db.scheduleBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleSettingsRefs(
    Expression<bool> Function($$ScheduleSettingsTableFilterComposer f) f,
  ) {
    final $$ScheduleSettingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleSettings,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleSettingsTableFilterComposer(
            $db: $db,
            $table: $db.scheduleSettings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> scheduleWeekNotesRefs(
    Expression<bool> Function($$ScheduleWeekNotesTableFilterComposer f) f,
  ) {
    final $$ScheduleWeekNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleWeekNotes,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleWeekNotesTableFilterComposer(
            $db: $db,
            $table: $db.scheduleWeekNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LabSpacesTableOrderingComposer
    extends Composer<_$AppDatabase, $LabSpacesTable> {
  $$LabSpacesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LabSpacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LabSpacesTable> {
  $$LabSpacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get accentColor => $composableBuilder(
    column: $table.accentColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> kanbanColumnsRefs<T extends Object>(
    Expression<T> Function($$KanbanColumnsTableAnnotationComposer a) f,
  ) {
    final $$KanbanColumnsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanColumns,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanColumnsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanColumns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> kanbanCardsRefs<T extends Object>(
    Expression<T> Function($$KanbanCardsTableAnnotationComposer a) f,
  ) {
    final $$KanbanCardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> spaceFolderLinksRefs<T extends Object>(
    Expression<T> Function($$SpaceFolderLinksTableAnnotationComposer a) f,
  ) {
    final $$SpaceFolderLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.spaceFolderLinks,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SpaceFolderLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.spaceFolderLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleBlocksRefs<T extends Object>(
    Expression<T> Function($$ScheduleBlocksTableAnnotationComposer a) f,
  ) {
    final $$ScheduleBlocksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleBlocks,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleBlocksTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleBlocks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleSettingsRefs<T extends Object>(
    Expression<T> Function($$ScheduleSettingsTableAnnotationComposer a) f,
  ) {
    final $$ScheduleSettingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scheduleSettings,
      getReferencedColumn: (t) => t.labSpaceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScheduleSettingsTableAnnotationComposer(
            $db: $db,
            $table: $db.scheduleSettings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> scheduleWeekNotesRefs<T extends Object>(
    Expression<T> Function($$ScheduleWeekNotesTableAnnotationComposer a) f,
  ) {
    final $$ScheduleWeekNotesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.scheduleWeekNotes,
          getReferencedColumn: (t) => t.labSpaceId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ScheduleWeekNotesTableAnnotationComposer(
                $db: $db,
                $table: $db.scheduleWeekNotes,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$LabSpacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LabSpacesTable,
          LabSpaceRow,
          $$LabSpacesTableFilterComposer,
          $$LabSpacesTableOrderingComposer,
          $$LabSpacesTableAnnotationComposer,
          $$LabSpacesTableCreateCompanionBuilder,
          $$LabSpacesTableUpdateCompanionBuilder,
          (LabSpaceRow, $$LabSpacesTableReferences),
          LabSpaceRow,
          PrefetchHooks Function({
            bool kanbanColumnsRefs,
            bool kanbanCardsRefs,
            bool spaceFolderLinksRefs,
            bool scheduleBlocksRefs,
            bool scheduleSettingsRefs,
            bool scheduleWeekNotesRefs,
          })
        > {
  $$LabSpacesTableTableManager(_$AppDatabase db, $LabSpacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$LabSpacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$LabSpacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$LabSpacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> accentColor = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => LabSpacesCompanion(
                id: id,
                name: name,
                accentColor: accentColor,
                status: status,
                startDate: startDate,
                dueDate: dueDate,
                createdAt: createdAt,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String accentColor,
                Value<String> status = const Value.absent(),
                Value<DateTime?> startDate = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
              }) => LabSpacesCompanion.insert(
                id: id,
                name: name,
                accentColor: accentColor,
                status: status,
                startDate: startDate,
                dueDate: dueDate,
                createdAt: createdAt,
                deletedAt: deletedAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$LabSpacesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            kanbanColumnsRefs = false,
            kanbanCardsRefs = false,
            spaceFolderLinksRefs = false,
            scheduleBlocksRefs = false,
            scheduleSettingsRefs = false,
            scheduleWeekNotesRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (kanbanColumnsRefs) db.kanbanColumns,
                if (kanbanCardsRefs) db.kanbanCards,
                if (spaceFolderLinksRefs) db.spaceFolderLinks,
                if (scheduleBlocksRefs) db.scheduleBlocks,
                if (scheduleSettingsRefs) db.scheduleSettings,
                if (scheduleWeekNotesRefs) db.scheduleWeekNotes,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (kanbanColumnsRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      KanbanColumnRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._kanbanColumnsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).kanbanColumnsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (kanbanCardsRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      KanbanCardRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._kanbanCardsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).kanbanCardsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (spaceFolderLinksRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      SpaceFolderLinkRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._spaceFolderLinksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).spaceFolderLinksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (scheduleBlocksRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      ScheduleBlockRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._scheduleBlocksRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleBlocksRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (scheduleSettingsRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      ScheduleSettingsRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._scheduleSettingsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleSettingsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                  if (scheduleWeekNotesRefs)
                    await $_getPrefetchedData<
                      LabSpaceRow,
                      $LabSpacesTable,
                      ScheduleWeekNoteRow
                    >(
                      currentTable: table,
                      referencedTable: $$LabSpacesTableReferences
                          ._scheduleWeekNotesRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$LabSpacesTableReferences(
                                db,
                                table,
                                p0,
                              ).scheduleWeekNotesRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.labSpaceId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LabSpacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LabSpacesTable,
      LabSpaceRow,
      $$LabSpacesTableFilterComposer,
      $$LabSpacesTableOrderingComposer,
      $$LabSpacesTableAnnotationComposer,
      $$LabSpacesTableCreateCompanionBuilder,
      $$LabSpacesTableUpdateCompanionBuilder,
      (LabSpaceRow, $$LabSpacesTableReferences),
      LabSpaceRow,
      PrefetchHooks Function({
        bool kanbanColumnsRefs,
        bool kanbanCardsRefs,
        bool spaceFolderLinksRefs,
        bool scheduleBlocksRefs,
        bool scheduleSettingsRefs,
        bool scheduleWeekNotesRefs,
      })
    >;
typedef $$KanbanColumnsTableCreateCompanionBuilder =
    KanbanColumnsCompanion Function({
      Value<int> id,
      required int labSpaceId,
      required String name,
      required int position,
      Value<bool> isDefault,
    });
typedef $$KanbanColumnsTableUpdateCompanionBuilder =
    KanbanColumnsCompanion Function({
      Value<int> id,
      Value<int> labSpaceId,
      Value<String> name,
      Value<int> position,
      Value<bool> isDefault,
    });

final class $$KanbanColumnsTableReferences
    extends
        BaseReferences<_$AppDatabase, $KanbanColumnsTable, KanbanColumnRow> {
  $$KanbanColumnsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.kanbanColumns.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$KanbanCardsTable, List<KanbanCardRow>>
  _kanbanCardsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.kanbanCards,
    aliasName: $_aliasNameGenerator(
      db.kanbanColumns.id,
      db.kanbanCards.columnId,
    ),
  );

  $$KanbanCardsTableProcessedTableManager get kanbanCardsRefs {
    final manager = $$KanbanCardsTableTableManager(
      $_db,
      $_db.kanbanCards,
    ).filter((f) => f.columnId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_kanbanCardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$KanbanColumnsTableFilterComposer
    extends Composer<_$AppDatabase, $KanbanColumnsTable> {
  $$KanbanColumnsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> kanbanCardsRefs(
    Expression<bool> Function($$KanbanCardsTableFilterComposer f) f,
  ) {
    final $$KanbanCardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.columnId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KanbanColumnsTableOrderingComposer
    extends Composer<_$AppDatabase, $KanbanColumnsTable> {
  $$KanbanColumnsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KanbanColumnsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KanbanColumnsTable> {
  $$KanbanColumnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> kanbanCardsRefs<T extends Object>(
    Expression<T> Function($$KanbanCardsTableAnnotationComposer a) f,
  ) {
    final $$KanbanCardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.kanbanCards,
      getReferencedColumn: (t) => t.columnId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanCardsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanCards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$KanbanColumnsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KanbanColumnsTable,
          KanbanColumnRow,
          $$KanbanColumnsTableFilterComposer,
          $$KanbanColumnsTableOrderingComposer,
          $$KanbanColumnsTableAnnotationComposer,
          $$KanbanColumnsTableCreateCompanionBuilder,
          $$KanbanColumnsTableUpdateCompanionBuilder,
          (KanbanColumnRow, $$KanbanColumnsTableReferences),
          KanbanColumnRow,
          PrefetchHooks Function({bool labSpaceId, bool kanbanCardsRefs})
        > {
  $$KanbanColumnsTableTableManager(_$AppDatabase db, $KanbanColumnsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$KanbanColumnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$KanbanColumnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$KanbanColumnsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> labSpaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
              }) => KanbanColumnsCompanion(
                id: id,
                labSpaceId: labSpaceId,
                name: name,
                position: position,
                isDefault: isDefault,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int labSpaceId,
                required String name,
                required int position,
                Value<bool> isDefault = const Value.absent(),
              }) => KanbanColumnsCompanion.insert(
                id: id,
                labSpaceId: labSpaceId,
                name: name,
                position: position,
                isDefault: isDefault,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$KanbanColumnsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            labSpaceId = false,
            kanbanCardsRefs = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (kanbanCardsRefs) db.kanbanCards],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$KanbanColumnsTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$KanbanColumnsTableReferences
                                    ._labSpaceIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (kanbanCardsRefs)
                    await $_getPrefetchedData<
                      KanbanColumnRow,
                      $KanbanColumnsTable,
                      KanbanCardRow
                    >(
                      currentTable: table,
                      referencedTable: $$KanbanColumnsTableReferences
                          ._kanbanCardsRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$KanbanColumnsTableReferences(
                                db,
                                table,
                                p0,
                              ).kanbanCardsRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) => referencedItems.where(
                            (e) => e.columnId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$KanbanColumnsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KanbanColumnsTable,
      KanbanColumnRow,
      $$KanbanColumnsTableFilterComposer,
      $$KanbanColumnsTableOrderingComposer,
      $$KanbanColumnsTableAnnotationComposer,
      $$KanbanColumnsTableCreateCompanionBuilder,
      $$KanbanColumnsTableUpdateCompanionBuilder,
      (KanbanColumnRow, $$KanbanColumnsTableReferences),
      KanbanColumnRow,
      PrefetchHooks Function({bool labSpaceId, bool kanbanCardsRefs})
    >;
typedef $$KanbanCardsTableCreateCompanionBuilder =
    KanbanCardsCompanion Function({
      Value<int> id,
      required int labSpaceId,
      required int columnId,
      required String title,
      Value<String?> description,
      Value<String> priority,
      required int position,
      Value<DateTime?> dueDate,
      Value<int?> sourceNoteId,
      Value<String?> sourceAnchor,
      Value<int?> originTaskId,
      Value<int?> originFolderColor,
      Value<DateTime?> originTaskDoneAt,
      Value<DateTime> createdAt,
    });
typedef $$KanbanCardsTableUpdateCompanionBuilder =
    KanbanCardsCompanion Function({
      Value<int> id,
      Value<int> labSpaceId,
      Value<int> columnId,
      Value<String> title,
      Value<String?> description,
      Value<String> priority,
      Value<int> position,
      Value<DateTime?> dueDate,
      Value<int?> sourceNoteId,
      Value<String?> sourceAnchor,
      Value<int?> originTaskId,
      Value<int?> originFolderColor,
      Value<DateTime?> originTaskDoneAt,
      Value<DateTime> createdAt,
    });

final class $$KanbanCardsTableReferences
    extends BaseReferences<_$AppDatabase, $KanbanCardsTable, KanbanCardRow> {
  $$KanbanCardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.kanbanCards.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $KanbanColumnsTable _columnIdTable(_$AppDatabase db) =>
      db.kanbanColumns.createAlias(
        $_aliasNameGenerator(db.kanbanCards.columnId, db.kanbanColumns.id),
      );

  $$KanbanColumnsTableProcessedTableManager get columnId {
    final $_column = $_itemColumn<int>('column_id')!;

    final manager = $$KanbanColumnsTableTableManager(
      $_db,
      $_db.kanbanColumns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_columnIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NotesTable _sourceNoteIdTable(_$AppDatabase db) =>
      db.notes.createAlias(
        $_aliasNameGenerator(db.kanbanCards.sourceNoteId, db.notes.id),
      );

  $$NotesTableProcessedTableManager? get sourceNoteId {
    final $_column = $_itemColumn<int>('source_note_id');
    if ($_column == null) return null;
    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceNoteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TasksTable _originTaskIdTable(_$AppDatabase db) =>
      db.tasks.createAlias(
        $_aliasNameGenerator(db.kanbanCards.originTaskId, db.tasks.id),
      );

  $$TasksTableProcessedTableManager? get originTaskId {
    final $_column = $_itemColumn<int>('origin_task_id');
    if ($_column == null) return null;
    final manager = $$TasksTableTableManager(
      $_db,
      $_db.tasks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_originTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$KanbanCardsTableFilterComposer
    extends Composer<_$AppDatabase, $KanbanCardsTable> {
  $$KanbanCardsTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceAnchor => $composableBuilder(
    column: $table.sourceAnchor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get originFolderColor => $composableBuilder(
    column: $table.originFolderColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get originTaskDoneAt => $composableBuilder(
    column: $table.originTaskDoneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KanbanColumnsTableFilterComposer get columnId {
    final $$KanbanColumnsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.columnId,
      referencedTable: $db.kanbanColumns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanColumnsTableFilterComposer(
            $db: $db,
            $table: $db.kanbanColumns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableFilterComposer get sourceNoteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableFilterComposer get originTaskId {
    final $$TasksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableFilterComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KanbanCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $KanbanCardsTable> {
  $$KanbanCardsTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceAnchor => $composableBuilder(
    column: $table.sourceAnchor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get originFolderColor => $composableBuilder(
    column: $table.originFolderColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get originTaskDoneAt => $composableBuilder(
    column: $table.originTaskDoneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KanbanColumnsTableOrderingComposer get columnId {
    final $$KanbanColumnsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.columnId,
      referencedTable: $db.kanbanColumns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanColumnsTableOrderingComposer(
            $db: $db,
            $table: $db.kanbanColumns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableOrderingComposer get sourceNoteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableOrderingComposer get originTaskId {
    final $$TasksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableOrderingComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KanbanCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KanbanCardsTable> {
  $$KanbanCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get sourceAnchor => $composableBuilder(
    column: $table.sourceAnchor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get originFolderColor => $composableBuilder(
    column: $table.originFolderColor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get originTaskDoneAt => $composableBuilder(
    column: $table.originTaskDoneAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$KanbanColumnsTableAnnotationComposer get columnId {
    final $$KanbanColumnsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.columnId,
      referencedTable: $db.kanbanColumns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$KanbanColumnsTableAnnotationComposer(
            $db: $db,
            $table: $db.kanbanColumns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NotesTableAnnotationComposer get sourceNoteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TasksTableAnnotationComposer get originTaskId {
    final $$TasksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.originTaskId,
      referencedTable: $db.tasks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TasksTableAnnotationComposer(
            $db: $db,
            $table: $db.tasks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$KanbanCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KanbanCardsTable,
          KanbanCardRow,
          $$KanbanCardsTableFilterComposer,
          $$KanbanCardsTableOrderingComposer,
          $$KanbanCardsTableAnnotationComposer,
          $$KanbanCardsTableCreateCompanionBuilder,
          $$KanbanCardsTableUpdateCompanionBuilder,
          (KanbanCardRow, $$KanbanCardsTableReferences),
          KanbanCardRow,
          PrefetchHooks Function({
            bool labSpaceId,
            bool columnId,
            bool sourceNoteId,
            bool originTaskId,
          })
        > {
  $$KanbanCardsTableTableManager(_$AppDatabase db, $KanbanCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$KanbanCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$KanbanCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$KanbanCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> labSpaceId = const Value.absent(),
                Value<int> columnId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> sourceNoteId = const Value.absent(),
                Value<String?> sourceAnchor = const Value.absent(),
                Value<int?> originTaskId = const Value.absent(),
                Value<int?> originFolderColor = const Value.absent(),
                Value<DateTime?> originTaskDoneAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => KanbanCardsCompanion(
                id: id,
                labSpaceId: labSpaceId,
                columnId: columnId,
                title: title,
                description: description,
                priority: priority,
                position: position,
                dueDate: dueDate,
                sourceNoteId: sourceNoteId,
                sourceAnchor: sourceAnchor,
                originTaskId: originTaskId,
                originFolderColor: originFolderColor,
                originTaskDoneAt: originTaskDoneAt,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int labSpaceId,
                required int columnId,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String> priority = const Value.absent(),
                required int position,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<int?> sourceNoteId = const Value.absent(),
                Value<String?> sourceAnchor = const Value.absent(),
                Value<int?> originTaskId = const Value.absent(),
                Value<int?> originFolderColor = const Value.absent(),
                Value<DateTime?> originTaskDoneAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => KanbanCardsCompanion.insert(
                id: id,
                labSpaceId: labSpaceId,
                columnId: columnId,
                title: title,
                description: description,
                priority: priority,
                position: position,
                dueDate: dueDate,
                sourceNoteId: sourceNoteId,
                sourceAnchor: sourceAnchor,
                originTaskId: originTaskId,
                originFolderColor: originFolderColor,
                originTaskDoneAt: originTaskDoneAt,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$KanbanCardsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({
            labSpaceId = false,
            columnId = false,
            sourceNoteId = false,
            originTaskId = false,
          }) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$KanbanCardsTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$KanbanCardsTableReferences
                                    ._labSpaceIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (columnId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.columnId,
                            referencedTable: $$KanbanCardsTableReferences
                                ._columnIdTable(db),
                            referencedColumn:
                                $$KanbanCardsTableReferences
                                    ._columnIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (sourceNoteId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.sourceNoteId,
                            referencedTable: $$KanbanCardsTableReferences
                                ._sourceNoteIdTable(db),
                            referencedColumn:
                                $$KanbanCardsTableReferences
                                    ._sourceNoteIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (originTaskId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.originTaskId,
                            referencedTable: $$KanbanCardsTableReferences
                                ._originTaskIdTable(db),
                            referencedColumn:
                                $$KanbanCardsTableReferences
                                    ._originTaskIdTable(db)
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

typedef $$KanbanCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KanbanCardsTable,
      KanbanCardRow,
      $$KanbanCardsTableFilterComposer,
      $$KanbanCardsTableOrderingComposer,
      $$KanbanCardsTableAnnotationComposer,
      $$KanbanCardsTableCreateCompanionBuilder,
      $$KanbanCardsTableUpdateCompanionBuilder,
      (KanbanCardRow, $$KanbanCardsTableReferences),
      KanbanCardRow,
      PrefetchHooks Function({
        bool labSpaceId,
        bool columnId,
        bool sourceNoteId,
        bool originTaskId,
      })
    >;
typedef $$SpaceFolderLinksTableCreateCompanionBuilder =
    SpaceFolderLinksCompanion Function({
      required int labSpaceId,
      required int folderId,
      Value<int> rowid,
    });
typedef $$SpaceFolderLinksTableUpdateCompanionBuilder =
    SpaceFolderLinksCompanion Function({
      Value<int> labSpaceId,
      Value<int> folderId,
      Value<int> rowid,
    });

final class $$SpaceFolderLinksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SpaceFolderLinksTable,
          SpaceFolderLinkRow
        > {
  $$SpaceFolderLinksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.spaceFolderLinks.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FoldersTable _folderIdTable(_$AppDatabase db) =>
      db.folders.createAlias(
        $_aliasNameGenerator(db.spaceFolderLinks.folderId, db.folders.id),
      );

  $$FoldersTableProcessedTableManager get folderId {
    final $_column = $_itemColumn<int>('folder_id')!;

    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SpaceFolderLinksTableFilterComposer
    extends Composer<_$AppDatabase, $SpaceFolderLinksTable> {
  $$SpaceFolderLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpaceFolderLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $SpaceFolderLinksTable> {
  $$SpaceFolderLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpaceFolderLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $SpaceFolderLinksTable> {
  $$SpaceFolderLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SpaceFolderLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SpaceFolderLinksTable,
          SpaceFolderLinkRow,
          $$SpaceFolderLinksTableFilterComposer,
          $$SpaceFolderLinksTableOrderingComposer,
          $$SpaceFolderLinksTableAnnotationComposer,
          $$SpaceFolderLinksTableCreateCompanionBuilder,
          $$SpaceFolderLinksTableUpdateCompanionBuilder,
          (SpaceFolderLinkRow, $$SpaceFolderLinksTableReferences),
          SpaceFolderLinkRow,
          PrefetchHooks Function({bool labSpaceId, bool folderId})
        > {
  $$SpaceFolderLinksTableTableManager(
    _$AppDatabase db,
    $SpaceFolderLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$SpaceFolderLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$SpaceFolderLinksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$SpaceFolderLinksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> labSpaceId = const Value.absent(),
                Value<int> folderId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SpaceFolderLinksCompanion(
                labSpaceId: labSpaceId,
                folderId: folderId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int labSpaceId,
                required int folderId,
                Value<int> rowid = const Value.absent(),
              }) => SpaceFolderLinksCompanion.insert(
                labSpaceId: labSpaceId,
                folderId: folderId,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$SpaceFolderLinksTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({labSpaceId = false, folderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$SpaceFolderLinksTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$SpaceFolderLinksTableReferences
                                    ._labSpaceIdTable(db)
                                    .id,
                          )
                          as T;
                }
                if (folderId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.folderId,
                            referencedTable: $$SpaceFolderLinksTableReferences
                                ._folderIdTable(db),
                            referencedColumn:
                                $$SpaceFolderLinksTableReferences
                                    ._folderIdTable(db)
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

typedef $$SpaceFolderLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SpaceFolderLinksTable,
      SpaceFolderLinkRow,
      $$SpaceFolderLinksTableFilterComposer,
      $$SpaceFolderLinksTableOrderingComposer,
      $$SpaceFolderLinksTableAnnotationComposer,
      $$SpaceFolderLinksTableCreateCompanionBuilder,
      $$SpaceFolderLinksTableUpdateCompanionBuilder,
      (SpaceFolderLinkRow, $$SpaceFolderLinksTableReferences),
      SpaceFolderLinkRow,
      PrefetchHooks Function({bool labSpaceId, bool folderId})
    >;
typedef $$OnboardingFlagsTableCreateCompanionBuilder =
    OnboardingFlagsCompanion Function({
      required String key,
      required DateTime seenAt,
      Value<int> rowid,
    });
typedef $$OnboardingFlagsTableUpdateCompanionBuilder =
    OnboardingFlagsCompanion Function({
      Value<String> key,
      Value<DateTime> seenAt,
      Value<int> rowid,
    });

class $$OnboardingFlagsTableFilterComposer
    extends Composer<_$AppDatabase, $OnboardingFlagsTable> {
  $$OnboardingFlagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OnboardingFlagsTableOrderingComposer
    extends Composer<_$AppDatabase, $OnboardingFlagsTable> {
  $$OnboardingFlagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OnboardingFlagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OnboardingFlagsTable> {
  $$OnboardingFlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<DateTime> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);
}

class $$OnboardingFlagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OnboardingFlagsTable,
          OnboardingFlagRow,
          $$OnboardingFlagsTableFilterComposer,
          $$OnboardingFlagsTableOrderingComposer,
          $$OnboardingFlagsTableAnnotationComposer,
          $$OnboardingFlagsTableCreateCompanionBuilder,
          $$OnboardingFlagsTableUpdateCompanionBuilder,
          (
            OnboardingFlagRow,
            BaseReferences<
              _$AppDatabase,
              $OnboardingFlagsTable,
              OnboardingFlagRow
            >,
          ),
          OnboardingFlagRow,
          PrefetchHooks Function()
        > {
  $$OnboardingFlagsTableTableManager(
    _$AppDatabase db,
    $OnboardingFlagsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$OnboardingFlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$OnboardingFlagsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$OnboardingFlagsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<DateTime> seenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OnboardingFlagsCompanion(
                key: key,
                seenAt: seenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required DateTime seenAt,
                Value<int> rowid = const Value.absent(),
              }) => OnboardingFlagsCompanion.insert(
                key: key,
                seenAt: seenAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OnboardingFlagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OnboardingFlagsTable,
      OnboardingFlagRow,
      $$OnboardingFlagsTableFilterComposer,
      $$OnboardingFlagsTableOrderingComposer,
      $$OnboardingFlagsTableAnnotationComposer,
      $$OnboardingFlagsTableCreateCompanionBuilder,
      $$OnboardingFlagsTableUpdateCompanionBuilder,
      (
        OnboardingFlagRow,
        BaseReferences<_$AppDatabase, $OnboardingFlagsTable, OnboardingFlagRow>,
      ),
      OnboardingFlagRow,
      PrefetchHooks Function()
    >;
typedef $$NotificationsTableCreateCompanionBuilder =
    NotificationsCompanion Function({
      Value<int> id,
      required String message,
      Value<DateTime> createdAt,
    });
typedef $$NotificationsTableUpdateCompanionBuilder =
    NotificationsCompanion Function({
      Value<int> id,
      Value<String> message,
      Value<DateTime> createdAt,
    });

class $$NotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableFilterComposer({
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

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableOrderingComposer({
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

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationsTable> {
  $$NotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NotificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationsTable,
          NotificationRow,
          $$NotificationsTableFilterComposer,
          $$NotificationsTableOrderingComposer,
          $$NotificationsTableAnnotationComposer,
          $$NotificationsTableCreateCompanionBuilder,
          $$NotificationsTableUpdateCompanionBuilder,
          (
            NotificationRow,
            BaseReferences<_$AppDatabase, $NotificationsTable, NotificationRow>,
          ),
          NotificationRow,
          PrefetchHooks Function()
        > {
  $$NotificationsTableTableManager(_$AppDatabase db, $NotificationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$NotificationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NotificationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NotificationsCompanion(
                id: id,
                message: message,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String message,
                Value<DateTime> createdAt = const Value.absent(),
              }) => NotificationsCompanion.insert(
                id: id,
                message: message,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationsTable,
      NotificationRow,
      $$NotificationsTableFilterComposer,
      $$NotificationsTableOrderingComposer,
      $$NotificationsTableAnnotationComposer,
      $$NotificationsTableCreateCompanionBuilder,
      $$NotificationsTableUpdateCompanionBuilder,
      (
        NotificationRow,
        BaseReferences<_$AppDatabase, $NotificationsTable, NotificationRow>,
      ),
      NotificationRow,
      PrefetchHooks Function()
    >;
typedef $$ScheduleBlocksTableCreateCompanionBuilder =
    ScheduleBlocksCompanion Function({
      Value<int> id,
      required int labSpaceId,
      Value<int?> folderId,
      required String title,
      Value<String?> location,
      required String startTime,
      required String endTime,
      required String days,
      required String color,
      Value<int> useFolderColor,
      Value<DateTime> createdAt,
    });
typedef $$ScheduleBlocksTableUpdateCompanionBuilder =
    ScheduleBlocksCompanion Function({
      Value<int> id,
      Value<int> labSpaceId,
      Value<int?> folderId,
      Value<String> title,
      Value<String?> location,
      Value<String> startTime,
      Value<String> endTime,
      Value<String> days,
      Value<String> color,
      Value<int> useFolderColor,
      Value<DateTime> createdAt,
    });

final class $$ScheduleBlocksTableReferences
    extends
        BaseReferences<_$AppDatabase, $ScheduleBlocksTable, ScheduleBlockRow> {
  $$ScheduleBlocksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.scheduleBlocks.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ScheduleBlocksTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleBlocksTable> {
  $$ScheduleBlocksTableFilterComposer({
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

  ColumnFilters<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get days => $composableBuilder(
    column: $table.days,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useFolderColor => $composableBuilder(
    column: $table.useFolderColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleBlocksTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleBlocksTable> {
  $$ScheduleBlocksTableOrderingComposer({
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

  ColumnOrderings<int> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get days => $composableBuilder(
    column: $table.days,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useFolderColor => $composableBuilder(
    column: $table.useFolderColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleBlocksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleBlocksTable> {
  $$ScheduleBlocksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<String> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<String> get days =>
      $composableBuilder(column: $table.days, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get useFolderColor => $composableBuilder(
    column: $table.useFolderColor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleBlocksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleBlocksTable,
          ScheduleBlockRow,
          $$ScheduleBlocksTableFilterComposer,
          $$ScheduleBlocksTableOrderingComposer,
          $$ScheduleBlocksTableAnnotationComposer,
          $$ScheduleBlocksTableCreateCompanionBuilder,
          $$ScheduleBlocksTableUpdateCompanionBuilder,
          (ScheduleBlockRow, $$ScheduleBlocksTableReferences),
          ScheduleBlockRow,
          PrefetchHooks Function({bool labSpaceId})
        > {
  $$ScheduleBlocksTableTableManager(
    _$AppDatabase db,
    $ScheduleBlocksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ScheduleBlocksTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$ScheduleBlocksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$ScheduleBlocksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> labSpaceId = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String> startTime = const Value.absent(),
                Value<String> endTime = const Value.absent(),
                Value<String> days = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int> useFolderColor = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ScheduleBlocksCompanion(
                id: id,
                labSpaceId: labSpaceId,
                folderId: folderId,
                title: title,
                location: location,
                startTime: startTime,
                endTime: endTime,
                days: days,
                color: color,
                useFolderColor: useFolderColor,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int labSpaceId,
                Value<int?> folderId = const Value.absent(),
                required String title,
                Value<String?> location = const Value.absent(),
                required String startTime,
                required String endTime,
                required String days,
                required String color,
                Value<int> useFolderColor = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ScheduleBlocksCompanion.insert(
                id: id,
                labSpaceId: labSpaceId,
                folderId: folderId,
                title: title,
                location: location,
                startTime: startTime,
                endTime: endTime,
                days: days,
                color: color,
                useFolderColor: useFolderColor,
                createdAt: createdAt,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ScheduleBlocksTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({labSpaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$ScheduleBlocksTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$ScheduleBlocksTableReferences
                                    ._labSpaceIdTable(db)
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

typedef $$ScheduleBlocksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleBlocksTable,
      ScheduleBlockRow,
      $$ScheduleBlocksTableFilterComposer,
      $$ScheduleBlocksTableOrderingComposer,
      $$ScheduleBlocksTableAnnotationComposer,
      $$ScheduleBlocksTableCreateCompanionBuilder,
      $$ScheduleBlocksTableUpdateCompanionBuilder,
      (ScheduleBlockRow, $$ScheduleBlocksTableReferences),
      ScheduleBlockRow,
      PrefetchHooks Function({bool labSpaceId})
    >;
typedef $$ScheduleSettingsTableCreateCompanionBuilder =
    ScheduleSettingsCompanion Function({
      Value<int> labSpaceId,
      Value<int?> showSaturday,
      Value<int?> showSunday,
      Value<String> dayStartTime,
      Value<String> dayEndTime,
    });
typedef $$ScheduleSettingsTableUpdateCompanionBuilder =
    ScheduleSettingsCompanion Function({
      Value<int> labSpaceId,
      Value<int?> showSaturday,
      Value<int?> showSunday,
      Value<String> dayStartTime,
      Value<String> dayEndTime,
    });

final class $$ScheduleSettingsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ScheduleSettingsTable,
          ScheduleSettingsRow
        > {
  $$ScheduleSettingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.scheduleSettings.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ScheduleSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleSettingsTable> {
  $$ScheduleSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get showSaturday => $composableBuilder(
    column: $table.showSaturday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get showSunday => $composableBuilder(
    column: $table.showSunday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayStartTime => $composableBuilder(
    column: $table.dayStartTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayEndTime => $composableBuilder(
    column: $table.dayEndTime,
    builder: (column) => ColumnFilters(column),
  );

  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleSettingsTable> {
  $$ScheduleSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get showSaturday => $composableBuilder(
    column: $table.showSaturday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get showSunday => $composableBuilder(
    column: $table.showSunday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayStartTime => $composableBuilder(
    column: $table.dayStartTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayEndTime => $composableBuilder(
    column: $table.dayEndTime,
    builder: (column) => ColumnOrderings(column),
  );

  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleSettingsTable> {
  $$ScheduleSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get showSaturday => $composableBuilder(
    column: $table.showSaturday,
    builder: (column) => column,
  );

  GeneratedColumn<int> get showSunday => $composableBuilder(
    column: $table.showSunday,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dayStartTime => $composableBuilder(
    column: $table.dayStartTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dayEndTime => $composableBuilder(
    column: $table.dayEndTime,
    builder: (column) => column,
  );

  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleSettingsTable,
          ScheduleSettingsRow,
          $$ScheduleSettingsTableFilterComposer,
          $$ScheduleSettingsTableOrderingComposer,
          $$ScheduleSettingsTableAnnotationComposer,
          $$ScheduleSettingsTableCreateCompanionBuilder,
          $$ScheduleSettingsTableUpdateCompanionBuilder,
          (ScheduleSettingsRow, $$ScheduleSettingsTableReferences),
          ScheduleSettingsRow,
          PrefetchHooks Function({bool labSpaceId})
        > {
  $$ScheduleSettingsTableTableManager(
    _$AppDatabase db,
    $ScheduleSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$ScheduleSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$ScheduleSettingsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ScheduleSettingsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> labSpaceId = const Value.absent(),
                Value<int?> showSaturday = const Value.absent(),
                Value<int?> showSunday = const Value.absent(),
                Value<String> dayStartTime = const Value.absent(),
                Value<String> dayEndTime = const Value.absent(),
              }) => ScheduleSettingsCompanion(
                labSpaceId: labSpaceId,
                showSaturday: showSaturday,
                showSunday: showSunday,
                dayStartTime: dayStartTime,
                dayEndTime: dayEndTime,
              ),
          createCompanionCallback:
              ({
                Value<int> labSpaceId = const Value.absent(),
                Value<int?> showSaturday = const Value.absent(),
                Value<int?> showSunday = const Value.absent(),
                Value<String> dayStartTime = const Value.absent(),
                Value<String> dayEndTime = const Value.absent(),
              }) => ScheduleSettingsCompanion.insert(
                labSpaceId: labSpaceId,
                showSaturday: showSaturday,
                showSunday: showSunday,
                dayStartTime: dayStartTime,
                dayEndTime: dayEndTime,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ScheduleSettingsTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({labSpaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$ScheduleSettingsTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$ScheduleSettingsTableReferences
                                    ._labSpaceIdTable(db)
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

typedef $$ScheduleSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleSettingsTable,
      ScheduleSettingsRow,
      $$ScheduleSettingsTableFilterComposer,
      $$ScheduleSettingsTableOrderingComposer,
      $$ScheduleSettingsTableAnnotationComposer,
      $$ScheduleSettingsTableCreateCompanionBuilder,
      $$ScheduleSettingsTableUpdateCompanionBuilder,
      (ScheduleSettingsRow, $$ScheduleSettingsTableReferences),
      ScheduleSettingsRow,
      PrefetchHooks Function({bool labSpaceId})
    >;
typedef $$ScheduleWeekNotesTableCreateCompanionBuilder =
    ScheduleWeekNotesCompanion Function({
      Value<int> id,
      required int labSpaceId,
      required String weekStartDate,
      required String note,
    });
typedef $$ScheduleWeekNotesTableUpdateCompanionBuilder =
    ScheduleWeekNotesCompanion Function({
      Value<int> id,
      Value<int> labSpaceId,
      Value<String> weekStartDate,
      Value<String> note,
    });

final class $$ScheduleWeekNotesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ScheduleWeekNotesTable,
          ScheduleWeekNoteRow
        > {
  $$ScheduleWeekNotesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LabSpacesTable _labSpaceIdTable(_$AppDatabase db) =>
      db.labSpaces.createAlias(
        $_aliasNameGenerator(db.scheduleWeekNotes.labSpaceId, db.labSpaces.id),
      );

  $$LabSpacesTableProcessedTableManager get labSpaceId {
    final $_column = $_itemColumn<int>('lab_space_id')!;

    final manager = $$LabSpacesTableTableManager(
      $_db,
      $_db.labSpaces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_labSpaceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ScheduleWeekNotesTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduleWeekNotesTable> {
  $$ScheduleWeekNotesTableFilterComposer({
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

  ColumnFilters<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  $$LabSpacesTableFilterComposer get labSpaceId {
    final $$LabSpacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableFilterComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleWeekNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduleWeekNotesTable> {
  $$ScheduleWeekNotesTableOrderingComposer({
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

  ColumnOrderings<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  $$LabSpacesTableOrderingComposer get labSpaceId {
    final $$LabSpacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableOrderingComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleWeekNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduleWeekNotesTable> {
  $$ScheduleWeekNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get weekStartDate => $composableBuilder(
    column: $table.weekStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$LabSpacesTableAnnotationComposer get labSpaceId {
    final $$LabSpacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.labSpaceId,
      referencedTable: $db.labSpaces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LabSpacesTableAnnotationComposer(
            $db: $db,
            $table: $db.labSpaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScheduleWeekNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduleWeekNotesTable,
          ScheduleWeekNoteRow,
          $$ScheduleWeekNotesTableFilterComposer,
          $$ScheduleWeekNotesTableOrderingComposer,
          $$ScheduleWeekNotesTableAnnotationComposer,
          $$ScheduleWeekNotesTableCreateCompanionBuilder,
          $$ScheduleWeekNotesTableUpdateCompanionBuilder,
          (ScheduleWeekNoteRow, $$ScheduleWeekNotesTableReferences),
          ScheduleWeekNoteRow,
          PrefetchHooks Function({bool labSpaceId})
        > {
  $$ScheduleWeekNotesTableTableManager(
    _$AppDatabase db,
    $ScheduleWeekNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ScheduleWeekNotesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$ScheduleWeekNotesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ScheduleWeekNotesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> labSpaceId = const Value.absent(),
                Value<String> weekStartDate = const Value.absent(),
                Value<String> note = const Value.absent(),
              }) => ScheduleWeekNotesCompanion(
                id: id,
                labSpaceId: labSpaceId,
                weekStartDate: weekStartDate,
                note: note,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int labSpaceId,
                required String weekStartDate,
                required String note,
              }) => ScheduleWeekNotesCompanion.insert(
                id: id,
                labSpaceId: labSpaceId,
                weekStartDate: weekStartDate,
                note: note,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$ScheduleWeekNotesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({labSpaceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
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
                if (labSpaceId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.labSpaceId,
                            referencedTable: $$ScheduleWeekNotesTableReferences
                                ._labSpaceIdTable(db),
                            referencedColumn:
                                $$ScheduleWeekNotesTableReferences
                                    ._labSpaceIdTable(db)
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

typedef $$ScheduleWeekNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduleWeekNotesTable,
      ScheduleWeekNoteRow,
      $$ScheduleWeekNotesTableFilterComposer,
      $$ScheduleWeekNotesTableOrderingComposer,
      $$ScheduleWeekNotesTableAnnotationComposer,
      $$ScheduleWeekNotesTableCreateCompanionBuilder,
      $$ScheduleWeekNotesTableUpdateCompanionBuilder,
      (ScheduleWeekNoteRow, $$ScheduleWeekNotesTableReferences),
      ScheduleWeekNoteRow,
      PrefetchHooks Function({bool labSpaceId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$NoteImagesTableTableManager get noteImages =>
      $$NoteImagesTableTableManager(_db, _db.noteImages);
  $$NoteVersionsTableTableManager get noteVersions =>
      $$NoteVersionsTableTableManager(_db, _db.noteVersions);
  $$NoteTaskLinksTableTableManager get noteTaskLinks =>
      $$NoteTaskLinksTableTableManager(_db, _db.noteTaskLinks);
  $$NoteBlocksTableTableManager get noteBlocks =>
      $$NoteBlocksTableTableManager(_db, _db.noteBlocks);
  $$LabSpacesTableTableManager get labSpaces =>
      $$LabSpacesTableTableManager(_db, _db.labSpaces);
  $$KanbanColumnsTableTableManager get kanbanColumns =>
      $$KanbanColumnsTableTableManager(_db, _db.kanbanColumns);
  $$KanbanCardsTableTableManager get kanbanCards =>
      $$KanbanCardsTableTableManager(_db, _db.kanbanCards);
  $$SpaceFolderLinksTableTableManager get spaceFolderLinks =>
      $$SpaceFolderLinksTableTableManager(_db, _db.spaceFolderLinks);
  $$OnboardingFlagsTableTableManager get onboardingFlags =>
      $$OnboardingFlagsTableTableManager(_db, _db.onboardingFlags);
  $$NotificationsTableTableManager get notifications =>
      $$NotificationsTableTableManager(_db, _db.notifications);
  $$ScheduleBlocksTableTableManager get scheduleBlocks =>
      $$ScheduleBlocksTableTableManager(_db, _db.scheduleBlocks);
  $$ScheduleSettingsTableTableManager get scheduleSettings =>
      $$ScheduleSettingsTableTableManager(_db, _db.scheduleSettings);
  $$ScheduleWeekNotesTableTableManager get scheduleWeekNotes =>
      $$ScheduleWeekNotesTableTableManager(_db, _db.scheduleWeekNotes);
}
