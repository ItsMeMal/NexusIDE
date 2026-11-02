import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class NexusGatewayClient {
  static const defaultBaseUrl = 'https://ai-router.mallss-nexus.sbs/v1';
  static const defaultModel = 'Nexus-Free';

  String normalizeUrl(String value) => value.trim().replaceAll(RegExp(r'/+$'), '');

  Future<List<String>> testConnection(String url, String key) async {
    final response = await http.get(
      Uri.parse(normalizeUrl(url) + '/models'),
      headers: {'Authorization': 'Bearer ' + key.trim()},
    ).timeout(const Duration(seconds: 25));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_error(data, response.statusCode));
    }
    final result = <String>[];
    final entries = data?['data'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is Map && entry['id'] is String) result.add(entry['id'] as String);
      }
    }
    result.sort();
    return result;
  }

  Future<String> complete(String url, String key, String model, List<Map<String, String>> messages) async {
    final response = await http.post(
      Uri.parse(normalizeUrl(url) + '/chat/completions'),
      headers: {
        'Authorization': 'Bearer ' + key.trim(),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'model': model.trim(), 'messages': messages, 'stream': false, 'temperature': 0.2}),
    ).timeout(const Duration(seconds: 150));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_error(data, response.statusCode));
    }
    final choices = data?['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) throw Exception('Gateway returned no completion.');
    final message = (choices.first as Map)['message'];
    if (message is! Map || message['content'] == null) throw Exception('Model returned an empty message.');
    final content = message['content'];
    if (content is String) return content;
    if (content is List) return content.whereType<Map>().map((x) => x['text'] is String ? x['text'] as String : '').where((x) => x.isNotEmpty).join('\n');
    return content.toString();
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final value = jsonDecode(body);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return null;
  }

  String _error(Map<String, dynamic>? data, int status) {
    final error = data?['error'];
    if (error is Map && error['message'] is String) return 'Gateway HTTP ' + status.toString() + ': ' + (error['message'] as String);
    return 'Gateway HTTP ' + status.toString() + '. Check API key, model ID, and quota.';
  }

  String friendlyError(Object error) {
    if (error is TimeoutException) return 'Gateway timed out.';
    if (error is SocketException) return 'Cannot reach gateway. Check network and API URL.';
    if (error is FormatException) return 'Gateway returned invalid data.';
    return error.toString().replaceFirst('Exception: ', '');
  }
}
