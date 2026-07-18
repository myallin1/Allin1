// ================================================================
// API Service - Allin1 Super App Backend
// ================================================================
// Production-ready API service with Dio HTTP client, interceptors,
// retry logic, caching, and comprehensive error handling.
//
// Features:
// - Dio HTTP client with custom interceptors
// - Exponential backoff retry logic
// - Request/response caching with Hive
// - Circuit breaker pattern for resilience
// - Rate limiting and request debouncing
// - Failover URL support
// - Performance monitoring
// - Comprehensive logging
//
// Author: NJ TECH Backend Team
// Version: 1.0.0
// ================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '../models/api_models.dart';

// ================================================================
// Type Definitions
// ================================================================

/// Callback for logging API events
typedef ApiLogCallback = void Function(LogLevel level, String message);

/// Callback for tracking request metrics
typedef MetricsCallback = void Function(
  String endpoint,
  RequestMetrics metrics,
);

// ================================================================
// Log Level Enum
// ================================================================

enum LogLevel {
  none,
  error,
  warning,
  info,
  debug,
}

// ================================================================
// Circuit Breaker State
// ================================================================

enum CircuitState {
  /// Circuit is closed, requests flow normally
  closed,

  /// Circuit is open, requests fail immediately
  open,

  /// Circuit is half-open, testing if service recovered
  halfOpen,
}

// ================================================================
// API Service Exception
// ================================================================

/// Custom exception for API-related errors.
class ApiServiceException implements Exception {
  /// Error message
  final String message;

  /// Error code for programmatic handling
  final String code;

  /// Original exception if any
  final Exception? originalException;

  /// HTTP status code if applicable
  final int? statusCode;

  /// Whether the error is retryable
  final bool isRetryable;

  /// Additional error details
  final Map<String, dynamic>? details;

  ApiServiceException({
    required this.message,
    this.code = 'API_ERROR',
    this.originalException,
    this.statusCode,
    this.isRetryable = false,
    this.details,
  });

  @override
  String toString() {
    return 'ApiServiceException($code): $message'
        '${statusCode != null ? ' [HTTP $statusCode]' : ''}'
        '${originalException != null ? ' caused by: $originalException' : ''}';
  }
}

// ================================================================
// API Service Class
// ================================================================

/// Production-ready API service for the Allin1 Super App.
///
/// This service provides:
/// - Thread-safe HTTP client with connection pooling
/// - Automatic retry with exponential backoff
/// - Response caching for improved performance
/// - Circuit breaker for fault tolerance
/// - Request deduplication and debouncing
/// - Comprehensive error handling and logging
/// - Performance metrics tracking
///
/// Usage:
/// ```dart
/// final apiService = ApiService();
/// await apiService.initialize();
///
/// final response = await apiService.sendChat(
///   message: 'Hello',
///   history: [...],
/// );
/// ```
class ApiService {
  // ================================================================
  // Singleton Pattern
  // ================================================================

  static final ApiService _instance = ApiService._internal();

  /// Get the singleton instance of ApiService
  static ApiService get instance => _instance;

  /// Check if the service has been initialized
  static bool get isInitialized => _instance._isInitialized;

  // ================================================================
  // Internal State
  // ================================================================

  bool _isInitialized = false;

  /// Dio HTTP client instance
  late Dio _dio;

  /// Hive box for caching responses
  late Box<String> _cacheBox;

  /// Request debouncer - tracks pending requests
  final Map<String, Completer<ChatResponse>> _pendingRequests = {};

  /// Rate limiter - tracks request timestamps
  final List<DateTime> _requestTimestamps = [];

  /// Circuit breaker state
  CircuitState _circuitState = CircuitState.closed;

  /// Consecutive failure count for circuit breaker
  int _consecutiveFailures = 0;

  /// Whether to use failover URL
  bool _useFailover = false;

  /// Failover cooldown end time
  DateTime? _failoverCooldownEnd;

  // ================================================================
  // Callbacks
  // ================================================================

  /// Callback for logging (set by app)
  ApiLogCallback? onLog;

  /// Callback for metrics (set by app)
  MetricsCallback? onMetrics;

  // ================================================================
  // Constructor
  // ================================================================

  ApiService._internal();

  // ================================================================
  // Initialization
  // ================================================================

