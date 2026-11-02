import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'ai_agent_context.dart';
import 'ai_agent_proposals.dart';
import 'ai_agent_review_dialog.dart';
import 'ai_agent_service.dart';

const _agentPanel = Color(0xFF111821);
const _agentBg = Color(0xFF0D1117);
const _agentBorder = Color(0xFF243140);
const _agentText = Color(0xFFE6EDF3);
const _agentMuted = Color(0xFF8B98A9);
const _agentAccent = Color(0xFF62D3CE);

class AiAgentPanel extends StatefulWidget {
  const AiAgentPanel({
    required this.workspacePath,
    required this.getOpenFiles,
    required this.onApplyChanges,
    this.onClose,
    super.key,
  });

  final String? workspacePath;
  final List<AiAgentContextFile> Function() getOpenFiles;
  final Future<void> Function(Map<String, String> changes) onApplyChanges;
  final VoidCallback? onClose;

  @override
  State<AiAgentPanel> createState() => _AiAgentPanelState();
}

class _AiAgentPanelState extends State<AiAgentPanel> {
  static const _accessTokenName = 'nexuside.oauth.accessToken';
  static const _refreshTokenName = 'nexuside.oauth.refreshToken';
  static const _expiresAtName = 'nexuside.oauth.expiresAt';
  static const _emailName = 'nexuside.gateway.accountEmail';
  static const _displayNameName = 'nexuside.gateway.displayName';
  static const _selectedModelName = 'nexuside.agent.selectedModel';
  static const _legacyKeyName = 'nexuside.gateway.apiKey';
  static const _legacySessionName = 'nexuside.gateway.sessionCookie';
  static const _legacyApiKeyIdName = 'nexuside.gateway.apiKeyId';

  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  final _secureStorage = FlutterSecureStorage();
  final _client = NexusGatewayClient();
  final _contextBuilder = AiAgentWorkspaceContext();
  final _parser = AiAgentProposalParser();
  final List<_ChatMessage> _messages = [];

  bool _loading = false;
  bool _testing = false;
  bool _authBusy = false;
  bool _signedIn = false;
  bool _loadingModels = false;
  List<String> _models = <String>[];
  String _selectedModel = NexusGatewayClient.defaultModel;
  String? _accessToken;
  String? _refreshToken;
  int? _accessExpiresAt;
  String? _accountEmail;
  String? _displayName;
  String? _status;
  bool _statusError = false;

