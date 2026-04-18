import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:voice_agent/core/models/transcript.dart';

sealed class ApiResult {
  const ApiResult();
}

class ApiSuccess extends ApiResult {
  const ApiSuccess({this.body});
  final String? body;
}

class ApiPermanentFailure extends ApiResult {
  const ApiPermanentFailure({required this.statusCode, required this.message});
  final int statusCode;
  final String message;
}

class ApiTransientFailure extends ApiResult {
  const ApiTransientFailure({required this.reason});
  final String reason;
}

class ApiNotConfigured extends ApiResult {
  const ApiNotConfigured();
}

class ApiClient {
  ApiClient({Dio? dio, this.baseUrl, this.token})
      : _dio = dio ?? _createDefaultDio();

  final Dio _dio;
  final String? baseUrl;
  final String? token;

  static Dio _createDefaultDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 2),
      followRedirects: false,
      maxRedirects: 0,
    ));
  }

  Future<ApiResult> post(
    Transcript transcript, {
    required String url,
    String? token,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: {
          'text': transcript.text,
          'timestamp':
              transcript.createdAt ~/ 1000, // ms to epoch seconds
          'language': transcript.language,
          'deviceId': transcript.deviceId,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        final dynamic data = response.data;
        final String? body =
            data == null ? null : (data is String ? data : jsonEncode(data));
        return ApiSuccess(body: body);
      }
      return classifyStatusCode(statusCode, response.statusMessage);
    } on DioException catch (e) {
      return classifyDioException(e);
    }
  }

  /// Test connection to the API endpoint without sending real data.
  /// Sends a minimal payload that does not pollute the user's backend.
  Future<ApiResult> testConnection({
    required String url,
    String? token,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: {'test': true},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return const ApiSuccess();
      }
      return classifyStatusCode(statusCode, response.statusMessage);
    } on DioException catch (e) {
      return classifyDioException(e);
    }
  }

  Future<ApiResult> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return request('GET', path, queryParameters: queryParameters);
  }

  Future<ApiResult> patch(
    String path, {
    Map<String, dynamic>? data,
  }) {
    return request('PATCH', path, data: data);
  }

  Future<ApiResult> delete(String path) {
    return request('DELETE', path);
  }

  Future<ApiResult> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (baseUrl == null) return const ApiNotConfigured();

    final url = '$baseUrl$path';
    try {
      final response = await _dio.request<dynamic>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token!.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        final dynamic responseData = response.data;
        final String? body = responseData == null
            ? null
            : (responseData is String
                ? responseData
                : jsonEncode(responseData));
        return ApiSuccess(body: body);
      }
      return classifyStatusCode(statusCode, response.statusMessage);
    } on DioException catch (e) {
      return classifyDioException(e);
    }
  }

  ApiResult classifyStatusCode(int statusCode, String? message) {
    if (statusCode == 408 || statusCode == 429 || statusCode >= 500) {
      return ApiTransientFailure(
        reason: 'Server error: $statusCode ${message ?? ''}',
      );
    }
    return ApiPermanentFailure(
      statusCode: statusCode,
      message: message ?? 'Request failed',
    );
  }

  ApiResult classifyDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode != null) {
      return classifyStatusCode(statusCode, e.response?.statusMessage);
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiTransientFailure(reason: 'Timeout: ${e.type.name}');
      case DioExceptionType.connectionError:
        return ApiTransientFailure(reason: 'Connection error: ${e.message}');
      case DioExceptionType.cancel:
        return const ApiTransientFailure(reason: 'Request cancelled');
      default:
        return ApiTransientFailure(reason: 'Network error: ${e.message}');
    }
  }
}
