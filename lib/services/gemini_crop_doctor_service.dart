import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GeminiCropDoctorResult {
  const GeminiCropDoctorResult({
    required this.cropKh,
    required this.cropEn,
    required this.diseaseKh,
    required this.diseaseEn,
    required this.severityKh,
    required this.confidenceText,
    required this.confidenceScore,
    required this.symptomsKh,
    required this.treatmentKh,
    required this.preventionKh,
    required this.warningKh,
  });

  final String cropKh;
  final String cropEn;
  final String diseaseKh;
  final String diseaseEn;
  final String severityKh;
  final String confidenceText;
  final double confidenceScore;
  final String symptomsKh;
  final List<String> treatmentKh;
  final List<String> preventionKh;
  final String warningKh;

  factory GeminiCropDoctorResult.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      if (value is String && value.trim().isNotEmpty) {
        return [value.trim()];
      }
      return const [];
    }

    final confidenceText = json['confidence']?.toString().trim() ?? 'មធ្យម';

    return GeminiCropDoctorResult(
      cropKh: _cleanText(json['crop_kh'], 'មិនអាចកំណត់បាន'),
      cropEn: _cleanText(json['crop_en'], 'Unknown'),
      diseaseKh: _cleanText(json['disease_kh'], 'មិនអាចកំណត់បាន'),
      diseaseEn: _cleanText(json['disease_en'], 'Unknown'),
      severityKh: _cleanText(json['severity_kh'], 'មិនច្បាស់'),
      confidenceText: confidenceText,
      confidenceScore: _confidenceToScore(confidenceText),
      symptomsKh: _cleanText(json['symptoms_kh'], 'មិនមានរោគសញ្ញាច្បាស់លាស់ក្នុងរូបភាពនេះទេ។'),
      treatmentKh: toStringList(json['treatment_kh']),
      preventionKh: toStringList(json['prevention_kh']),
      warningKh: _cleanText(
        json['warning_kh'],
        'លទ្ធផលនេះជាជំនួយពី AI ប៉ុណ្ណោះ។ សូមពិគ្រោះអ្នកជំនាញកសិកម្មមុនប្រើថ្នាំ។',
      ),
    );
  }

  DiseaseResultView toDiseaseResultView() {
    final buffer = StringBuffer();
    buffer.writeln('រោគសញ្ញា: $symptomsKh');

    if (treatmentKh.isNotEmpty) {
      buffer.writeln('\nវិធីព្យាបាល:');
      for (final item in treatmentKh) {
        buffer.writeln('• $item');
      }
    }

    if (preventionKh.isNotEmpty) {
      buffer.writeln('\nវិធីការពារ:');
      for (final item in preventionKh) {
        buffer.writeln('• $item');
      }
    }

    buffer.writeln('\n$warningKh');

    return DiseaseResultView(
      disease: diseaseKh,
      severity: severityKh,
      confidence: confidenceScore,
      recommendation: buffer.toString().trim(),
    );
  }

  static String _cleanText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _confidenceToScore(String confidence) {
    final text = confidence.trim().toLowerCase();
    final percentMatch = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(text);
    if (percentMatch != null) {
      final value = double.tryParse(percentMatch.group(1)!);
      if (value != null) return (value / 100).clamp(0.0, 1.0).toDouble();
    }

    final decimalValue = double.tryParse(text);
    if (decimalValue != null) {
      return decimalValue > 1
          ? (decimalValue / 100).clamp(0.0, 1.0).toDouble()
          : decimalValue.clamp(0.0, 1.0).toDouble();
    }

    if (text.contains('high') || text.contains('ខ្ពស់')) return 0.85;
    if (text.contains('low') || text.contains('ទាប')) return 0.45;
    return 0.65;
  }
}

class DiseaseResultView {
  const DiseaseResultView({
    required this.disease,
    required this.severity,
    required this.confidence,
    required this.recommendation,
  });

  final String disease;
  final String severity;
  final double confidence;
  final String recommendation;
}

class GeminiCropDoctorService {
  GeminiCropDoctorService({http.Client? client}) : _client = client ?? http.Client();

  // HTTP Cloud Function, no Gemini key in app.
  static final Uri _functionUri = Uri.parse(
    'https://asia-southeast1-kasiai-33c68.cloudfunctions.net/analyzeCropImageHttp',
  );

  final http.Client _client;

  Future<GeminiCropDoctorResult> analyzeCropImage(File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final mimeType = _mimeTypeForPath(imageFile.path);

      final response = await _client
          .post(
            _functionUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'imageBase64': base64Image,
              'mimeType': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 120));

      Map<String, dynamic> decoded = {};
      if (response.body.trim().isNotEmpty) {
        final value = jsonDecode(response.body);
        decoded = _toStringKeyMap(value);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        final message = error is Map
            ? (error['message']?.toString() ?? response.body)
            : response.body;
        throw Exception('AI Cloud HTTP error ${response.statusCode}: $message');
      }

      return GeminiCropDoctorResult.fromJson(decoded);
    } catch (error) {
      throw Exception('AI Cloud function failed: $error');
    }
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  Map<String, dynamic> _toStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _normalizeValue(item)));
    }
    throw Exception('AI Cloud result មិនមែនជា JSON object ត្រឹមត្រូវ។');
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _normalizeValue(item)));
    }
    if (value is List) {
      return value.map(_normalizeValue).toList();
    }
    return value;
  }
}
