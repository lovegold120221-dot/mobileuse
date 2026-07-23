import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Client for a Kokoro-FastAPI TTS server.
///
/// Expects an OpenAI-compatible `/v1/audio/speech` endpoint that can return
/// raw 24 kHz mono PCM bytes. When no server is reachable, synthesis fails
/// so the caller can fall back to on-device TTS.
class KokoroTtsService {
  final String baseUrl;
  final String voice;
  final double speed;

  KokoroTtsService({
    this.baseUrl = 'http://localhost:8888',
    this.voice = 'af_heart',
    this.speed = 1.0,
  });

  /// Synthesize [text] and play it through the native PCM audio player.
  /// Returns true on success, false on any failure.
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return true;
    try {
      final uri = Uri.parse('$baseUrl/v1/audio/speech');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': 'kokoro',
              'input': text.trim(),
              'voice': voice,
              'response_format': 'pcm',
              'speed': speed,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        developer.log(
          'Kokoro TTS returned ${response.statusCode}: ${response.body}',
          name: 'KokoroTts',
        );
        return false;
      }

      final base64 = base64Encode(response.bodyBytes);
      await const MethodChannel('com.privateagent/accessibility').invokeMethod(
        'playPcmAudio',
        {
          'data': base64,
          'sampleRate': 24000,
        },
      );
      return true;
    } catch (e) {
      developer.log('Kokoro TTS error: $e', name: 'KokoroTts');
      return false;
    }
  }
}
