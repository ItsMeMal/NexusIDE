import 'dart:convert';

import 'package:flutter/material.dart';
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
  static const _keyName = 'nexuside.gateway.apiKey';
  static const _sessionName = 'nexuside.gateway.sessionCookie';
  static const _apiKeyIdName = 'nexuside.gateway.apiKeyId';
  static const _emailName = 'nexuside.gateway.accountEmail';
  static const _displayNameName = 'nexuside.gateway.displayName';

  final _key = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
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
  bool _registerMode = false;
  bool _signedIn = false;
  String? _sessionCookie;
  String? _apiKeyId;
  String? _accountEmail;
  String? _displayName;
  String? _status;
  bool _statusError = false;

  String get _baseUrl => NexusGatewayClient.defaultBaseUrl;
  String get _gatewayOrigin => _baseUrl.replaceFirst(RegExp(r'/v1
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _key.dispose();
    _email.dispose();
    _password.dispose();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final key = await _secureStorage.read(key: _keyName);
      final cookie = await _secureStorage.read(key: _sessionName);
      final keyId = await _secureStorage.read(key: _apiKeyIdName);
      final email = await _secureStorage.read(key: _emailName);
      final displayName = await _secureStorage.read(key: _displayNameName);

      if (key == null || cookie == null || email == null) {
        // Discard a legacy manually-entered key: NexusIDE now signs in through an account.
        if (key != null && (cookie == null || email == null)) {
          await _secureStorage.delete(key: _keyName);
        }
        if (!mounted) return;
        setState(() {
          _signedIn = false;
          _status = null;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(_gatewayOrigin + '/auth/me'),
        headers: {'Cookie': cookie, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _key.text = key;
          _sessionCookie = cookie;
          _apiKeyId = keyId;
          _accountEmail = email;
          _displayName = displayName ?? email;
          _signedIn = true;
          _status = null;
        });
      } else {
        setState(() {
          _signedIn = false;
          _accountEmail = email;
          _status = 'Your account session has expired. Sign in again to reconnect.';
          _statusError = true;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = false;
        _status = 'Could not restore account session: ' + _client.friendlyError(error);
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

  String? _cookieFromResponse(http.Response response) {
    final header = response.headers['set-cookie'];
    if (header == null || header.trim().isEmpty) return null;
    final pair = header.split(';').first.trim();
    if (!pair.startsWith('mnr_session=')) return null;
    return pair;
  }

  Future<void> _authenticate() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _setStatus('Enter a valid email address.', true);
      return;
    }
    if (password.length < 10 || password.length > 128) {
      _setStatus('Password must contain 10–128 characters.', true);
      return;
    }

    setState(() {
      _authBusy = true;
      _status = _registerMode ? 'Creating your account…' : 'Signing in…';
      _statusError = false;
    });

    String? newCookie;
    String? newKeyId;
    try {
      final endpoint = _registerMode ? '/auth/register' : '/auth/login';
      final response = await http.post(
        Uri.parse(_baseUrl + endpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': email.split('@').first,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = _decodeResponse(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseError(response));
      }
      newCookie = _cookieFromResponse(response);
      if (newCookie == null) {
        throw Exception('The gateway did not return an account session cookie.');
      }

      final userData = responseData?['user'];
      final responseEmail = userData is Map && userData['email'] is String
          ? (userData['email'] as String).toLowerCase()
          : email;
      final displayName = userData is Map && userData['display_name'] is String
          ? userData['display_name'] as String
          : email.split('@').first;

      // If the previous account session is still valid, revoke its app key before replacing it.
      final previousCookie = await _secureStorage.read(key: _sessionName);
      final previousKeyId = await _secureStorage.read(key: _apiKeyIdName);
      final previousEmail = await _secureStorage.read(key: _emailName);
      if (previousKeyId != null && previousCookie != null) {
        final cookieToUse = previousEmail?.toLowerCase() == responseEmail
            ? newCookie
            : previousCookie;
        try {
          await http.delete(
            Uri.parse(_gatewayOrigin + '/account/api-keys/' + previousKeyId),
            headers: {'Cookie': cookieToUse, 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      final keyResponse = await http.post(
        Uri.parse(_gatewayOrigin + '/account/api-keys'),
        headers: {
          'Cookie': newCookie,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'name': 'NexusIDE'}),
      ).timeout(const Duration(seconds: 30));

      final keyData = _decodeResponse(keyResponse.body);
      if (keyResponse.statusCode < 200 || keyResponse.statusCode >= 300) {
        throw Exception(_responseError(keyResponse));
      }
      final rawKey = keyData?['key'];
      final keyId = keyData?['id'];
      if (rawKey is! String || rawKey.isEmpty || keyId == null) {
        throw Exception('The gateway did not return a usable NexusIDE API key.');
      }
      newKeyId = keyId.toString();

      await _secureStorage.write(key: _keyName, value: rawKey);
      await _secureStorage.write(key: _sessionName, value: newCookie);
      await _secureStorage.write(key: _apiKeyIdName, value: newKeyId);
      await _secureStorage.write(key: _emailName, value: responseEmail);
      await _secureStorage.write(key: _displayNameName, value: displayName);

      if (!mounted) return;
      _password.clear();
      setState(() {
        _key.text = rawKey;
        _sessionCookie = newCookie;
        _apiKeyId = newKeyId;
        _accountEmail = responseEmail;
        _displayName = displayName;
        _signedIn = true;
        _authBusy = false;
        _status = 'Signed in. Nexus-Free is ready.';
        _statusError = false;
        _messages
          ..clear()
          ..add(_ChatMessage(
            'assistant',
            'You are signed in. Ask me to explain your code or propose a change; nothing is written until you review it.',
          ));
      });
      _scrollToBottom();
    } catch (error) {
      if (newCookie != null) {
        try {
          if (newKeyId != null) {
            await http.delete(
              Uri.parse(_gatewayOrigin + '/account/api-keys/' + newKeyId),
              headers: {'Cookie': newCookie, 'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 10));
          }
          await http.post(
            Uri.parse(_gatewayOrigin + '/auth/logout'),
            headers: {'Cookie': newCookie},
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _status = _client.friendlyError(error);
        _statusError = true;
      });
    }
  }

  Future<void> _logout() async {
    final cookie = _sessionCookie;
    final keyId = _apiKeyId;
    var revoked = false;
    setState(() {
      _authBusy = true;
      _status = 'Signing out…';
      _statusError = false;
    });
    if (cookie != null && keyId != null) {
      try {
        final response = await http.delete(
          Uri.parse(_gatewayOrigin + '/account/api-keys/' + keyId),
          headers: {'Cookie': cookie, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 15));
        revoked = response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {}
    }
    if (cookie != null) {
      try {
        await http.post(
          Uri.parse(_gatewayOrigin + '/auth/logout'),
          headers: {'Cookie': cookie},
        ).timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    for (final name in <String>[_keyName, _sessionName, _apiKeyIdName, _emailName, _displayNameName]) {
      try {
        await _secureStorage.delete(key: name);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _key.clear();
      _sessionCookie = null;
      _apiKeyId = null;
      _accountEmail = null;
      _displayName = null;
      _signedIn = false;
      _authBusy = false;
      _messages.clear();
      _status = revoked
          ? 'Signed out. The NexusIDE API key was revoked.'
          : 'Signed out locally. If key revocation failed, revoke the NexusIDE key in your gateway dashboard.';
      _statusError = !revoked;
    });
  }

  Future<void> _testConnection() async {
    if (!_signedIn || _key.text.trim().isEmpty) {
      _setStatus('Sign in to your Nexus account first.', true);
      return;
    }
    setState(() {
      _testing = true;
      _status = 'Checking gateway…';
      _statusError = false;
    });
    try {
      final models = await _client.testConnection(_baseUrl, _key.text.trim());
      if (!mounted) return;
      setState(() {
        _testing = false;
        _status = 'Connected. Models found: ' + models.length.toString() + '.';
        _statusError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _status = _client.friendlyError(error);
        _statusError = true;
      });
    }
  }

  Future<void> _send() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _loading) return;
    if (!_signedIn || _key.text.trim().isEmpty) {
      _setStatus('Sign in to your Nexus account first.', true);
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

      final raw = await _client.complete(_baseUrl, _key.text.trim(), _modelId, requestMessages);
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
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _agentAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _agentAccent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: _agentAccent, size: 25),
              ),
              const SizedBox(height: 20),
              Text(
                _registerMode ? 'Create your Nexus account' : 'Sign in to Nexus',
                style: const TextStyle(color: _agentText, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use your Mallss Nexus Route account. NexusIDE will connect Nexus-Free automatically; no API key or model setup is required.',
                style: TextStyle(color: _agentMuted, fontSize: 12, height: 1.55),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_authBusy,
                style: const TextStyle(color: _agentText, fontSize: 13),
                decoration: _authDecoration('Email address', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_authBusy,
                onSubmitted: (_) => _authenticate(),
                style: const TextStyle(color: _agentText, fontSize: 13),
                decoration: _authDecoration('Password', Icons.lock_outline_rounded),
              ),
              const SizedBox(height: 7),
              Text(
                _registerMode ? 'Password must contain 10–128 characters.' : 'Sign in with the same account you use on the gateway website.',
                style: const TextStyle(color: _agentMuted, fontSize: 10, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: _authBusy ? null : _authenticate,
                  style: FilledButton.styleFrom(backgroundColor: _agentAccent, foregroundColor: _agentBg),
                  child: _authBusy
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: _agentBg))
                      : Text(_registerMode ? 'Create account' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _authBusy ? null : () => setState(() {
                  _registerMode = !_registerMode;
                  _status = null;
                }),
                child: Text(
                  _registerMode ? 'Already have an account? Sign in' : 'New to Nexus? Create account',
                  style: const TextStyle(color: _agentMuted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: _agentBorder),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: _agentAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your API key is generated automatically and stored securely on this device. You can sign out to revoke the key.',
                      style: TextStyle(color: _agentMuted, fontSize: 10, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _authDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: _agentMuted),
      filled: true,
      fillColor: _agentBg,
      isDense: true,
      labelStyle: const TextStyle(color: _agentMuted, fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentAccent)),
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
              IconButton(tooltip: 'Sign out', onPressed: _authBusy ? null : _logout, visualDensity: VisualDensity.compact, icon: const Icon(Icons.logout_rounded, size: 18, color: _agentMuted)),
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
                return const Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentAccent)),
                    SizedBox(width: 8),
                    Text('Nexus-Free is thinking…', style: TextStyle(color: _agentMuted, fontSize: 11)),
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
                  decoration: BoxDecoration(color: isUser ? const Color(0xFF193336) : _agentBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: isUser ? const Color(0xFF285052) : _agentBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isUser ? 'YOU' : 'NEXUS-FREE', style: TextStyle(color: isUser ? _agentAccent : _agentMuted, fontSize: 9, fontWeight: FontWeight.w700)),
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
                Expanded(child: Text(NexusGatewayClient.defaultModel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _agentMuted, fontSize: 10))),
                TextButton.icon(onPressed: _loading || _testing ? null : _testConnection, icon: const Icon(Icons.cloud_done_outlined, size: 14), label: const Text('Check'), style: TextButton.styleFrom(foregroundColor: _agentMuted, textStyle: const TextStyle(fontSize: 10))),
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
), '');
  String get _modelId => NexusGatewayClient.defaultModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _key.dispose();
    _email.dispose();
    _password.dispose();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final key = await _secureStorage.read(key: _keyName);
      final cookie = await _secureStorage.read(key: _sessionName);
      final keyId = await _secureStorage.read(key: _apiKeyIdName);
      final email = await _secureStorage.read(key: _emailName);
      final displayName = await _secureStorage.read(key: _displayNameName);

      if (key == null || cookie == null || email == null) {
        // Discard a legacy manually-entered key: NexusIDE now signs in through an account.
        if (key != null && (cookie == null || email == null)) {
          await _secureStorage.delete(key: _keyName);
        }
        if (!mounted) return;
        setState(() {
          _signedIn = false;
          _status = null;
        });
        return;
      }

      final response = await http.get(
        Uri.parse(_gatewayOrigin + '/auth/me'),
        headers: {'Cookie': cookie, 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        setState(() {
          _key.text = key;
          _sessionCookie = cookie;
          _apiKeyId = keyId;
          _accountEmail = email;
          _displayName = displayName ?? email;
          _signedIn = true;
          _status = null;
        });
      } else {
        setState(() {
          _signedIn = false;
          _accountEmail = email;
          _status = 'Your account session has expired. Sign in again to reconnect.';
          _statusError = true;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = false;
        _status = 'Could not restore account session: ' + _client.friendlyError(error);
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

  String? _cookieFromResponse(http.Response response) {
    final header = response.headers['set-cookie'];
    if (header == null || header.trim().isEmpty) return null;
    final pair = header.split(';').first.trim();
    if (!pair.startsWith('mnr_session=')) return null;
    return pair;
  }

  Future<void> _authenticate() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _setStatus('Enter a valid email address.', true);
      return;
    }
    if (password.length < 10 || password.length > 128) {
      _setStatus('Password must contain 10–128 characters.', true);
      return;
    }

    setState(() {
      _authBusy = true;
      _status = _registerMode ? 'Creating your account…' : 'Signing in…';
      _statusError = false;
    });

    String? newCookie;
    String? newKeyId;
    try {
      final endpoint = _registerMode ? '/auth/register' : '/auth/login';
      final response = await http.post(
        Uri.parse(_baseUrl + endpoint),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': email.split('@').first,
        }),
      ).timeout(const Duration(seconds: 30));

      final responseData = _decodeResponse(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_responseError(response));
      }
      newCookie = _cookieFromResponse(response);
      if (newCookie == null) {
        throw Exception('The gateway did not return an account session cookie.');
      }

      final userData = responseData?['user'];
      final responseEmail = userData is Map && userData['email'] is String
          ? (userData['email'] as String).toLowerCase()
          : email;
      final displayName = userData is Map && userData['display_name'] is String
          ? userData['display_name'] as String
          : email.split('@').first;

      // If the previous account session is still valid, revoke its app key before replacing it.
      final previousCookie = await _secureStorage.read(key: _sessionName);
      final previousKeyId = await _secureStorage.read(key: _apiKeyIdName);
      final previousEmail = await _secureStorage.read(key: _emailName);
      if (previousKeyId != null && previousCookie != null) {
        final cookieToUse = previousEmail?.toLowerCase() == responseEmail
            ? newCookie
            : previousCookie;
        try {
          await http.delete(
            Uri.parse(_gatewayOrigin + '/account/api-keys/' + previousKeyId),
            headers: {'Cookie': cookieToUse, 'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      final keyResponse = await http.post(
        Uri.parse(_gatewayOrigin + '/account/api-keys'),
        headers: {
          'Cookie': newCookie,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'name': 'NexusIDE'}),
      ).timeout(const Duration(seconds: 30));

      final keyData = _decodeResponse(keyResponse.body);
      if (keyResponse.statusCode < 200 || keyResponse.statusCode >= 300) {
        throw Exception(_responseError(keyResponse));
      }
      final rawKey = keyData?['key'];
      final keyId = keyData?['id'];
      if (rawKey is! String || rawKey.isEmpty || keyId == null) {
        throw Exception('The gateway did not return a usable NexusIDE API key.');
      }
      newKeyId = keyId.toString();

      await _secureStorage.write(key: _keyName, value: rawKey);
      await _secureStorage.write(key: _sessionName, value: newCookie);
      await _secureStorage.write(key: _apiKeyIdName, value: newKeyId);
      await _secureStorage.write(key: _emailName, value: responseEmail);
      await _secureStorage.write(key: _displayNameName, value: displayName);

      if (!mounted) return;
      _password.clear();
      setState(() {
        _key.text = rawKey;
        _sessionCookie = newCookie;
        _apiKeyId = newKeyId;
        _accountEmail = responseEmail;
        _displayName = displayName;
        _signedIn = true;
        _authBusy = false;
        _status = 'Signed in. Nexus-Free is ready.';
        _statusError = false;
        _messages
          ..clear()
          ..add(_ChatMessage(
            'assistant',
            'You are signed in. Ask me to explain your code or propose a change; nothing is written until you review it.',
          ));
      });
      _scrollToBottom();
    } catch (error) {
      if (newCookie != null) {
        try {
          if (newKeyId != null) {
            await http.delete(
              Uri.parse(_gatewayOrigin + '/account/api-keys/' + newKeyId),
              headers: {'Cookie': newCookie, 'Accept': 'application/json'},
            ).timeout(const Duration(seconds: 10));
          }
          await http.post(
            Uri.parse(_gatewayOrigin + '/auth/logout'),
            headers: {'Cookie': newCookie},
          ).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _status = _client.friendlyError(error);
        _statusError = true;
      });
    }
  }

  Future<void> _logout() async {
    final cookie = _sessionCookie;
    final keyId = _apiKeyId;
    var revoked = false;
    setState(() {
      _authBusy = true;
      _status = 'Signing out…';
      _statusError = false;
    });
    if (cookie != null && keyId != null) {
      try {
        final response = await http.delete(
          Uri.parse(_gatewayOrigin + '/account/api-keys/' + keyId),
          headers: {'Cookie': cookie, 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 15));
        revoked = response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {}
    }
    if (cookie != null) {
      try {
        await http.post(
          Uri.parse(_gatewayOrigin + '/auth/logout'),
          headers: {'Cookie': cookie},
        ).timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    for (final name in <String>[_keyName, _sessionName, _apiKeyIdName, _emailName, _displayNameName]) {
      try {
        await _secureStorage.delete(key: name);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _key.clear();
      _sessionCookie = null;
      _apiKeyId = null;
      _accountEmail = null;
      _displayName = null;
      _signedIn = false;
      _authBusy = false;
      _messages.clear();
      _status = revoked
          ? 'Signed out. The NexusIDE API key was revoked.'
          : 'Signed out locally. If key revocation failed, revoke the NexusIDE key in your gateway dashboard.';
      _statusError = !revoked;
    });
  }

  Future<void> _testConnection() async {
    if (!_signedIn || _key.text.trim().isEmpty) {
      _setStatus('Sign in to your Nexus account first.', true);
      return;
    }
    setState(() {
      _testing = true;
      _status = 'Checking gateway…';
      _statusError = false;
    });
    try {
      final models = await _client.testConnection(_baseUrl, _key.text.trim());
      if (!mounted) return;
      setState(() {
        _testing = false;
        _status = 'Connected. Models found: ' + models.length.toString() + '.';
        _statusError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _status = _client.friendlyError(error);
        _statusError = true;
      });
    }
  }

  Future<void> _send() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _loading) return;
    if (!_signedIn || _key.text.trim().isEmpty) {
      _setStatus('Sign in to your Nexus account first.', true);
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

      final raw = await _client.complete(_baseUrl, _key.text.trim(), _modelId, requestMessages);
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
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _agentAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _agentAccent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: _agentAccent, size: 25),
              ),
              const SizedBox(height: 20),
              Text(
                _registerMode ? 'Create your Nexus account' : 'Sign in to Nexus',
                style: const TextStyle(color: _agentText, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use your Mallss Nexus Route account. NexusIDE will connect Nexus-Free automatically; no API key or model setup is required.',
                style: TextStyle(color: _agentMuted, fontSize: 12, height: 1.55),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_authBusy,
                style: const TextStyle(color: _agentText, fontSize: 13),
                decoration: _authDecoration('Email address', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_authBusy,
                onSubmitted: (_) => _authenticate(),
                style: const TextStyle(color: _agentText, fontSize: 13),
                decoration: _authDecoration('Password', Icons.lock_outline_rounded),
              ),
              const SizedBox(height: 7),
              Text(
                _registerMode ? 'Password must contain 10–128 characters.' : 'Sign in with the same account you use on the gateway website.',
                style: const TextStyle(color: _agentMuted, fontSize: 10, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: _authBusy ? null : _authenticate,
                  style: FilledButton.styleFrom(backgroundColor: _agentAccent, foregroundColor: _agentBg),
                  child: _authBusy
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: _agentBg))
                      : Text(_registerMode ? 'Create account' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _authBusy ? null : () => setState(() {
                  _registerMode = !_registerMode;
                  _status = null;
                }),
                child: Text(
                  _registerMode ? 'Already have an account? Sign in' : 'New to Nexus? Create account',
                  style: const TextStyle(color: _agentMuted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: _agentBorder),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, color: _agentAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your API key is generated automatically and stored securely on this device. You can sign out to revoke the key.',
                      style: TextStyle(color: _agentMuted, fontSize: 10, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _authDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: _agentMuted),
      filled: true,
      fillColor: _agentBg,
      isDense: true,
      labelStyle: const TextStyle(color: _agentMuted, fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _agentAccent)),
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
                child: Text(_accountEmail ?? 'Signed in', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _agentMuted, fontSize: 10)),
              ),
              IconButton(tooltip: 'Sign out', onPressed: _authBusy ? null : _logout, visualDensity: VisualDensity.compact, icon: const Icon(Icons.logout_rounded, size: 18, color: _agentMuted)),
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
                return const Padding(
                  padding: EdgeInsets.all(10),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentAccent)),
                    SizedBox(width: 8),
                    Text('Nexus-Free is thinking…', style: TextStyle(color: _agentMuted, fontSize: 11)),
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
                  decoration: BoxDecoration(color: isUser ? const Color(0xFF193336) : _agentBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: isUser ? const Color(0xFF285052) : _agentBorder)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isUser ? 'YOU' : 'NEXUS-FREE', style: TextStyle(color: isUser ? _agentAccent : _agentMuted, fontSize: 9, fontWeight: FontWeight.w700)),
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
                Expanded(child: Text(NexusGatewayClient.defaultModel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _agentMuted, fontSize: 10))),
                TextButton.icon(onPressed: _loading || _testing ? null : _testConnection, icon: const Icon(Icons.cloud_done_outlined, size: 14), label: const Text('Check'), style: TextButton.styleFrom(foregroundColor: _agentMuted, textStyle: const TextStyle(fontSize: 10))),
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
