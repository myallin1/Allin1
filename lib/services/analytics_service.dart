// ================================================================
// Analytics Service - Allin1 Super App
// ================================================================
// Comprehensive analytics and monitoring service using Firebase.
//
// Features:
// - Event tracking with Firebase Analytics
// - Crash reporting with Crashlytics
// - Performance monitoring
// - User property tracking
// - Screen view tracking
// - E-commerce event tracking
//
// Author: NJ TECH Backend Team
// Version: 1.0.0
// ================================================================

import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

// ================================================================
// Analytics Event Types
// ================================================================

/// Standard analytics events for the Allin1 Super App.
class AnalyticsEvents {
  // ================================================================
  // User Engagement Events
  // ================================================================

  /// User sent a message in chat
  static const String messageSent = 'message_sent';

  /// User started a voice input session
  static const String voiceInputStarted = 'voice_input_started';

  /// User completed a voice input session
  static const String voiceInputCompleted = 'voice_input_completed';

  /// User cancelled voice input
  static const String voiceInputCancelled = 'voice_input_cancelled';

  /// User tapped a quick suggestion chip
  static const String quickChipTapped = 'quick_chip_tapped';

  /// User cleared chat history
  static const String chatCleared = 'chat_cleared';

  /// User copied a message
  static const String messageCopied = 'message_copied';

  /// User shared a message (WhatsApp, etc.)
  static const String messageShared = 'message_shared';

  // ================================================================
  // Commerce Events
  // ================================================================

  /// User viewed a commerce card
  static const String commerceCardViewed = 'commerce_card_viewed';

  /// User tapped a commerce card
  static const String commerceCardTapped = 'commerce_card_tapped';

  /// User initiated an order
  static const String orderInitiated = 'order_initiated';

  /// User placed an order
  static const String orderPlaced = 'order_placed';

  /// User viewed products
  static const String viewItemList = 'view_item_list';

  /// User selected a product
  static const String selectItem = 'select_item';

  /// User viewed product details
  static const String viewItem = 'view_item';

  /// User added item to cart
  static const String addToCart = 'add_to_cart';

  /// User removed item from cart
  static const String removeFromCart = 'remove_from_cart';

  /// User began checkout
  static const String beginCheckout = 'begin_checkout';

  /// User added payment info
  static const String addPaymentInfo = 'add_payment_info';

  /// User completed purchase
  static const String purchase = 'purchase';

  /// User requested a refund
  static const String refund = 'refund';

  // ================================================================
  // Category-Specific Events
  // ================================================================

  /// User browsed food delivery options
  static const String browseFood = 'browse_food';

  /// User browsed grocery items
  static const String browseGrocery = 'browse_grocery';

  /// User browsed tech accessories
  static const String browseTech = 'browse_tech';

  /// User requested bike taxi
  static const String requestBikeTaxi = 'request_bike_taxi';

  /// User viewed market rates
  static const String viewMarketRates = 'view_market_rates';

  // ================================================================
  // App Lifecycle Events
  // ================================================================

  /// User completed onboarding
  static const String onboardingCompleted = 'onboarding_completed';

  /// User logged in
  static const String login = 'login';

  /// User logged out
  static const String logout = 'logout';

  /// User registered
  static const String signUp = 'sign_up';

  /// App updated
  static const String appUpdated = 'app_updated';

  // ================================================================
  // Error & Issue Events
  // ================================================================

  /// API error occurred
  static const String apiError = 'api_error';

  /// Payment failed
  static const String paymentFailed = 'payment_failed';

  /// Order failed
  static const String orderFailed = 'order_failed';

  /// Network error
  static const String networkError = 'network_error';
}

// ================================================================
// Analytics Service Class
// ================================================================

/// Centralized analytics and monitoring service.
///
/// This service provides:
/// - Event tracking with Firebase Analytics
/// - Crash reporting with Crashlytics
/// - Performance monitoring with Firebase Performance
/// - User property management
/// - Screen view tracking
///
/// Usage:
/// ```dart
/// final analytics = AnalyticsService();
/// await analytics.initialize();
///
/// // Track an event
/// await analytics.trackEvent(
///   AnalyticsEvents.messageSent,
///   parameters: {'message_length': 50},
/// );
///
/// // Track a screen view
/// await analytics.trackScreen('ChatScreen');
/// ```
class AnalyticsService {
  // ================================================================
  // Singleton Pattern
  // ================================================================

