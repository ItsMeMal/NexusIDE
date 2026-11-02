# NexusIDE

NexusIDE is a cross-platform coding workspace built with Flutter. This first milestone focuses on a reliable editor foundation for Windows, with a responsive layout that can later be refined for Android.

## Stage 1 — IDE foundation

Included in this increment:
- Open a workspace folder or one or more files.
- Browse folders in the Explorer panel.
- Open multiple files in tabs and switch between them.
- Edit text files and save with the toolbar or Ctrl+S / Cmd+S.
- Confirm before discarding unsaved changes when closing a tab.
- Move the Explorer into a drawer on narrow screens.

Not implemented yet: syntax highlighting, file creation, terminal, AI Agent integration, and extensions. Those will be added in later, separate increments.

## Technology

- Flutter and Dart
- file_selector for native file and directory pickers
- path for cross-platform path handling

## Requirements

- Flutter SDK with Dart 3.9 or newer
- Windows development tools to build the Windows desktop app
- Android SDK to build for Android

## First-time setup on Windows

This repository starts with Dart source. Generate the native Windows and Android runner folders once, without overwriting the source code:

1. Install Flutter and check `flutter doctor`.
2. Clone the repository and open its directory in PowerShell.
3. Run:

   `powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_platforms.ps1`

4. Fetch dependencies:

   `flutter pub get`

5. Start the Windows app:

   `flutter run -d windows`

The script refuses to overwrite existing Windows or Android folders. Do not run it again after the native runners have been generated.

For Android, connect an emulator or device, then use `flutter devices` and `flutter run -d <device-id>`. The full Acode-inspired mobile workflow is planned for a later stage.

## Roadmap

1. **IDE foundation** — workspace browsing, tabs, text editing, and saving.
2. **AI Agent basics** — Nexus AI Gateway connection, project context, and reviewable file diffs.
3. **Nexus Extensions** — start with themes and snippets before evaluating broader compatibility.
4. **Developer tools** — terminal and deeper language tooling.
5. **Android refinement** — optimize the mobile editor around an Acode-inspired workflow.

This is an incremental project. Features in the roadmap should not be treated as already available.
