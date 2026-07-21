// ================================================================
// API Configuration - Allin1 Super App Backend
// ================================================================
// Centralized configuration for API endpoints, timeouts, retries,
// and resilience patterns.
//
// Author: NJ TECH Backend Team
// Version: 1.0.0
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Primary API configuration for the Allin1 Super App commerce backend.
///
/// This class provides:
/// - Multiple endpoint URLs with automatic failover
/// - Configurable timeouts for different operation types
/// - Retry policies with exponential backoff
/// - Rate limiting thresholds
/// - Cache TTL settings
abstract final class ApiConfig {
  // ================================================================
  // API Endpoints
  // ================================================================

  /// Primary backend URL - Qwen AI API
  static const String primaryBaseUrl = 'https://chat.qwen.ai/api/v1';

  /// Failover backup URL
  static const String failoverBaseUrl = 'https://chat.qwen.ai/api/v1';

  /// Chat endpoint path
  static const String chatEndpoint = '/chat/completions';

  /// Full primary chat URL
  static String get chatUrl => '$primaryBaseUrl$chatEndpoint';

  /// Full failover chat URL
  static String get failoverChatUrl => '$failoverBaseUrl$chatEndpoint';

  // ================================================================
  // Access Tokens
  // ================================================================

  /// Qwen Access Token (to be injected from local storage session)
  static String? qwenAccessToken;

  /// Ola Maps API Key (Krutrim)
  /// Loaded from the local `.env` file via flutter_dotenv.
  ///
  /// Callers MUST `await ApiConfig.ensureEnvLoaded()` before reading this,
  /// otherwise it silently returns '' — see ensureEnvLoaded() docs.
  static String get olaMapsApiKey =>
      (dotenv.env['OLA_MAPS_API_KEY'] ?? '').trim();

  // ================================================================
  // Environment loading
  // ================================================================

  /// Memoised in-flight/completed `.env` load.
  static Future<void>? _envLoadFuture;

  /// Loads `.env` exactly once, no matter how many callers race for it.
  ///
  /// Why this exists: `.env` is an asset, so on web it is fetched over
  /// HTTP rather than read from a local file. The app previously called
  /// `dotenv.load()` in exactly one place (SplashSetupScreen.initState),
  /// while `main_hero.dart` / `main_customer.dart` kicked off
  /// `MapService().initialize()` concurrently via `unawaited(...)`. On web
  /// the warm-up reliably won that race, read an empty `dotenv.env`,
  /// logged `Ola API key present=false length=0`, and set
  /// `_isInitialized = true` — so the later, correctly-ordered call from
  /// the splash screen hit the early-return guard and the empty-key state
  /// was cached for the entire session.
  ///
  /// Awaiting this before any dotenv read makes the ordering explicit and
  /// removes the race on every platform. Safe to call repeatedly and from
  /// multiple entrypoints concurrently: subsequent callers await the same
  /// future rather than triggering a second load.
  static Future<void> ensureEnvLoaded() => _envLoadFuture ??= _loadEnv();

  static Future<void> _loadEnv() async {
    if (dotenv.isInitialized) {
      return;
    }
    try {
      await dotenv.load();
      debugPrint('[ApiConfig] .env loaded (${dotenv.env.length} keys)');
    } catch (e) {
      // Non-fatal: callers degrade to empty-string config and their own
      // fallbacks (MapService falls back to OSM/Haversine). Do not
      // rethrow — a missing .env must not block app startup.
      debugPrint('[ApiConfig] .env load failed: $e');
    }
  }

  // ================================================================
  // Timeout Configuration (milliseconds)
  // ================================================================

  /// Connection timeout - time to establish TCP connection
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Send timeout - time to send request body
  static const Duration sendTimeout = Duration(seconds: 15);

  /// Receive timeout - time to wait for response
  /// Longer for chat operations which may involve LLM processing
  static const Duration receiveTimeout = Duration(seconds: 45);

  /// Quick operations timeout (health checks, etc.)
  static const Duration quickTimeout = Duration(seconds: 5);

  // ================================================================
  // Retry Configuration
  // ================================================================

  /// Maximum number of retry attempts before failing
  static const int maxRetries = 3;

  /// Initial delay before first retry (milliseconds)
  static const int initialRetryDelayMs = 1000;

  /// Maximum delay between retries (milliseconds)
  static const int maxRetryDelayMs = 10000;

  /// Exponential backoff multiplier
  static const double retryMultiplier = 2;

  /// HTTP status codes that should trigger a retry
  static const List<int> retryableStatusCodes = [
    408, // Request Timeout
    429, // Too Many Requests
    500, // Internal Server Error
    502, // Bad Gateway
    503, // Service Unavailable
    504, // Gateway Timeout
  ];

