// ================================================================
// ManualRefreshHeader — shared "round arrow + last synced" control
// ================================================================
// Part of the app-wide move (per Nizam's request) away from
// always-on Firestore listeners on non-urgent screens, toward a
// tap-to-refresh model: data loads once, a small round refresh
// button in the corner re-fetches fresh data on demand, and a
// "Last synced" caption shows how stale the on-screen data is.
// Safety-critical / truly-live screens (SOS alerts, active ride
// tracking, chat) are intentionally NOT converted to this pattern —
// only browse/overview/report screens.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ManualRefreshHeader extends StatelessWidget {
  final DateTime? lastSyncedAt;
  final bool loading;
  final VoidCallback onRefresh;
  final Color accentColor;
  final Color textColor;
  final String? label;

  const ManualRefreshHeader({
    required this.lastSyncedAt, required this.loading, required this.onRefresh, super.key,
    this.accentColor = const Color(0xFFFF4FA3),
    this.textColor = Colors.white70,
    this.label,
  });

  String _formatSynced() {
    if (lastSyncedAt == null) return 'Not synced yet';
    final now = DateTime.now();
    final diff = now.difference(lastSyncedAt!);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    final h = lastSyncedAt!.hour.toString().padLeft(2, '0');
    final m = lastSyncedAt!.minute.toString().padLeft(2, '0');
    return 'Synced at $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label ?? _formatSynced(),
            style: TextStyle(color: textColor, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          onTap: loading ? null : onRefresh,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.14),
              border: Border.all(color: accentColor.withValues(alpha: 0.4)),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(7),
                    child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                  )
                : Icon(Icons.refresh_rounded, size: 18, color: accentColor),
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DateTime?>('lastSyncedAt', lastSyncedAt));
    properties.add(DiagnosticsProperty<bool>('loading', loading));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRefresh', onRefresh));
    properties.add(ColorProperty('accentColor', accentColor));
    properties.add(ColorProperty('textColor', textColor));
    properties.add(StringProperty('label', label));
  }
}
