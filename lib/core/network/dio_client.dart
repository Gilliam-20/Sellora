import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'api_exception.dart';

/// Thin wrapper around Dio, registered once in InitialBinding and
/// injected wherever a service needs to reach the Cloud Functions
/// backend (CJ Dropshipping proxy, IntaSend proxy).
///
/// Every request automatically attaches the signed-in user's Supabase
/// access token (a JWT), so the backend can verify the caller before
/// touching CJ Dropshipping or IntaSend on their behalf. NOTE: until
/// Phase 2 ports functions/ to Edge Functions, the deployed Cloud
/// Functions still verify *Firebase* ID tokens and will reject these —
/// harmless while AppConstants.useMockData is true, since nothing calls
/// them. See WORKLOG.md, 2026-09-26.
class DioClient extends GetxService {
  late final Dio dio;

  DioClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // supabase_flutter refreshes the session itself, so the current
          // access token is already fresh.
          final token =
              Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? data, Duration? receiveTimeout}) async {
    try {
      final response = await dio.post(
        path,
        data: data,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      );
      return Map<String, dynamic>.from(response.data ?? {});
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message']?.toString() ??
            e.message ??
            'Network error',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final response = await dio.get(path, queryParameters: query);
      return Map<String, dynamic>.from(response.data ?? {});
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message']?.toString() ??
            e.message ??
            'Network error',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
