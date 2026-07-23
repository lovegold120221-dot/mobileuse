import 'dart:developer' as developer;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'kokoro_tts_service.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final KokoroTtsService _kokoro = KokoroTtsService();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<void> init() async {
    if (_isInitialized) return;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        _isListening = false;
      },
    );
  }

  /// Start listening for speech. Returns transcribed text via callback.
  Future<void> startListening({
    required Function(String) onResult,
    required Function() onDone,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    if (!_isInitialized) await init();
    if (!_isInitialized) return;

    _isListening = true;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
          onDone();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.confirmation,
        partialResults: false,
        listenFor: listenFor,
        pauseFor: pauseFor,
      ),
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    _isListening = false;
    await _speech.stop();
  }

  /// Speak text aloud using Kokoro TTS only. Never uses on-device/mobile TTS.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final ok = await _kokoro.speak(text);
    if (!ok) {
      developer.log(
        'Kokoro TTS unavailable; chat response was not spoken.',
        name: 'VoiceService',
      );
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {}

  void dispose() {
    _speech.stop();
  }
}
