import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/preset.dart';
import '../models/extracted_outcome.dart';
import '../models/unstuck_response.dart';
import '../models/outcome_type.dart';

/// Structured result from the Magic preset.
/// If the backend is old or the JSON parse fell through, [intent] will
/// be null and [text] will still hold the polished rewrite.
class MagicResult {
  final String text;
  final String? intent;
  final String? label;
  final double? confidence;
  final List<String> alternatives;

  MagicResult({
    required this.text,
    this.intent,
    this.label,
    this.confidence,
    this.alternatives = const [],
  });
}

class AIService {
  // Backend URL - Change this based on your setup
  // PRODUCTION: Use your Railway deployment URL
  // LOCAL: Use your computer's local IP (find with 'ipconfig' or 'ifconfig')
  static const String _backendUrl = 'https://voicebubble-production.up.railway.app';
  
  // UNCOMMENT THIS FOR LOCAL DEVELOPMENT:
  // static const String _backendUrl = 'http://192.168.1.XXX:3000'; // Replace XXX with your local IP
  
  final Dio _dio = Dio();
  
  AIService() {
    _dio.options.headers = {
      'Content-Type': 'application/json',
    };
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }
  
  /// Convert audio file to text using backend Whisper API
  Future<String> transcribeAudio(File audioFile) async {
    try {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioFile.path,
          filename: 'audio.wav',
        ),
      });
      
      final response = await _dio.post(
        '$_backendUrl/api/transcribe',
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        ),
      );
      
      return response.data['text'] ?? '';
    } catch (e) {
      print('Transcription error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }
  
  /// Rewrite text using backend GPT-4 mini API
  Future<String> rewriteText(String text, Preset preset, String languageCode) async {
    try {
      // Use batch endpoint (non-streaming) for simplicity
      final response = await _dio.post(
        '$_backendUrl/api/rewrite/batch',
        data: {
          'text': text,
          'presetId': preset.id,
          'language': languageCode, // Output language preference
        },
      );

      return response.data['text'] ?? '';
    } catch (e) {
      print('Rewrite error: $e');
      throw Exception('Failed to rewrite text: $e');
    }
  }

  /// Run the Magic preset and return the STRUCTURED response with the
  /// auto-detected intent. The server returns extra fields alongside
  /// `text`; if they're missing (old backend, or fallback path) the
  /// caller still gets a valid MagicResult with just the text.
  Future<MagicResult> rewriteMagic({
    required String text,
    required String languageCode,
  }) async {
    try {
      final response = await _dio.post(
        '$_backendUrl/api/rewrite/batch',
        data: {
          'text': text,
          'presetId': 'magic',
          'language': languageCode,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return MagicResult(
        text: (data['text'] ?? '').toString(),
        intent: data['intent'] is String ? data['intent'] as String : null,
        label: data['label'] is String ? data['label'] as String : null,
        confidence: (data['confidence'] is num) ? (data['confidence'] as num).toDouble() : null,
        alternatives: (data['alternatives'] is List)
            ? (data['alternatives'] as List).whereType<String>().toList()
            : const <String>[],
      );
    } catch (e) {
      print('Magic rewrite error: $e');
      throw Exception('Failed to auto-rewrite: $e');
    }
  }
  
  /// Rewrite text with context for continuation flow
  Future<String> rewriteWithContext({
    required String text,
    required Preset preset,
    required String languageCode,
    List<String>? contextTexts,
  }) async {
    try {
      final Map<String, dynamic> requestData = {
        'text': text,
        'presetId': preset.id,
        'language': languageCode,
      };

      // Add context if provided
      if (contextTexts != null && contextTexts.isNotEmpty) {
        requestData['context'] = contextTexts;
      }

      final response = await _dio.post(
        '$_backendUrl/api/rewrite/batch',
        data: requestData,
      );
      
      return response.data['text'] ?? '';
    } catch (e) {
      print('Rewrite with context error: $e');
      throw Exception('Failed to rewrite text with context: $e');
    }
  }
  
  /// Extract atomic outcomes from text (for Outcomes preset)
  Future<List<ExtractedOutcome>> extractOutcomes(String text, String languageCode) async {
    try {
      final response = await _dio.post(
        '$_backendUrl/api/extract/outcomes',
        data: {
          'text': text,
          'language': languageCode,
        },
      );
      
      // Backend returns: { outcomes: [{ type: 'task', text: '...' }, ...] }
      final outcomesList = response.data['outcomes'] as List;
      return outcomesList.map((o) => 
        ExtractedOutcome(
          id: const Uuid().v4(),
          type: OutcomeTypeExtension.fromString(o['type'] as String),
          text: o['text'] as String,
        )
      ).toList();
    } catch (e) {
      print('Extract outcomes error: $e');
      throw Exception('Failed to extract outcomes: $e');
    }
  }
  
  /// Extract insight and action from text (for Unstuck preset)
  Future<UnstuckResponse> extractUnstuck(String text, String languageCode) async {
    try {
      final response = await _dio.post(
        '$_backendUrl/api/extract/unstuck',
        data: {
          'text': text,
          'language': languageCode,
        },
      );
      
      // Backend returns: { insight: '...', action: '...' }
      return UnstuckResponse(
        insight: response.data['insight'] as String,
        action: response.data['action'] as String,
      );
    } catch (e) {
      print('Extract unstuck error: $e');
      throw Exception('Failed to extract unstuck: $e');
    }
  }

}

