import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionKeyManager {
  EncryptionKeyManager._();
  static final EncryptionKeyManager instance = EncryptionKeyManager._();

  static const _storageKey = 'db_encryption_key';
  static const _keyLength = 32;

  final _secureStorage = const FlutterSecureStorage();
  String? _cachedKey;

  Future<String> getOrCreateKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) {
      return _cachedKey = existing;
    }

    final key = _generateKey();
    await _secureStorage.write(key: _storageKey, value: key);
    return _cachedKey = key;
  }

  String _generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      _keyLength,
      (_) => random.nextInt(256),
    );
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
