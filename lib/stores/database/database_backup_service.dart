import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'add_database.dart';
import 'encryption_key_manager.dart';

class DatabaseRestoreResult {
  const DatabaseRestoreResult({
    required this.safetyBackupPath,
    required this.restoredRowCount,
  });

  final String safetyBackupPath;
  final int restoredRowCount;
}

class DatabaseBackupService {
  DatabaseBackupService._();

  static final instance = DatabaseBackupService._();

  static const _format = 'personal-organizer-sqlite-json';
  static const _formatVersion = 1;
  static const _encryptedFormatVersion = 2;
  static const _encryptedFormatVersionV3 = 3;

  /// v4：在 v3 基础上增加 HMAC-SHA256 完整性校验（Encrypt-then-MAC）。
  static const _encryptedFormatVersionV4 = 4;

  static const _saltLength = 16;
  static const _ivLength = 16;
  static const _hmacLength = 32;
  static const _pbkdf2Iterations = 10000;
  static const _derivedKeyLength = 32;

  /// v4 一次派生 64 字节：前 32 字节为 AES 密钥，后 32 字节为 HMAC 密钥。
  static const _derivedKeyLengthV4 = 64;

  static final List<int> _magicBytes = [0x4C, 0x4F, 0x42, 0x4B];

  /// 备份文件是否为 v4+（用户口令加密）格式，决定恢复时是否需要弹口令框。
  bool requiresPassphrase(Uint8List bytes) =>
      bytes.length >= _magicBytes.length + 1 &&
      _areListsEqual(bytes.sublist(0, _magicBytes.length), _magicBytes) &&
      bytes[_magicBytes.length] == _encryptedFormatVersionV4;

  Future<void> validateBackup(
    Uint8List bytes, {
    String? passphrase,
  }) async {
    final db = await AppDatabase.instance.database;
    final payload = await _decodePayload(bytes, passphrase: passphrase);
    await _validatePayload(payload, await _getTables(db), db);
  }

  /// 用户口令非空时生成 v4 口令备份（可跨设备恢复）；
  /// 口令为 null 时生成 v3 设备密钥备份（仅本机可解，用于恢复前回滚备份）。
  /// [name] 为用户给备份起的名字（可空），会写入加密 payload 元数据。
  Future<Uint8List> createBackupBytes({
    String? passphrase,
    String name = '',
  }) async {
    final db = await AppDatabase.instance.database;
    final formatVersion =
        passphrase != null ? _encryptedFormatVersionV4 : _encryptedFormatVersionV3;
    final payload = await db.transaction(
      (e) => _buildPayload(e, formatVersion, name: name),
    );
    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return _encryptPayload(Uint8List.fromList(jsonBytes), passphrase);
  }

