// ================================================================
// chitti_summarizer.dart — Smart Executive Summarizer for Chitti AI
// ================================================================
// NEW (Part C — Nizam: "customer sonnatha apdiye enkita vanthu
// sollakudathu summarize panni avanga sollavarratha enaku theliva sollanum").
//
// When an admin or hero asks Chitti to read recent communications or
// open customer enquiries, Chitti must act like an authentic executive
// assistant — understanding the core intent and presenting a concise
// 1-line summary in Tamil or English, rather than parroting raw verbatim
// sentences or leaking bank OTP numbers.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../guru_api_service.dart';

class ChittiSummarizer {
  ChittiSummarizer._();

  static final GuruApiService _api = GuruApiService();

  /// Redacts sensitive 4-8 digit numeric tokens (OTPs, PINs, bank codes)
  /// before passing text to speech or summarization models.
  static String redactSensitiveTokens(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(r'\b(?:\d[\s-]?){4,8}\b'),
      (match) => '[REDACTED]',
    );
  }

  /// Summarizes a customer message, SMS, or inquiry into ONE clear,
  /// actionable sentence in Tamil or English.
  static Future<String> summarizeMessage({
    required String sender,
    required String message,
    bool isTamil = true,
  }) async {
    final sanitized = redactSensitiveTokens(message.trim());
    if (sanitized.isEmpty) {
      return isTamil ? 'தகவல் எதுவும் இல்லை.' : 'No message content.';
    }

    // 1. Check if the message is clearly an OTP / transactional bank alert
    if (_isOtpOrBankAlert(sanitized)) {
      return isTamil
          ? 'வங்கியிலிருந்து பரிவர்த்தனை அல்லது OTP அறிவிப்பு வந்துள்ளது.'
          : 'Bank transaction or OTP notification received.';
    }

    // 2. Online Tier: attempt fast LLM summarization with 3.5s timeout
    try {
      final prompt =
          'You are Chitti AI executive assistant for an app admin. '
          'Summarize the following message from "$sender" into ONE short, '
          'natural, clear sentence in ${isTamil ? 'Tamil' : 'English'} stating what they want or need '
          '(e.g. "$sender டெலிவரி தாமதம் குறித்து கேட்டுள்ளார்" or "$sender is asking about repair cost"). '
          'Do NOT repeat verbatim quotes or dump raw text. Be concise.\n\n'
          'Message: $sanitized';

      final response = await _api
          .sendMessage(
            message: prompt,
            languageLabel: isTamil ? 'Tamil' : 'English',
          )
          .timeout(const Duration(milliseconds: 3500));

      final cleanResponse = response.trim();
      // Verify valid response from model (not fallback error message)
      if (cleanResponse.isNotEmpty &&
          !cleanResponse.toLowerCase().contains('full ai chat is not switched on') &&
          !cleanResponse.toLowerCase().contains('not available')) {
        return cleanResponse;
      }
    } catch (e) {
      debugPrint('[ChittiSummarizer] Online summarization fallback: $e');
    }

    // 3. Offline / Fast Heuristic Tier:
    return heuristicSummary(sender: sender, message: sanitized, isTamil: isTamil);
  }

  /// Fast rule-based heuristic summarizer for offline scenarios or network timeouts.
  static String heuristicSummary({
    required String sender,
    required String message,
    bool isTamil = true,
  }) {
    final sanitized = redactSensitiveTokens(message.trim());
    if (sanitized.isEmpty) {
      return isTamil ? 'தகவல் எதுவும் இல்லை.' : 'No message content.';
    }
    final lower = sanitized.toLowerCase();

    if (_isOtpOrBankAlert(sanitized)) {
      return isTamil
          ? 'வங்கியிலிருந்து பரிவர்த்தனை அல்லது OTP அறிவிப்பு வந்துள்ளது.'
          : 'Bank transaction or OTP alert received.';
    }

    // Pricing / Quote inquiry
    if (lower.contains('evlo') ||
        lower.contains('rate') ||
        lower.contains('price') ||
        lower.contains('cost') ||
        lower.contains('charge') ||
        lower.contains('kattanam') ||
        lower.contains('விலை') ||
        lower.contains('கட்டணம்') ||
        lower.contains('ரூபாய்')) {
      return isTamil
          ? '$sender விலை அல்லது கட்டண விபரம் கேட்டுள்ளார்.'
          : '$sender is inquiring about service pricing or charges.';
    }

    // Delivery / Order status / Delay
    if (lower.contains('delay') ||
        lower.contains('late') ||
        lower.contains('order') ||
        lower.contains('delivery') ||
        lower.contains('enga') ||
        lower.contains('status') ||
        lower.contains('எங்க') ||
        lower.contains('தாமதம்') ||
        lower.contains('டெலிவரி')) {
      return isTamil
          ? '$sender டெலிவரி அல்லது ஆர்டர் நிலை குறித்து கேட்டுள்ளார்.'
          : '$sender is asking about order delivery or status.';
    }

    // Gadget Repair / Service
    if (lower.contains('display') ||
        lower.contains('screen') ||
        lower.contains('battery') ||
        lower.contains('repair') ||
        lower.contains('service') ||
        lower.contains('mobile') ||
        lower.contains('laptop') ||
        lower.contains('சாம்சங்') ||
        lower.contains('டிஸ்ப்ளே') ||
        lower.contains('சர்வீஸ்')) {
      return isTamil
          ? '$sender சாதனம் பழுதுநீக்கம் அல்லது சர்வீஸ் பற்றி கேட்டுள்ளார்.'
          : '$sender is inquiring about gadget service or repair.';
    }

    // Ride / Transport
    if (lower.contains('auto') ||
        lower.contains('bike') ||
        lower.contains('taxi') ||
        lower.contains('ride') ||
        lower.contains('cab') ||
        lower.contains('booking') ||
        lower.contains('பைக்') ||
        lower.contains('ஆட்டோ') ||
        lower.contains('பயணம்')) {
      return isTamil
          ? '$sender வாகன முன்பதிவு அல்லது பயணம் குறித்து கேட்டுள்ளார்.'
          : '$sender is inquiring about ride or transport booking.';
    }

    // Greeting / General message
    if (lower.contains('hi') ||
        lower.contains('hello') ||
        lower.contains('vanakkam') ||
        lower.contains('வணக்கம்')) {
      return isTamil
          ? '$sender உங்களுடன் உரையாடலைத் தொடங்கியுள்ளார்.'
          : '$sender has reached out with a greeting.';
    }

    // General fallback: concise excerpt without verbatim dump
    final short = sanitized.length > 50 ? '${sanitized.substring(0, 47)}…' : sanitized;
    return isTamil
        ? '$sender அனுப்பிய செய்தி: $short'
        : 'Message from $sender: $short';
  }

  static bool _isOtpOrBankAlert(String text) {
    final lower = text.toLowerCase();
    return lower.contains('otp') ||
        lower.contains('verification code') ||
        lower.contains('debited') ||
        lower.contains('credited') ||
        lower.contains('bank a/c') ||
        lower.contains('upi ref') ||
        lower.contains('secret code') ||
        lower.contains('do not share');
  }
}