  /// Initialize the API service.
  ///
  /// Must be called before using the service.
  /// Typically called during app startup.
  Future<void> initialize({String? qwenToken}) async {
    if (_isInitialized) {
      _log(LogLevel.warning, 'ApiService already initialized');
      return;
    }

    if (qwenToken != null) {
      ApiConfig.qwenAccessToken = qwenToken;
    }

    try {
      // Initialize Hive for caching
      await _initializeCache();

      // Configure Dio HTTP client
      _configureDio();

      _isInitialized = true;
      _log(LogLevel.info, 'ApiService initialized successfully');
    } catch (e, stackTrace) {
      _log(LogLevel.error, 'Failed to initialize ApiService: $e');
      _log(LogLevel.error, 'Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Initialize Hive cache box
  Future<void> _initializeCache() async {
    try {
      _cacheBox = await Hive.openBox<String>('api_cache');
      _log(LogLevel.debug, 'Cache box initialized');
    } catch (e) {
      _log(LogLevel.error, 'Failed to initialize cache: $e');
      rethrow;
    }
  }

  /// Configure Dio HTTP client with interceptors and settings
  void _configureDio() {
    final baseOptions = BaseOptions(
      baseUrl: ApiConfig.primaryBaseUrl,
      connectTimeout: ApiConfig.connectionTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      contentType: ApiConfig.contentTypeJson,
      headers: {
        'Accept': ApiConfig.acceptHeader,
        'Content-Type': ApiConfig.contentTypeJson,
      },
    );

    _dio = Dio(baseOptions)
      ..interceptors.addAll([
        _RequestInterceptor(),
        _ResponseInterceptor(onLog: _log, onMetrics: onMetrics),
        _ErrorInterceptor(),
      ]);

    // Configure HTTP client with connection pooling (Not supported on Web)
    if (!kIsWeb) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        // Connection pooling settings
        final client = HttpClient()
          ..maxConnectionsPerHost = 10
          ..idleTimeout = const Duration(seconds: 30);
        return client;
      };
    }

    _log(LogLevel.debug, 'Dio client configured');
  }

  // ================================================================
  // Public API Methods
  // ================================================================

  /// Send a chat message to the backend.
  ///
  /// This is the primary method for voice chat interactions.
  ///
  /// Parameters:
  /// - [message]: The user's message text
  /// - [history]: Conversation history for context
  /// - [systemPrompt]: Optional system prompt to guide AI behavior
  /// - [userId]: Optional user identifier
  /// - [sessionId]: Optional session identifier
  /// - [language]: Optional language preference ('ta' or 'en')
  /// - [useCache]: Whether to use cached responses (default: false for chat)
  /// - [enableRetry]: Whether to retry on failure (default: true)
  ///
  /// Returns:
  /// - [ChatResponse]: The AI's response
  ///
  /// Throws:
  /// - [ApiServiceException]: If the request fails
  Future<ChatResponse> sendChat({
    required String message,
    List<MessageHistory> history = const [],
    String? systemPrompt,
    String? userId,
    String? sessionId,
    String? language,
    bool useCache = false,
    bool enableRetry = true,
  }) async {
    _checkInitialization();

    // Check circuit breaker
    _checkCircuitBreaker();

    // Check rate limiting
    _checkRateLimit();

    // Generate cache key
    final cacheKey = ApiConfig.generateCacheKey(
      endpoint: ApiConfig.chatEndpoint,
      params: {'message': message, 'sessionId': sessionId ?? 'default'},
    );

    // Check cache if enabled
    if (useCache) {
      final cachedResponse = await _getCachedResponse(cacheKey);
      if (cachedResponse != null) {
        _log(LogLevel.debug, 'Cache hit for request');
        return cachedResponse;
      }
    }

    // Check for pending identical request (deduplication)
    final dedupKey = '$cacheKey:$message';
    if (_pendingRequests.containsKey(dedupKey)) {
      _log(LogLevel.debug, 'Deduplicating identical request');
      return _pendingRequests[dedupKey]!.future;
    }

    // Create request
    final request = ChatRequest(
      message: message,
      history: history,
      systemPrompt: systemPrompt,
      userId: userId,
      sessionId: sessionId,
      language: language,
    );

    // Create completer for deduplication
    final completer = Completer<ChatResponse>();
    _pendingRequests[dedupKey] = completer;

    try {
      // Send request with retry logic
      final response = await _sendWithRetry(
        request: request,
        endpoint: ApiConfig.chatEndpoint,
        enableRetry: enableRetry,
        cacheKey: useCache ? cacheKey : null,
      );

      completer.complete(response);
      return response;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingRequests.remove(dedupKey);
    }
  }

  /// Send a generic POST request to any endpoint.
  ///
  /// For advanced use cases when you need more control.
  Future<Map<String, dynamic>> post({
    required String endpoint,
    required Map<String, dynamic> data,
    Duration? timeout,
    bool useCache = false,
    int cacheTtlSeconds = 0,
  }) async {
    _checkInitialization();

    final cacheKey = ApiConfig.generateCacheKey(
      endpoint: endpoint,
      params: data,
    );

    // Check cache
    if (useCache && cacheTtlSeconds > 0) {
      final cached = await _getCachedResponse(cacheKey);
      if (cached != null) {
        return cached.toJson()['data'] as Map<String, dynamic>;
      }
    }

    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: data,
      options: Options(
        sendTimeout: timeout ?? ApiConfig.sendTimeout,
        receiveTimeout: timeout ?? ApiConfig.receiveTimeout,
      ),
    );

    final responseData = response.data!;

    // Cache if enabled
    if (useCache && cacheTtlSeconds > 0) {
      await _cacheResponse(cacheKey, responseData, cacheTtlSeconds);
    }

    return responseData;
  }

