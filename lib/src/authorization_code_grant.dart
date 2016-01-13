// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:http/http.dart' as http;

import 'client.dart';
import 'authorization_exception.dart';
import 'handle_access_token_response.dart';
import 'utils.dart';

/// A class for obtaining credentials via an [authorization code grant][].
///
/// This method of authorization involves sending the resource owner to the
/// authorization server where they will authorize the client. They're then
/// redirected back to your server, along with an authorization code. This is
/// used to obtain [Credentials] and create a fully-authorized [Client].
///
/// To use this class, you must first call [getAuthorizationUrl] to get the URL
/// to which to redirect the resource owner. Then once they've been redirected
/// back to your application, call [handleAuthorizationResponse] or
/// [handleAuthorizationCode] to process the authorization server's response and
/// construct a [Client].
///
/// [authorization code grant]: http://tools.ietf.org/html/draft-ietf-oauth-v2-31#section-4.1
class AuthorizationCodeGrant {
  /// The client identifier for this client.
  ///
  /// The authorization server will issue each client a separate client
  /// identifier and secret, which allows the server to tell which client is
  /// accessing it. Some servers may also have an anonymous identifier/secret
  /// pair that any client may use.
  ///
  /// This is usually global to the program using this library.
  final String identifier;

  /// The client secret for this client.
  ///
  /// The authorization server will issue each client a separate client
  /// identifier and secret, which allows the server to tell which client is
  /// accessing it. Some servers may also have an anonymous identifier/secret
  /// pair that any client may use.
  ///
  /// This is usually global to the program using this library.
  ///
  /// Note that clients whose source code or binary executable is readily
  /// available may not be able to make sure the client secret is kept a secret.
  /// This is fine; OAuth2 servers generally won't rely on knowing with
  /// certainty that a client is who it claims to be.
  final String secret;

  /// A URL provided by the authorization server that serves as the base for the
  /// URL that the resource owner will be redirected to to authorize this
  /// client.
  ///
  /// This will usually be listed in the authorization server's OAuth2 API
  /// documentation.
  final Uri authorizationEndpoint;

  /// A URL provided by the authorization server that this library uses to
  /// obtain long-lasting credentials.
  ///
  /// This will usually be listed in the authorization server's OAuth2 API
  /// documentation.
  final Uri tokenEndpoint;

  /// Whether to use HTTP Basic authentication for authorizing the client.
  final bool _basicAuth;

  /// The HTTP client used to make HTTP requests.
  http.Client _httpClient;

  /// The URL to which the resource owner will be redirected after they
  /// authorize this client with the authorization server.
  Uri _redirectEndpoint;

  /// The scopes that the client is requesting access to.
  List<String> _scopes;

  /// An opaque string that users of this library may specify that will be
  /// included in the response query parameters.
  String _stateString;

  /// The current state of the grant object.
  _State _state = _State.initial;

  /// Creates a new grant.
  ///
  /// If [basicAuth] is `true` (the default), the client credentials are sent to
  /// the server using using HTTP Basic authentication as defined in [RFC 2617].
  /// Otherwise, they're included in the request body. Note that the latter form
  /// is not recommended by the OAuth 2.0 spec, and should only be used if the
  /// server doesn't support Basic authentication.
  ///
  /// [RFC 2617]: https://tools.ietf.org/html/rfc2617
  ///
  /// [httpClient] is used for all HTTP requests made by this grant, as well as
  /// those of the [Client] is constructs.
  AuthorizationCodeGrant(
          this.identifier,
          this.authorizationEndpoint,
          this.tokenEndpoint,
          {this.secret, bool basicAuth: true, http.Client httpClient})
      : _basicAuth = basicAuth,
        _httpClient = httpClient == null ? new http.Client() : httpClient;

  /// Returns the URL to which the resource owner should be redirected to
  /// authorize this client.
  ///
  /// The resource owner will then be redirected to [redirect], which should
  /// point to a server controlled by the client. This redirect will have
  /// additional query parameters that should be passed to
  /// [handleAuthorizationResponse].
  ///
  /// The specific permissions being requested from the authorization server may
  /// be specified via [scopes]. The scope strings are specific to the
  /// authorization server and may be found in its documentation. Note that you
  /// may not be granted access to every scope you request; you may check the
  /// [Credentials.scopes] field of [Client.credentials] to see which scopes you
  /// were granted.
  ///
  /// An opaque [state] string may also be passed that will be present in the
  /// query parameters provided to the redirect URL.
  ///
  /// It is a [StateError] to call this more than once.
  Uri getAuthorizationUrl(Uri redirect, {Iterable<String> scopes,
      String state}) {
    if (_state != _State.initial) {
      throw new StateError('The authorization URL has already been generated.');
    }
    _state = _State.awaitingResponse;

    if (scopes == null) {
      scopes = [];
    } else {
      scopes = scopes.toList();
    }

    this._redirectEndpoint = redirect;
    this._scopes = scopes;
    this._stateString = state;
    var parameters = {
      "response_type": "code",
      "client_id": this.identifier,
      "redirect_uri": redirect.toString()
    };

    if (state != null) parameters['state'] = state;
    if (!scopes.isEmpty) parameters['scope'] = scopes.join(' ');

    return addQueryParameters(this.authorizationEndpoint, parameters);
  }

