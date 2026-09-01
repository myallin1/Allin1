import 'dart:async';

import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/map_service.dart';

class SplashSetupScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashSetupScreen({required this.nextScreen, super.key});

  @override
  State<SplashSetupScreen> createState() => _SplashSetupScreenState();
}

class _SplashSetupScreenState extends State<SplashSetupScreen> {
  @override
  void initState() {
    super.initState();
    // FIX (Instant Launch): this used to `await` both calls below before
    // ever navigating anywhere -- MapService().initialize() makes a real
    // network call to validate the Ola Maps key (up to a 5s timeout
    // before falling back to OSM), so EVERY cold start of the app paid
    // that cost before the customer/hero saw anything but this loading
    // screen. Both calls are idempotent (ApiConfig caches its load
    // Future; MapService now has its own in-flight guard, see
    // map_service.dart) and are already warmed up unawaited from
    // main()'s _warmCustomerServices()/_warmHeroServices() -- this
    // screen doesn't need to gate navigation on them at all anymore, it
    // just makes sure they're running and moves straight to the real
    // screen below.
    unawaited(_warmUpInBackground());
  }

  Future<void> _warmUpInBackground() async {
    try {
      await ApiConfig.ensureEnvLoaded();
      await MapService().initialize();
    } catch (e) {
      debugPrint('SplashSetupScreen init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Renders the real destination screen immediately instead of a
    // blocking BrandedLoadingScreen gate -- the destination screen (e.g.
    // DashboardScreen) is responsible for its own instant paint + silent
    // background data loading.
    return widget.nextScreen;
  }
}