  // ================================================================
  // Rate Limiting Configuration
  // ================================================================

  /// Minimum time between identical requests (debouncing)
  static const Duration requestDebounceDuration = Duration(milliseconds: 500);

  /// Maximum requests per minute per user (client-side enforcement)
  static const int maxRequestsPerMinute = 30;

  /// Maximum requests per hour per user (client-side enforcement)
  static const int maxRequestsPerHour = 500;

  // ================================================================
  // Cache Configuration
  // ================================================================

  /// Default cache TTL for successful responses (minutes)
  static const int defaultCacheTtlMinutes = 5;

  /// Cache TTL for chat responses (usually should not cache)
  static const int chatCacheTtlMinutes = 0; // No caching for chat

  /// Cache TTL for static/reference data (minutes)
  static const int staticDataCacheTtlMinutes = 60;

  /// Maximum cache size in MB
  static const int maxCacheSizeMb = 50;

  /// Cache key prefix for namespacing
  static const String cacheKeyPrefix = 'erode_superapp_cache_';

  // ================================================================
  // Request Deduplication
  // ================================================================

  /// Time window for request deduplication (milliseconds)
  /// Identical requests within this window will be deduplicated
  static const Duration deduplicationWindow = Duration(milliseconds: 300);

  // ================================================================
  // Failover Configuration
  // ================================================================

  /// Number of consecutive failures before switching to failover
  static const int failoverThreshold = 3;

  /// Time to wait before attempting to switch back to primary (minutes)
  static const int failoverCooldownMinutes = 5;

  // ================================================================
  // Headers & Authentication
  // ================================================================

  /// Default content type for API requests
  static const String contentTypeJson = 'application/json';

  /// Accept header
  static const String acceptHeader = 'application/json';

  /// Client identifier header
  static const String clientVersionHeader = 'X-Client-Version';

  /// Platform identifier header
  static const String platformHeader = 'X-Platform';

  /// Request ID header for tracing
  static const String requestIdHeader = 'X-Request-ID';

  // ================================================================
  // Logging Configuration
  // ================================================================

  /// Enable detailed request/response logging in debug mode
  static const bool enableDebugLogging = true;

  /// Enable request/response body logging (disable in production for sensitive data)
  static const bool enableBodyLogging = false;

  /// Log level: 0=none, 1=errors, 2=warnings, 3=info, 4=debug
  static const int logLevel = 3;

  // ================================================================
  // Performance Monitoring
  // ================================================================

  /// Enable performance tracking for slow requests
  static const bool enablePerformanceTracking = true;

  /// Threshold for slow request logging (milliseconds)
  static const int slowRequestThresholdMs = 3000;

  /// Threshold for very slow request (considered as potential issue)
  static const int verySlowRequestThresholdMs = 10000;

  // ================================================================
  // Circuit Breaker Configuration
  // ================================================================

  /// Circuit breaker open state duration (seconds)
  static const int circuitBreakerOpenDurationSeconds = 30;

  /// Number of failures to trip the circuit breaker
  static const int circuitBreakerFailureThreshold = 5;

  /// Minimum calls before circuit breaker can trip
  static const int circuitBreakerMinimumCalls = 10;

  // ================================================================
  // Helper Methods
  // ================================================================

  /// Get the current base URL (primary or failover based on status)
  static String getBaseUrl({bool forceFailover = false}) {
    if (forceFailover) {
      return failoverBaseUrl;
    }
    return primaryBaseUrl;
  }

  /// Build full URL from endpoint path
  static String buildUrl(String endpoint, {bool useFailover = false}) {
    final base = useFailover ? failoverBaseUrl : primaryBaseUrl;
    return '$base$endpoint';
  }

  /// Check if a status code is retryable
  static bool isRetryableStatusCode(int statusCode) {
    return retryableStatusCodes.contains(statusCode);
  }

  /// Calculate retry delay with exponential backoff
  ///
  /// [attempt] is the current retry attempt number (1-based)
  static Duration calculateRetryDelay(int attempt) {
    final delayMs =
        initialRetryDelayMs * retryMultiplier.pow(attempt - 1).toInt();
    return Duration(
      milliseconds: delayMs.clamp(0, maxRetryDelayMs),
    );
  }

  /// Generate a cache key for a request
  static String generateCacheKey({
    required String endpoint,
    required Map<String, dynamic> params,
  }) {
    final sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return '$cacheKeyPrefix$endpoint:${sortedParams.toString()}';
  }
}

/// Extension to add pow method to double
extension MathExtension on double {
  double pow(int exponent) {
    double result = 1;
    for (int i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