  String get _baseUrl => NexusGatewayClient.defaultBaseUrl;
  String get _gatewayOrigin => _baseUrl.substring(0, _baseUrl.length - 3);
  String get _modelId => _selectedModel.isEmpty ? NexusGatewayClient.defaultModel : _selectedModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _clearLegacyGatewaySession() async {
    final cookie = await _secureStorage.read(key: _legacySessionName);
    final keyId = await _secureStorage.read(key: _legacyApiKeyIdName);
    if (cookie != null && cookie.isNotEmpty && keyId != null && keyId.isNotEmpty) {
      try {
        await http.delete(
          Uri.parse(_gatewayOrigin + '/account/api-keys/' + keyId),
          headers: {'Cookie': cookie, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
      try {
        await http.post(
          Uri.parse(_gatewayOrigin + '/auth/logout'),
          headers: {'Cookie': cookie},
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    for (final legacy in <String>[_legacyKeyName, _legacySessionName, _legacyApiKeyIdName]) {
      try { await _secureStorage.delete(key: legacy); } catch (_) {}
    }
  }

  Future<void> _loadSettings() async {
    try {
      await _clearLegacyGatewaySession();
      var accessToken = await _secureStorage.read(key: _accessTokenName);
      var refreshToken = await _secureStorage.read(key: _refreshTokenName);
      final expiresAt = int.tryParse(await _secureStorage.read(key: _expiresAtName) ?? '');
      final savedEmail = await _secureStorage.read(key: _emailName);
      final savedDisplayName = await _secureStorage.read(key: _displayNameName);
      if (refreshToken == null || refreshToken.isEmpty) {
        await _clearOAuthStorage();
        if (!mounted) return;
        setState(() {
          _signedIn = false;
          _accessToken = null;
          _refreshToken = null;
          _accessExpiresAt = null;
          _status = null;
        });
        return;
      }
      if (accessToken == null || expiresAt == null ||
          expiresAt <= DateTime.now().millisecondsSinceEpoch + 60000) {
        accessToken = await _refreshAccessToken();
        refreshToken = await _secureStorage.read(key: _refreshTokenName) ?? refreshToken;
      }
      var response = await http.get(
        Uri.parse(_gatewayOrigin + '/auth/oauth/me'),
        headers: {'Authorization': 'Bearer ' + accessToken, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) {
        accessToken = await _refreshAccessToken();
        refreshToken = await _secureStorage.read(key: _refreshTokenName) ?? refreshToken;
        response = await http.get(
          Uri.parse(_gatewayOrigin + '/auth/oauth/me'),
          headers: {'Authorization': 'Bearer ' + accessToken, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 20));
      }
      final data = _decodeResponse(response.body);
      final user = data?['user'];
      if (response.statusCode < 200 || response.statusCode >= 300 || user is! Map) {
        throw Exception(_responseError(response));
      }
      final email = user['email'] is String ? user['email'] as String : savedEmail ?? '';
      final displayName = user['display_name'] is String
          ? user['display_name'] as String
          : savedDisplayName ?? email;
      await _secureStorage.write(key: _emailName, value: email);
      await _secureStorage.write(key: _displayNameName, value: displayName);
      final currentExpiry = int.tryParse(await _secureStorage.read(key: _expiresAtName) ?? '');
      if (!mounted) return;
      setState(() {
        _accessToken = accessToken;
        _refreshToken = refreshToken;
        _accessExpiresAt = currentExpiry;
        _accountEmail = email;
        _displayName = displayName;
        _signedIn = true;
        _status = null;
        _statusError = false;
      });
      await _loadAvailableModels();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = false;
        _status = 'Could not restore the gateway connection: ' + _client.friendlyError(error);
        _statusError = true;
      });
    }
  }

  void _setStatus(String text, [bool error = false]) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  Map<String, dynamic>? _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String _responseError(http.Response response) {
    final decoded = _decodeResponse(response.body);
    final error = decoded?['error'];
    if (error is Map && error['message'] is String) return error['message'] as String;
    if (decoded?['message'] is String) return decoded!['message'] as String;
    return 'Request failed (HTTP ' + response.statusCode.toString() + ').';
  }

  String _randomUrlToken(int byteLength) {
    final random = math.Random.secure();
    return base64UrlEncode(List<int>.generate(byteLength, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<http.Response> _oauthFormPost(Map<String, String> values, {String endpoint = '/auth/oauth/token'}) {
    return http.post(
      Uri.parse(_gatewayOrigin + endpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
      body: Uri(queryParameters: values).query,
    ).timeout(const Duration(seconds: 30));
  }

  Future<String> _saveOAuthTokens(Map<String, dynamic> data) async {
    final accessToken = data['access_token'];
    final refreshToken = data['refresh_token'];
    final expiresIn = data['expires_in'];
    if (accessToken is! String || accessToken.isEmpty ||
        refreshToken is! String || refreshToken.isEmpty ||
        expiresIn is! num || expiresIn <= 0) {
      throw Exception('Gateway returned an invalid OAuth token response.');
    }
    final expiresAt = DateTime.now().millisecondsSinceEpoch + expiresIn.toInt() * 1000;
    await _secureStorage.write(key: _accessTokenName, value: accessToken);
    await _secureStorage.write(key: _refreshTokenName, value: refreshToken);
    await _secureStorage.write(key: _expiresAtName, value: expiresAt.toString());
    final user = data['user'];
    if (user is Map) {
      if (user['email'] is String) await _secureStorage.write(key: _emailName, value: user['email'] as String);
      if (user['display_name'] is String) await _secureStorage.write(key: _displayNameName, value: user['display_name'] as String);
    }
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _accessExpiresAt = expiresAt;
    return accessToken;
  }

  Future<String> _refreshAccessToken() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenName);
    if (refreshToken == null || refreshToken.isEmpty) throw Exception('No gateway refresh token. Connect again.');
    final response = await _oauthFormPost({
      'grant_type': 'refresh_token',
      'client_id': 'nexuside',
      'refresh_token': refreshToken,
    });
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_responseError(response));
    final data = _decodeResponse(response.body);
    if (data == null) throw Exception('Gateway returned invalid OAuth token data.');
    return _saveOAuthTokens(data);
  }

  Future<String> _validAccessToken() async {
    final accessToken = _accessToken ?? await _secureStorage.read(key: _accessTokenName);
    final expiresAt = _accessExpiresAt ?? int.tryParse(await _secureStorage.read(key: _expiresAtName) ?? '');
    if (accessToken != null && expiresAt != null &&
        expiresAt > DateTime.now().millisecondsSinceEpoch + 60000) return accessToken;
    return _refreshAccessToken();
  }

  Future<void> _clearOAuthStorage() async {
    for (final key in <String>[
      _accessTokenName, _refreshTokenName, _expiresAtName,
      _legacyKeyName, _legacySessionName, _legacyApiKeyIdName, _emailName, _displayNameName,
    ]) {
      try { await _secureStorage.delete(key: key); } catch (_) {}
    }
  }

  Future<void> _authenticate() async {
    setState(() {
      _authBusy = true;
      _status = 'Opening Mallss Nexus Route in your browser…';
      _statusError = false;
    });
    HttpServer? callbackServer;
    try {
      final state = _randomUrlToken(32);
      final verifier = _randomUrlToken(48);
      final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
      callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri = Uri(scheme: 'http', host: '127.0.0.1', port: callbackServer.port, path: '/oauth/callback');
      final callbackCompleter = Completer<Uri>();
      callbackServer.listen((request) async {
        if (request.method != 'GET' || request.uri.path != '/oauth/callback') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        final callback = request.uri;
        if (callback.queryParameters['state'] != state ||
            (callback.queryParameters['code'] == null && callback.queryParameters['error'] == null)) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.text;
          request.response.write('Invalid authorization callback. Return to NexusIDE and try again.');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.write(
          '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NexusIDE connected</title>'
          '<style>body{background:#0d1117;color:#e6edf3;font:16px system-ui;display:grid;place-items:center;min-height:90vh}.card{max-width:420px;padding:28px;border:1px solid #30363d;border-radius:16px}h1{font-size:22px}p{color:#9da7b3}</style></head>'
          '<body><main class="card"><h1>Return to NexusIDE</h1><p>Authorization response received. You can close this browser tab and return to the app.</p></main></body></html>',
        );
        await request.response.close();
        if (!callbackCompleter.isCompleted) callbackCompleter.complete(callback);
      });
      final authorizeUri = Uri.parse(_gatewayOrigin + '/auth/oauth/authorize').replace(queryParameters: {
        'client_id': 'nexuside',
        'response_type': 'code',
        'redirect_uri': redirectUri.toString(),
        'scope': 'models:read inference',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });
      final opened = await launchUrl(authorizeUri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Could not open the system browser.');
      if (mounted) _setStatus('Sign in and approve NexusIDE in your browser…');
      final callback = await callbackCompleter.future.timeout(const Duration(minutes: 5));
      if (callback.queryParameters['state'] != state) throw Exception('OAuth state validation failed. Connect again.');
      final oauthError = callback.queryParameters['error'];
      if (oauthError != null) {
        if (oauthError == 'access_denied') throw Exception('Connection was cancelled.');
        throw Exception('Gateway authorization failed: ' + oauthError);
      }
      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) throw Exception('Gateway returned no authorization code.');
      final tokenResponse = await _oauthFormPost({
        'grant_type': 'authorization_code',
        'client_id': 'nexuside',
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'code_verifier': verifier,
      });
      if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) throw Exception(_responseError(tokenResponse));
      final tokenData = _decodeResponse(tokenResponse.body);
      if (tokenData == null) throw Exception('Gateway returned invalid OAuth token data.');
      final previousRefreshToken = await _secureStorage.read(key: _refreshTokenName);
      final accessToken = await _saveOAuthTokens(tokenData);
      final newRefreshToken = tokenData['refresh_token'];
      if (previousRefreshToken != null && previousRefreshToken.isNotEmpty &&
          newRefreshToken is String && previousRefreshToken != newRefreshToken) {
        try {
          await _oauthFormPost({
            'token': previousRefreshToken,
            'token_type_hint': 'refresh_token',
          }, endpoint: '/auth/oauth/revoke');
        } catch (_) {}
      }
      final user = tokenData['user'];
      final email = user is Map && user['email'] is String ? user['email'] as String : '';
      final displayName = user is Map && user['display_name'] is String ? user['display_name'] as String : email;
      for (final key in <String>[_legacyKeyName, _legacySessionName, _legacyApiKeyIdName]) {
        await _secureStorage.delete(key: key);
      }
      if (!mounted) return;
      _prompt.clear();
      setState(() {
        _accessToken = accessToken;
        _accountEmail = email;
        _displayName = displayName;
        _signedIn = true;
        _authBusy = false;
        _status = 'Connected to Mallss Nexus Route.';
        _statusError = false;
        _messages
          ..clear()
          ..add(_ChatMessage('assistant', 'Connected to your gateway account. Ask me to explain your code or propose a change; nothing is written until you review it.'));
      });
      _scrollToBottom();
      await _loadAvailableModels();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _status = _client.friendlyError(error);
        _statusError = true;
      });
    } finally {
      await callbackServer?.close(force: true);
    }
  }

  Future<void> _logout() async {
    final refreshToken = _refreshToken ?? await _secureStorage.read(key: _refreshTokenName);
    setState(() { _authBusy = true; _status = 'Disconnecting gateway account…'; _statusError = false; });
    var revoked = false;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        final response = await _oauthFormPost({
          'token': refreshToken,
          'token_type_hint': 'refresh_token',
        }, endpoint: '/auth/oauth/revoke');
        revoked = response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {}
    }
    await _clearOAuthStorage();
    if (!mounted) return;
    setState(() {
      _accessToken = null; _refreshToken = null; _accessExpiresAt = null;
      _accountEmail = null; _displayName = null; _signedIn = false;
      _authBusy = false; _messages.clear();
      _status = revoked ? 'Disconnected. This NexusIDE session was revoked.' :
          'Disconnected locally. The gateway session could not be revoked; it will expire automatically.';
      _statusError = !revoked;
    });
  }

  Future<void> _selectModel(String? model) async {
    if (model == null || model.trim().isEmpty || model == _selectedModel) return;
    setState(() {
      _selectedModel = model;
      _status = 'Model changed to ' + model + '.';
      _statusError = false;
    });
    try {
      await _secureStorage.write(key: _selectedModelName, value: model);
    } catch (error) {
      if (mounted) _setStatus('Model is active, but its preference could not be saved: ' + _client.friendlyError(error), true);
    }
  }

  Future<void> _loadAvailableModels({bool announce = false, bool checkButton = false}) async {
    if (!_signedIn) return;
    if (mounted) {
      setState(() {
        _loadingModels = true;
        if (checkButton) {
          _testing = true;
          _status = 'Checking gateway models…';
          _statusError = false;
        }
      });
    }
    try {
      final token = await _validAccessToken();
      final models = await _client.testConnection(_baseUrl, token);
      final savedModel = await _secureStorage.read(key: _selectedModelName);
      var selected = savedModel ?? _selectedModel;
      if (!models.contains(selected)) {
        selected = models.contains(NexusGatewayClient.defaultModel)
            ? NexusGatewayClient.defaultModel
            : (models.isNotEmpty ? models.first : NexusGatewayClient.defaultModel);
      }
      await _secureStorage.write(key: _selectedModelName, value: selected);
      if (!mounted) return;
      setState(() {
        _models = models;
        _selectedModel = selected;
        _loadingModels = false;
        _testing = false;
        if (announce) {
          _status = models.isEmpty
              ? 'Gateway connected, but no models were returned.'
              : 'Gateway ready · ' + models.length.toString() + ' models available.';
          _statusError = models.isEmpty;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _testing = false;
        if (announce) {
          _status = _client.friendlyError(error);
          _statusError = true;
        }
      });
    }
  }

  Future<void> _testConnection() async {
    if (!_signedIn) {
      _setStatus('Connect your gateway account first.', true);
      return;
    }
    await _loadAvailableModels(announce: true, checkButton: true);
  }

  Future<void> _send() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _loading) return;
    if (!_signedIn) {
      _setStatus('Connect your gateway account first.', true);
      return;
    }

    final history = _messages.toList(growable: false);
    setState(() {
      _messages.add(_ChatMessage('user', prompt));
      _prompt.clear();
      _loading = true;
      _status = null;
    });
    _scrollToBottom();

    try {
      final contextText = await _buildProjectContext();
      final requestMessages = <Map<String, String>>[
        {'role': 'system', 'content': _systemPrompt},
      ];
      for (final item in history.skip(history.length > 8 ? history.length - 8 : 0)) {
        requestMessages.add({'role': item.role, 'content': item.text});
      }
      requestMessages.add({
        'role': 'user',
        'content': 'CURRENT TASK:\n' + prompt + '\n\nWORKSPACE CONTEXT:\n' + contextText,
      });

      final token = await _validAccessToken();
      final raw = await _client.complete(_baseUrl, token, _modelId, requestMessages);
      final parsed = _parser.parse(raw);
      final allowedChanges = parsed.changes
          .where((change) => !_isSensitiveFile(change['path'] ?? ''))
          .toList(growable: false);
      final changes = await _parser.prepare(widget.workspacePath, allowedChanges);
      var answer = parsed.message;
      if (parsed.changes.isNotEmpty && changes.isEmpty) {
        answer += '\n\nNo changes were prepared. Open a workspace and use paths relative to it.';
      }
      if (changes.length < parsed.changes.length) {
        answer += '\n\nSome proposed paths were rejected for safety.';
      }
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage('assistant', answer, changes: changes));
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage('assistant', 'Request failed: ' + _client.friendlyError(error)));
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  static const _systemPrompt =
      'You are the NexusIDE coding agent. Use the supplied workspace tree and open-file content. '
      'Return ONLY a valid JSON object shaped like {"message":"short explanation","changes":[{"path":"relative/path","content":"complete resulting file content"}]}. '
      'For normal chat, changes must be an empty array. For file edits, include the COMPLETE resulting content. '
      'Use workspace-relative paths with forward slashes. Never use absolute paths or parent traversal. Do not delete files. '
      'Do not claim changes were applied. The user must review the changes before applying. Do not wrap JSON in Markdown fences.';

  Future<String> _buildProjectContext() async {
    final root = widget.workspacePath;
    if (root == null || root.isEmpty) return 'No workspace is open. Answer general questions only and do not propose file changes.';
    final out = StringBuffer();
    out.writeln('Workspace root: ' + p.basename(root));
    out.writeln('PROJECT TREE:');
    out.writeln(await _contextBuilder.tree(root));
    out.writeln('\nOPEN FILE CONTENTS:');
    var remaining = 32000;
    final files = widget.getOpenFiles().take(8).toList(growable: false);
    if (files.isEmpty) out.writeln('(No files open)');
    for (final file in files) {
      if (remaining <= 0) break;
      if (_isSensitiveFile(file.path)) {
        out.writeln('\n--- FILE: ' + file.path + ' --- [contents omitted because the filename appears sensitive]');
        continue;
      }
      final body = file.content.length > remaining ? file.content.substring(0, remaining) : file.content;
      out.writeln('\n--- FILE: ' + file.path + ' ---');
      out.writeln(body);
      remaining -= body.length;
    }
    return out.toString();
  }

  bool _isSensitiveFile(String path) {
    final name = p.basename(path).toLowerCase();
    const sensitiveNames = <String>{
      'credentials.json',
      'service-account.json',
      'secrets.json',
      'id_rsa',
      'id_ed25519',
      'id_ecdsa',
      '.npmrc',
    };
    if (sensitiveNames.contains(name)) return true;
    if (name == '.env') return true;
    if (name.startsWith('.env.') &&
        name != '.env.example' &&
        name != '.env.sample' &&
        name != '.env.template') return true;
    if (name.contains('service-account') || name.contains('service_account') ||
        name.contains('credential') || name.contains('secret')) return true;
    return name.endsWith('.pem') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.key') ||
        name.endsWith('.p8') ||
        name.endsWith('.jks') ||
        name.endsWith('.keystore');
  }

  Future<void> _review(_ChatMessage message) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiAgentReviewDialog(changes: message.changes),
    );
    if (approved != true || !mounted) return;
    try {
      await widget.onApplyChanges({for (final change in message.changes) change.path: change.newContent});
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage('assistant', 'Applied ' + message.changes.length.toString() + ' reviewed file change(s).')));
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMessage('assistant', 'Could not apply changes: ' + _client.friendlyError(error))));
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    });
  }

  Widget _buildLoginView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 30, 18, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: _agentAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(15), border: Border.all(color: _agentAccent.withOpacity(0.3))),
              child: const Icon(Icons.link_rounded, color: _agentAccent, size: 27),
            ),
            const SizedBox(height: 20),
            const Text('Connect AI Agent', style: TextStyle(color: _agentText, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            const Text(
              'Connect your Mallss Nexus Route account. Your system browser will open so you can sign in and approve access. NexusIDE saves the connection securely for future sessions.',
              style: TextStyle(color: _agentMuted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 46, child: FilledButton(
              onPressed: _authBusy ? null : _authenticate,
              style: FilledButton.styleFrom(backgroundColor: _agentAccent, foregroundColor: _agentBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _authBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _agentBg))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.link_rounded, size: 18), SizedBox(width: 9),
                    Text('Connect Mallss Nexus Route', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
            )),
            const SizedBox(height: 13),
            const Text('No gateway URL or API key to enter. You can disconnect the account at any time.', textAlign: TextAlign.center, style: TextStyle(color: _agentMuted, fontSize: 10, height: 1.5)),
            const SizedBox(height: 22),
            const Divider(color: _agentBorder),
            const SizedBox(height: 14),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_user_outlined, color: _agentAccent, size: 16), SizedBox(width: 8),
              Expanded(child: Text('Gateway access tokens are stored in secure device storage and refreshed automatically. NexusIDE never asks for your gateway password inside the IDE.', style: TextStyle(color: _agentMuted, fontSize: 10, height: 1.5))),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: _agentPanel, border: Border(left: BorderSide(color: _agentBorder))),
      child: Column(children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _agentBorder))),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 17, color: _agentAccent),
            const SizedBox(width: 8),
            const Expanded(child: Text('AI AGENT', style: TextStyle(color: _agentText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
            if (_signedIn) ...[
              Flexible(
                child: Text(_displayName ?? _accountEmail ?? 'Signed in', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _agentMuted, fontSize: 10)),
              ),
              IconButton(tooltip: 'Disconnect', onPressed: _authBusy ? null : _logout, visualDensity: VisualDensity.compact, icon: const Icon(Icons.logout_rounded, size: 18, color: _agentMuted)),
            ],
            if (widget.onClose != null) IconButton(tooltip: 'Close AI Agent', onPressed: widget.onClose, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18, color: _agentMuted)),
          ]),
        ),
        if (_status != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _statusError ? const Color(0xFF3A2026) : const Color(0xFF172A2B),
            child: Text(_status!, style: TextStyle(color: _statusError ? const Color(0xFFFFA7AE) : const Color(0xFFA7E8E2), fontSize: 11, height: 1.35)),
          ),
        if (!_signedIn)
          Expanded(child: _buildLoginView())
        else ...[
          if (widget.workspacePath == null)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Open a workspace to enable project context and reviewed file changes.', style: TextStyle(color: _agentMuted, fontSize: 11)),
            ),
          Expanded(child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(10),
            itemCount: _messages.length + (_loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (_loading && index == _messages.length) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentAccent)),
                    const SizedBox(width: 8),
                    Text(_modelId + ' is thinking…', style: const TextStyle(color: _agentMuted, fontSize: 11)),
                  ]),
                );
              }
              final item = _messages[index];
              final isUser = item.role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: isUser ? const Color(0xFF193336) : const Color(0xFF121A24), borderRadius: BorderRadius.only(topLeft: const Radius.circular(14), topRight: const Radius.circular(14), bottomLeft: Radius.circular(isUser ? 14 : 4), bottomRight: Radius.circular(isUser ? 4 : 14)), border: Border.all(color: isUser ? const Color(0xFF285052) : _agentBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isUser ? 'YOU' : _modelId.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isUser ? _agentAccent : _agentMuted, fontSize: 9, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    SelectableText(item.text, style: const TextStyle(color: _agentText, fontSize: 12, height: 1.5)),
                    if (item.changes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _review(item),
                        icon: const Icon(Icons.difference_rounded, size: 15),
                        label: Text('Review ' + item.changes.length.toString() + ' file(s)'),
                        style: OutlinedButton.styleFrom(foregroundColor: _agentAccent, side: const BorderSide(color: _agentBorder), textStyle: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ]),
                ),
              );
            },
          )),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _agentBorder))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _prompt,
                minLines: 2,
                maxLines: 5,
                enabled: !_loading,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: _agentText, fontSize: 12),
                decoration: InputDecoration(hintText: 'Ask Nexus-Free about your code…', hintStyle: const TextStyle(color: _agentMuted, fontSize: 11), filled: true, fillColor: _agentBg, isDense: true, contentPadding: const EdgeInsets.all(10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentBorder))),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Flexible(
                  child: Tooltip(
                    message: 'Choose the model used for new requests',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _models.contains(_selectedModel) ? _selectedModel : null,
                        hint: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_loadingModels ? Icons.sync_rounded : Icons.smart_toy_outlined, size: 14, color: _agentAccent),
                          const SizedBox(width: 5),
                          SizedBox(
                            width: 104,
                            child: Text(
                              _loadingModels ? 'Loading models…' : _selectedModel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _agentText, fontSize: 10),
                            ),
                          ),
                        ]),
                        isExpanded: false,
                        menuMaxHeight: 320,
                        dropdownColor: _agentPanel,
                        icon: const Icon(Icons.expand_more_rounded, color: _agentMuted, size: 16),
                        style: const TextStyle(color: _agentText, fontSize: 11),
                        onChanged: _loading || _loadingModels ? null : _selectModel,
                        items: _models.map((model) => DropdownMenuItem<String>(
                          value: model,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 210),
                            child: Text(model, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        )).toList(growable: false),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh model list',
                  onPressed: _loading || _testing || _loadingModels ? null : _testConnection,
                  visualDensity: VisualDensity.compact,
                  icon: _testing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: _agentAccent))
                      : const Icon(Icons.refresh_rounded, size: 16, color: _agentMuted),
                ),
                FilledButton(onPressed: _loading ? null : _send, style: FilledButton.styleFrom(minimumSize: const Size(38, 34), padding: const EdgeInsets.symmetric(horizontal: 10), backgroundColor: _agentAccent, foregroundColor: _agentBg), child: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentBg)) : const Icon(Icons.arrow_upward_rounded, size: 17)),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ChatMessage {
  _ChatMessage(this.role, this.text, {this.changes = const []});
  final String role;
  final String text;
  final List<AiAgentProposedChange> changes;
}
