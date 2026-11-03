import 'dart:io';

import 'package:path/path.dart' as p;

class AiAgentContextFile {
  const AiAgentContextFile(this.path, this.content);
  final String path;
  final String content;
}

class AiAgentWorkspaceContext {
  static const _ignoredDirectories = <String>{
    '.git',
    '.dart_tool',
    'build',
    'dist',
    'node_modules',
    'vendor',
    '.gradle',
    '.next',
    'coverage',
    'target',
    'out',
  };

  static const _textExtensions = <String>{
    '.dart', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx',
    '.py', '.pyi', '.java', '.kt', '.kts', '.cs', '.go', '.rs',
    '.php', '.rb', '.swift', '.c', '.h', '.cc', '.cpp', '.cxx',
    '.hpp', '.html', '.htm', '.css', '.scss', '.less', '.sass',
    '.json', '.jsonc', '.yaml', '.yml', '.toml', '.ini', '.cfg',
    '.xml', '.svg', '.md', '.mdx', '.sql', '.sh', '.bash', '.zsh',
    '.ps1', '.psm1', '.bat', '.cmd', '.gradle', '.properties',
    '.tf', '.hcl', '.proto', '.graphql', '.gql', '.vue', '.svelte',
    '.astro', '.env.example', '.txt',
  };

  static const _priorityFiles = <String>{
    'readme.md',
    'pubspec.yaml',
    'package.json',
    'tsconfig.json',
    'analysis_options.yaml',
    'cargo.toml',
    'go.mod',
    'pyproject.toml',
    'requirements.txt',
    'pom.xml',
    'build.gradle',
    'settings.gradle',
    'cmakelists.txt',
    'makefile',
    'dockerfile',
    'compose.yaml',
    'docker-compose.yml',
  };