  /// Send a generic GET request.
  Future<Map<String, dynamic>> get({
    required String endpoint,
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
    bool useCache = false,
    int cacheTtlSeconds = 300, // Default 5 minutes for GET
  }) async {
    _checkInitialization();

    final cacheKey = ApiConfig.generateCacheKey(
      endpoint: endpoint,
      params: queryParameters ?? {},
    );

    // Check cache
    if (useCache && cacheTtlSeconds > 0) {
      final cached = await _getCachedResponse(cacheKey);
      if (cached != null) {
        return cached.toJson()['data'] as Map<String, dynamic>;
      }
    }

    final response = await _dio.get<Map<String, dynamic>>(
      endpoint,
      queryParameters: queryParameters,
      options: Options(
        sendTimeout: timeout ?? ApiConfig.sendTimeout,
        receiveTimeout: timeout ?? ApiConfig.receiveTimeout,
      ),
    );

    final responseData = response.data!;

    // Cache if enabled
    if (useCache && cacheTtlSeconds > 0) {
      await _cacheResponse(cacheKey, responseData, cacheTtlSeconds);
    }

    return responseData;
  }

  /// Clear all cached responses.
  Future<void> clearCache() async {
    try {
      await _cacheBox.clear();
      _log(LogLevel.info, 'Cache cleared');
    } catch (e) {
      _log(LogLevel.error, 'Failed to clear cache: $e');
      rethrow;
    }
  }

  /// Clear cache for a specific endpoint.
  Future<void> clearCacheForEndpoint(String endpoint) async {
    try {
      final keysToDelete = <String>[];
      for (final key in _cacheBox.keys) {
        if (key.toString().contains(endpoint)) {
          keysToDelete.add(key.toString());
        }
      }
      for (final key in keysToDelete) {
        await _cacheBox.delete(key);
      }
      _log(
        LogLevel.debug,
        'Cleared ${keysToDelete.length} cache entries for $endpoint',
      );
    } catch (e) {
      _log(LogLevel.error, 'Failed to clear cache for endpoint: $e');
    }
  }

  /// Invalidate specific cache key.
  Future<void> invalidateCache(String cacheKey) async {
    try {
      await _cacheBox.delete(cacheKey);
      _log(LogLevel.debug, 'Invalidated cache key: $cacheKey');
    } catch (e) {
      _log(LogLevel.error, 'Failed to invalidate cache: $e');
    }
  }

  /// Get cache statistics.
  Map<String, dynamic> getCacheStats() {
    int validCount = 0;
    int expiredCount = 0;
    int totalSize = 0;

    for (final key in _cacheBox.keys) {
      final value = _cacheBox.get(key);
      if (value != null) {
        totalSize += value.toString().length;
        try {
          final cached = CachedResponse.fromJson(value as Map<String, dynamic>);
          if (cached.isValid) {
            validCount++;
          } else {
            expiredCount++;
          }
        } catch (_) {
          expiredCount++;
        }
      }
    }

    return {
      'validEntries': validCount,
      'expiredEntries': expiredCount,
      'totalEntries': validCount + expiredCount,
      'estimatedSizeBytes': totalSize,
      'estimatedSizeKB': totalSize / 1024,
    };
  }

  /// Reset circuit breaker state.
  void resetCircuitBreaker() {
    _circuitState = CircuitState.closed;
    _consecutiveFailures = 0;
    _useFailover = false;
    _log(LogLevel.info, 'Circuit breaker reset');
  }

  /// Dispose resources.
  void dispose() {
    _pendingRequests.clear();
    _requestTimestamps.clear();
    _dio.close();
    _log(LogLevel.info, 'ApiService disposed');
  }

  // ================================================================
  // Internal Methods
  // ================================================================