  Future<File> saveBackup(
    Directory directory, {
    String? passphrase,
    String name = '',
    DateTime? now,
  }) async {
    final bytes = await createBackupBytes(passphrase: passphrase, name: name);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${_fileName(now ?? DateTime.now(), name: name)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<DatabaseRestoreResult> restoreBackup(
    Uint8List bytes, {
    String? passphrase,
  }) async {
    final db = await AppDatabase.instance.database;
    final payload = await _decodePayload(bytes, passphrase: passphrase);
    final tables = await _getTables(db);
    await _validatePayload(payload, tables, db);

    final preservedSettings = await db.query(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: ['installation_id', 'installation_time'],
    );

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final safetyBackup = await saveBackup(documentsDirectory);
    final restoreOrder = await _deleteOrder(db, tables);
    final backupTables =
        (payload['tables']! as Map<String, dynamic>).keys.toSet();
    var restoredRowCount = 0;

    await db.transaction((transaction) async {
      await transaction.execute('PRAGMA defer_foreign_keys = ON');
      for (final table in restoreOrder.reversed) {
        await transaction.delete(table);
      }
      await transaction.delete('sqlite_sequence');

      // 仅恢复备份中存在的表（旧版本备份可能缺少新版新增的数据表，
      // 这些表保持空表并由列默认值兜底）。插入时显式指定备份自身的列集合，
      // 旧备份缺少的新列由 DDL 默认值填充。
      for (final table in restoreOrder) {
        if (!backupTables.contains(table)) continue;
        final rows =
            (payload['tables']! as Map<String, dynamic>)[table] as List;
        for (final row in rows) {
          await transaction.insert(
            table,
            Map<String, Object?>.from(row as Map),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          restoredRowCount++;
        }
      }

      for (final setting in preservedSettings) {
        await transaction.insert(
          'app_settings',
          setting,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    return DatabaseRestoreResult(
      safetyBackupPath: safetyBackup.path,
      restoredRowCount: restoredRowCount,
    );
  }

  Future<Uint8List> _encryptPayload(
    Uint8List plaintext,
    String? passphrase,
  ) async {
    final random = Random.secure();
    final ivBytes = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => random.nextInt(256)),
    );
    final iv = encrypt.IV(ivBytes);
    final salt = Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );

    if (passphrase == null) {
      // v3：设备密钥派生（恢复前回滚备份，本机应急使用）。
      final masterKey = await EncryptionKeyManager.instance.getOrCreateKey();
      final key = encrypt.Key(_pbkdf2HmacSha256(
        utf8.encode(masterKey),
        salt,
        _pbkdf2Iterations,
        _derivedKeyLength,
      ));
      final encrypted = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      ).encryptBytes(plaintext, iv: iv);
      final builder = BytesBuilder()
        ..add(_magicBytes)
        ..addByte(_encryptedFormatVersionV3)
        ..add(salt)
        ..add(ivBytes)
        ..add(encrypted.bytes);
      return Uint8List.fromList(builder.toBytes());
    }

    // v4：用户口令派生 AES + HMAC 双密钥（Encrypt-then-MAC）。
    final derived = _pbkdf2HmacSha256(
      utf8.encode(passphrase),
      salt,
      _pbkdf2Iterations,
      _derivedKeyLengthV4,
    );
    final aesKey = encrypt.Key(derived.sublist(0, _derivedKeyLength));
    final macKey = derived.sublist(_derivedKeyLength, _derivedKeyLengthV4);

    final encrypted = encrypt.Encrypter(
      encrypt.AES(aesKey, mode: encrypt.AESMode.cbc),
    ).encryptBytes(plaintext, iv: iv);

    final headerAndCipher = BytesBuilder()
      ..add(_magicBytes)
      ..addByte(_encryptedFormatVersionV4)
      ..add(salt)
      ..add(ivBytes)
      ..add(encrypted.bytes);
    final hmacBytes = Hmac(
      sha256,
      macKey,
    ).convert(headerAndCipher.toBytes()).bytes;

    final output = BytesBuilder()
      ..add(headerAndCipher.toBytes())
      ..add(hmacBytes);
    return Uint8List.fromList(output.toBytes());
  }

  Future<Uint8List> _decryptPayload(
    Uint8List bytes, {
    String? passphrase,
  }) async {
    if (bytes.length < _magicBytes.length + 1 + 16) {
      throw const FormatException('备份文件格式无效或版本不受支持');
    }

    final header = bytes.sublist(0, _magicBytes.length);
    if (!_areListsEqual(header, _magicBytes)) {
      throw const FormatException('备份文件格式无效或版本不受支持');
    }

    final formatVersion = bytes[_magicBytes.length];
    if (formatVersion == _encryptedFormatVersionV4) {
      final minimumLength =
          _magicBytes.length +
          1 +
          _saltLength +
          _ivLength +
          _hmacLength;
      if (bytes.length < minimumLength) {
        throw const FormatException('备份文件格式无效或版本不受支持');
      }
      final macOffset = bytes.length - _hmacLength;
      final signedPart = bytes.sublist(0, macOffset);
      final providedMac = bytes.sublist(macOffset);

      final salt = bytes.sublist(
        _magicBytes.length + 1,
        _magicBytes.length + 1 + _saltLength,
      );
      final ivByteOffset = _magicBytes.length + 1 + _saltLength;
      final ivBytes = bytes.sublist(ivByteOffset, ivByteOffset + _ivLength);
      final ciphertext = bytes.sublist(ivByteOffset + _ivLength, macOffset);

      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('请输入备份密码');
      }
      final derived = _pbkdf2HmacSha256(
        utf8.encode(passphrase),
        salt,
        _pbkdf2Iterations,
        _derivedKeyLengthV4,
      );
      final macKey = derived.sublist(_derivedKeyLength, _derivedKeyLengthV4);
      final expectedMac = Hmac(sha256, macKey).convert(signedPart).bytes;
      // 先验签再解密：文件被篡改/截断/换设备无密钥都会在这里被拒绝。
      if (!_areListsEqual(providedMac, expectedMac)) {
        throw const FormatException('备份完整性校验失败，文件可能已损坏或被篡改');
      }
      final iv = encrypt.IV(Uint8List.fromList(ivBytes));
      final encrypter = encrypt.Encrypter(
        encrypt.AES(
          encrypt.Key(derived.sublist(0, _derivedKeyLength)),
          mode: encrypt.AESMode.cbc,
        ),
      );
      return Uint8List.fromList(
        encrypter.decryptBytes(encrypt.Encrypted(ciphertext), iv: iv),
      );
    }
    if (formatVersion == _encryptedFormatVersionV3) {
      final minimumLength = _magicBytes.length + 1 + _saltLength + 16;
      if (bytes.length < minimumLength) {
        throw const FormatException('备份文件格式无效或版本不受支持');
      }
      final salt = bytes.sublist(
        _magicBytes.length + 1,
        _magicBytes.length + 1 + _saltLength,
      );
      final ivByteOffset = _magicBytes.length + 1 + _saltLength;
      final ivBytes = bytes.sublist(ivByteOffset, ivByteOffset + 16);
      final ciphertext = bytes.sublist(ivByteOffset + 16);
      return _decryptCiphertext(ciphertext, ivBytes, salt: salt);
    }
    if (formatVersion == _encryptedFormatVersion) {
      final ivBytes = bytes.sublist(
        _magicBytes.length + 1,
        _magicBytes.length + 1 + 16,
      );
      final ciphertext = bytes.sublist(_magicBytes.length + 1 + 16);
      return _decryptCiphertext(ciphertext, ivBytes);
    }
    throw const FormatException('备份文件版本不受支持');
  }

  Future<Uint8List> _decryptCiphertext(
    Uint8List ciphertext,
    List<int> ivBytes, {
    Uint8List? salt,
  }) async {
    final masterKey = await EncryptionKeyManager.instance.getOrCreateKey();
    final encrypt.Key key;
    if (salt != null) {
      key = encrypt.Key(_pbkdf2HmacSha256(
        utf8.encode(masterKey),
        salt,
        _pbkdf2Iterations,
        _derivedKeyLength,
      ));
    } else {
      final derivedKey = sha256.convert(utf8.encode(masterKey)).toString();
      key = encrypt.Key.fromUtf8(derivedKey.substring(0, 32));
    }
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));

    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    return Uint8List.fromList(encrypter.decryptBytes(encrypt.Encrypted(ciphertext), iv: iv));
  }

