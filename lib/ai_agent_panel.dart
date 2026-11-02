import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _urlPreference = 'nexuside.gateway.baseUrl';
  static const _modelPreference = 'nexuside.gateway.model';
  static const _keyName = 'nexuside.gateway.apiKey';

  final _url = TextEditingController(text: NexusGatewayClient.defaultBaseUrl);
  final _key = TextEditingController();
  final _model = TextEditingController(text: NexusGatewayClient.defaultModel);
  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  final _secureStorage = FlutterSecureStorage();
  final _client = NexusGatewayClient();
  final _contextBuilder = AiAgentWorkspaceContext();
  final _parser = AiAgentProposalParser();
  final List<_ChatMessage> _messages = [];

  bool _loading = false;
  bool _testing = false;
  String? _status;
  bool _statusError = false;

  String get _baseUrl => _client.normalizeUrl(_url.text);
  String get _modelId => _model.text.trim();

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      'assistant',
      'I can explain code or prepare file changes for review. Configure your gateway API key to get started.',
    ));
    _loadSettings();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedUrl = preferences.getString(_urlPreference);
      final savedModel = preferences.getString(_modelPreference);
      final savedKey = await _secureStorage.read(key: _keyName);
      if (!mounted) return;
      setState(() {
        if (savedUrl != null && savedUrl.isNotEmpty) _url.text = savedUrl;
        if (savedModel != null && savedModel.isNotEmpty) _model.text = savedModel;
        _key.text = savedKey ?? '';
      });
    } catch (error) {
      _setStatus('Could not load saved settings: ' + _client.friendlyError(error), true);
    }
  }

  void _setStatus(String text, [bool error = false]) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusError = error;
    });
  }

  Future<void> _saveSettings() async {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || uri.host.isEmpty ||
        !uri.path.endsWith('/v1') ||
        (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && (uri.host == 'localhost' || uri.host == '127.0.0.1')))) {
      _setStatus('Use a valid HTTPS API base URL ending in /v1.', true);
      return;
    }
    if (_modelId.isEmpty) {
      _setStatus('Enter a model ID, such as Nexus-Free.', true);
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_urlPreference, _baseUrl);
      await preferences.setString(_modelPreference, _modelId);
      if (_key.text.trim().isEmpty) {
        await _secureStorage.delete(key: _keyName);
      } else {
        await _secureStorage.write(key: _keyName, value: _key.text.trim());
      }
      _setStatus('Gateway settings saved on this device.');
    } catch (error) {
      _setStatus('Could not save settings: ' + _client.friendlyError(error), true);
    }
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _agentPanel,
        title: const Row(children: [
          Icon(Icons.tune_rounded, color: _agentAccent, size: 20),
          SizedBox(width: 8),
          Text('AI Agent settings'),
        ]),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Use an API key created in your Mallss Nexus Route dashboard.',
              style: TextStyle(color: _agentMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _settingsField(_url, 'API base URL', NexusGatewayClient.defaultBaseUrl),
            const SizedBox(height: 10),
            _settingsField(_key, 'Gateway API key', 'Paste your gateway key', secret: true),
            const SizedBox(height: 10),
            _settingsField(_model, 'Model ID', NexusGatewayClient.defaultModel),
            const SizedBox(height: 10),
            const Text(
              'The key is stored using secure device storage. Open-file content and the workspace tree are sent when you submit a prompt.',
              style: TextStyle(color: _agentMuted, fontSize: 11, height: 1.4),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: _testing ? null : () async {
              await _testConnection();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: _testing ? const Text('Testing…') : const Text('Test connection'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await _saveSettings();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _settingsField(TextEditingController controller, String label, String hint, {bool secret = false}) {
    return TextField(
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      style: const TextStyle(color: _agentText, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: _agentBg,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (_key.text.trim().isEmpty) {
      _setStatus('Add your gateway API key in settings first.', true);
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
    if (_key.text.trim().isEmpty || _modelId.isEmpty) {
      _setStatus('Open settings and add your gateway API key and model ID.', true);
      await _showSettings();
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
      final changes = await _parser.prepare(widget.workspacePath, parsed.changes);
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
      'credentials.json', 'service-account.json', 'secrets.json',
      'id_rsa', 'id_ed25519', 'id_ecdsa',
    };
    if (sensitiveNames.contains(name)) return true;
    if (name == '.env') return true;
    if (name.startsWith('.env.') &&
        name != '.env.example' &&
        name != '.env.sample' &&
        name != '.env.template') return true;
    return name.endsWith('.pem') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.key');
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
            IconButton(tooltip: 'Gateway settings', onPressed: _showSettings, visualDensity: VisualDensity.compact, icon: const Icon(Icons.tune_rounded, size: 18, color: _agentMuted)),
            if (widget.onClose != null) IconButton(tooltip: 'Close AI Agent', onPressed: widget.onClose, visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18, color: _agentMuted)),
          ]),
        ),
        if (_status != null)
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), color: _statusError ? const Color(0xFF3A2026) : const Color(0xFF172A2B), child: Text(_status!, style: TextStyle(color: _statusError ? const Color(0xFFFFA7AE) : const Color(0xFFA7E8E2), fontSize: 11))),
        if (widget.workspacePath == null)
          const Padding(padding: EdgeInsets.all(10), child: Text('Open a workspace to enable project context and reviewed file changes.', style: TextStyle(color: _agentMuted, fontSize: 11))),
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(10),
          itemCount: _messages.length + (_loading ? 1 : 0),
          itemBuilder: (context, index) {
            if (_loading && index == _messages.length) {
              return const Padding(padding: EdgeInsets.all(10), child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentAccent)),
                SizedBox(width: 8),
                Text('Nexus-Free is thinking…', style: TextStyle(color: _agentMuted, fontSize: 11)),
              ]));
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
              Expanded(child: Text(_modelId.isEmpty ? NexusGatewayClient.defaultModel : _modelId, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _agentMuted, fontSize: 10))),
              TextButton.icon(onPressed: _loading || _testing ? null : _testConnection, icon: const Icon(Icons.cloud_done_outlined, size: 14), label: const Text('Connect'), style: TextButton.styleFrom(foregroundColor: _agentMuted, textStyle: const TextStyle(fontSize: 10))),
              FilledButton(onPressed: _loading ? null : _send, style: FilledButton.styleFrom(minimumSize: const Size(38, 34), padding: const EdgeInsets.symmetric(horizontal: 10), backgroundColor: _agentAccent, foregroundColor: _agentBg), child: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _agentBg)) : const Icon(Icons.arrow_upward_rounded, size: 17)),
            ]),
          ]),
        ),
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