  static AnalyticsService? _instance;

  /// Get the singleton instance
  static AnalyticsService get instance {
    _instance ??= AnalyticsService._internal();
    return _instance!;
  }

  /// Check if initialized
  static bool get isInitialized => _instance?._isInitialized ?? false;

  // ================================================================
  // Internal State
  // ================================================================

  bool _isInitialized = false;

  /// Firebase Analytics instance
  FirebaseAnalytics? _analytics;

  /// Firebase Analytics observer for screen tracking
  FirebaseAnalyticsObserver? _observer;

  /// Get the analytics observer
  FirebaseAnalyticsObserver getObserver() {
    if (_observer == null) {
      // Return a basic observer if not initialized to avoid crashes
      // though typically initialize() should be called first.
      return FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
    }
    return _observer!;
  }

  /// Firebase Crashlytics instance
  FirebaseCrashlytics? _crashlytics;

  /// Firebase Performance instance
  FirebasePerformance? _performance;

  /// Current user ID (set after login)
  String? _userId;

  /// Whether analytics is enabled (can be disabled for privacy)
  bool _isEnabled = true;

  /// Event queue for offline tracking
  final List<_QueuedEvent> _eventQueue = [];

  /// Maximum queue size
  static const int _maxQueueSize = 100;

  // ================================================================
  // Constructor
  // ================================================================

  AnalyticsService._internal();

  // ================================================================
  // Initialization
  // ================================================================