  bool _areListsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Uint8List _pbkdf2HmacSha256(
    List<int> password,
    List<int> salt,
    int iterations,
    int dkLen,
  ) {
    // Hmac 实例可重复调用 convert，不要在万次迭代里反复 new。
    final mac = Hmac(sha256, password);
    final numBlocks = (dkLen + 31) ~/ 32;
    final result = BytesBuilder();
    for (var block = 1; block <= numBlocks; block++) {
      final blockBytes = ByteData(4)..setUint32(0, block);
      var u = mac.convert(<int>[...salt, ...blockBytes.buffer.asUint8List()]).bytes;
      final xor = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = mac.convert(u).bytes;
        for (var j = 0; j < xor.length; j++) {
          xor[j] ^= u[j];
        }
      }
      result.add(xor);
    }
    return Uint8List.fromList(result.toBytes().sublist(0, dkLen));
  }

  Future<Map<String, dynamic>> _decodePayload(
    Uint8List bytes, {
    String? passphrase,
  }) async {
    final Uint8List jsonBytes;

    if (bytes.length >= _magicBytes.length &&
        _areListsEqual(bytes.sublist(0, _magicBytes.length), _magicBytes)) {
      jsonBytes = await _decryptPayload(bytes, passphrase: passphrase);
    } else {
      // 不再接受无 magic 的明文 JSON：所有备份必须经加密封装，
      // 防止伪造明文备份绕过加密直接导入。
      throw const FormatException('备份文件格式无效或版本不受支持');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(jsonBytes));
    } on FormatException {
      rethrow;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format ||
        (decoded['format_version'] != _formatVersion &&
         decoded['format_version'] != _encryptedFormatVersion &&
         decoded['format_version'] != _encryptedFormatVersionV3 &&
         decoded['format_version'] != _encryptedFormatVersionV4) ||
        decoded['tables'] is! Map<String, dynamic> ||
        decoded['columns'] is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式无效或版本不受支持');
    }
    return decoded;
  }

  Future<Map<String, Object?>> _buildPayload(
    DatabaseExecutor executor,
    int formatVersion, {
    String name = '',
  }) async {
    final tables = await _getTables(executor);
    final data = <String, List<Map<String, Object?>>>{};
    final columns = <String, List<String>>{};
    for (final table in tables) {
      final tableInfo = await executor.rawQuery('PRAGMA table_info("$table")');
      columns[table] = tableInfo
          .map((column) => column['name'] as String)
          .toList();
      final rows = await executor.query(table);
      data[table] = rows.map((row) => Map<String, Object?>.from(row)).toList();
    }
    final versionRows = await executor.rawQuery('PRAGMA user_version');
    return {
      'format': _format,
      'format_version': formatVersion,
      'database_version': versionRows.first['user_version'],
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      // F1：用户命名写入加密元数据，恢复端解密后可显示原始命名。
      'name': name,
      'columns': columns,
      'tables': data,
    };
  }

  Future<List<String>> _getTables(DatabaseExecutor executor) async {
    final rows = await executor.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  Future<void> _validatePayload(
    Map<String, dynamic> payload,
    List<String> tables,
    DatabaseExecutor executor,
  ) async {
    final data = payload['tables']! as Map<String, dynamic>;
    final backupColumns = payload['columns']! as Map<String, dynamic>;
    final currentTables = tables.toSet();
    // 备份允许缺少新版本新增的表（恢复时留空），但不允许包含当前版本
    // 已不存在的表，避免写入无法解释的数据。
    if (!data.keys.every(currentTables.contains) ||
        !backupColumns.keys.every(currentTables.contains)) {
      throw const FormatException('备份中的数据表与当前应用不匹配');
    }
    for (final table in data.keys) {
      final rows = data[table];
      final columns = backupColumns[table];
      if (rows is! List ||
          columns is! List ||
          columns.any((c) => c is! String)) {
        throw FormatException('备份中的 $table 表结构无效');
      }
      final schemaRows = await executor.rawQuery('PRAGMA table_info("$table")');
      final currentColumns = schemaRows
          .map((column) => column['name'] as String)
          .toSet();
      // 旧版本备份的列可能少于当前 schema：缺失列必须有 DDL 默认值
      // （新增列均按此约定设计），恢复时按显式列名插入即可。
      if (!currentColumns.containsAll(columns.cast<String>())) {
        throw FormatException('备份中的 $table 表结构与当前应用不兼容');
      }
      final allowedColumns = columns.toSet();
      for (final row in rows) {
        if (row is! Map ||
            row.keys.any(
              (key) => key is! String || !allowedColumns.contains(key),
            ) ||
            row.values.any(
              (value) => value != null && value is! String && value is! num,
            )) {
          throw FormatException('备份中的 $table 表记录无效');
        }
      }
    }
  }

  Future<List<String>> _deleteOrder(
    DatabaseExecutor executor,
    List<String> tables,
  ) async {
    final children = {for (final table in tables) table: <String>[]};
    for (final table in tables) {
      final foreignKeys = await executor.rawQuery(
        'PRAGMA foreign_key_list("$table")',
      );
      for (final foreignKey in foreignKeys) {
        final parent = foreignKey['table'] as String;
        if (parent != table && children.containsKey(parent)) {
          children[parent]!.add(table);
        }
      }
    }

    final visited = <String>{};
    final active = <String>{};
    final order = <String>[];
    void visit(String table) {
      if (visited.contains(table)) return;
      if (!active.add(table)) {
        throw StateError('数据库存在循环外键，无法安全恢复备份');
      }
      for (final child in children[table]!) {
        visit(child);
      }
      active.remove(table);
      visited.add(table);
      order.add(table);
    }

    for (final table in tables) {
      visit(table);
    }
    return order;
  }

  static String twoDigits(int value) => value.toString().padLeft(2, '0');

  /// 备份文件名中的非法字符（Windows/Android 保留字符与控制字符）。
  static final RegExp _illegalFileNameChars = RegExp(r'[\\/:*?"<>|\x00-\x1f]');

  /// 规范化用户输入的备份名称为合法文件名词段：
  /// 去非法字符、压缩空白、限制长度。
  static String sanitizeBackupName(String raw) {
    var cleaned = raw.replaceAll(_illegalFileNameChars, ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length > 40) cleaned = cleaned.substring(0, 40).trim();
    return cleaned;
  }

  /// 单文件备份命名：`生活手账[_<名称>]_<yyyyMMdd>_<HHmmss>.enc`。
  static String buildBackupFileName(DateTime date, {String name = ''}) {
    final safeName = sanitizeBackupName(name);
    final stamp = '${date.year}${twoDigits(date.month)}${twoDigits(date.day)}'
        '_${twoDigits(date.hour)}${twoDigits(date.minute)}'
        '${twoDigits(date.second)}';
    return safeName.isEmpty
        ? '生活手账_$stamp.enc'
        : '生活手账_${safeName}_$stamp.enc';
  }

  /// 从备份文件名解析用户名称与导出时间；无法解析时返回 null，
  /// 调用方可用文件修改时间兜底。
  static ({String name, DateTime time})? parseBackupFileName(String fileName) {
    final match = RegExp(
      r'^生活手账(?:_(.+))?_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.enc$',
    ).firstMatch(fileName);
    if (match == null) return null;
    final name = match.group(1) ?? '';
    final dt = DateTime(
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
      int.parse(match.group(7)!),
    );
    return (name: name, time: dt);
  }

  String _fileName(DateTime date, {String name = ''}) =>
      buildBackupFileName(date, name: name);
}
