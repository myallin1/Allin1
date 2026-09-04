// ================================================================
// admin_shell_nav.dart — let a deep link reach the right bottom tab
// ================================================================
// AUDIT FIX (Sep 5 2026, second pass).
//
// openInAdminBrowser() switched the GitHub/Browser SEGMENT and loaded
// the link, but nothing switched the admin shell's BOTTOM tab. So a
// github.com link tapped in Gmail did everything right and left the
// admin looking at the Overview tab, with the page he asked for loaded
// two tabs away. From his side that is indistinguishable from the tap
// having done nothing at all.
//
// WHY A TINY SERVICE AND NOT A DIRECT CALL
// The obvious fix is for admin_web_tabs_screen to call a static on
// SuperAdminHomeScreen — but SuperAdminHomeScreen already imports
// admin_web_tabs_screen, so that is an import cycle for one function
// call. This holds the callback instead: the shell registers itself
// while it is mounted, and anything that needs a tab switch asks here
// without knowing what the shell is.
//
// Deliberately a no-op when nothing is registered. On a cold start the
// link arrives before the shell exists, and that case is already
// covered — AdminWebTabsScreen reads the segment from a static, so the
// tab it eventually builds is the right one. Failing quietly is correct
// here, not a swallowed error.
import 'package:flutter/foundation.dart';

class AdminShellNav {
  AdminShellNav._();

  /// Index of the GitHub/Browser tab in the admin shell's IndexedStack.
  static const int webTabIndex = 4;

  static void Function(int index)? _switcher;

  /// Called by the shell's State in initState, and cleared in dispose so
  /// a stale closure can never setState on a dead State.
  static void register(void Function(int index) switcher) {
    _switcher = switcher;
  }

  static void unregister(void Function(int index) switcher) {
    // == and NOT identical(): Dart guarantees that two tear-offs of the
    // same instance method on the same object compare equal, but it does
    // NOT guarantee they are the same object. identical() here would
    // silently fail to clear the callback on dispose, leaving a closure
    // holding a dead State alive for the life of the process.
    if (_switcher == switcher) _switcher = null;
  }

  /// Brings a bottom tab to the front, if the shell is currently up.
  static void openTab(int index) {
    final switcher = _switcher;
    if (switcher == null) return;
    try {
      switcher(index);
    } catch (e) {
      debugPrint('[AdminShellNav] tab switch failed: $e');
    }
  }
}
