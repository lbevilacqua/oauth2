import 'dart:convert';


class FlowState {


  factory FlowState.fromJson(String json) {
    void validate(final bool condition, final String message) {
      if (condition) return;
      throw FormatException('Failed to load flow state: $message.\n\n$json');
    }

    var parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      validate(false, 'invalid JSON');
    }

    validate(parsed is Map, 'was not a JSON map');

    validate((parsed as Map).containsKey('phase'), 'did not contain required field "phase"');
    validate(parsed['phase'] is String, 'required field "phase" was not a string, was ${parsed["phase"]}');

    validate(parsed.containsKey('pkceVerifier'), 'did not contain required field "pkceVerifier"');
    validate(parsed['pkceVerifier'] is String, 'required field "pkceVerifier" was not a string, was ${parsed["pkceVerifier"]}');

    var scopes = parsed['scopes'];
    validate(scopes == null || scopes is List, 'field "scopes" was not a list, was "$scopes"');

    return FlowState(
      phase: parsed['phase'] as String,
      pkceVerifier: parsed['pkceVerifier'] as String,
      redirectUri: parsed['redirectUri'] as String?,
      state: parsed['state'] as String?,
      scopes: (scopes as List).map((scope) => scope as String).toList(),
    );
  }


  final String phase;
  final String pkceVerifier;

  final String? redirectUri;

  final String? state;

  final List<String>? scopes;


  const FlowState({
    required this.phase,
    required this.pkceVerifier,
    this.redirectUri,
    this.state,
    this.scopes,
  });


  String toJson() => jsonEncode({
    'phase': phase,
    'pkceVerifier': pkceVerifier,
    'redirectUri': redirectUri,
    'state': state,
    'scopes': scopes,
  });

}