  /// Check if service is initialized
  void _checkInitialization() {
    if (!_isInitialized) {
      throw ApiServiceException(
        message: 'ApiService not initialized. Call initialize() first.',
        code: 'NOT_INITIALIZED',
      );
    }
  }

  /// Check circuit breaker state
  void _checkCircuitBreaker() {
    final now = DateTime.now();

    if (_circuitState == CircuitState.open) {
      // Check if cooldown period has passed
      if (_failoverCooldownEnd != null && now.isAfter(_failoverCooldownEnd!)) {
        _circuitState = CircuitState.halfOpen;
        _log(LogLevel.warning, 'Circuit breaker half-open, testing primary');
      } else {
        throw ApiServiceException(
          message: 'Service temporarily unavailable (circuit open)',
          code: 'CIRCUIT_OPEN',
          isRetryable: true,
        );
      }
    }
  }

  /// Check rate limiting
  void _checkRateLimit() {
    final now = DateTime.now();

    // Remove timestamps older than 1 minute
    _requestTimestamps.removeWhere(
      (ts) => now.difference(ts) > const Duration(minutes: 1),
    );

    // Check per-minute limit
    if (_requestTimestamps.length >= ApiConfig.maxRequestsPerMinute) {
      throw ApiServiceException(
        message: 'Rate limit exceeded. Please try again later.',
        code: 'RATE_LIMIT_EXCEEDED',
        isRetryable: true,
      );
    }

    _requestTimestamps.add(now);
  }

  Future<ChatResponse> _sendWithRetry({
    required ChatRequest request,
    required String endpoint,
    required bool enableRetry,
    String? cacheKey,
    int cacheTtl = 0,
  }) async {
    int attempt = 0;
    Exception? lastException;

    while (attempt <= (enableRetry ? ApiConfig.maxRetries : 0)) {
      try {
        if (attempt > 0) {
          // Wait with exponential backoff
          final delay = ApiConfig.calculateRetryDelay(attempt);
          _log(
            LogLevel.debug,
            'Retry attempt $attempt, waiting ${delay.inMilliseconds}ms',
          );
          await Future<void>.delayed(delay);
        }

        final response = await _sendRequest(
          request: request,
          endpoint: endpoint,
          cacheKey: cacheKey,
          cacheTtl: cacheTtl,
        );

        // Success - reset circuit breaker
        _onSuccess();

        return response;
      } on DioException catch (e) {
        lastException = e;
        _onFailure(e);

        if (!enableRetry ||
            !ApiConfig.isRetryableStatusCode(e.response?.statusCode ?? 0)) {
          break;
        }
      } catch (e) {
        lastException = e as Exception;
        _onFailure(e);

        if (!enableRetry) {
          break;
        }
      }

      attempt++;
    }

    // All retries exhausted
    throw ApiServiceException(
      message: 'Request failed after $attempt attempts: $lastException',
      code: 'MAX_RETRIES_EXCEEDED',
      originalException: lastException,
    );
  }

  Future<ChatResponse> _sendRequest({
    required ChatRequest request,
    required String endpoint,
    String? cacheKey,
    int cacheTtl = 0,
  }) async {
    final startTime = DateTime.now();
    final baseUrl =
        _useFailover ? ApiConfig.failoverBaseUrl : ApiConfig.primaryBaseUrl;
    final url = '$baseUrl$endpoint';

    _log(LogLevel.debug, 'Sending request to: $url');
    _log(LogLevel.debug, 'Request ID: ${request.requestId}');

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: request.toJson(),
        options: Options(
          headers: {
            ApiConfig.requestIdHeader: request.requestId,
            ApiConfig.clientVersionHeader: '1.0.0',
            ApiConfig.platformHeader: kIsWeb
                ? 'web'
                : (Platform.isAndroid
                    ? 'android'
                    : (Platform.isIOS ? 'ios' : 'unknown')),
            if (ApiConfig.qwenAccessToken != null)
              'Authorization': 'Bearer ${ApiConfig.qwenAccessToken}',
          },
        ),
      );

      final duration = DateTime.now().difference(startTime);

      // Parse response
      final chatResponse = ChatResponse.fromJson(
        response.data!,
        statusCode: response.statusCode ?? 200,
      );

      // Cache if enabled
      if (cacheKey != null && cacheTtl > 0) {
        await _cacheResponse(
          cacheKey,
          response.data!,
          cacheTtl,
        );
      }

      // Log performance
      _logPerformance(endpoint, duration, chatResponse.success);

