# AGENTS.md — Miko Project Instructions

## Project Overview
Vanilla JavaScript client for **Gemini 2.0 Flash Multimodal Live API**. Real-time text, audio, video, and screen sharing via WebSocket/WebRTC. No build step, no dependencies.

## Quick Start
```bash
# 1. Configure API key (once)
cp js/config/config.example.js js/config/config.js
# Edit js/config/config.js with your Google AI Studio API key

# 2. Run dev server
python -m http.server 8000
# or: npx http-server 8000

# 3. Open http://localhost:8000
```

## Project Structure
```
├── index.html          # Main HTML entry
├── js/
│   ├── main.js         # App entry point, UI wiring, WebSocket lifecycle
│   ├── config/         # CONFIG object (API key, voice, system prompt)
│   ├── core/           # WebSocket client, worklet registry
│   ├── audio/          # AudioRecorder, AudioStreamer, worklets
│   ├── video/          # VideoManager, VideoRecorder, ScreenRecorder
│   ├── tools/          # Function calling (google-search, weather)
│   └── utils/          # Logger, memory (Mem0), error-boundary
├── css/
│   ├── style.css       # Main styles
│   └── stoyle.css      # Duplicate? (verify before editing)
└── TODO.md             # Contribution notes
```

## Key Conventions
- **No build step** — edit files directly, reload browser
- **ES modules** — all JS uses `import`/`export`, served via HTTP (not `file://`)
- **Configuration** — `js/config/config.js` is gitignored; copy from `config.example.js`
- **API key** — never commit real keys; the example has a placeholder
- **Voice config** — `CONFIG.VOICE.NAME` maps to Gemini voices (Aoede, Charon, Kore, Fenrir, Puck, Orus)
- **Audio sample rates** — input fixed at 16kHz; output configurable via UI (default 24kHz)

## Development Workflow
1. Edit source files in `js/` and `css/`
2. Refresh browser — no hot reload
3. Check browser console for logs (Logger utility writes there)
4. Test features: Connect → Mic → Camera → Screen Share → Text chat

## Adding Custom Tools
See `js/tools/README.md`. Create a new tool module exporting a function schema and handler, register in `tool-manager.js`.

## Memory Integration
Uses Mem0 (`js/utils/memory.js`) for conversation persistence. Configured via `searchMemory`/`addMemory` calls in `main.js` on `turncomplete` events.

## Common Tasks
| Task | Command/Action |
|------|----------------|
| Run locally | `python -m http.server 8000` |
| Change API key | Edit `js/config/config.js` |
| Switch voice | Use voice dropdown in UI (persists to localStorage) |
| Add tool | Edit `js/tools/tool-manager.js` + new file in `js/tools/` |
| Modify system prompt | Edit `CONFIG.SYSTEM_INSTRUCTION.TEXT` in `config.js` |

## Gotchas
- **CORS/WebSocket** — must serve via HTTP(S), not `file://`
- **Microphone permission** — browser blocks until user gesture (handled via click listener)
- **AudioContext** — must be resumed after user interaction (handled in `connectToWebsocket`)
- **Two config files** — `config.js` (real) vs `config.example.js` (template); only example is tracked
- **Duplicate CSS** — `style.css` and `stoyle.css` appear identical; verify before editing
- **Hardcoded API key** in `config.example.js` — replace before use

## Testing
No automated tests. Manual verification via browser:
1. Connect to API
2. Send text message
3. Toggle microphone (verify audio visualizer)
4. Toggle camera (verify video preview)
5. Share screen
6. Check logs panel for errors

## Deployment
GitHub Pages (static) — push to `main`, enable Pages in repo settings. See README for live demo URL.

## References
- Original React implementation: https://github.com/google-gemini/multimodal-live-api-web-console
- Issue motivating this port: https://github.com/google-gemini/multimodal-live-api-web-console/issues/19
- Gemini Live API docs: https://ai.google.dev/gemini-api/docs/live