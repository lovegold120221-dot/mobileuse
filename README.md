# MobileUse Agent

World's first mobile-use agent by Eburon AI.

An open-source Android automation agent built with Flutter + Kotlin. Uses
OpenAI-compatible LLMs and Android Accessibility Services to read screens,
execute multi-step tasks, and interact via voice (Gemini Live API) across any
installed application.

## Features

- **AI-Driven Automation** — Describe what you want in natural language; the
  agent reads the screen, decides the next action, and executes it — loop until
  done.
- **Gemini Live Voice Agent** — Real-time voice interaction via WebSocket
  ("Beatrice" voice companion). Tap the orb, speak naturally, get spoken
  responses with full device control.
- **Dual Input Modes** — **Chat** (text conversation with any AI provider) and
  **Agent** (voice orb + text input with Gemini Live).
- **Screen Reading** — Parses the Android UI tree to map clickable, scrollable,
  and editable elements with coordinates.
- **Skill Memory** — Successful task sequences are saved as JSONL skills and
  replayed without an LLM (Jaccard similarity matching).
- **Recovery Engine** — Hard-coded fallback strategies when actions fail
  (scroll, press back, wait).
- **Remote Access** — Telegram Bot API background polling for remote commands.
- **Floating Overlay** — Chat bubble overlay that works on top of other apps
  (currently stabilizing — disabled by default).
- **Voice I/O** — Speech-to-text (Google), Text-to-speech (FlutterTTS / Kokoro
  TTS), and native raw PCM audio for Gemini Live.
- **Shizuku Integration** — Optional ADB-level fallback for swipe, scroll, and
  keyboard actions.
- **Task History** — Full execution logs with analytics (success rate, tokens,
  steps).
- **Multiple AI Providers** — DeepSeek, Groq, NVIDIA NIM, Ollama (local),
  OpenCode (Termux), Gemini, OpenRouter, or any OpenAI-compatible endpoint.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Flutter Dart Layer                                      │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────────┐   │
│  │ main.dart│  │overlay    │  │ Services             │   │
│  │(App UI)  │  │_main.dart │  │ AI, ActionHandler,   │   │
│  │          │  │(Floating  │  │ TaskExecutor, Voice,  │   │
│  │HomeScreen│  │ Overlay)  │  │ GeminiLive, Telegram  │   │
│  │Settings  │  │           │  │ ScreenAutomation      │   │
│  │Onboarding│  │           │  └───────────┬───────────┘   │
│  └────┬─────┘  └─────┬─────┘             │               │
│       └───────┬───────┘                  │               │
│               │    MethodChannel          │               │
│               │  "com.privateagent/      │               │
│               │    accessibility"        │               │
├───────────────┼──────────────────────────┼───────────────┤
│  Kotlin Layer │ (MainActivity.kt)        │               │
│  - 25+ MethodChannel handlers            │               │
│  - EventChannel for accessibility events │               │
│  - AudioRecord mic + AudioTrack playback │               │
│  - BackgroundEngineReceiver              │               │
├───────────────┼──────────────────────────┼───────────────┤
│  Android Accessibility Service            │               │
│  (AgentAccessibilityService.kt)          │               │
│  - Screen tree traversal (dumpScreen)    │               │
│  - Click by text / coordinates           │               │
│  - Text input, scroll, swipe, back/home  │               │
│  - Screenshot capture (API 30+)          │               │
└──────────────────────────────────────────────────────────┘
```

### Task Execution Loop

1. Verify accessibility service is running
2. Check skill memory for a matching replay (Jaccard > 0.6)
3. Apply navigation shortcuts (home screen first to avoid AI seeing its own UI)
4. Main loop (up to `maxSteps`, default 15):
   - Adaptive delay (1–3s based on last action type)
   - Dump screen (compressed or full)
   - Send to AI with task context + screen content
   - Parse JSON action (handles code fences, truncated JSON)
   - Execute via Accessibility Service (Shizuku ADB fallback)
   - Track failures; use RecoveryEngine after 5 consecutive failures
   - Save to skill memory on success
5. Log to task history (JSONL)

### Gemini Live Voice Pipeline

```
Tap orb → mic permission → AudioRecord (16kHz PCM16 mono)
  → base64 chunks → WebSocket realtimeInput → Gemini Live API
  → serverContent (audio response) → AudioTrack (24kHz PCM16 mono) playback
  → function calls → ActionHandler → device actions
