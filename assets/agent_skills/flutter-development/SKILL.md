---
name: flutter-development
description: Build and maintain Flutter and Dart apps, widgets, state, navigation, layouts, platform integrations, and Windows or Android builds.
---
# Flutter and Dart development

- Follow the repository's Dart SDK constraint, Flutter version assumptions, current widget patterns, and existing state-management approach.
- Prefer small composable widgets and clear typed APIs. Avoid unnecessary architecture layers.
- Keep build methods declarative; move asynchronous and stateful work into appropriate lifecycle methods or callbacks.
- Account for mounted state after awaits, dispose controllers and subscriptions, and handle loading/error/empty states.
- Make layouts responsive to narrow widths and text scaling. Avoid overflow-prone fixed-width controls.
- Use const constructors where values are constant, but never mark a widget const when any argument depends on runtime state.
- Check platform-specific file, URL, storage, and permission behavior before relying on it.
- If a local Flutter SDK is unavailable, be explicit that analysis and builds remain unverified.
