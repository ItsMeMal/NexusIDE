import 'dart:io';
import 'package:path/path.dart' as p;

class AiAgentContextFile {
  const AiAgentContextFile(this.path, this.content);
  final String path;
  final String content;
}

class AiAgentWorkspaceContext {
  Future<String> tree(String path) async {
    final root = Directory(path);
    if (!await root.exists()) return '(workspace unavailable)';
    const ignored = <String>{'.git', '.dart_tool', 'build', 'dist', 'node_modules', '.gradle', 'vendor'};
    final lines = <String>[];
    final queue = <MapEntry<Directory, int>>[MapEntry(root, 0)];
    while (queue.isNotEmpty && lines.length < 140) {
      final current = queue.removeAt(0);
      List<FileSystemEntity> entries;
      try {
        entries = await current.key.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      entries.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      for (final entry in entries) {
        if (lines.length >= 140) break;
        final name = p.basename(entry.path);
        if (entry is Directory && ignored.contains(name)) continue;
        lines.add(('  ' * current.value) + name + (entry is Directory ? '/' : ''));
        if (entry is Directory && current.value < 4) queue.add(MapEntry(entry, current.value + 1));
      }
    }
    return lines.isEmpty ? '(empty workspace)' : lines.join('\n');
  }
}
