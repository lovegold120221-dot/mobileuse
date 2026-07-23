import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import 'action_handler.dart';

const String _defaultApiKey = '';

const String voicePersonalityPrompt = r'''
You are Beatrice, a warm and natural voice companion for Android users.

CRITICAL: Only call a function when the user explicitly asks you to do something on their phone. If the user is just chatting, asking questions, making casual conversation, or being friendly, DO NOT call any function — just reply naturally with your voice.

When the user does give a task instruction, call the execute_task function with the full goal as one clear sentence. Do NOT use read_screen proactively — only if you genuinely need screen context to proceed.

Reply out loud briefly and naturally (1-3 short sentences). Be warm, direct, and concise.

If a function fails, briefly explain and ask if the user wants to retry or try another way.

The user can interrupt or say "stop" to cancel.
''';

enum LiveVoiceState { idle, connecting, listening, speaking }

const MethodChannel _channel = MethodChannel('com.privateagent/accessibility');
const EventChannel _audioEventChannel = EventChannel('com.privateagent/audio_stream');

class GeminiLiveService {
  String apiKey;
  String model;
  String voiceName;
  int outputSampleRate;
  final ActionHandler actionHandler;

  LiveSession? _session;
  GoogleGenAI? _genAI;
  StreamSubscription? _audioSub;

  LiveVoiceState _state = LiveVoiceState.idle;
  bool _active = false;
  String? _pendingText;
  bool _resumeRecordingAfterTurn = false;

  final StreamController<LiveVoiceState> _stateCtrl =
      StreamController.broadcast();
  Stream<LiveVoiceState> get stateStream => _stateCtrl.stream;
  LiveVoiceState get state => _state;

  Function(String)? onResponseText;
  Function(String)? onUserText;
  Function(String)? onError;
  Function()? onTurnComplete;

