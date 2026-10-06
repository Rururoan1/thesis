// lib/services/api_service.dart
// ─────────────────────────────
// All HTTP communication with the Flask backend lives here.
// Change [baseUrl] to match your deployment host.
//
// Every request automatically carries the signed-in user's mobile number in
// the `X-User-Id` header, so the backend can store and return each farmer's
// scans separately. Screens do not need to pass the user themselves.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/analysis_result.dart';
import '../../models/history_response.dart';
import 'auth_service.dart';

class ApiService {

  /// static const String baseUrl = 'http://10.0.2.2:5000';
  // static const String baseUrl = 'http://10.0.2.2:5000';
  // Android emulator → localhost
  // static const String baseUrl = 'http://192.168.1.126:5000';
  // static const String baseUrl = 'https://my-domain.com';   //
  static const String baseUrl = 'https://michaelcomisas88--rice-pest-detector-flask-app.modal.run';

  static const Duration _timeout = Duration(seconds: 120);


  ApiService._internal();
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  /// Headers sent with every authenticated request.
  Map<String, String> get _userHeaders {
    final userId = AuthService.instance.currentUser;
    if (userId == null) {
      throw const ApiException('Please sign in first.', statusCode: 401);
    }
    return {'X-User-Id': userId};
  }

  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/'))
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }


  /// Upload [imageFile] and return an [AnalysisResult].
  Future<AnalysisResult> analyzeImage(File imageFile) async {
    final uri     = Uri.parse('$baseUrl/api/v1/analyze');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_userHeaders);

    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamedResponse = await request.send().timeout(_timeout);
    final response         = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] == true) {
        return AnalysisResult.fromJson(json['data'] as Map<String, dynamic>);
      }
      throw ApiException(json['message'] ?? 'Unknown error');
    }

    _handleError(response);
    throw ApiException('Unexpected error (${response.statusCode})');
  }


  Future<HistoryResponse> getHistory({int page = 1, int perPage = 20}) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/history?page=$page&per_page=$perPage',
    );
    final response =
    await http.get(uri, headers: _userHeaders).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HistoryResponse.fromJson(json['data'] as Map<String, dynamic>);
    }
    _handleError(response);
    throw ApiException('Failed to fetch history (${response.statusCode})');
  }


  Future<AnalysisResult> getAnalysisById(int id) async {
    final uri      = Uri.parse('$baseUrl/api/v1/history/$id');
    final response =
    await http.get(uri, headers: _userHeaders).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return AnalysisResult.fromJson(json['data'] as Map<String, dynamic>);
    }
    _handleError(response);
    throw ApiException('Failed to fetch analysis #$id (${response.statusCode})');
  }


  Future<Map<String, dynamic>> getStats() async {
    final uri      = Uri.parse('$baseUrl/api/v1/stats');
    final response =
    await http.get(uri, headers: _userHeaders).timeout(_timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['data'] as Map<String, dynamic>;
    }
    _handleError(response);
    throw ApiException('Failed to fetch stats (${response.statusCode})');
  }


  void _handleError(http.Response response) {
    String message = 'An error occurred (${response.statusCode})';
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      message = json['message'] as String? ?? message;
    } catch (_) {}
    throw ApiException(message, statusCode: response.statusCode);
  }
}


class ApiException implements Exception {
  final String message;
  final int?   statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (HTTP $statusCode)';
}
