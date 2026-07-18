import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// HeroUpdateService handles OTA updates for the Hero (Driver) App.
/// Designed for Lead Architect standards with full Web/Chrome safety.
class HeroUpdateService {
  static final HeroUpdateService _instance = HeroUpdateService._internal();
  factory HeroUpdateService() => _instance;
  HeroUpdateService._internal();

  final Dio _dio = Dio();
  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  static const String updateUrl = 'https://bit.ly/njtech-hero-update';

  /// Triggers the update process.
  /// On Web: Opens the link in a new tab.
  /// On Mobile: Downloads and installs the APK.
  Future<void> triggerUpdate(BuildContext context) async {
    if (kIsWeb) {
      unawaited(_handleWebUpdate(context));
    } else {
      await _handleMobileUpdate(context);
    }
  }

  /// Web-safe update handler - Opens link in new tab.
  Future<void> _handleWebUpdate(BuildContext context) async {
    final Uri uri = Uri.parse(updateUrl);

    // Show feedback as requested for Web UI Test
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web UI Test: Update triggered'),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch update link'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Mobile update handler - Downloads and installs APK.
  Future<void> _handleMobileUpdate(BuildContext context) async {
    if (_isDownloading) {
      return;
    }

    try {
      _isDownloading = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading Hero Update...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final directories = await getExternalCacheDirectories();
      if (directories == null || directories.isEmpty) {
        throw Exception('Storage not available');
      }

      final filePath = '${directories.first.path}/hero_update.apk';

      await _dio.download(
        updateUrl,
        filePath,
        onReceiveProgress: (received, total) {
          // Progress can be piped here if a dialog is used
          if (total != -1) {
            debugPrint(
              'Download Progress: ${(received / total * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );

      _isDownloading = false;

      // Launch installation
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Install failed: ${result.message}')),
        );
      }
    } catch (e) {
      _isDownloading = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
