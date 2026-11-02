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

- Google OAuth uses a server-side web client. The client secret stays in the gateway environment; NexusIDE uses a one-time code + PKCE handoff.

- Sign in with Google through the system browser using the Mallss Nexus Route OAuth connector; no email/password form is shown in NexusIDE.
- Gateway URL and model selection are fixed internally: https://ai-router.mallss-nexus.sbs/v1 and Nexus-Free.
- NexusIDE creates an account-owned API key automatically after login and stores it with secure device storage.
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
- http for gateway requests
- flutter_secure_storage for the API key
- flutter_web_auth_2 for browser-based OAuth on desktop and mobile
- crypto for the PKCE code challenge
- path for cross-platform path handling

## Google sign-in setup

Configure these environment variables on the Mallss Nexus Route gateway and redeploy it:

- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`
- `GOOGLE_OAUTH_REDIRECT_URI=https://ai-router.mallss-nexus.sbs/auth/google/callback`
- Optional: `NEXUSIDE_OAUTH_REDIRECT_URI=nexuside://oauth/callback`

Create a **Web application** OAuth client in Google Cloud Console and register the exact callback URL as an authorized redirect URI. The Google client secret must never be added to this Flutter repository. The gateway README has the same deployment notes.

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
