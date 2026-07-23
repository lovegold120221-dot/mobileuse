# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

MobileUse Agent is an Android automation app built with **Flutter/Dart** and **Kotlin**. It uses an OpenAI-compatible chat-completion API to drive a screen-read → decide → act loop through Android Accessibility Services.

- Package name: `com.orailnoor.privateagent`
- `minSdk = 26` (Android 8.0). Screenshot capture requires API 30+.
- The root `android/build.gradle.kts` redirects the `build/` directory to `../../build/`.
- Release builds currently sign with the debug key (`android/app/build.gradle.kts`).

## Common commands

Resolve dependencies:

```sh
flutter pub get
```

Run the app on a connected Android device or emulator:

```sh
flutter run
```

Build release artifacts:

```sh
flutter build apk              # universal APK
flutter build apk --split-per-abi
flutter build appbundle
```

Run the test suite:

```sh
flutter test
```

Run a single test file:

```sh
flutter test test/ai_service_test.dart
```

Linting uses `flutter_lints` via `analysis_options.yaml`:

```sh
flutter analyze
```

Format Dart code:

```sh
dart format lib test
```

The GitHub Actions workflow (`.github/workflows/android-release.yml`) runs `flutter pub get`, `flutter test`, and `flutter build apk --release` on tag pushes matching `v*`.

## Architecture

### Three-layer bridge

1. **Flutter Dart layer** (`lib/services/screen_automation_service.dart`) sends commands over the `MethodChannel` named `com.privateagent/accessibility`.
2. **Kotlin layer** (`android/app/src/main/kotlin/com/orailnoor/privateagent/MainActivity.kt` and `AgentAccessibilityService.kt`) receives those calls and performs accessibility actions.
3. **Android Accessibility Service** (`AgentAccessibilityService`) actually reads the UI tree, dispatches gestures, presses system buttons, and captures screenshots.

### Entry points

- `lib/main.dart` — the main Flutter app (onboarding, settings, chat home). It also declares `overlayMain()` because the overlay entry point lives in the same file.
- `lib/overlay_main.dart` — the floating chat overlay UI. It runs in a separate Flutter engine and executes tasks directly from the overlay isolate.
- `lib/config/feature_flags.dart` — `floatingOverlayEnabled` is currently `false`; the overlay implementation is present but disabled while being stabilized.

### Main task loop

`TaskExecutor` (`lib/services/task_executor.dart`) implements the core AI-guided loop:

1. Check whether `AgentAccessibilityService` is running.
2. Try to replay a previously recorded skill from `SkillMemoryService` (JSONL file in the app documents directory) using Jaccard keyword matching.
3. Apply hard-coded navigation shortcuts (`_getNavigationShortcut`) for common requests (e.g., "open Settings", "turn on WiFi").
4. Otherwise, repeatedly: dump the screen, send it to the AI with the task prompt, parse the returned JSON action, execute it, and loop until `is_complete` is true, the step limit is reached, or the task is cancelled.

Adaptive delays are applied after each action: 3s for `open_app`, 2s for `type_text`, 1.5s for clicks, 1s for scroll. Stuck detection triggers recovery after 5 consecutive failures; `RecoveryEngine` chooses between wait/back/scroll/home.

### AI provider layer

`AiService` (`lib/services/ai_service.dart`) talks to any OpenAI-compatible chat-completion endpoint. Defaults are DeepSeek (`https://api.deepseek.com`, `deepseek-chat`). Settings are persisted in `SharedPreferences`:

- `api_key`, `api_base_url`, `api_model`
- `api_max_steps` (default 15), `api_disable_max_steps`
- `api_temperature` (default 1.0), `api_max_tokens` (default 1024)
- `api_use_screen_compression`, `api_use_system_prompt`

Important provider-specific behavior:

- The API key is auto-stripped if the user pastes a `Bearer ` prefix.
- NVIDIA (`integrate.api.nvidia.com`) forces `_effectiveMaxTokens` to at least 4096 for `z-ai/glm-5.2`.
- `sendTaskMessage` retries 4× with exponential backoff.
- Reasoning blocks (`<think>…</think>`) are stripped from streamed and non-streamed responses.
- `parseAction` tolerates truncated JSON by appending closing braces, which matters for small local models.

### Action routing

`ActionHandler` (`lib/services/action_handler.dart`) routes parsed actions:

- Single-step actions: `open_app`, `make_call`, `send_sms`, `set_alarm`, `set_volume`, `set_brightness`, `run_adb_command`, `read_screen`, etc.
- Multi-step actions: `execute_task` spawns a fresh `TaskExecutor`.

Screen-automation actions are forwarded to `ScreenAutomationService`, which calls the native accessibility channel. If accessibility gestures fail, swipe/scroll/enter fall back to ADB shell commands via `ShizukuService` when Shizuku is available.

### Background engine / floating overlay

The overlay uses a cached Flutter engine registered with the key `"myCachedEngine"`. `BackgroundEngineReceiver` listens for the broadcast `com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS` and registers the accessibility `MethodChannel` on that cached engine so the overlay isolate can call native accessibility methods.

`OverlayApp` (`lib/overlay_main.dart`) bootstraps by sending that broadcast, initializing `AiService`, and only then accepting tasks. The main app forwards tasks received from the overlay bubble through `onOverlayTask` in `lib/main.dart`.

### Native accessibility service

`AgentAccessibilityService` (`android/app/…/AgentAccessibilityService.kt`):

- Exposes itself as a singleton (`instance`) and reports running state via `isRunning()`.
- `dumpScreen()` traverses the accessibility tree and returns a flat list of interactive nodes with text, bounds, and class names. Nodes from the app's own package are excluded.
- Performs clicks (`clickByText` / `clickAtCoordinates`), text input (`typeText`), scrolling (`scroll`), swipes, and global actions (back, home, notifications).
- `takeScreenshot()` requires API 30+ and returns a JPEG-compressed Base64 string.

### Local plugins

`pubspec.yaml` overrides two plugins via `dependency_overrides`:

- `flutter_overlay_window` from `./local_plugins/flutter_overlay_window/` — floating overlay window.
- `agent_native` from `./local_plugins/agent_native/` — currently a stub exposing only `getPlatformVersion`.

### Skill memory

Recorded successful multi-step task runs are saved to `skills_memory.jsonl` in the app documents directory by `SkillMemoryService`. Each skill stores extracted keywords and a list of `ActionStep`s. On later similar requests, the skill is replayed without calling the LLM. Reliability is computed from success/fail counts (fewer than 30% failures).

### Telegram integration

`TelegramService` polls the Telegram Bot API in the background using a token stored in `SharedPreferences`. It reuses the same `ActionHandler` and `AiService` instances as the main app.

## Local development notes

- `assets/local_config/ai_test_config.json` is gitignored and intended for local dev credentials.
- The only tests live in `test/ai_service_test.dart` and cover NVIDIA URL/model filtering. There are no integration tests yet.
- The `.github/workflows/` directory contains the Android release workflow only.
- No Cursor rules (`.cursorrules` or `.cursor/rules/`) or Copilot instructions (`.github/copilot-instructions.md`) exist in this repository.

## Conventions to preserve

- Do not list every component or file structure in this guidance.
- Do not include generic development practices (e.g., "write tests for all new utilities").
- When editing Dart, keep the existing style: `const` constructors where possible, descriptive names, and adaptive delays inside `TaskExecutor`.
- When editing Kotlin, keep accessibility node traversal patterns (recycle nodes, skip the app's own package, prefer clickable parents before coordinate fallback).
- The floating overlay is intentionally disabled via `FeatureFlags.floatingOverlayEnabled`; do not enable it in committed code without a clear stabilization plan.
