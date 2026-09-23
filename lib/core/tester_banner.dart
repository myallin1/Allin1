import 'package:flutter/material.dart';

import 'app_env.dart';

/// Wraps the whole app. In staging it paints a small "TEST BUILD" ribbon in the
/// top-right and exposes a hidden tester menu (long-press the ribbon). In prod
/// it returns [child] unchanged - and because [AppEnv.isStaging] is a const
/// `false` there, this entire overlay is tree-shaken out of the release binary.
///
/// Usage (in any MaterialApp): `builder: (context, child) => TesterBanner(child: child)`.
class TesterBanner extends StatelessWidget {
  const TesterBanner({required this.child, this.extraMenuItems, super.key});

  final Widget? child;

  /// Optional app-specific tester-menu tiles (e.g. a quick link to an
  /// admin-only screen). Built lazily via a context-aware callback so a
  /// flavor that has nothing extra to add can simply omit this.
  final List<Widget> Function(BuildContext context)? extraMenuItems;

  @override
  Widget build(BuildContext context) {
    final Widget content = child ?? const SizedBox.shrink();
    if (!AppEnv.isStaging) return content;
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          content,
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: GestureDetector(
                onLongPress: () => _openTesterMenu(context),
                child: Container(
                  margin: const EdgeInsets.only(top: 4, right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB00020),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'TEST ${AppEnv.env}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openTesterMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('Tester menu'),
              subtitle: Text('Staging build - not visible in production'),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Environment'),
              trailing: Text(AppEnv.env),
            ),
            if (extraMenuItems != null) ...extraMenuItems!(ctx),
            // Add more tester-only tools here (feature flags, fake data,
            // screen jumps, log dumps). They all vanish in prod.
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
