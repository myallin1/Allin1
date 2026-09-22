// ================================================================
// whatsapp_broadcast_service.dart — Bulk outreach & video dispatcher
// ================================================================
// Allows admin to formulate promotional messages with optional video links
// and dispatch them to recipient lists with rate limiting and progress.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

@immutable
class BroadcastRecipient {
  const BroadcastRecipient({
    required this.phoneNumber,
    this.name,
    this.sent = false,
    this.error,
  });

  final String phoneNumber;
  final String? name;
  final bool sent;
  final String? error;

  BroadcastRecipient copyWith({
    String? phoneNumber,
    String? name,
    bool? sent,
    String? error,
  }) {
    return BroadcastRecipient(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      sent: sent ?? this.sent,
      error: error ?? this.error,
    );
  }
}

class WhatsAppBroadcastService {
  WhatsAppBroadcastService._();

  /// Clean phone numbers into valid WhatsApp international format (+91...)
  static String formatPhoneNumber(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '91$digits';
    }
    if (digits.startsWith('0') && digits.length == 11) {
      return '91${digits.substring(1)}';
    }
    if (digits.startsWith('91') && digits.length == 12) {
      return digits;
    }
    return digits;
  }

  /// Parses comma/newline/space separated raw phone number strings into clean list
  static List<BroadcastRecipient> parseNumbers(String rawText) {
    final rawLines = rawText.split(RegExp(r'[\n,;]+'));
    final List<BroadcastRecipient> recipients = [];
    final Set<String> seen = {};

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Extract optional Name: Phone pattern
      String? name;
      String numberPart = trimmed;
      if (trimmed.contains(':') || trimmed.contains('-')) {
        final parts = trimmed.split(RegExp(r'[:\-]'));
        if (parts.length >= 2) {
          name = parts[0].trim();
          numberPart = parts.sublist(1).join('-').trim();
        }
      }

      final cleanNumber = formatPhoneNumber(numberPart);
      if (cleanNumber.length >= 10 && !seen.contains(cleanNumber)) {
        seen.add(cleanNumber);
        recipients.add(BroadcastRecipient(
          phoneNumber: cleanNumber,
          name: name,
        ));
      }
    }
    return recipients;
  }

  /// Constructs the WhatsApp deep link / web link for an individual message
  static String buildWhatsAppUrl({
    required String phoneNumber,
    required String message,
    String? videoUrl,
  }) {
    final cleanPhone = formatPhoneNumber(phoneNumber);
    final buffer = StringBuffer();
    buffer.write(message.trim());

    if (videoUrl != null && videoUrl.trim().isNotEmpty) {
      buffer.writeln('\n');
      buffer.writeln('🎬 Watch Video: ${videoUrl.trim()}');
    }

    final encodedText = Uri.encodeComponent(buffer.toString());
    return 'https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedText';
  }

  /// Launches WhatsApp for a single recipient
  static Future<bool> sendSingleMessage({
    required String phoneNumber,
    required String message,
    String? videoUrl,
  }) async {
    final urlStr = buildWhatsAppUrl(
      phoneNumber: phoneNumber,
      message: message,
      videoUrl: videoUrl,
    );
    final uri = Uri.parse(urlStr);

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[WhatsAppBroadcast] Launch error: $e');
    }
    return false;
  }
}
