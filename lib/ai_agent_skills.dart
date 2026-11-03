import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Portable Agent Skills loader. Bundled scripts and other skill resources are
/// instruction-only: NexusIDE does not execute them.
class AgentSkill {
  const AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    required this.source,
    required this.isBuiltIn,
  });

  final String id;
  final String name;
  final String description;
  final String instructions;
  final String source;
  final bool isBuiltIn;
}

class AiAgentSkillsService {
  static const _builtInPaths = <String>[
    'assets/agent_skills/coding-implementation/SKILL.md',
    'assets/agent_skills/debugging/SKILL.md',
    'assets/agent_skills/flutter-development/SKILL.md',
    'assets/agent_skills/ui-ux-design/SKILL.md',
    'assets/agent_skills/testing/SKILL.md',
    'assets/agent_skills/secure-code-review/SKILL.md',
    'assets/agent_skills/api-integration/SKILL.md',
  ];

  static const _skillRoots = <String>[
    '.agents/skills',
    '.claude/skills',
    '.github/skills',
    '.cursor/skills',
    '.skills',
    'skills',
  ];

  static const _stopWords = <String>{
    'about', 'after', 'also', 'and', 'application', 'asked', 'can', 'code',
    'does', 'for', 'from', 'have', 'help', 'into', 'just', 'make', 'need',
    'nexuside', 'please', 'project', 'should', 'that', 'their', 'them',
    'then', 'this', 'with', 'when', 'where', 'will', 'work', 'your',
    'using', 'want', 'feature', 'change', 'build', 'create', 'implement',
    'update', 'support', 'buat', 'bikin', 'tambah', 'tambahkan', 'perbaiki',
    'betulin', 'ubah', 'rubah', 'aplikasi', 'fitur', 'dong', 'saya', 'yang',
    'untuk', 'dengan', 'pada', 'dari', 'agar', 'bisa', 'juga', 'ini',
  };

  static const _skillAliases = <String, Set<String>>{
    'ui-ux-design': <String>{
      'ui', 'ux', 'interface', 'screen', 'layout', 'styling', 'frontend',
      'responsive', 'visual', 'design', 'accessibility',
    },
    'flutter-development': <String>{
      'flutter', 'dart', 'widget', 'windows', 'android', 'mobile',
    },
    'api-integration': <String>{
      'api', 'oauth', 'rest', 'endpoint', 'http', 'json', 'gateway', 'token',
    },
    'secure-code-review': <String>{
      'security', 'auth', 'oauth', 'secret', 'credential', 'vulnerability',
      'validation', 'permission', 'token',
    },
    'debugging': <String>{
      'error', 'exception', 'stack', 'trace', 'bug', 'crash', 'failed',
    },
    'testing': <String>{
      'test', 'testing', 'unit', 'widget', 'integration', 'coverage',
      'regression', 'verify',
    },
  };