```

## Build

```sh
flutter build apk                    # universal APK
flutter build apk --split-per-abi    # per-arch split APKs
flutter build appbundle              # AAB for Play Store
```

- **minSdk** = 26 (Android 8.0), screenshots require API 30+
- Build output: `build/app/outputs/flutter-apk/app-universal-release.apk`
  (or `app-arm64-v8a-release.apk` for split builds)

## Quick Start (Free)

1. Install the APK on your Android device (API 30+ recommended).
2. Go to [OpenRouter.ai](https://openrouter.ai/) → free account → API key.
3. Launch MobileUse Agent → **Settings** → tap **OpenRouter** chip.
4. Paste your API key, enter a free model (e.g. `openai/gpt-oss-120b:free`).
5. Enable **MobileUse Agent Screen Control** in Android Accessibility Settings.
6. Start chatting or switch to **Agent** tab for the voice orb.

> **Restricted setting?** Android may block accessibility for sideloaded apps.
> Go to **Settings → Apps → MobileUse Agent → ⋮ → Allow restricted settings**.

### Gemini Live (Voice Agent)

The Agent tab uses Gemini Live API for real-time voice. An API key for
`models/gemini-3.1-flash-live-preview` is compiled into debug builds. For
release, configure your own key via `_defaultApiKey` in
`lib/services/gemini_live_service.dart`.

## AI Provider Presets

| Provider    | Base URL / Notes                                  |
|-------------|---------------------------------------------------|
| **Ollama**  | `http://localhost:11434/v1` — local via Termux    |
| **OpenCode**| `http://localhost:8080/v1` — Termux proot-distro  |
| **Gemini**  | `https://generativelanguage.googleapis.com/v1beta/openai/` |
| **NVIDIA**  | `https://integrate.api.nvidia.com/v1` — 14+ free models |
| **DeepSeek**| `https://api.deepseek.com` — default              |
| **Groq**    | `https://api.groq.com/openai/v1`                 |
| **OpenRouter** | `https://openrouter.ai/api/v1`               |

Settings are auto-saved to `SharedPreferences` on any change.

## Permissions Required

- **Accessibility Service** — Screen reading and automation
- **Microphone** — Voice input (STT + Gemini Live)
- **Notifications** — Task completion alerts (Android 13+)
- **Phone / SMS** — Make calls and send messages
- **Contacts** — Contact search for calls/SMS
- **Overlay** — Floating chat bubble (optional)
- **Shizuku** — ADB fallback (optional)

## Project Structure

```
lib/
├── config/feature_flags.dart          # Feature toggles (overlay)
├── main.dart                          # App entry + overlay entry point
├── overlay_main.dart                  # Floating chat overlay (separate engine)
├── models/
│   ├── agent_action.dart              # Action schema + action list
│   ├── chat_message.dart              # Message model with action results
│   └── saved_skill.dart               # Skill memory model
├── screens/
│   ├── home_screen.dart               # Main chat + agent UI
│   ├── onboarding_screen.dart         # 3-step setup wizard
│   ├── settings_screen.dart           # Full configuration
│   └── task_history_screen.dart       # Execution logs + analytics
├── services/
│   ├── action_handler.dart            # Central action dispatcher
│   ├── ai_service.dart                # OpenAI-compatible API client
│   ├── alarm_service.dart             # Android alarm/timer intents
│   ├── app_launcher_service.dart      # App launch + URL open
│   ├── chat_history_service.dart      # Session persistence (JSON)
│   ├── communication_service.dart     # Call, SMS, email
│   ├── contacts_service.dart          # Contact search
│   ├── gemini_live_service.dart       # Gemini Live WebSocket + voice
│   ├── kokoro_tts_service.dart        # Kokoro TTS client
│   ├── notification_service.dart      # Local push notifications
│   ├── recovery_engine.dart           # Hard-coded failure recovery
│   ├── screen_automation_service.dart # Native bridge (MethodChannel)
│   ├── shizuku_service.dart           # ADB-level commands
│   ├── skill_memory_service.dart      # JSONL skill persistence
│   ├── system_control_service.dart    # Volume + brightness
│   ├── task_executor.dart             # AI-guided automation loop
│   ├── task_history_logger.dart       # JSONL task logs
│   ├── telegram_service.dart          # Bot API polling
│   └── voice_service.dart             # STT + TTS (with Kokoro fallback)
└── widgets/
    ├── message_bubble.dart            # Chat message renderer
    └── voice_orb.dart                 # Animated Gemini Live orb

android/app/src/main/kotlin/com/orailnoor/privateagent/
├── MainActivity.kt                    # MethodChannel + AudioRecord/Track
├── AgentAccessibilityService.kt       # Core accessibility service
└── Test.kt                            # Compile-time verification

local_plugins/
├── flutter_overlay_window/            # Patched overlay plugin
└── agent_native/                      # Stub plugin (unused)
```

## Telegram Remote Access

1. Create a bot via [BotFather](https://t.me/botfather) on Telegram.
2. Enter the bot token in **Settings → Telegram Remote Access**.
3. Enable the integration — the app polls Telegram in the background.
4. Send text commands to the bot; replies include execution results.

## Testing

```sh
flutter test                              # all tests
flutter test test/ai_service_test.dart    # single file
```

3 unit tests exist (AI service parsing). No integration tests.

## Skill Memory

Successful task sequences are saved to `skills_memory.jsonl` in the app
documents directory. Skills are matched by Jaccard similarity (>0.6) and
replayed without LLM cost on repeat requests.

## License

Open-source and available for modification.

