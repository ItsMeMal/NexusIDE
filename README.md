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

- Connect to Mallss Nexus Route using its OpenAI-compatible Chat Completions API.
- Default API base URL: https://ai-router.mallss-nexus.sbs/v1
- Default model ID: Nexus-Free.
- Test the API key and endpoint from AI Agent settings.
- Include a limited workspace tree and the contents of up to eight open files as project context.
- Ask questions about code or request file changes.
- Review each proposed file side by side with the current contents before applying it. The agent never writes its proposal automatically.
- API keys are stored with secure device storage. Common secret files such as .env, private keys, and service-account credentials are excluded from file-content context.

To connect the agent, create an API key in the Mallss Nexus Route dashboard at https://ai-router.mallss-nexus.sbs/dashboard, open AI Agent in NexusIDE, enter the key, and save settings. Your prompts and the included workspace context are sent to the configured model when you submit a request. Avoid opening sensitive files that are not safe to share with the model.

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
- http for gateway requests
- flutter_secure_storage for the API key
- shared_preferences for non-secret settings
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
