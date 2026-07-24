# MobileUse Agent — Agent Guide

**Android automation agent (Flutter + Kotlin + Accessibility Services).**

## Entrypoints

- `lib/main.dart` — app UI (onboarding, settings, home). Also declares `@pragma("vm:entry-point") void overlayMain()`.
- `lib/overlay_main.dart` — floating chat overlay in a **separate Flutter engine** (`FlutterEngineCache` key `"myCachedEngine"`).
- `FeatureFlags.floatingOverlayEnabled = false` in `lib/config/feature_flags.dart` (currently disabled).

## Build, Lint, Format

```sh
flutter pub get
flutter analyze
dart format lib test
flutter build apk                    # universal APK
flutter build apk --split-per-abi    # per-arch split APKs
flutter build appbundle              # AAB for Play Store
```

- `minSdk = 26` (Android 8.0), screenshots require API 30+ (silently return null on lower).
- Release builds use debug signing (`android/app/build.gradle.kts`).
- `build/` redirected by root `android/build.gradle.kts` to `../../build/`.
- Gradle: `isCoreLibraryDesugaringEnabled = true`, `jvmTarget = 17`.

## Testing

```sh
flutter test                              # all tests (3 exist)
flutter test test/ai_service_test.dart    # single file
```

Standalone JSON truncation test: `dart run test_parse.dart`.

No integration tests.

## CI

`.github/workflows/android-release.yml` — triggers on tag push `v*`. Runs `flutter pub get` → `flutter test` → `flutter build apk --release` (universal + split-per-abi) → uploads APKs with `sha256sum` checksums.

## AI Provider

OpenAI-compatible `/chat/completions` endpoint. Defaults: `https://api.deepseek.com` / `deepseek-chat`.

Provider presets (Settings chip buttons):
- **Ollama** — `http://localhost:11434/v1` / `gemma3:4b`
- **OpenCode** — `http://localhost:8080/v1` / `deepseek-chat`
- **Gemini** — `https://generativelanguage.googleapis.com/v1beta/openai/` / `gemini-2.0-flash`
- **NVIDIA** — `https://integrate.api.nvidia.com/v1` / `z-ai/glm-5.2`
- **DeepSeek** — `https://api.deepseek.com` / `deepseek-chat`
- **Groq** — `https://api.groq.com/openai/v1`

- API key auto-strips `"Bearer "` prefix.
- NVIDIA GLM model forces `_effectiveMaxTokens` to 4096 minimum (small models consume budget reasoning).
- Two system prompts: `_systemPrompt` (agent mode → JSON actions) and `_chatSystemPrompt` (chat mode).
- `sendTaskMessage` retries 4× with linear 3s×n backoff (3s, 6s, 9s, 12s).
- `<think>…</think>` reasoning blocks stripped from all responses.
- Conversation history capped at 20 messages.
- `parseAction` handles truncated JSON (appends closing `}`) and code fences.

## Architecture

- **Three layers**: Flutter Dart → MethodChannel `com.privateagent/accessibility` → Kotlin `AgentAccessibilityService`.
- **Task loop** (`TaskExecutor`): AI-guided screen-read → act → repeat with adaptive delays (3s open_app, 2s type_text, 1.5s click, 1s scroll). Stuck detection after 5 consecutive failures triggers `RecoveryEngine` (wait/back/scroll/home based on screen content).
- **Navigation shortcuts**: Hard-coded app/keyword patterns in `TaskExecutor._getNavigationShortcut()` — press Home first if currently in the app's own package to avoid AI seeing its own UI.
- **Skill memory**: JSONL at `skills_memory.jsonl` in app documents dir. Jaccard similarity matching (>0.6). Replayed without LLM.
- **Shizuku fallback**: Swipe, scroll, press_enter fall back to ADB shell commands via `shizuku_api` when accessibility gestures fail.
- **Telegram**: Background polling via `TelegramService` — bot token in `SharedPreferences`.
- **Background engine**: `BackgroundEngineReceiver` registers accessibility channels on cached Flutter engine via broadcast `com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS`.
- **Audio pipeline**: Kotlin `AudioRecord` (16kHz PCM16 mono → base64 chunks via EventChannel) for mic; `AudioTrack` (24kHz PCM16 mono) with `LinkedBlockingQueue` for playback.
- **Gemini Live**: Uses `gemini_live` Dart package (`^2026.7.19`) with WebSocket. `_defaultApiKey` in `lib/services/gemini_live_service.dart` is empty — must be configured for release.

## Local Plugins

`dependency_overrides` in `pubspec.yaml` patches two plugins:

| Plugin | Path | Purpose |
|--------|------|---------|
| `flutter_overlay_window` | `./local_plugins/flutter_overlay_window/` | Floating overlay window |
| `agent_native` | `./local_plugins/agent_native/` | Stub (only `getPlatformVersion`) |

## Key Conventions

- `assets/local_config/ai_test_config.json` gitignored (local dev credentials).
- `release/` directory gitignored.
- Default max task steps: 15 (can be disabled via `disableMaxSteps` toggle → max 999).
- The app's own package (`com.orailnoor.privateagent`) is excluded from screen dumps and accessibility event forwarding.
- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml`.
- When editing Dart: prefer `const` constructors, descriptive names.
- When editing Kotlin: recycle nodes, skip own package, prefer clickable parents before coordinate fallback.
