// lib/services/auth_service.dart
// ─────────────────────────────────
// Local accounts: full name + mobile number + 4-digit PIN.
// The mobile number is the unique ID. Every piece of per-user data
// (offline queue, scan history, ...) must be stored under
// `AuthService.instance.scopedKey('your_key')` so each farmer only sees
// their own rice-field captures.

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _usersKey    = 'auth_users';          // { mobile: {name, salt, hash, fails, lockUntil} }
  static const _sessionKey  = 'auth_current_mobile';
  static const _hashRounds  = 5000;
  static const _maxFails    = 5;
  static const _lockMinutes = 1;

  /// Holds the signed-in mobile number (null = signed out).
  final ValueNotifier<String?> userNotifier = ValueNotifier<String?>(null);

  String? _displayName;

  String? get currentUser => userNotifier.value;   // mobile number
  String? get displayName => _displayName;         // farmer's full name
  bool get isLoggedIn => currentUser != null;

  /// e.g. scopedKey('offline_pests_queue') -> 'offline_pests_queue__09171234567'
  String scopedKey(String baseKey) {
    final user = currentUser;
    if (user == null) throw const AuthException('No user is signed in.');
    return '${baseKey}__$user';
  }

  /// Call once in main() before runApp().
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sessionKey);
    final users = _readUsers(prefs);
    if (saved != null && users[saved] != null) {
      _displayName = users[saved]['name'] as String?;
      userNotifier.value = saved;
    }
  }

  Future<void> register({
    required String name,
    required String mobile,
    required String pin,
  }) async {
    final cleanName = name.trim();
    final number = normalizeMobile(mobile);

    if (cleanName.length < 2) {
      throw const AuthException('Please enter your full name.');
    }
    if (number == null) {
      throw const AuthException('Enter a valid mobile number, e.g. 09171234567.');
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const AuthException('PIN must be exactly 4 digits.');
    }

    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    if (users.containsKey(number)) {
      throw const AuthException(
          'This mobile number is already registered. Please sign in.');
    }

    final salt = _newSalt();
    users[number] = {
      'name': cleanName,
      'salt': salt,
      'hash': _hash(pin, salt),
      'fails': 0,
      'lockUntil': 0,
    };
    await _saveUsers(prefs, users);
    await prefs.setString(_sessionKey, number);

    _displayName = cleanName;
    userNotifier.value = number;
  }

  Future<void> login({required String mobile, required String pin}) async {
    final number = normalizeMobile(mobile);
    if (number == null) {
      throw const AuthException('Enter a valid mobile number.');
    }

    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    final record = users[number];
    if (record == null) {
      throw const AuthException(
          'No account for this number yet. Tap "Create account".');
    }

    // Lockout after too many wrong PINs.
    final now = DateTime.now().millisecondsSinceEpoch;
    final lockUntil = (record['lockUntil'] as int?) ?? 0;
    if (lockUntil > now) {
      final secs = ((lockUntil - now) / 1000).ceil();
      throw AuthException('Too many wrong attempts. Try again in $secs seconds.');
    }

    if (_hash(pin, record['salt'] as String) != record['hash']) {
      final fails = ((record['fails'] as int?) ?? 0) + 1;
      if (fails >= _maxFails) {
        record['fails'] = 0;
        record['lockUntil'] =
            now + const Duration(minutes: _lockMinutes).inMilliseconds;
        await _saveUsers(prefs, users);
        throw const AuthException(
            'Too many wrong attempts. Try again in 1 minute.');
      }
      record['fails'] = fails;
      await _saveUsers(prefs, users);
      throw AuthException(
          'Wrong PIN. ${_maxFails - fails} tries left.');
    }

    record['fails'] = 0;
    record['lockUntil'] = 0;
    await _saveUsers(prefs, users);
    await prefs.setString(_sessionKey, number);

    _displayName = record['name'] as String?;
    userNotifier.value = number;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    _displayName = null;
    userNotifier.value = null;
  }

  /// "+63 917 123 4567", "63917...", "0917-123-4567" -> "09171234567".
  /// Returns null if it isn't a valid PH mobile number.
  static String? normalizeMobile(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('63') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    } else if (digits.length == 10 && digits.startsWith('9')) {
      digits = '0$digits';
    }
    return RegExp(r'^09\d{9}$').hasMatch(digits) ? digits : null;
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  Map<String, dynamic> _readUsers(SharedPreferences prefs) {
    final raw = prefs.getString(_usersKey);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(SharedPreferences prefs, Map<String, dynamic> users) =>
      prefs.setString(_usersKey, jsonEncode(users));

  String _newSalt() {
    final rnd = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }


  String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < _hashRounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }
}