  /// Processes the query parameters added to a redirect from the authorization
  /// server.
  ///
  /// Note that this "response" is not an HTTP response, but rather the data
  /// passed to a server controlled by the client as query parameters on the
  /// redirect URL.
  ///
  /// It is a [StateError] to call this more than once, to call it before
  /// [getAuthorizationUrl] is called, or to call it after
  /// [handleAuthorizationCode] is called.
  ///
  /// Throws [FormatError] if [parameters] is invalid according to the OAuth2
  /// spec or if the authorization server otherwise provides invalid responses.
  /// If `state` was passed to [getAuthorizationUrl], this will throw a
  /// [FormatError] if the `state` parameter doesn't match the original value.
  ///
  /// Throws [AuthorizationException] if the authorization fails.
  Future<Client> handleAuthorizationResponse(Map<String, String> parameters)
      async {
    if (_state == _State.initial) {
      throw new StateError(
          'The authorization URL has not yet been generated.');
    } else if (_state == _State.finished) {
      throw new StateError(
          'The authorization code has already been received.');
    }
    _state = _State.finished;

    if (_stateString != null) {
      if (!parameters.containsKey('state')) {
        throw new FormatException('Invalid OAuth response for '
            '"$authorizationEndpoint": parameter "state" expected to be '
            '"$_stateString", was missing.');
      } else if (parameters['state'] != _stateString) {
        throw new FormatException('Invalid OAuth response for '
            '"$authorizationEndpoint": parameter "state" expected to be '
            '"$_stateString", was "${parameters['state']}".');
      }
    }

    if (parameters.containsKey('error')) {
      var description = parameters['error_description'];
      var uriString = parameters['error_uri'];
      var uri = uriString == null ? null : Uri.parse(uriString);
      throw new AuthorizationException(parameters['error'], description, uri);
    } else if (!parameters.containsKey('code')) {
      throw new FormatException('Invalid OAuth response for '
          '"$authorizationEndpoint": did not contain required parameter '
          '"code".');
    }

    return await _handleAuthorizationCode(parameters['code']);
  }

  /// Processes an authorization code directly.
  ///
  /// Usually [handleAuthorizationResponse] is preferable to this method, since
  /// it validates all of the query parameters. However, some authorization
  /// servers allow the user to copy and paste an authorization code into a
  /// command-line application, in which case this method must be used.
  ///
  /// It is a [StateError] to call this more than once, to call it before
  /// [getAuthorizationUrl] is called, or to call it after
  /// [handleAuthorizationCode] is called.
  ///
  /// Throws [FormatError] if the authorization server provides invalid
  /// responses while retrieving credentials.
  ///
  /// Throws [AuthorizationException] if the authorization fails.
  Future<Client> handleAuthorizationCode(String authorizationCode) async {
    if (_state == _State.initial) {
      throw new StateError(
          'The authorization URL has not yet been generated.');
    } else if (_state == _State.finished) {
      throw new StateError(
          'The authorization code has already been received.');
    }
    _state = _State.finished;

    return await _handleAuthorizationCode(authorizationCode);
  }

  /// This works just like [handleAuthorizationCode], except it doesn't validate
  /// the state beforehand.
  Future<Client> _handleAuthorizationCode(String authorizationCode) async {
    var startTime = new DateTime.now();

    var headers = {};

    var body = {
      "grant_type": "authorization_code",
      "code": authorizationCode,
      "redirect_uri": this._redirectEndpoint.toString()
    };

    if (_basicAuth && secret != null) {
      headers["Authorization"] = basicAuthHeader(identifier, secret);
    } else {
      // The ID is required for this request any time basic auth isn't being
      // used, even if there's no actual client authentication to be done.
      body["client_id"] = identifier;
      if (secret != null) body["client_secret"] = secret;
    }

    var response = await _httpClient.post(this.tokenEndpoint,
        headers: headers, body: body);

    var credentials = handleAccessTokenResponse(
        response, tokenEndpoint, startTime, _scopes);
    return new Client(
        credentials,
        identifier: this.identifier,
        secret: this.secret,
        basicAuth: _basicAuth,
        httpClient: _httpClient);
  }

  /// Closes the grant and frees its resources.
  ///
  /// This will close the underlying HTTP client, which is shared by the
  /// [Client] created by this grant, so it's not safe to close the grant and
  /// continue using the client.
  void close() {
    if (_httpClient != null) _httpClient.close();
    _httpClient = null;
  }
}

/// States that [AuthorizationCodeGrant] can be in.
class _State {
  /// [AuthorizationCodeGrant.getAuthorizationUrl] has not yet been called for
  /// this grant.
  static const initial = const _State("initial");

  // [AuthorizationCodeGrant.getAuthorizationUrl] has been called but neither
  // [AuthorizationCodeGrant.handleAuthorizationResponse] nor
  // [AuthorizationCodeGrant.handleAuthorizationCode] has been called.
  static const awaitingResponse = const _State("awaiting response");

  // [AuthorizationCodeGrant.getAuthorizationUrl] and either
  // [AuthorizationCodeGrant.handleAuthorizationResponse] or
  // [AuthorizationCodeGrant.handleAuthorizationCode] have been called.
  static const finished = const _State("finished");

  final String _name;

  const _State(this._name);

  String toString() => _name;
}
