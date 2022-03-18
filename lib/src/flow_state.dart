import 'dart:convert';


class FlowState {


  factory FlowState.fromJson(String json) {
    void validate(condition, message) {
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

    validate(parsed.containsKey('phase'), 'did not contain required field "phase"');
    validate(parsed['phase'] is String, 'required field "phase" was not a string, was ${parsed["phase"]}');

    validate(parsed.containsKey('pkceVerifier'), 'did not contain required field "pkceVerifier"');
    validate(parsed['pkceVerifier'] is String, 'required field "pkceVerifier" was not a string, was ${parsed["pkceVerifier"]}');

    var scopes = parsed['scopes'];
    validate(scopes == null || scopes is List, 'field "scopes" was not a list, was "$scopes"');

    return FlowState(
      phase: parsed['phase'],
      pkceVerifier: parsed['pkceVerifier'],
      redirectUri: parsed['redirectUri'],
      state: parsed['state'],
      scopes: (scopes as List).map((scope) => scope as String).toList(),
    );
  }


  final String phase;
  final String pkceVerifier;

  final String? redirectUri;

  final String? state;

  final List<String>? scopes;


  const FlowState({
    required final this.phase,
    required final this.pkceVerifier,
    final this.redirectUri,
    final this.state,
    final this.scopes,
  });


  String toJson() => jsonEncode({
    'phase': phase,
    'pkceVerifier': pkceVerifier,
    'redirectUri': redirectUri,
    'state': state,
    'scopes': scopes,
  });

}
