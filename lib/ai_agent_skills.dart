import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Portable Agent Skills loader. Skills are instruction-only: bundled scripts
/// and other resources are never executed by NexusIDE.
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
    'about', 'after', 'agent', 'also', 'and', 'app', 'application', 'asked',
    'build', 'change', 'code', 'create', 'feature', 'for', 'from', 'help',
    'how', 'into', 'make', 'need', 'nexuside', 'our', 'please', 'project',
    'should', 'that', 'their', 'then', 'this', 'when', 'with', 'work',
    'your', 'use', 'using', 'implement', 'update', 'want',
  };

  Future<List<AgentSkill>> loadSkills(String? workspacePath) async {
    final skillsById = <String, AgentSkill>{};

    for (final assetPath in _builtInPaths) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        final skill = _parseSkill(raw, source: 'Built-in', isBuiltIn: true,
          fallbackName: p.basename(p.dirname(assetPath)));
        if (skill != null) skillsById[skill.id] = skill;
      } catch (_) {
        // Keep the rest of the skill catalog usable if one bundled skill is absent.
      }
    }

    if (workspacePath != null && workspacePath.trim().isNotEmpty) {
      final root = Directory(p.normalize(p.absolute(workspacePath)));
      if (await root.exists()) {
        for (final relativeRoot in _skillRoots) {
          final skillsRoot = Directory(p.join(root.path, relativeRoot));
          if (!await skillsRoot.exists()) continue;
          await _scanSkillsRoot(
            skillsRoot,
            root.path,
            skillsById,
            maxSkills: 80,
          );
        }
      }
    }

    final result = skillsById.values.toList(growable: false);
    result.sort((a, b) {
      if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Future<void> _scanSkillsRoot(
    Directory skillsRoot,
    String workspaceRoot,
    Map<String, AgentSkill> output, {
    required int maxSkills,
  }) async {
    List<FileSystemEntity> firstLevel;
    try {
      firstLevel = await skillsRoot.list(followLinks: false).toList();
    } catch (_) {
      return;
    }
    for (final entry in firstLevel) {
      if (output.length >= maxSkills || entry is Link) break;
      if (entry is! Directory) continue;
      final directSkill = File(p.join(entry.path, 'SKILL.md'));
      if (await directSkill.exists()) {
        await _loadWorkspaceSkill(directSkill, workspaceRoot, output);
        continue;
      }

      // Support category nesting such as .agents/skills/frontend/my-skill/SKILL.md.
      List<FileSystemEntity> nested;
      try {
        nested = await entry.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final nestedEntry in nested) {
        if (output.length >= maxSkills) break;
        if (nestedEntry is! Directory || nestedEntry is Link) continue;
        final nestedSkill = File(p.join(nestedEntry.path, 'SKILL.md'));
        if (await nestedSkill.exists()) {
          await _loadWorkspaceSkill(nestedSkill, workspaceRoot, output);
        }
      }
    }
  }

  Future<void> _loadWorkspaceSkill(
    File file,
    String workspaceRoot,
    Map<String, AgentSkill> output,
  ) async {
    try {
      if (await file.length() > 40000) return;
      final raw = await file.readAsString();
      final relative = p.relative(file.parent.path, from: workspaceRoot)
        .replaceAll(String.fromCharCode(92), '/');
      final skill = _parseSkill(
        raw,
        source: relative,
        isBuiltIn: false,
        fallbackName: p.basename(file.parent.path),
      );
      if (skill != null) {
        // A project skill can intentionally override a built-in skill with the
        // same ID; it never changes the bundled skill on disk.
        output[skill.id] = skill;
      }
    } catch (_) {
      // Ignore malformed or unreadable skills instead of failing the Agent.
    }
  }

  AgentSkill? _parseSkill(
    String raw, {
    required String source,
    required bool isBuiltIn,
    required String fallbackName,
  }) {
    final normalized = raw.replaceFirst('\r\n', '\n');
    if (!normalized.startsWith('---\n')) return null;
    final close = normalized.indexOf('\n---', 4);
    if (close < 0) return null;
    final frontmatter = normalized.substring(4, close);
    final bodyStart = normalized.indexOf('\n', close + 4);
    if (bodyStart < 0) return null;
    final instructions = normalized.substring(bodyStart + 1).trim();
    if (instructions.isEmpty) return null;

    final nameValue = _frontmatterScalar(frontmatter, 'name');
    final descriptionValue = _frontmatterScalar(frontmatter, 'description');
    final rawName = (nameValue == null || nameValue.isEmpty) ? fallbackName : nameValue;
    final id = _slug(rawName);
    final description = (descriptionValue ?? '').trim();
    if (id.isEmpty || description.isEmpty) return null;

    return AgentSkill(
      id: id,
      name: rawName.replaceAll('-', ' ').trim(),
      description: description.length > 1024 ? description.substring(0, 1024) : description,
      instructions: instructions.length > 14000 ? instructions.substring(0, 14000) : instructions,
      source: source,
      isBuiltIn: isBuiltIn,
    );
  }

  String? _frontmatterScalar(String frontmatter, String key) {
    for (final line in frontmatter.split('\n')) {
      final match = RegExp('^\\s*' + RegExp.escape(key) + r'\s*:\s*(.*?)\s*).firstMatch(line);
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

  String _slug(String input) {
    final slug = input.trim().toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 64) return slug.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    return slug;
  }

  /// Returns pinned skills plus the best task-matched skills. Skill bodies
  /// are loaded only for the current request (progressive disclosure).
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
      r'\b(create|build|implement|add|fix|debug|refactor|rewrite|update|code|write|generate|develop|test|design|integrat|support)\w*\b',
    ).hasMatch(prompt);
    final implementation = available.where((s) => s.id == 'coding-implementation');
    if (isCodingTask && implementation.isNotEmpty) {
      selected[implementation.first.id] = implementation.first;
    }

    final promptWords = _words(prompt);
    final scored = <_ScoredSkill>[];
    for (final skill in available) {
      if (selected.containsKey(skill.id)) continue;
      final idWords = _words(skill.id.replaceAll('-', ' '));
      final descriptionWords = _words(skill.description);
      final keywords = <String>{...idWords, ...descriptionWords}
        .where((word) => word.length >= 4 && !_stopWords.contains(word))
        .toSet();
      var score = 0;
      for (final word in keywords) {
        if (promptWords.contains(word)) score += word.length >= 7 ? 2 : 1;
        // Simple prefix matching helps e.g. "authentication" match "auth".
        if (word.length >= 5 && promptWords.any((input) =>
            input.length >= 5 && (input.startsWith(word) || word.startsWith(input)))) {
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

  Set<String> _words(String text) {
    return RegExp(r'[a-z0-9]{3,}').allMatches(text)
      .map((match) => match.group(0)!)
      .where((word) => !_stopWords.contains(word))
      .toSet();
  }
}

class _ScoredSkill {
  const _ScoredSkill(this.skill, this.score);
  final AgentSkill skill;
  final int score;
}
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

  String _slug(String input) {
    final slug = input.trim().toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 64) return slug.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    return slug;
  }

  /// Returns pinned skills plus the best task-matched skills. Skill bodies
  /// are loaded only for the current request (progressive disclosure).
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
      r'\\b(create|build|implement|add|fix|debug|refactor|rewrite|update|code|write|generate|develop|test|design|integrat|support)\\w*\\b',
    ).hasMatch(prompt);
    final implementation = available.where((s) => s.id == 'coding-implementation');
    if (isCodingTask && implementation.isNotEmpty) {
      selected[implementation.first.id] = implementation.first;
    }

    final promptWords = _words(prompt);
    final scored = <_ScoredSkill>[];
    for (final skill in available) {
      if (selected.containsKey(skill.id)) continue;
      final idWords = _words(skill.id.replaceAll('-', ' '));
      final descriptionWords = _words(skill.description);
      final keywords = <String>{...idWords, ...descriptionWords}
        .where((word) => word.length >= 4 && !_stopWords.contains(word))
        .toSet();
      var score = 0;
      for (final word in keywords) {
        if (promptWords.contains(word)) score += word.length >= 7 ? 2 : 1;
        // Simple prefix matching helps e.g. "authentication" match "auth".
        if (word.length >= 5 && promptWords.any((input) =>
            input.length >= 5 && (input.startsWith(word) || word.startsWith(input)))) {
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

  Set<String> _words(String text) {
    return RegExp(r'[a-z0-9]{3,}').allMatches(text)
      .map((match) => match.group(0)!)
      .where((word) => !_stopWords.contains(word))
      .toSet();
  }
}

class _ScoredSkill {
  const _ScoredSkill(this.skill, this.score);
  final AgentSkill skill;
  final int score;
}
