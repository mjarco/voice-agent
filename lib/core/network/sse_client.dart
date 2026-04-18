import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:voice_agent/core/network/api_client.dart';

class SseEvent {
  const SseEvent({this.event, required this.data, this.id});
  final String? event;
  final String data;
  final String? id;
}

class SseClient {
  SseClient({required this.apiClient, Dio? dio})
      : _dio = dio ?? _createSseDio();

  final ApiClient apiClient;
  final Dio _dio;

  static Dio _createSseDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: false,
      maxRedirects: 0,
      responseType: ResponseType.stream,
    ));
  }

  Stream<SseEvent> post(
    String path, {
    required Map<String, dynamic> data,
  }) {
    final controller = StreamController<SseEvent>();

    if (apiClient.baseUrl == null) {
      controller.addError(const ApiNotConfigured());
      controller.close();
      return controller.stream;
    }

    final url = '${apiClient.baseUrl}$path';
    _startStream(controller, url, data);

    return controller.stream;
  }

  Future<void> _startStream(
    StreamController<SseEvent> controller,
    String url,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post<ResponseBody>(
        url,
        data: data,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            if (apiClient.token != null && apiClient.token!.isNotEmpty)
              'Authorization': 'Bearer ${apiClient.token}',
          },
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data!.stream;
      String buffer = '';
      String? currentEvent;
      String? currentId;
      final dataLines = <String>[];

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          var line = buffer.substring(0, newlineIndex);
          buffer = buffer.substring(newlineIndex + 1);

          if (line.endsWith('\r')) {
            line = line.substring(0, line.length - 1);
          }

          if (line.isEmpty) {
            if (dataLines.isNotEmpty) {
              controller.add(SseEvent(
                event: currentEvent,
                data: dataLines.join('\n'),
                id: currentId,
              ));
            }
            currentEvent = null;
            currentId = null;
            dataLines.clear();
          } else if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
          } else if (line.startsWith('event:')) {
            currentEvent = line.substring(6).trimLeft();
          } else if (line.startsWith('id:')) {
            currentId = line.substring(3).trimLeft();
          }
          // Lines starting with ':' are comments — ignored
        }
      }

      if (dataLines.isNotEmpty) {
        controller.add(SseEvent(
          event: currentEvent,
          data: dataLines.join('\n'),
          id: currentId,
        ));
      }

      await controller.close();
    } on DioException catch (e) {
      controller.addError(apiClient.classifyDioException(e));
      await controller.close();
    }
  }
}