  Future<String> tree(String path) async {
    final root = Directory(path);
    if (!await root.exists()) return '(workspace unavailable)';
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
        if (entry is Directory && _ignoredDirectories.contains(name.toLowerCase())) continue;
        lines.add(('  ' * current.value) + name + (entry is Directory ? '/' : ''));
        if (entry is Directory && current.value < 4) {
          queue.add(MapEntry(entry, current.value + 1));
        }
      }
    }
    return lines.isEmpty ? '(empty workspace)' : lines.join('\n');
  }

  /// Reads useful project source/configuration from disk as well as unsaved
  /// editor buffers. Open buffers take priority so the model sees current edits.
  Future<List<AiAgentContextFile>> readFiles(
    String path, {
    List<AiAgentContextFile> preferredFiles = const <AiAgentContextFile>[],
    int maxFiles = 16,
    int maxChars = 48000,
  }) async {
    final rootPath = p.normalize(p.absolute(path));
    final root = Directory(rootPath);
    if (!await root.exists()) return <AiAgentContextFile>[];

    final result = <String, AiAgentContextFile>{};
    var usedChars = 0;

    void addFile(String relativePath, String content) {
      if (result.length >= maxFiles || usedChars >= maxChars) return;
      final normalized = relativePath.replaceAll(String.fromCharCode(92), '/');
      if (!_isSafeTextPath(normalized)) return;
      final key = normalized.toLowerCase();
      if (result.containsKey(key)) {
        result.remove(key);
      }
      final remaining = maxChars - usedChars;
      final body = content.length > remaining ? content.substring(0, remaining) : content;
      result[key] = AiAgentContextFile(normalized, body);
      usedChars += body.length;
    }

    for (final file in preferredFiles) {
      if (result.length >= maxFiles || usedChars >= maxChars) break;
      addFile(file.path, file.content);
    }

    final candidates = <_WorkspaceCandidate>[];
    final queue = <MapEntry<Directory, int>>[MapEntry(root, 0)];
    var scanned = 0;
    while (queue.isNotEmpty && scanned < 1200) {
      final current = queue.removeAt(0);
      List<FileSystemEntity> entries;
      try {
        entries = await current.key.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      entries.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      for (final entry in entries) {
        if (++scanned > 1200) break;
        final name = p.basename(entry.path);
        final lowerName = name.toLowerCase();
        if (entry is Link) continue;
        if (entry is Directory) {
          if (!_ignoredDirectories.contains(lowerName) && current.value < 7) {
            queue.add(MapEntry(entry, current.value + 1));
          }
          continue;
        }
        if (entry is! File || !_isSafeTextPath(name)) continue;
        try {
          final length = await entry.length();
          if (length <= 0 || length > 350000) continue;
        } catch (_) {
          continue;
        }
        final relative = p.relative(entry.path, from: rootPath).replaceAll(String.fromCharCode(92), '/');
        candidates.add(_WorkspaceCandidate(relative, entry.path, _priority(relative)));
      }
    }

    candidates.sort((a, b) {
      final score = a.priority.compareTo(b.priority);
      if (score != 0) return score;
      final depth = a.relativePath.split('/').length.compareTo(b.relativePath.split('/').length);
      if (depth != 0) return depth;
      return a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase());
    });

    for (final candidate in candidates) {
      if (result.length >= maxFiles || usedChars >= maxChars) break;
      if (result.containsKey(candidate.relativePath.toLowerCase())) continue;
      try {
        final content = await File(candidate.absolutePath).readAsString();
        if (content.trim().isEmpty) continue;
        addFile(candidate.relativePath, content);
      } catch (_) {
        // Skip binary, unreadable, or concurrently removed files.
      }
    }
    return result.values.toList(growable: false);
  }

  int _priority(String relativePath) {
    final name = p.basename(relativePath).toLowerCase();
    if (_priorityFiles.contains(name)) return 0;
    if (const <String>{
      'main.dart', 'main.py', 'main.js', 'main.ts', 'main.tsx',
      'index.js', 'index.ts', 'index.tsx', 'app.dart', 'app.py',
      'app.js', 'app.ts', 'app.tsx', 'server.js', 'server.ts',
      'routes.dart', 'router.dart',
    }.contains(name)) return 1;
    if (relativePath.split('/').length <= 2) return 2;
    return 3;
  }

  bool _isSafeTextPath(String path) {
    final normalized = path.replaceAll(String.fromCharCode(92), '/');
    final segments = normalized.split('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains(':') ||
        segments.any((part) => part.isEmpty || part == '.' || part == '..') ||
        segments.any((part) => _ignoredDirectories.contains(part.toLowerCase()))) {
      return false;
    }
    final name = p.basename(normalized).toLowerCase();
    if (name == 'skill.md') return false;
    if (name == '.env' ||
        (name.startsWith('.env.') &&
            name != '.env.example' &&
            name != '.env.sample' &&
            name != '.env.template') ||
        name == '.npmrc' ||
        name == 'credentials.json' ||
        name == 'service-account.json' ||
        name == 'secrets.json' ||
        name.contains('service-account') ||
        name.contains('service_account') ||
        name.contains('credential') ||
        name.contains('secret') ||
        name.endsWith('.lock') ||
        name.endsWith('.min.js') ||
        name.endsWith('.min.css') ||
        name.endsWith('.pem') ||
        name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.key') ||
        name.endsWith('.p8') ||
        name.endsWith('.jks') ||
        name.endsWith('.keystore') ||
        name == 'id_rsa' ||
        name == 'id_ed25519' ||
        name == 'id_ecdsa') {
      return false;
    }
    if (name == 'dockerfile' || name == 'makefile' || name == 'procfile') return true;
    if (_textExtensions.any(name.endsWith)) return true;
    final extension = p.extension(name);
    return extension.isEmpty &&
        (name == '.gitignore' ||
         name == '.gitattributes' ||
         name == '.editorconfig' ||
         name == '.prettierrc' ||
         name == '.eslintrc');
  }
}

class _WorkspaceCandidate {
  const _WorkspaceCandidate(this.relativePath, this.absolutePath, this.priority);
  final String relativePath;
  final String absolutePath;
  final int priority;
}
