# MobileUse Agent — Agent Guide

**Android automation agent (Flutter + Kotlin + Accessibility Services).**

## Entrypoints

- `lib/main.dart` — main app (settings, onboarding, home).
- `lib/overlay_main.dart` — floating chat overlay widget. **Separate `@pragma("vm:entry-point") void overlayMain()`**.
- Feature flag in `lib/config/feature_flags.dart`: `floatingOverlayEnabled = false` (currently disabled).

## Build & Run

```sh
flutter build apk                    # universal APK
flutter build apk --split-per-abi    # per-arch split APKs
flutter build appbundle              # AAB for Play Store
```

- `minSdk = 26` (Android 8.0), screenshot requires API 30+.
- Release builds use debug signing config by default — override in `android/app/build.gradle.kts`.
- `build/` dir is redirected by root `android/build.gradle.kts` to `../../build/`.
- APK releases: `app-universal-release.apk` when available, otherwise `app-arm64-v8a-release.apk`.

## Testing

Only 3 unit tests exist, all in `test/ai_service_test.dart`:

```sh
flutter test                              # all tests
flutter test test/ai_service_test.dart    # single file
```

No integration tests, no CI workflows (`.github/workflows/` is empty).

## AI Provider

OpenAI-compatible chat completions API. Defaults: `https://api.deepseek.com` / `deepseek-chat`. Quickly configurable for OpenRouter, NVIDIA NIM, etc.

Provider presets available in Settings (chip buttons):
- **Ollama** — `http://localhost:11434/v1` / `gemma3:4b` (local on-device via Termux)
- **OpenCode** — `http://localhost:8080/v1` / `deepseek-chat` (Termux proot-distro)
- **Gemini** — `https://generativelanguage.googleapis.com/v1beta/openai/` / `gemini-2.0-flash` (OpenAI-compatible endpoint, key from Google AI Studio)
- **NVIDIA** — `https://integrate.api.nvidia.com/v1` / `z-ai/glm-5.2`
- **DeepSeek** — `https://api.deepseek.com` / `deepseek-chat`
- **Groq** — `https://api.groq.com/openai/v1`

- API key auto-strips `"Bearer "` prefix.
- NVIDIA `z-ai/glm-5.2` model forces `_effectiveMaxTokens` to 4096 minimum.
- `sendTaskMessage` retries 4× with 3s exponential backoff.
- `parseAction` handles truncated JSON (missing closing `}` from small models).
- `<think>…</think>` reasoning blocks auto-stripped from responses.

## Architecture Notes

- **Three layers**: Flutter Dart → MethodChannel (`com.privateagent/accessibility`) → Kotlin `AgentAccessibilityService`.
- **Background engine**: `BackgroundEngineReceiver` registers accessibility channels on `FlutterEngineCache` key `"myCachedEngine"` via broadcast `com.orailnoor.privateagent.REGISTER_BACKGROUND_CHANNELS`.
- **Task loop**: `TaskExecutor` runs AI-guided screen-read → act → repeat loop with adaptive delays (1-3s depending on action type). Stuck detection after 5 consecutive failures.
- **Navigation shortcuts**: Hard-coded app/keyword patterns in `TaskExecutor._getNavigationShortcut()` — press Home first to avoid AI seeing its own chat UI.
- **Recovery engine**: Hard-coded `RecoveryEngine` — press back, scroll, or wait based on screen content.
- **Skill memory**: JSONL at `skills_memory.jsonl` in app documents dir. Jaccard similarity matching. Replayed without LLM.
- **Shizuku fallback**: Some actions (swipe, scroll, press enter) fall back to ADB commands via `shizuku_api` if accessibility service can't execute them.
- **Telegram**: Background polling via `TelegramService` — bot token stored in `SharedPreferences`.

## Local Plugins

`dependency_overrides` in `pubspec.yaml` patches two plugins:

| Plugin | Path | Purpose |
|--------|------|---------|
| `flutter_overlay_window` | `./local_plugins/flutter_overlay_window/` | Floating overlay widget |
| `agent_native` | `./local_plugins/agent_native/` | Stub (only `getPlatformVersion`) |

## Models

- `AgentAction` — single-step actions with JSON schema (`action`, `params`, `response`).
- `ChatMessage` — role/content pair.
- `SavedSkill` — recorded action sequences for skill replay.

## Key Conventions

- Screenshots require Android 11 (API 30). Lower APIs silently return null.
- `<think>` blocks stripped from all AI responses before display.
- Conversation history capped at 20 messages.
- Default max task steps: 15 (can be disabled via `disableMaxSteps` toggle).
- `assets/local_config/ai_test_config.json` gitignored (local dev credentials).
- Gradle: `isCoreLibraryDesugaringEnabled = true`, `jvmTarget = 17`.
