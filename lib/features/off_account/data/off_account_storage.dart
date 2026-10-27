import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';

/// An Open Food Facts login.
class OffCredentials {
  /// The username, never the email address: Open Food Facts asks for it.
  final String username;
  final String password;

  const OffCredentials(this.username, this.password);

  // Never print the password, even by accident in a log or error message.
  @override
  String toString() => 'OffCredentials($username, ***)';
}

/// Keeps the user's Open Food Facts login in the phone's encrypted secure
/// storage (the Android Keystore), apart from the app's other data. It is only
/// read when the user uploads something.
class OffAccountStorage {
  static const _usernameKey = 'off_account_username';
  static const _passwordKey = 'off_account_password';

  final FlutterSecureStorage _storage;

  OffAccountStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? SecureAppStorageProvider.secureAppStorage;

  /// The saved login, or null when nobody is logged in.
  Future<OffCredentials?> read() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || username.isEmpty || password == null) return null;
    return OffCredentials(username, password);
  }

  Future<void> save(OffCredentials credentials) async {
    await _storage.write(key: _usernameKey, value: credentials.username);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
