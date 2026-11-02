import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

const bg = Color(0xFF0D1117);
const panel = Color(0xFF111821);
const surface = Color(0xFF151F2B);
const border = Color(0xFF243140);
const muted = Color(0xFF8B98A9);
const foreground = Color(0xFFE6EDF3);
const accent = Color(0xFF62D3CE);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusIdeApp());
}

class NexusIdeApp extends StatelessWidget {
  const NexusIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'NexusIDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors.copyWith(primary: accent, surface: panel),
        scaffoldBackgroundColor: bg,
        dividerColor: border,
        splashColor: accent.withOpacity(0.08),
        highlightColor: accent.withOpacity(0.04),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: foreground,
              displayColor: foreground,
            ),
      ),
      home: const IdeHome(),
    );
  }
}

class SaveFileIntent extends Intent {
  const SaveFileIntent();
}

class OpenDocument {
  OpenDocument(this.path, String content)
      : name = p.basename(path),
        controller = TextEditingController(text: content);

  final String path;
  final String name;
  final TextEditingController controller;
  bool dirty = false;

  void dispose() => controller.dispose();
}

class IdeHome extends StatefulWidget {
  const IdeHome({super.key});

  @override
  State<IdeHome> createState() => _IdeHomeState();
}

class _IdeHomeState extends State<IdeHome> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final List<OpenDocument> documents = [];
  String? workspacePath;
  int activeIndex = -1;

  OpenDocument? get activeDocument =>
      activeIndex >= 0 && activeIndex < documents.length
          ? documents[activeIndex]
          : null;

  @override
  void dispose() {
    for (final document in documents) {
      document.dispose();
    }
    super.dispose();
  }

  Future<void> openFolder() async {
    try {
      final selected = await fs.getDirectoryPath(confirmButtonText: 'Open Folder');
      if (selected == null || !mounted) return;
      setState(() => workspacePath = selected);
      scaffoldKey.currentState?.closeDrawer();
    } catch (error) {
      if (mounted) showMessage('Could not open folder: $error');
    }
  }

  Future<void> openFiles() async {
    try {
      final selected = await fs.openFiles();
      for (final file in selected) {
        await openFile(file.path);
      }
    } catch (error) {
      if (mounted) showMessage('Could not open file: $error');
    }
  }

  Future<void> openFile(String filePath) async {
    if (filePath.isEmpty) return;
    final alreadyOpen = documents.indexWhere(
      (doc) => p.equals(doc.path, filePath),
    );
    if (alreadyOpen >= 0) {
      setState(() => activeIndex = alreadyOpen);
      return;
    }

    try {
      final content = await File(filePath).readAsString();
      if (!mounted) return;
      final document = OpenDocument(filePath, content);
      document.controller.addListener(() {
        if (!mounted || document.dirty) return;
        setState(() => document.dirty = true);
      });
      setState(() {
        documents.add(document);
        activeIndex = documents.length - 1;
      });
    } catch (error) {
      if (mounted) showMessage('Could not open this file as text: $error');
    }
  }

  Future<void> saveFile() async {
    final document = activeDocument;
    if (document == null) return;
    try {
      await File(document.path).writeAsString(
        document.controller.text,
        flush: true,
      );
      if (!mounted) return;
      setState(() => document.dirty = false);
      showMessage('Saved ' + document.name);
    } catch (error) {
      if (mounted) showMessage('Could not save ' + document.name + ': $error');
    }
  }

  Future<void> closeDocument(int index) async {
    if (index < 0 || index >= documents.length) return;
    final document = documents[index];
    if (document.dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Unsaved changes'),
          content: Text('Discard unsaved changes in ' + document.name + '?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }

    setState(() {
      final wasActive = activeIndex == index;
      documents.removeAt(index);
      if (documents.isEmpty) {
        activeIndex = -1;
      } else if (wasActive) {
        activeIndex = math.min(index, documents.length - 1);
      } else if (activeIndex > index) {
        activeIndex--;
      }
    });
    document.dispose();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final document = activeDocument;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): SaveFileIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveFileIntent: CallbackAction<SaveFileIntent>(
            onInvoke: (_) {
              saveFile();
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final veryCompact = constraints.maxWidth < 440;
            final explorer = WorkspaceExplorer(
              workspacePath: workspacePath,
              onOpenFolder: openFolder,
              onOpenFile: openFiles,
              onSelectFile: (path) {
                openFile(path);
                if (compact) scaffoldKey.currentState?.closeDrawer();
              },
            );

            return Scaffold(
              key: scaffoldKey,
              backgroundColor: bg,
              drawer: compact
                  ? Drawer(
                      backgroundColor: panel,
                      width: math.min(constraints.maxWidth * 0.84, 320.0),
                      child: SafeArea(child: explorer),
                    )
                  : null,
              body: SafeArea(
                child: Column(
                  children: [
                    WindowHeader(
                      compact: compact,
                      veryCompact: veryCompact,
                      workspacePath: workspacePath,
                      canSave: document != null,
                      onMenu: () => scaffoldKey.currentState?.openDrawer(),
                      onOpenFolder: openFolder,
                      onOpenFile: openFiles,
                      onSave: saveFile,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (!compact) const ActivityRail(),
                          if (!compact)
                            Container(
                              width: 264,
                              decoration: const BoxDecoration(
                                color: panel,
                                border: Border(right: BorderSide(color: border)),
                              ),
                              child: explorer,
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                EditorTabs(
                                  documents: documents,
                                  activeIndex: activeIndex,
                                  onSelect: (index) => setState(() => activeIndex = index),
                                  onClose: closeDocument,
                                ),
                                Expanded(
                                  child: document == null
                                      ? WelcomeView(
                                          onOpenFolder: openFolder,
                                          onOpenFile: openFiles,
                                        )
                                      : CodeEditor(document: document),
                                ),
                                StatusBar(document: document),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class WindowHeader extends StatelessWidget {
  const WindowHeader({
    required this.compact,
    required this.veryCompact,
    required this.workspacePath,
    required this.canSave,
    required this.onMenu,
    required this.onOpenFolder,
    required this.onOpenFile,
    required this.onSave,
    super.key,
  });

  final bool compact;
  final bool veryCompact;
  final String? workspacePath;
  final bool canSave;
  final VoidCallback onMenu;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenFile;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: panel,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          if (compact)
            IconButton(
              tooltip: 'Show Explorer',
              onPressed: onMenu,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.menu_rounded),
            ),
          const BrandMark(size: 30),
          const SizedBox(width: 9),
          const Text(
            'NexusIDE',
            style: TextStyle(
              color: foreground,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!veryCompact) ...[
            const SizedBox(width: 14),
            Container(width: 1, height: 23, color: border),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                workspacePath == null ? 'No workspace open' : p.basename(workspacePath!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ] else
            const Spacer(),
          if (!compact)
            TextButton.icon(
              onPressed: onOpenFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 17),
              label: const Text('Open Folder'),
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                textStyle: const TextStyle(fontSize: 12),
              ),
            )
          else
            IconButton(
              tooltip: 'Open folder',
              onPressed: onOpenFolder,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.folder_open_rounded, size: 20),
            ),
          IconButton(
            tooltip: 'Open file',
            onPressed: onOpenFile,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.note_add_outlined, size: 19),
          ),
          IconButton(
            tooltip: 'Save file (Ctrl+S)',
            onPressed: canSave ? onSave : null,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.save_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({required this.size, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.13),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent.withOpacity(0.28)),
      ),
      child: Icon(Icons.terminal_rounded, color: accent, size: size * 0.62),
    );
  }
}

class ActivityRail extends StatelessWidget {
  const ActivityRail({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      decoration: const BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -36),
            child: SizedBox(
              width: 50,
              height: 36,
              child: Icon(Icons.folder_copy_outlined, color: foreground, size: 21),
            ),
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Icon(Icons.settings_outlined, color: muted, size: 20),
          ),
        ],
      ),
    );
  }
}

class WorkspaceExplorer extends StatefulWidget {
  const WorkspaceExplorer({
    required this.workspacePath,
    required this.onOpenFolder,
    required this.onOpenFile,
    required this.onSelectFile,
    super.key,
  });

  final String? workspacePath;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenFile;
  final ValueChanged<String> onSelectFile;

  @override
  State<WorkspaceExplorer> createState() => _WorkspaceExplorerState();
}

class _WorkspaceExplorerState extends State<WorkspaceExplorer> {
  Future<List<FileSystemEntity>>? entriesFuture;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(covariant WorkspaceExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath) refresh();
  }

  void refresh() {
    final path = widget.workspacePath;
    entriesFuture = path == null ? null : listDirectory(path);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 7),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'EXPLORER',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open folder',
                    onPressed: widget.onOpenFolder,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Open file',
                    onPressed: widget.onOpenFile,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: border),
          if (widget.workspacePath == null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.folder_open_outlined, size: 32, color: muted),
                    const SizedBox(height: 12),
                    const Text(
                      'No workspace open',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Open a folder to browse its files.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: widget.onOpenFolder,
                      icon: const Icon(Icons.folder_open, size: 17),
                      label: const Text('Open Folder'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 13, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.keyboard_arrow_down, size: 17, color: muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      p.basename(widget.workspacePath!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<FileSystemEntity>>(
                future: entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Could not read this folder. Check its permissions.',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    );
                  }
                  final entries = snapshot.data ?? const <FileSystemEntity>[];
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('This folder is empty.', style: TextStyle(color: muted, fontSize: 12)),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: entries
                        .map(
                          (entity) => ExplorerEntry(
                            entity: entity,
                            depth: 0,
                            onSelectFile: widget.onSelectFile,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ExplorerEntry extends StatefulWidget {
  const ExplorerEntry({
    required this.entity,
    required this.depth,
    required this.onSelectFile,
    super.key,
  });

  final FileSystemEntity entity;
  final int depth;
  final ValueChanged<String> onSelectFile;

  @override
  State<ExplorerEntry> createState() => _ExplorerEntryState();
}

class _ExplorerEntryState extends State<ExplorerEntry> {
  Future<List<FileSystemEntity>>? childrenFuture;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.entity.path);
    final isDirectory = widget.entity is Directory;
    final inset = 10.0 + (widget.depth * 12.0);

    if (isDirectory) {
      return Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: accent.withOpacity(0.08),
        ),
        child: Material(
          color: Colors.transparent,
          child: ExpansionTile(
          key: PageStorageKey<String>(widget.entity.path),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          dense: true,
          visualDensity: VisualDensity.compact,
          tilePadding: EdgeInsets.only(left: inset, right: 10),
          childrenPadding: const EdgeInsets.only(left: 8),
          leading: const Icon(Icons.folder_rounded, size: 17, color: accent),
          iconColor: accent,
          collapsedIconColor: muted,
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: foreground, fontSize: 12.5),
          ),
          onExpansionChanged: (expanded) {
            if (expanded && childrenFuture == null) {
              setState(() {
                childrenFuture = listDirectory(widget.entity.path);
              });
            }
          },
          children: childrenFuture == null
              ? const <Widget>[]
              : [
                  FutureBuilder<List<FileSystemEntity>>(
                    future: childrenFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(10),
                          child: LinearProgressIndicator(minHeight: 2),
                        );
                      }
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(18, 4, 8, 8),
                          child: Text('Folder unavailable', style: TextStyle(color: muted, fontSize: 11)),
                        );
                      }
                      final children = snapshot.data ?? const <FileSystemEntity>[];
                      if (children.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.fromLTRB(30, 4, 8, 10),
                          child: Text('Empty folder', style: TextStyle(color: muted, fontSize: 11)),
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: children
                            .map(
                              (child) => ExplorerEntry(
                                entity: child,
                                depth: widget.depth + 1,
                                onSelectFile: widget.onSelectFile,
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelectFile(widget.entity.path),
        child: Padding(
          padding: EdgeInsets.only(left: inset + 2, right: 10),
          child: SizedBox(
            height: 31,
            child: Row(
              children: [
                Icon(fileIcon(name), size: 16, color: fileColor(name)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: foreground, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<List<FileSystemEntity>> listDirectory(String path) async {
  final entities = await Directory(path).list(followLinks: false).toList();
  const ignored = <String>{'.git', '.dart_tool', 'build', 'node_modules', '.gradle'};
  final visible = entities.where((entity) {
    return !(entity is Directory && ignored.contains(p.basename(entity.path)));
  }).toList();
  visible.sort((a, b) {
    final aDir = a is Directory;
    final bDir = b is Directory;
    if (aDir != bDir) return aDir ? -1 : 1;
    return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
  });
  return visible;
}

IconData fileIcon(String name) {
  switch (p.extension(name).toLowerCase()) {
    case '.dart':
    case '.java':
    case '.kt':
    case '.kts':
    case '.swift':
    case '.c':
    case '.h':
    case '.cpp':
    case '.hpp':
    case '.cs':
    case '.go':
    case '.rs':
    case '.php':
    case '.rb':
    case '.lua':
    case '.sh':
    case '.bat':
    case '.ps1':
    case '.sql':
      return Icons.code_rounded;
    case '.py':
      return Icons.terminal_rounded;
    case '.yaml':
    case '.yml':
    case '.json':
    case '.toml':
    case '.xml':
      return Icons.data_object_rounded;
    case '.md':
    case '.txt':
      return Icons.article_outlined;
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.svg':
      return Icons.image_outlined;
    case '.html':
    case '.css':
      return Icons.web_asset_outlined;
    case '.js':
    case '.ts':
    case '.tsx':
    case '.jsx':
      return Icons.javascript_rounded;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

Color fileColor(String name) {
  switch (p.extension(name).toLowerCase()) {
    case '.dart':
    case '.java':
    case '.kt':
    case '.kts':
    case '.swift':
    case '.c':
    case '.h':
    case '.cpp':
    case '.hpp':
    case '.cs':
    case '.go':
    case '.rs':
    case '.php':
    case '.rb':
    case '.lua':
      return const Color(0xFF72B7F2);
    case '.py':
      return const Color(0xFFF1C56A);
    case '.yaml':
    case '.yml':
    case '.json':
    case '.toml':
    case '.xml':
      return const Color(0xFFF1C56A);
    case '.md':
      return const Color(0xFF9BA9BC);
    case '.html':
      return const Color(0xFFE89A67);
    case '.css':
      return const Color(0xFF7C9DF5);
    case '.js':
    case '.ts':
    case '.tsx':
    case '.jsx':
      return const Color(0xFFE7C45B);
    default:
      return muted;
  }
}

class EditorTabs extends StatelessWidget {
  const EditorTabs({
    required this.documents,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  final List<OpenDocument> documents;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final Future<void> Function(int) onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: panel,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: documents.isEmpty
          ? const Row(
              children: [
                SizedBox(width: 16),
                Icon(Icons.code_rounded, color: muted, size: 15),
                SizedBox(width: 8),
                Text('Editor', style: TextStyle(color: muted, fontSize: 12)),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List<Widget>.generate(documents.length, (index) {
                  final document = documents[index];
                  final selected = index == activeIndex;
                  return InkWell(
                    onTap: () => onSelect(index),
                    child: Container(
                      width: 172,
                      height: 40,
                      padding: const EdgeInsets.only(left: 12, right: 6),
                      decoration: BoxDecoration(
                        color: selected ? bg : panel,
                        border: Border(
                          right: const BorderSide(color: border),
                          top: BorderSide(
                            color: selected ? accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(fileIcon(document.name), size: 15, color: selected ? accent : muted),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              document.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: selected ? foreground : muted, fontSize: 12),
                            ),
                          ),
                          if (document.dirty)
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                            ),
                          SizedBox(
                            width: 24,
                            height: 28,
                            child: IconButton(
                              onPressed: () => onClose(index),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Close ' + document.name,
                              icon: const Icon(Icons.close_rounded, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
    );
  }
}

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    required this.onOpenFolder,
    required this.onOpenFile,
    super.key,
  });

  final VoidCallback onOpenFolder;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 48),
              const SizedBox(height: 24),
              const Text(
                'A calmer place to build.',
                style: TextStyle(
                  color: foreground,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Open a project to start editing. NexusIDE is being built in small, testable stages.',
                style: TextStyle(color: muted, height: 1.6, fontSize: 13),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onOpenFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Open Folder'),
                style: FilledButton.styleFrom(
                  foregroundColor: bg,
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onOpenFile,
                icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
                label: const Text('Open File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: foreground,
                  side: const BorderSide(color: border),
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
                ),
              ),
              const SizedBox(height: 28),
              const Divider(color: border),
              const SizedBox(height: 13),
              const WelcomeDetail(
                icon: Icons.folder_outlined,
                title: 'Workspace Explorer',
                subtitle: 'Browse your project folders.',
              ),
              const SizedBox(height: 13),
              const WelcomeDetail(
                icon: Icons.edit_note_rounded,
                title: 'Multi-file editing',
                subtitle: 'Switch between files using tabs.',
              ),
              const SizedBox(height: 13),
              const WelcomeDetail(
                icon: Icons.save_outlined,
                title: 'Save with Ctrl+S',
                subtitle: 'Changes are saved to the local file.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WelcomeDetail extends StatelessWidget {
  const WelcomeDetail({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: foreground, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: muted, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class CodeEditor extends StatelessWidget {
  const CodeEditor({required this.document, super.key});
  final OpenDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              Icon(fileIcon(document.name), color: accent, size: 15),
              const SizedBox(width: 8),
              Text(document.name, style: const TextStyle(color: foreground, fontSize: 12)),
              const SizedBox(width: 9),
              const Icon(Icons.chevron_right_rounded, size: 14, color: muted),
              Expanded(
                child: Text(
                  document.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: bg,
            padding: const EdgeInsets.fromLTRB(17, 12, 14, 8),
            child: TextField(
              controller: document.controller,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: accent,
              style: const TextStyle(
                color: Color(0xFFD6E0EB),
                fontFamily: 'Consolas',
                fontSize: 13.5,
                height: 1.65,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                hintText: 'Start writing...',
                hintStyle: TextStyle(color: muted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StatusBar extends StatelessWidget {
  const StatusBar({required this.document, super.key});
  final OpenDocument? document;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: accent.withOpacity(0.45))),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, color: accent, size: 7),
          const SizedBox(width: 7),
          const Text(
            'NEXUSIDE',
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              document == null ? 'Ready' : document!.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ),
          const SizedBox(width: 10),
          const Text('UTF-8', style: TextStyle(color: muted, fontSize: 10)),
          const SizedBox(width: 12),
          const Text('LF', style: TextStyle(color: muted, fontSize: 10)),
          if (document != null) ...[
            const SizedBox(width: 12),
            Text(languageForName(document!.name), style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

String languageForName(String filename) {
  switch (p.extension(filename).toLowerCase()) {
    case '.dart':
      return 'Dart';
    case '.js':
    case '.mjs':
    case '.cjs':
      return 'JavaScript';
    case '.ts':
    case '.tsx':
      return 'TypeScript';
    case '.py':
      return 'Python';
    case '.html':
      return 'HTML';
    case '.css':
      return 'CSS';
    case '.json':
      return 'JSON';
    case '.yaml':
    case '.yml':
      return 'YAML';
    case '.md':
      return 'Markdown';
    default:
      return 'Plain Text';
  }
}