      return chatResponse;
    } on DioException {
      final duration = DateTime.now().difference(startTime);
      _logPerformance(endpoint, duration, false);
      rethrow;
    }
  }

  /// Handle successful request
  void _onSuccess() {
    _consecutiveFailures = 0;

    if (_circuitState == CircuitState.halfOpen) {
      _circuitState = CircuitState.closed;
      _useFailover = false;
      _log(LogLevel.info, 'Circuit breaker closed, back to primary');
    }
  }

  /// Handle failed request
  void _onFailure(Object error) {
    _consecutiveFailures++;

    _log(
      LogLevel.error,
      'Request failed: $error (consecutive failures: $_consecutiveFailures)',
    );

    // Check if circuit breaker should trip
    if (_consecutiveFailures >= ApiConfig.circuitBreakerFailureThreshold) {
      _circuitState = CircuitState.open;
      _failoverCooldownEnd = DateTime.now().add(
        const Duration(seconds: ApiConfig.circuitBreakerOpenDurationSeconds),
      );
      _useFailover = true;
      _log(LogLevel.error, 'Circuit breaker opened, switching to failover');
    }
  }

  /// Log performance metrics
  void _logPerformance(String endpoint, Duration duration, bool success) {
    final metrics = RequestMetrics(
      durationMs: duration.inMilliseconds,
    );

    if (onMetrics != null) {
      onMetrics?.call(endpoint, metrics);
    }

    if (duration.inMilliseconds > ApiConfig.verySlowRequestThresholdMs) {
      _log(
        LogLevel.error,
        'Very slow request: ${duration.inMilliseconds}ms for $endpoint',
      );
    } else if (duration.inMilliseconds > ApiConfig.slowRequestThresholdMs) {
      _log(
        LogLevel.warning,
        'Slow request: ${duration.inMilliseconds}ms for $endpoint',
      );
    }
  }

  /// Get cached response
  Future<ChatResponse?> _getCachedResponse(String cacheKey) async {
    try {
      final cachedData = _cacheBox.get(cacheKey);
      if (cachedData != null) {
        final decoded = jsonDecode(cachedData) as Map<String, dynamic>;
        final cached = CachedResponse.fromJson(decoded);
        if (cached.isValid) {
          return ChatResponse(
            response: cached.data['response'] as String? ?? '',
            statusCode: 200,
            success: true,
          );
        } else {
          // Cache expired, remove it
          await _cacheBox.delete(cacheKey);
        }
      }
    } catch (e) {
      _log(LogLevel.error, 'Error reading cache: $e');
    }
    return null;
  }

  /// Cache a response
  Future<void> _cacheResponse(
    String cacheKey,
    Map<String, dynamic> data,
    int ttlSeconds,
  ) async {
    try {
      final cached = CachedResponse.fromApiResponse(data, cacheKey, ttlSeconds);
      await _cacheBox.put(cacheKey, jsonEncode(cached.toJson()));
      _log(LogLevel.debug, 'Cached response for key: $cacheKey');
    } catch (e) {
      _log(LogLevel.error, 'Error caching response: $e');
    }
  }

  /// Log a message
  void _log(LogLevel level, String message) {
    if (level.index > ApiConfig.logLevel) {
      return;
    }

    onLog?.call(level, message);
    if (onLog == null && kDebugMode && ApiConfig.enableDebugLogging) {
      debugPrint('[ApiService/${level.name}] $message');
    }
  }
}

// ================================================================
// Dio Interceptors
// ================================================================

/// Interceptor for adding request metadata
class _RequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Add request ID if not present
    if (options.headers[ApiConfig.requestIdHeader] == null) {
      options.headers[ApiConfig.requestIdHeader] = const Uuid().v4();
    }

    // Add timestamp
    options.headers['X-Request-Timestamp'] = DateTime.now().toIso8601String();

    handler.next(options);
  }
}

/// Interceptor for logging responses
class _ResponseInterceptor extends Interceptor {
  final ApiLogCallback? onLog;
  final MetricsCallback? onMetrics;

  _ResponseInterceptor({
    required this.onLog,
    required this.onMetrics,
  });

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log(
      LogLevel.debug,
      'Response: ${response.statusCode} for ${response.requestOptions.uri}',
    );

    // Track metrics
    if (onMetrics != null) {
      // Metrics would be tracked with timing from request interceptor
    }

    handler.next(response);
  }

  void _log(LogLevel level, String message) {
    onLog?.call(level, message);
  }
}

/// Interceptor for handling errors
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Log error
    debugPrint('[ApiService/Error] ${err.type}: ${err.message}');

    // Transform DioException to ApiServiceException
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          type: err.type,
          message: 'Request timeout: ${err.type.name}',
          error: err.error,
          response: err.response,
        ),
      );
    } else {
      handler.next(err);
    }
  }
}