  Future<List<AgentSkill>> loadSkills(String? workspacePath) async {
    final byId = <String, AgentSkill>{};

    for (final assetPath in _builtInPaths) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        final skill = _parse(
          raw,
          source: 'Built-in',
          isBuiltIn: true,
          fallbackName: p.basename(p.dirname(assetPath)),
        );
        if (skill != null) byId[skill.id] = skill;
      } catch (_) {
        // A missing bundled skill must not prevent the remaining skills loading.
      }
    }

    if (workspacePath != null && workspacePath.trim().isNotEmpty) {
      final root = Directory(p.normalize(p.absolute(workspacePath)));
      if (await root.exists()) {
        for (final relative in _skillRoots) {
          final directory = Directory(p.join(root.path, relative));
          if (await directory.exists()) {
            await _scanRoot(directory, root.path, byId, maxSkills: 80);
          }
        }
      }
    }

    final skills = byId.values.toList(growable: false);
    skills.sort((a, b) {
      if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return skills;
  }

  Future<void> _scanRoot(
    Directory root,
    String workspacePath,
    Map<String, AgentSkill> output, {
    required int maxSkills,
  }) async {
    List<FileSystemEntity> children;
    try {
      children = await root.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    for (final child in children) {
      if (output.length >= maxSkills) return;
      if (child is! Directory || child is Link) continue;

      final skillFile = File(p.join(child.path, 'SKILL.md'));
      if (await skillFile.exists()) {
        await _loadProjectSkill(skillFile, workspacePath, output);
        continue;
      }

      // Also support category nesting: skills/frontend/my-skill/SKILL.md.
      List<FileSystemEntity> nested;
      try {
        nested = await child.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final item in nested) {
        if (output.length >= maxSkills) return;
        if (item is! Directory || item is Link) continue;
        final nestedFile = File(p.join(item.path, 'SKILL.md'));
        if (await nestedFile.exists()) {
          await _loadProjectSkill(nestedFile, workspacePath, output);
        }
      }
    }
  }

  Future<void> _loadProjectSkill(
    File file,
    String workspacePath,
    Map<String, AgentSkill> output,
  ) async {
    try {
      if (await file.length() > 40000) return;
      final raw = await file.readAsString();
      final relative = p.relative(file.parent.path, from: workspacePath)
          .replaceAll(String.fromCharCode(92), '/');
      final skill = _parse(
        raw,
        source: relative,
        isBuiltIn: false,
        fallbackName: p.basename(file.parent.path),
      );
      if (skill != null) {
        // A project skill can override a bundled skill with the same ID.
        output[skill.id] = skill;
      }
    } catch (_) {
      // Skip malformed, unreadable, or concurrently removed files.
    }
  }

  AgentSkill? _parse(
    String raw, {
    required String source,
    required bool isBuiltIn,
    required String fallbackName,
  }) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return null;
    final close = normalized.indexOf('\n---', 4);
    if (close < 0) return null;

    final frontmatter = normalized.substring(4, close);
    final bodyStart = normalized.indexOf('\n', close + 4);
    if (bodyStart < 0) return null;
    final instructions = normalized.substring(bodyStart + 1).trim();
    if (instructions.isEmpty) return null;

    final declaredName = _readScalar(frontmatter, 'name');
    final description = (_readScalar(frontmatter, 'description') ?? '').trim();
    final rawName = declaredName == null || declaredName.isEmpty
        ? fallbackName
        : declaredName;
    final id = _slug(rawName);
    if (id.isEmpty || description.isEmpty) return null;

    return AgentSkill(
      id: id,
      name: rawName.replaceAll('-', ' ').trim(),
      description: description.length > 1024
          ? description.substring(0, 1024)
          : description,
      instructions: instructions.length > 14000
          ? instructions.substring(0, 14000)
          : instructions,
      source: source,
      isBuiltIn: isBuiltIn,
    );
  }

  String? _readScalar(String frontmatter, String key) {
    for (final line in frontmatter.split('\n')) {
      final match = RegExp(
        RegExp(r'^\s*' + RegExp.escape(key) + r'\s*:\s*(.*?)\s*$'),
      ).firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  String _slug(String value) {
    final result = value.toLowerCase().trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (result.length <= 64) return result;
    return result.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
  }

  /// Keeps pinned skills active and loads only a few task-relevant skills.
  List<AgentSkill> selectForTask(
    List<AgentSkill> available,
    String task,
    Set<String> pinnedIds, {
    int maxAutomatic = 3,
  }) {
    final selected = <String, AgentSkill>{};
    for (final skill in available) {
      if (pinnedIds.contains(skill.id)) selected[skill.id] = skill;
    }

    final prompt = task.toLowerCase();
    final isCodingTask = RegExp(
      r'\b(create|build|implement|add|fix|debug|refactor|rewrite|update|code|write|generate|develop|test|design|integrat|support|buat|bikin|tambah|tambahkan|perbaiki|betulin|ubah|rubah|koding|aplikasi|fitur|error|gagal|rusak|perbarui)\w*\b',
    ).hasMatch(prompt);
    for (final skill in available) {
      if (isCodingTask && skill.id == 'coding-implementation') {
        selected[skill.id] = skill;
      }
    }

    final promptWords = _words(prompt);
    final scored = <_ScoredSkill>[];
    for (final skill in available) {
      if (selected.containsKey(skill.id)) continue;
      final keywords = <String>{
        ..._words(skill.id.replaceAll('-', ' ')),
        ..._words(skill.description),
        ...?_skillAliases[skill.id],
      }.where((word) =>
          (word.length >= 3 || word == 'ui' || word == 'ux') &&
          !_stopWords.contains(word)).toSet();

      var score = 0;
      for (final word in keywords) {
        if (promptWords.contains(word)) score += word.length >= 7 ? 2 : 1;
        if (word.length >= 5 &&
            promptWords.any((input) =>
                input.length >= 5 &&
                (input.startsWith(word) || word.startsWith(input)))) {
          score++;
        }
      }
      if (score > 0) scored.add(_ScoredSkill(skill, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    var automatic = 0;
    for (final entry in scored) {
      if (automatic >= maxAutomatic || selected.length >= 5) break;
      selected[entry.skill.id] = entry.skill;
      automatic++;
    }
    return selected.values.toList(growable: false);
  }

  Set<String> _words(String text) => RegExp(r'[a-z0-9]{2,}')
      .allMatches(text)
      .map((match) => match.group(0)!)
      .where((word) => !_stopWords.contains(word))
      .toSet();
}

class _ScoredSkill {
  const _ScoredSkill(this.skill, this.score);
  final AgentSkill skill;
  final int score;
}