  GeminiLiveService({
    String? apiKey,
    this.model = 'gemini-2.5-flash-native-audio-preview-12-2025',
    this.voiceName = 'Aoede',
    this.outputSampleRate = 24000,
    ActionHandler? actionHandler,
  })  : apiKey = apiKey ?? _defaultApiKey,
        actionHandler = actionHandler ?? ActionHandler();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key');
    if (savedKey != null && savedKey.isNotEmpty) {
      apiKey = savedKey;
    }
    voiceName = prefs.getString('gemini_voice_name') ?? voiceName;
    outputSampleRate =
        int.tryParse(prefs.getString('gemini_output_sample_rate') ?? '') ??
            outputSampleRate;
  }

  Future<void> start() async {
    if (_state != LiveVoiceState.idle) {
      developer.log('start: already in state $_state, returning', name: 'GeminiLive');
      return;
    }
    _active = true;
    _setState(LiveVoiceState.connecting);
    developer.log('start: calling _connect()...', name: 'GeminiLive');
    try {
      await _connect();
      developer.log('start: _connect() completed successfully', name: 'GeminiLive');
    } catch (e, s) {
      final msg = 'Voice session failed: $e\n$s';
      developer.log('start failed: $e\n$s', name: 'GeminiLive');
      print('GeminiLive CRASH: $e\n$s');
      onError?.call(msg);
      await stop();
    }
  }

  Future<void> stop() async {
    _active = false;
    _pendingText = null;
    _resumeRecordingAfterTurn = false;
    await _stopNativeRecording();
    await _stopPcmAudio();
    await _session?.close();
    _session = null;
    _genAI = null;
    _setState(LiveVoiceState.idle);
  }

  Future<void> _connect() async {
    print('GeminiLive IN _connect: step 1 - creating GoogleGenAI');
    developer.log('_connect: step 1 - GoogleGenAI init', name: 'GeminiLive');
    _genAI = GoogleGenAI(apiKey: apiKey);

    developer.log('_connect: step 2 - live.connect()... model=$model', name: 'GeminiLive');
    print('GeminiLive IN _connect: step 2 - live.connect()...');
    try {
      _session = await _genAI!.live.connect(
        LiveConnectParameters(
          model: model,
          config: GenerationConfig(
            responseModalities: [Modality.AUDIO],
            speechConfig: SpeechConfig(
              voiceConfig: VoiceConfig(
                prebuiltVoiceConfig: PrebuiltVoiceConfig(
                  voiceName: voiceName,
                ),
              ),
            ),
          ),
          systemInstruction: Content(
            parts: [Part(text: voicePersonalityPrompt)],
          ),
          tools: _buildTools(),
          callbacks: LiveCallbacks(
            onOpen: _onWSOpen,
            onMessage: _onMessage,
            onError: (e, s) {
              final msg = 'Voice connection error: $e';
              developer.log('WS error: $e', name: 'GeminiLive');
              print('GeminiLive WS error: $e');
              onError?.call(msg);
              if (_active) unawaited(stop());
            },
            onClose: (code, reason) {
              developer.log('WS closed: $code $reason', name: 'GeminiLive');
              print('GeminiLive WS closed: $code $reason');
              if (_active) unawaited(stop());
            },
          ),
        ),
      );
    } catch (e, s) {
      print('GeminiLive _connect LIVE.CONNECT FAILED: $e\n$s');
      rethrow;
    }

    print('GeminiLive _connect: step 3 - connect() OK, setting listening');
    developer.log('_connect: step 3 - session established', name: 'GeminiLive');
    _setState(LiveVoiceState.listening);

    print('GeminiLive _connect: step 4 - starting audio');
    developer.log('_connect: step 4 - starting audio', name: 'GeminiLive');
    if (_pendingText != null && _pendingText!.trim().isNotEmpty) {
      final text = _pendingText!;
      _pendingText = null;
      _resumeRecordingAfterTurn = true;
      _sendClientContent(text);
    } else {
      try {
        await _startNativeRecording();
      } catch (e, s) {
        print('GeminiLive _startNativeRecording failed: $e\n$s');
        onError?.call('Recording start failed: $e');
      }
    }
    print('GeminiLive _connect: DONE');
  }

  List<Tool> _buildTools() {
    return [
      Tool(functionDeclarations: [
        FunctionDeclaration(
          name: 'execute_task',
          description:
              'Execute a task on the Android phone. Call this when the user explicitly asks you to do something on their phone — open an app, set something, send a message, search, click, scroll, type, etc. Provide the full goal as one clear sentence.',
          parameters: {
            'type': 'object',
            'properties': {
              'goal': {
                'type': 'string',
                'description':
                    'The full task to accomplish, phrased as a clear instruction for MobileUse Agent'
              }
            },
            'required': ['goal']
          },
        ),
        FunctionDeclaration(
          name: 'read_screen',
          description:
              'Read and describe what is currently visible on the screen. Only use this if you genuinely need screen context to complete a task.',
          parameters: {'type': 'object', 'properties': {}},
        ),
      ]),
    ];
  }

  void _onMessage(LiveServerMessage message) {
    try {
      if (message.toolCall != null) {
        _handleToolCall(message.toolCall!);
        return;
      }

      if (message.toolCallCancellation != null) {
        developer.log('Tool call cancelled', name: 'GeminiLive');
        return;
      }

      final sc = message.serverContent;
      if (sc == null) return;

      if (sc.interrupted == true) {
        developer.log('Model interrupted', name: 'GeminiLive');
        _setState(LiveVoiceState.listening);
        unawaited(_stopPcmAudio());
        _startNativeRecording();
        return;
      }

      if (sc.turnComplete == true) {
        developer.log('Turn complete', name: 'GeminiLive');
        _setState(LiveVoiceState.listening);
        onTurnComplete?.call();
        if (_active && _resumeRecordingAfterTurn) {
          _resumeRecordingAfterTurn = false;
          _startNativeRecording();
        } else if (_active && _pendingText == null) {
          _startNativeRecording();
        }
      }

      if (message.data != null && message.data!.isNotEmpty) {
        _setState(LiveVoiceState.speaking);
        unawaited(_stopNativeRecording());
        unawaited(_playAudioResponse(message.data!));
      }

      if (message.text != null && message.text!.isNotEmpty) {
        onResponseText?.call(message.text!);
      }

      if (sc.modelTurn != null && sc.modelTurn!.parts != null) {
        for (final part in sc.modelTurn!.parts!) {
          if (part.functionCall != null) {
            unawaited(_executeFunctionCall(part.functionCall!));
          }
        }
      }
    } catch (e) {
      developer.log('Parse msg error: $e', name: 'GeminiLive');
    }
  }

  void _onWSOpen() {
    developer.log('Gemini Live WS opened (setup pending)', name: 'GeminiLive');
  }

  Future<void> _startNativeRecording() async {
    if (_state == LiveVoiceState.speaking) return;
    if (_audioSub != null) return;
    try {
      await _channel.invokeMethod('startRecording', {'sampleRate': 16000});
    } catch (e) {
      developer.log('startRecording error: $e', name: 'GeminiLive');
      onError?.call('Microphone error: $e');
      return;
    }
    _audioSub = _audioEventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! String) return;
        if (_session == null || !_active) return;
        _sendRealtimeInput(event);
      },
      onError: (e) {
        developer.log('Audio stream error: $e', name: 'GeminiLive');
        onError?.call('Audio stream error: $e');
      },
    );
  }

  Future<void> _stopNativeRecording() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (e) {
      developer.log('stopRecording error: $e', name: 'GeminiLive');
    }
  }

  Future<void> _stopPcmAudio() async {
    try {
      await _channel.invokeMethod('stopPcmAudio');
    } catch (e) {
      developer.log('stopPcmAudio error: $e', name: 'GeminiLive');
    }
  }

  void _sendRealtimeInput(String base64Data) {
    if (_session == null) return;
    _session!.sendMediaChunks([
      Blob(mimeType: 'audio/pcm;rate=16000', data: base64Data),
    ]);
  }

  void sendUserText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    onUserText?.call(trimmed);

    if (_session == null) {
      _active = true;
      _pendingText = trimmed;
      _resumeRecordingAfterTurn = true;
      _setState(LiveVoiceState.connecting);
      unawaited(_connect());
      return;
    }

    if (_state == LiveVoiceState.connecting) {
      _pendingText = trimmed;
      _resumeRecordingAfterTurn = true;
      return;
    }

    unawaited(_stopNativeRecording());
    _resumeRecordingAfterTurn = true;
    _sendClientContent(trimmed);
  }

  void _sendClientContent(String text) {
    if (_session == null) return;
    _session!.sendClientContent(
      turns: [
        Content(parts: [Part(text: text)], role: 'user'),
      ],
      turnComplete: true,
    );
  }

  Future<void> _playAudioResponse(String base64Data) async {
    if (base64Data.isEmpty) return;
    try {
      await _channel.invokeMethod('playPcmAudio', {
        'data': base64Data,
        'sampleRate': outputSampleRate,
      });
    } catch (e) {
      developer.log('playPcmAudio error: $e', name: 'GeminiLive');
    }
  }

  void _handleToolCall(LiveServerToolCall toolCall) {
    final fcs = toolCall.functionCalls;
    if (fcs == null) return;
    for (final fc in fcs) {
      unawaited(_executeFunctionCall(fc));
    }
  }

  Future<void> _executeFunctionCall(FunctionCall fc) async {
    final name = fc.name ?? '';
    final args = fc.args ?? {};
    final id = fc.id;

    developer.log('Function call: $name($args)', name: 'GeminiLive');

    final action = AgentAction(
      action: name,
      params: Map<String, dynamic>.from(
        args.map((k, v) => MapEntry(k, v is String ? v : v.toString())),
      ),
      response: '',
    );

    String result;
    try {
      final r = await actionHandler.execute(action);
      result = r.success ? (r.details ?? 'Done') : 'Failed: ${r.details}';
    } catch (e) {
      result = 'Error: $e';
    }

    developer.log('Function result: $result', name: 'GeminiLive');

    if (id != null && _session != null) {
      _session!.sendFunctionResponse(
        id: id,
        name: name,
        response: {'output': result},
      );
    }
  }

  void _setState(LiveVoiceState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  void dispose() {
    _active = false;
    _stateCtrl.close();
    _audioSub?.cancel();
    _session?.close();
  }
}
