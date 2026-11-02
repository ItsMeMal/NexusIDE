# NexusIDE

NexusIDE is a cross-platform Flutter coding workspace. The Windows layout follows familiar desktop IDE patterns; Android refinement is planned for a later stage.

## Stage 1 — IDE foundation

- Open a workspace folder or one or more files.
- Browse nested folders in Explorer.
- Open multiple files in tabs, switch between them, and horizontally scroll the tab bar.
- Edit and save local files with Ctrl+S / Cmd+S.
- Syntax highlighting and line numbers for common programming languages.
- Confirm before discarding unsaved changes.
- Use a responsive Explorer drawer on narrow screens.

## Stage 2 — AI Agent basics

- Connect AI Agent through browser-based OAuth to your Mallss Nexus Route account; the gateway login happens in the browser, never inside NexusIDE.
- The gateway opens a browser sign-in and explicit consent screen, then returns to NexusIDE through a local loopback callback.
- Authorization Code + PKCE produces short-lived access and rotating refresh tokens. Tokens stay in secure device storage and refresh automatically; no API key entry or gateway URL configuration is exposed in the UI.
- Disconnect revokes the OAuth session and its gateway-side app credential.
- Choose any model exposed by the gateway from the Agent composer; the model list can be refreshed and the selection is remembered on the device.
- The Agent sends a limited workspace tree and up to eight open files as context when you submit a prompt.
- Ask questions about code or request file changes.
- Review proposed file changes before applying them; the Agent never writes a proposal automatically.
- Sign out attempts to revoke the NexusIDE-generated API key and ends the gateway account session.
- Common secret files such as .env, private keys, and service-account credentials are excluded from project file-content context.

Your prompts and included workspace context are sent to the configured model when you submit a request. Avoid opening sensitive files that are not safe to share with the model.

The AI Agent currently supports proposed file creation and updates, not file deletion. Review the changes before applying them.

## Roadmap

1. IDE foundation — complete initial editor, file browsing, tabs, syntax highlighting, and saving.
2. AI Agent basics — gateway connection, workspace context, and review-before-apply file changes.
3. Nexus Extensions — start with themes and snippets before evaluating broader compatibility.
4. Developer tools — terminal and deeper language tooling.
5. Android refinement — optimize the mobile editor around an Acode-inspired workflow.

## Technology

- Flutter and Dart
- code_text_field and highlight for the editor
- file_selector for native file and directory pickers
- http for gateway requests and OAuth token exchange
- crypto for PKCE challenges
- url_launcher for launching the system browser
- flutter_secure_storage for access and refresh tokens
- path for cross-platform path handling

## Requirements

- Flutter SDK with Dart 3.9 or newer
- Windows development tools to build the Windows desktop app
- Android SDK to build for Android

## First-time setup on Windows

This repository starts with Dart source. Generate the native Windows and Android runner folders once, without overwriting source code:

1. Install Flutter and check flutter doctor.
2. Clone this repository and open its directory in PowerShell.
3. Run:

   ~~~powershell
   powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_platforms.ps1
   ~~~

4. Fetch dependencies:

   ~~~powershell
   flutter pub get
   ~~~

5. Start the Windows app:

   ~~~powershell
   flutter run -d windows
   ~~~

The bootstrap script refuses to overwrite existing Windows or Android folders. Do not run it again after the native runners have been generated.

For Android, connect an emulator or device, then use flutter devices and flutter run -d DEVICE_ID. The full Acode-inspired mobile workflow is planned for a later stage.
