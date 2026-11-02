import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class AiAgentProposedChange {
  const AiAgentProposedChange(this.path, this.absolutePath, this.oldContent, this.newContent);
  final String path;
  final String absolutePath;
  final String? oldContent;
  final String newContent;
  bool get isNew => oldContent == null;
}
class AiAgentResponse {
  const AiAgentResponse(this.message, this.changes);
  final String message;
  final List<Map<String, String>> changes;
}
class AiAgentProposalParser {
  AiAgentResponse parse(String raw) {
    var value = raw.trim();
    final fence = String.fromCharCode(96) * 3;
    if (value.startsWith(fence)) {
      final newline = value.indexOf('\n');
      if (newline >= 0) value = value.substring(newline + 1);
      if (value.endsWith(fence)) value = value.substring(0, value.length - 3).trim();
    }
    final first = value.indexOf('{');
    final last = value.lastIndexOf('}');
    if (first >= 0 && last > first) value = value.substring(first, last + 1);
    try {
      final json = jsonDecode(value);
      if (json is Map) {
        final changes = <Map<String, String>>[];
        final list = json['changes'];
        if (list is List) for (final item in list.take(16)) {
          if (item is Map && item['path'] is String && item['content'] is String) {
            changes.add({'path': item['path'] as String, 'content': item['content'] as String});
          }
        }
        return AiAgentResponse(json['message'] is String ? json['message'] as String : raw, changes);
      }
    } catch (_) {}
    return AiAgentResponse(raw, const []);
  }

  Future<List<AiAgentProposedChange>> prepare(String? workspace, List<Map<String, String>> proposed) async {
    if (workspace == null || workspace.isEmpty) return [];
    final root = p.normalize(p.absolute(workspace));
    final result = <AiAgentProposedChange>[];
    final seen = <String>{};
    for (final item in proposed) {
      final relative = item['path']!.trim().split(String.fromCharCode(92)).join('/');
      final parts = relative.split('/');
      if (relative.isEmpty || relative.startsWith('/') || relative.contains(':') ||
          parts.any((s) => s.isEmpty || s == '.' || s == '..') ||
          parts.contains('.git') || parts.contains('node_modules') || item['content']!.length > 500000) continue;
      final absolute = p.normalize(p.join(root, parts.join(p.separator)));
      if (!p.isWithin(root, absolute) || p.equals(root, absolute) || !seen.add(absolute.toLowerCase())) continue;

      // Do not read or propose writes through symbolic links.
      var linkedParent = false;
      var parent = root;
      for (final segment in parts.take(parts.length - 1)) {
        parent = p.join(parent, segment);
        if (await FileSystemEntity.type(parent, followLinks: false) == FileSystemEntityType.link) {
          linkedParent = true;
          break;
        }
      }
      if (linkedParent) continue;
      final targetType = await FileSystemEntity.type(absolute, followLinks: false);
      if (targetType == FileSystemEntityType.link || targetType == FileSystemEntityType.directory) continue;
      String? oldContent;
      try {
        final file = File(absolute);
        if (await file.exists()) oldContent = await file.readAsString();
      } catch (_) { continue; }
      result.add(AiAgentProposedChange(relative, absolute, oldContent, item['content']!));
    }
    return result;
  }
}