  /// Initialize the analytics service.
  ///
  /// Should be called during app startup, after Firebase initialization.
  Future<void> initialize({
    bool enableAnalytics = true,
    bool enableCrashlytics = true,
    bool enablePerformance = true,
  }) async {
    if (_isInitialized) {
      debugPrint('[AnalyticsService] Already initialized');
      return;
    }

    try {
      _isEnabled = enableAnalytics;

      // Initialize Analytics
      if (enableAnalytics) {
        _analytics = FirebaseAnalytics.instance;
        _observer = FirebaseAnalyticsObserver(
          analytics: _analytics!,
        );
        await _analytics!.logAppOpen();
        debugPrint('[AnalyticsService] Analytics initialized');
      }

      // Initialize Crashlytics
      if (enableCrashlytics) {
        if (!kIsWeb) {
          _crashlytics = FirebaseCrashlytics.instance;

          // Set crashlytics to collect crashes in production
          await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);

          // Set custom keys for better crash context
          await _crashlytics!.setCustomKey('app_version', '1.0.0');

          // Enable uncaught error handling
          if (!kDebugMode) {
            FlutterError.onError = _crashlytics!.recordFlutterError;
          }
        }

        debugPrint('[AnalyticsService] Crashlytics initialized');
      }

      // Initialize Performance Monitoring
      _isInitialized = true;

      // Finalize user ID if it was set before initialization
      if (_userId != null) {
        await _analytics!.setUserId(id: _userId);
      }

      // Flush any events queued during app startup
      await _flushQueuedEvents();

      debugPrint('[AnalyticsService] Fully initialized');
    } catch (e, stackTrace) {
      debugPrint('[AnalyticsService] Initialization failed: $e');
      debugPrint('[AnalyticsService] Stack trace: $stackTrace');
      // Don't rethrow - analytics failure shouldn't crash the app
    }
  }

  // ================================================================
  // Event Tracking
  // ================================================================

  /// Track a custom event.
  ///
  /// Parameters:
  /// - [eventName]: Name of the event (use AnalyticsEvents constants)
  /// - [parameters]: Optional event parameters
  /// - [value]: Optional numeric value associated with the event
  Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? parameters,
    double? value,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      _queueEvent(eventName, parameters, value);
      return;
    }

    try {
      // Convert parameters to Map<String, Object>
      final sanitizedParams = _sanitizeParameters(parameters);

      await _analytics!.logEvent(
        name: eventName,
        parameters: sanitizedParams,
      );

      debugPrint('[AnalyticsService] Tracked: $eventName');
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to track event $eventName: $e');
      _queueEvent(eventName, parameters, value);
    }
  }

  /// Track a screen view.
  ///
  /// Should be called when a new screen is displayed.
  Future<void> trackScreen(
    String screenName, {
    String? screenClass,
    Map<String, dynamic>? parameters,
  }) async {
    if (!_isEnabled || !_isInitialized) {
      return;
    }

    try {
      await _analytics!.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
        parameters: _sanitizeParameters(parameters),
      );

      debugPrint('[AnalyticsService] Screen view: $screenName');
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to track screen: $e');
    }
  }

  // ================================================================
  // E-commerce Tracking
  // ================================================================

  /// Track viewing an item list.
  Future<void> trackViewItemList({
    required String itemListId,
    required String itemListName,
    List<Map<String, dynamic>>? items,
  }) async {
    await trackEvent(
      AnalyticsEvents.viewItemList,
      parameters: {
        'item_list_id': itemListId,
        'item_list_name': itemListName,
        if (items != null) 'items': items,
      },
    );
  }

  /// Track selecting an item.
  Future<void> trackSelectItem({
    required String itemId,
    required String itemName,
    String? itemListId,
    String? itemListName,
  }) async {
    await trackEvent(
      AnalyticsEvents.selectItem,
      parameters: {
        'item_id': itemId,
        'item_name': itemName,
        if (itemListId != null) 'item_list_id': itemListId,
        if (itemListName != null) 'item_list_name': itemListName,
      },
    );
  }

  /// Track viewing an item detail.
  Future<void> trackViewItem({
    required String itemId,
    required String itemName,
    double? price,
    String? currency,
    String? category,
  }) async {
    await trackEvent(
      AnalyticsEvents.viewItem,
      parameters: {
        'item_id': itemId,
        'item_name': itemName,
        if (price != null) 'price': price,
        if (currency != null) 'currency': currency,
        if (category != null) 'item_category': category,
      },
    );
  }

  /// Track adding an item to cart.
  Future<void> trackAddToCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
    String? currency,
    String? category,
  }) async {
    await trackEvent(
      AnalyticsEvents.addToCart,
      parameters: {
        'item_id': itemId,
        'item_name': itemName,
        'price': price,
        'quantity': quantity,
        'value': price * quantity,
        if (currency != null) 'currency': currency,
        if (category != null) 'item_category': category,
      },
    );
  }

  /// Track removing an item from cart.
  Future<void> trackRemoveFromCart({
    required String itemId,
    required String itemName,
    required double price,
    required int quantity,
    String? currency,
  }) async {
    await trackEvent(
      AnalyticsEvents.removeFromCart,
      parameters: {
        'item_id': itemId,
        'item_name': itemName,
        'price': price,
        'quantity': quantity,
        if (currency != null) 'currency': currency,
      },
    );
  }

  /// Track beginning checkout.
  Future<void> trackBeginCheckout({
    required double value,
    required String currency,
    List<Map<String, dynamic>>? items,
    String? coupon,
  }) async {
    await trackEvent(
      AnalyticsEvents.beginCheckout,
      parameters: {
        'value': value,
        'currency': currency,
        if (items != null) 'items': items,
        if (coupon != null) 'coupon': coupon,
      },
    );
  }

  /// Track adding payment info.
  Future<void> trackAddPaymentInfo({
    required String paymentType,
    double? value,
    String? currency,
  }) async {
    await trackEvent(
      AnalyticsEvents.addPaymentInfo,
      parameters: {
        'payment_type': paymentType,
        if (value != null) 'value': value,
        if (currency != null) 'currency': currency,
      },
    );
  }

  /// Track a purchase.
  Future<void> trackPurchase({
    required String transactionId,
    required double value,
    required String currency,
    List<Map<String, dynamic>>? items,
    String? coupon,
    String? tax,
    String? shipping,
  }) async {
    await trackEvent(
      AnalyticsEvents.purchase,
      parameters: {
        'transaction_id': transactionId,
        'value': value,
        'currency': currency,
        if (items != null) 'items': items,
        if (coupon != null) 'coupon': coupon,
        if (tax != null) 'tax': tax,
        if (shipping != null) 'shipping': shipping,
      },
    );
  }

  /// Track a refund.
  Future<void> trackRefund({
    required String transactionId,
    required double value,
    required String currency,
    List<Map<String, dynamic>>? items,
  }) async {
    await trackEvent(
      AnalyticsEvents.refund,
      parameters: {
        'transaction_id': transactionId,
        'value': value,
        'currency': currency,
        if (items != null) 'items': items,
      },
    );
  }

  // ================================================================
  // User Management
  // ================================================================

  /// Set the current user ID.
  ///
  /// Should be called after user login.
  Future<void> setUserId(String userId) async {
    _userId = userId;

    if (_isInitialized && _isEnabled) {
      await _analytics!.setUserId(id: userId);
      debugPrint('[AnalyticsService] User ID set: $userId');
    }
  }

  /// Clear the user ID (on logout).
  Future<void> clearUserId() async {
    _userId = null;

    if (_isInitialized && _isEnabled) {
      await _analytics!.setUserId();
    }
  }

  /// Set a user property.
  Future<void> setUserProperty({
    required String name,
    required String value,
  }) async {
    if (!_isInitialized || !_isEnabled) {
      return;
    }

    try {
      await _analytics!.setUserProperty(name: name, value: value);
      debugPrint('[AnalyticsService] User property set: $name = $value');
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to set user property: $e');
    }
  }

  /// Set multiple user properties at once.
  Future<void> setUserProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setUserProperty(name: entry.key, value: entry.value);
    }
  }

  // ================================================================
  // Crash Reporting
  // ================================================================

  /// Record a non-fatal error.
  Future<void> recordError(
    Object exception,
    StackTrace stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      if (fatal) {
        await _crashlytics?.recordError(
          exception,
          stackTrace,
          reason: reason,
          fatal: true,
        );
      } else {
        // Non-fatal errors logged but don't crash
        debugPrint('[AnalyticsService] Non-fatal error: $exception');
        if (!kDebugMode) {
          await _crashlytics?.recordError(
            exception,
            stackTrace,
            reason: reason,
          );
        }
      }
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to record error: $e');
    }
  }

  /// Set a custom key for crash reports.
  Future<void> setCrashlyticsCustomKey({
    required String key,
    required String value,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setCustomKey(key, value);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to set custom key: $e');
    }
  }

  /// Set a custom key with int value.
  Future<void> setCrashlyticsCustomKeyInt({
    required String key,
    required int value,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setCustomKey(key, value);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to set custom key: $e');
    }
  }

  /// Set a custom key with double value.
  Future<void> setCrashlyticsCustomKeyDouble({
    required String key,
    required double value,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setCustomKey(key, value);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to set custom key: $e');
    }
  }

  /// Set a custom key with bool value.
  Future<void> setCrashlyticsCustomKeyBool({
    required String key,
    required bool value,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.setCustomKey(key, value);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to set custom key: $e');
    }
  }

  /// Log a message for crash context.
  Future<void> logCrashlyticsMessage(String message) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _crashlytics?.log(message);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to log message: $e');
    }
  }

  // ================================================================
  // Performance Monitoring
  // ================================================================

  /// Start a performance trace.
  ///
  /// Returns a [TraceHandler] that must be stopped when done.
  ///
  /// Usage:
  /// ```dart
  /// final trace = analytics.startTrace('api_request');
  /// try {
  ///   // Do work
  /// } finally {
  ///   trace.stop();
  /// }
  /// ```
  TraceHandler? startTrace(String traceName) {
    if (!_isInitialized || !_isEnabled) {
      return null;
    }

    try {
      final trace = _performance?.newTrace(traceName);
      trace?.start();
      return TraceHandler._(trace);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to start trace: $e');
      return null;
    }
  }

  /// Start an HTTP request trace.
  ///
  /// Automatically tracks network request performance.
  HttpMetricHandler? startHttpMetric(
    String url,
    HttpMethod method,
  ) {
    if (!_isInitialized || !_isEnabled) {
      return null;
    }

    try {
      final metric = _performance?.newHttpMetric(url, method);
      metric?.start();
      return HttpMetricHandler._(metric);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to start HTTP metric: $e');
      return null;
    }
  }

  // ================================================================
  // Settings
  // ================================================================

  /// Enable or disable analytics collection.
  Future<void> setAnalyticsEnabled(bool enabled) async {
    _isEnabled = enabled;

    if (_isInitialized) {
      await _analytics?.setAnalyticsCollectionEnabled(enabled);
      debugPrint(
        '[AnalyticsService] Analytics ${enabled ? 'enabled' : 'disabled'}',
      );
    }
  }

  /// Check if analytics is enabled.
  bool get isEnabled => _isEnabled;

  /// Get the analytics observer for Navigator.
  ///
  /// Use this with MaterialApp's navigatorObservers:
  /// ```dart
  /// MaterialApp(
  ///   navigatorObservers: [analytics.observer!],
  /// )
  /// ```
  FirebaseAnalyticsObserver? get observer => _observer;

  // ================================================================
  // Internal Methods
  // ================================================================

  /// Sanitize parameters for Firebase Analytics.
  Map<String, Object>? _sanitizeParameters(Map<String, dynamic>? params) {
    if (params == null) {
      return null;
    }

    final sanitized = <String, Object>{};

    for (final entry in params.entries) {
      if (entry.value == null) {
        continue;
      }

      // Firebase Analytics only supports certain types
      if (entry.value is String ||
          entry.value is int ||
          entry.value is double ||
          entry.value is num ||
          entry.value is bool) {
        sanitized[entry.key] = entry.value as Object;
      } else if (entry.value is List) {
        // Convert list to comma-separated string
        sanitized[entry.key] = (entry.value as List).join(',');
      } else {
        // Convert other types to string
        sanitized[entry.key] = entry.value.toString();
      }
    }

    return sanitized;
  }

  /// Queue an event for later delivery.
  void _queueEvent(
    String eventName,
    Map<String, dynamic>? parameters,
    double? value,
  ) {
    if (_eventQueue.length >= _maxQueueSize) {
      _eventQueue.removeAt(0); // Remove oldest
    }

    _eventQueue.add(
      _QueuedEvent(
        eventName: eventName,
        parameters: parameters,
        value: value,
        timestamp: DateTime.now(),
      ),
    );

    debugPrint('[AnalyticsService] Event queued: $eventName');
  }

  /// Flush queued events.
  Future<void> _flushQueuedEvents() async {
    if (!_isInitialized || !_isEnabled) {
      return;
    }

    final events = List.of(_eventQueue);
    _eventQueue.clear();

    for (final event in events) {
      try {
        await _analytics!.logEvent(
          name: event.eventName,
          parameters: _sanitizeParameters(event.parameters),
        );
      } catch (e) {
        debugPrint('[AnalyticsService] Failed to flush event: $e');
        // Re-queue failed events
        _eventQueue.add(event);
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    _eventQueue.clear();
    debugPrint('[AnalyticsService] Disposed');
  }
}

// ================================================================
// Helper Classes
// ================================================================

/// Handler for performance traces.
class TraceHandler {
  final Trace? _trace;

  TraceHandler._(this._trace);

  /// Set a metric for the trace.
  void setMetric(String metricName, int value) {
    _trace?.setMetric(metricName, value);
  }

  /// Stop the trace.
  void stop() {
    _trace?.stop();
  }
}

/// Handler for HTTP metrics.
class HttpMetricHandler {
  final HttpMetric? _metric;

  HttpMetricHandler._(this._metric);

  /// Set the HTTP response code.
  void setResponseCode(int code) {
    _metric?.httpResponseCode = code;
  }

  /// Set the response content type.
  void setContentType(String type) {
    _metric?.responseContentType = type;
  }

  /// Set a custom attribute.
  void setAttribute(String name, String value) {
    // Firebase Performance does not support custom attributes on HttpMetric
    // This is a no-op for compatibility
  }

  /// Stop the metric.
  void stop() {
    _metric?.stop();
  }
}

/// Queued event for offline tracking.
class _QueuedEvent {
  final String eventName;
  final Map<String, dynamic>? parameters;
  final double? value;
  final DateTime timestamp;

  _QueuedEvent({
    required this.eventName,
    required this.timestamp,
    this.parameters,
    this.value,
  });
}

/// HTTP methods for performance tracking.
enum AppHttpMethod {
  get,
  post,
  put,
  delete,
  patch,
  head,
  options,
}

// Extension to convert enum to Firebase value
extension AppHttpMethodExtension on AppHttpMethod {
  int get value {
    switch (this) {
      case AppHttpMethod.get:
        return 0;
      case AppHttpMethod.post:
        return 1;
      case AppHttpMethod.put:
        return 2;
      case AppHttpMethod.delete:
        return 3;
      case AppHttpMethod.patch:
        return 4;
      case AppHttpMethod.head:
        return 5;
      case AppHttpMethod.options:
        return 6;
    }
  }
}
