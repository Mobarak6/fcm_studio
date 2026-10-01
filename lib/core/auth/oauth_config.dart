import 'dart:convert';

import 'package:equatable/equatable.dart';

/// OAuth client IDs for Google sign-in, read from the git-ignored
/// `config/oauth.json` (spec §4.4, plan Decision 4).
class OAuthConfig extends Equatable {
  const OAuthConfig({
    this.desktopClientId,
    this.desktopClientSecret,
    this.webClientId,
  });

  /// Reads the JSON text of `config/oauth.json`. Blank values count as missing.
  factory OAuthConfig.parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('config/oauth.json must hold a JSON object.');
    }
    String? field(String name) {
      final value = decoded[name];
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return OAuthConfig(
      desktopClientId: field('desktopClientId'),
      desktopClientSecret: field('desktopClientSecret'),
      webClientId: field('webClientId'),
    );
  }

  static const assetPath = 'config/oauth.json';

  /// Loads the config with [read], or returns null when the file is missing
  /// or invalid, so Google sign-in is shown as not set up.
  static Future<OAuthConfig?> load(Future<String> Function() read) async {
    try {
      return OAuthConfig.parse(await read());
    } on Object {
      return null;
    }
  }

  final String? desktopClientId;
  final String? desktopClientSecret;
  final String? webClientId;

  bool get hasDesktopClient =>
      desktopClientId != null && desktopClientSecret != null;

  bool get hasWebClient => webClientId != null;

  @override
  List<Object?> get props => [
    desktopClientId,
    desktopClientSecret,
    webClientId,
  ];

  @override
  String toString() =>
      'OAuthConfig(desktop: $hasDesktopClient, web: $hasWebClient)';
}
