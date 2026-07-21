import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/map_service.dart';
import '../widgets/branded_loading_screen.dart';

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
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Idempotent + race-safe. Previously this was a bare dotenv.load(),
      // which the unawaited MapService warm-up in main_hero/main_customer
      // could beat to the punch.
      await ApiConfig.ensureEnvLoaded();
      await MapService().initialize();
    } catch (e) {
      debugPrint('SplashSetupScreen init error: $e');
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.nextScreen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same "made love with Erode" look used by _CustomerHomeGate's
    // loading state (main_customer.dart) and _IntroGate's first-launch
    // check — previously this screen had its own distinct pink design,
    // so customers saw 2-3 different-looking loading screens flash by
    // in sequence on a single cold start. Now it's one continuous look.
    return const BrandedLoadingScreen(statusText: 'Setting up for you...');
  }
}
