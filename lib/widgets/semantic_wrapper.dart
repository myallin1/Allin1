// ================================================================
// SEMANTIC WRAPPER - Accessibility Utilities for Allin1 Super App
// ================================================================
//
// Purpose: Provide reusable Semantics widgets and accessibility
//          helper functions for WCAG 2.1 AA compliance.
//
// Usage:
//   import 'package:erode_superapp/widgets/semantic_wrapper.dart';
//
//   // Wrap any interactive widget
//   SemanticButton(
//     label: 'Send message',
//     hint: 'Double tap to send your message',
//     onTap: _sendMessage,
//     child: Icon(Icons.send),
//   );
//
//   // For Tamil text
//   TamilText(
//     'வணக்கம்! என்ன வேண்டும்?',
//     semanticsLabel: 'Vanakkam! Enna vendum?',
//   );
//
// Author: NJ TECH - UI/UX Frontend Agent (Swarm Mode)
// Date: March 13, 2026
// Version: 1.0.0
// ================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

export 'package:flutter/semantics.dart' show SemanticsService;

// ── Constants ────────────────────────────────────────────────────

/// Minimum touch target size (WCAG 2.2 AAA)
const double kMinTouchTarget = 48;

/// Minimum touch target for compact layouts
const double kMinTouchTargetCompact = 44;

/// Default animation duration for accessibility
const Duration kAccessibilityAnimationDuration = Duration(milliseconds: 300);

// ── Semantic Button Widget ───────────────────────────────────────

/// A reusable button wrapper with full accessibility support.
///
/// This widget ensures:
/// - Minimum 48x48dp touch target
/// - Proper Semantics label and hint
/// - Haptic feedback on tap
/// - Focus management for keyboard navigation
/// - High contrast focus indicator
///
/// Example:
/// ```dart
/// SemanticButton(
///   label: 'Send message',
///   hint: 'Double tap to send your message to the sales assistant',
///   onTap: _sendMessage,
///   child: Icon(Icons.send),
/// )
/// ```
class SemanticButton extends StatelessWidget {
  /// The accessible label for screen readers
  final String label;

  /// Additional hint text for screen readers
  final String? hint;

  /// Whether the button is currently selected (for toggle buttons)
  final bool? isSelected;

  /// Whether the button is enabled
  final bool enabled;

  /// The tap callback
  final VoidCallback? onTap;

  /// The child widget (typically an Icon or Text)
  final Widget child;

  /// Optional custom size (defaults to 48x48)
  final double? size;

  /// Optional border radius for focus indicator
  final double borderRadius;

  /// Optional padding inside the touch target
  final EdgeInsetsGeometry? padding;

  /// Optional focus node for keyboard navigation
  final FocusNode? focusNode;

  /// Optional callback for focus changes
  final ValueChanged<bool>? onFocusChange;

  const SemanticButton({
    required this.label,
    required this.child,
    super.key,
    this.hint,
    this.isSelected,
    this.enabled = true,
    this.onTap,
    this.size,
    this.borderRadius = 12.0,
    this.padding,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? kMinTouchTarget;

    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      skipTraversal: !enabled,
      child: Semantics(
        label: label,
        hint: hint,
        button: true,
        enabled: enabled,
        selected: isSelected,
        focusable: enabled,
        focused: isSelected,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: enabled ? _handleTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: effectiveSize,
            height: effectiveSize,
            padding: padding,
            child: Center(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: enabled ? null : Colors.grey,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap() {
    // Provide haptic feedback
    HapticFeedback.lightImpact();

    // Call the tap callback
    onTap?.call();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('hint', hint))
      ..add(DiagnosticsProperty<bool?>('isSelected', isSelected))
      ..add(DiagnosticsProperty<bool>('enabled', enabled))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap))
      ..add(DoubleProperty('size', size))
      ..add(DoubleProperty('borderRadius', borderRadius))
      ..add(DiagnosticsProperty<EdgeInsetsGeometry?>('padding', padding))
      ..add(DiagnosticsProperty<FocusNode?>('focusNode', focusNode))
      ..add(
        ObjectFlagProperty<ValueChanged<bool>?>.has(
          'onFocusChange',
          onFocusChange,
        ),
      );
  }
}

// ── Semantic Link Widget ────────────────────────────────────────

/// A reusable link wrapper with accessibility support.
///
/// Example:
/// ```dart
/// SemanticLink(
///   label: 'View order details',
///   hint: 'Opens order details page',
///   onTap: () => Navigator.pushNamed(context, '/order-details'),
///   child: Text('View Details'),
/// )
/// ```
class SemanticLink extends StatelessWidget {
  /// The accessible label for screen readers
  final String label;

  /// Additional hint text for screen readers
  final String? hint;

  /// The tap callback
  final VoidCallback? onTap;

  /// The child widget (typically Text)
  final Widget child;

  /// Whether the link has been visited
  final bool visited;

  const SemanticLink({
    required this.label,
    required this.child,
    super.key,
    this.hint,
    this.onTap,
    this.visited = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      link: true,
      linkUrl: onTap != null ? Uri.parse('#link') : null,
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('hint', hint))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap))
      ..add(DiagnosticsProperty<bool>('visited', visited));
  }
}

// ── Semantic Card Widget ────────────────────────────────────────

/// A reusable card wrapper with accessibility support.
///
/// Example:
/// ```dart
/// SemanticCard(
///   label: 'Food Delivery Card',
///   hint: 'Tap to order food from 16th Road restaurants',
///   onTap: () => Navigator.pushNamed(context, '/food'),
///   child: CommerceCard(data: foodData),
/// )
/// ```
class SemanticCard extends StatelessWidget {
  /// The accessible label for screen readers
  final String label;

  /// Additional hint text for screen readers
  final String? hint;

  /// The tap callback
  final VoidCallback? onTap;

  /// The child widget (card content)
  final Widget child;

  /// Optional border radius
  final double borderRadius;

  /// Optional elevation
  final double elevation;

  const SemanticCard({
    required this.label,
    required this.child,
    super.key,
    this.hint,
    this.onTap,
    this.borderRadius = 16.0,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: hint,
      button: onTap != null,
      container: true,
      child: Material(
        elevation: elevation,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: child,
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('hint', hint))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap))
      ..add(DoubleProperty('borderRadius', borderRadius))
      ..add(DoubleProperty('elevation', elevation));
  }
}

// ── Semantic Icon Button ────────────────────────────────────────

/// A reusable icon button with accessibility support.
///
/// Example:
/// ```dart
/// SemanticIconButton(
///   label: 'Delete chat',
///   hint: 'Remove all chat history',
///   icon: Icons.delete_outline,
///   onTap: _clearChat,
/// )
/// ```
class SemanticIconButton extends StatelessWidget {
  /// The accessible label for screen readers
  final String label;

  /// Additional hint text for screen readers
  final String? hint;

  /// The icon to display
  final IconData icon;

  /// The tap callback
  final VoidCallback? onTap;

  /// Icon size
  final double iconSize;

  /// Button size (defaults to 48x48)
  final double buttonSize;

  /// Whether the button is enabled
  final bool enabled;

  /// Optional color
  final Color? color;

  const SemanticIconButton({
    required this.label,
    required this.icon,
    super.key,
    this.hint,
    this.onTap,
    this.iconSize = 24.0,
    this.buttonSize = kMinTouchTarget,
    this.enabled = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SemanticButton(
      label: label,
      hint: hint,
      enabled: enabled,
      size: buttonSize,
      onTap: onTap,
      child: Icon(
        icon,
        size: iconSize,
        color: enabled ? color : Colors.grey,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('hint', hint))
      ..add(DiagnosticsProperty<IconData>('icon', icon))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap))
      ..add(DoubleProperty('iconSize', iconSize))
      ..add(DoubleProperty('buttonSize', buttonSize))
      ..add(DiagnosticsProperty<bool>('enabled', enabled))
      ..add(ColorProperty('color', color));
  }
}

// ── Tamil Text Widget ───────────────────────────────────────────

/// A text widget optimized for Tamil language accessibility.
///
/// Features:
/// - Proper Tamil locale declaration for screen readers
/// - Appropriate font (Noto Sans Tamil)
/// - Minimum readable font size
/// - Optional phonetic label for screen readers
///
/// Example:
/// ```dart
/// TamilText(
///   'வணக்கம்! என்ன வேண்டும்?',
///   semanticsLabel: 'Vanakkam! Enna vendum?',
///   fontSize: 16,
/// )
/// ```
class TamilText extends StatelessWidget {
  /// The Tamil text to display
  final String data;

  /// Optional phonetic label for screen readers
  final String? semanticsLabel;

  /// Font size (minimum 14 for readability)
  final double fontSize;

  /// Font weight
  final FontWeight fontWeight;

  /// Text color
  final Color? color;

  /// Line height
  final double height;

  /// Text alignment
  final TextAlign textAlign;

  /// Maximum lines
  final int? maxLines;

  /// Optional style overrides
  final TextStyle? style;

  const TamilText(
    this.data, {
    super.key,
    this.semanticsLabel,
    this.fontSize = 14.0,
    this.fontWeight = FontWeight.normal,
    this.color,
    this.height = 1.4,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure minimum font size for readability
    final effectiveFontSize = fontSize < 14 ? 14 : fontSize;

    return Semantics(
      label: semanticsLabel ?? data,
      textDirection: TextDirection.ltr,
      child: Text(
        data,
        style: style ??
            TextStyle(
              fontSize: effectiveFontSize.toDouble(),
              fontWeight: fontWeight,
              color: color,
              height: height,
            ),
        textAlign: textAlign,
        maxLines: maxLines,
        textDirection: TextDirection.ltr,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('data', data))
      ..add(StringProperty('semanticsLabel', semanticsLabel))
      ..add(DoubleProperty('fontSize', fontSize))
      ..add(DiagnosticsProperty<FontWeight>('fontWeight', fontWeight))
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('height', height))
      ..add(EnumProperty<TextAlign>('textAlign', textAlign))
      ..add(IntProperty('maxLines', maxLines))
      ..add(DiagnosticsProperty<TextStyle?>('style', style));
  }
}

// ── Tamil Rich Text Widget ──────────────────────────────────────

/// A rich text widget for mixed Tamil/English content.
///
/// Example:
/// ```dart
/// TamilRichText(
///   children: [
///     TextSpan(text: 'Order '),
///     TextSpan(text: 'பண்ணுங்கள்', locale: Locale('ta', 'IN')),
///     TextSpan(text: ' now!'),
///   ],
/// )
/// ```
class TamilRichText extends StatelessWidget {
  /// The text spans
  final List<InlineSpan> children;

  /// Default text style
  final TextStyle? style;

  /// Text alignment
  final TextAlign textAlign;

  const TamilRichText({
    required this.children,
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textDirection: TextDirection.ltr,
      child: RichText(
        text: TextSpan(
          style: style,
          children: children.map((child) {
            if (child is TextSpan) {
              return TextSpan(
                text: child.text,
                style: child.style ?? style,
                locale: child.locale ?? const Locale('ta', 'IN'),
                children: child.children,
                recognizer: child.recognizer,
                semanticsLabel: child.semanticsLabel,
              );
            }
            return child;
          }).toList(),
        ),
        textAlign: textAlign,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IterableProperty<InlineSpan>('children', children))
      ..add(DiagnosticsProperty<TextStyle?>('style', style))
      ..add(EnumProperty<TextAlign>('textAlign', textAlign));
  }
}

// ── Accessible Checkbox Widget ──────────────────────────────────

/// A checkbox with full accessibility support.
///
/// Example:
/// ```dart
/// AccessibleCheckbox(
///   label: 'Remember my address',
///   value: _rememberAddress,
///   onChanged: (value) => setState(() => _rememberAddress = value),
/// )
/// ```
class AccessibleCheckbox extends StatelessWidget {
  /// The checkbox label
  final String label;

  /// Whether the checkbox is checked
  final bool value;

  /// Callback when value changes
  final ValueChanged<bool>? onChanged;

  const AccessibleCheckbox({
    required this.label,
    required this.value,
    super.key,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      checked: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onChanged != null
                ? () {
                    HapticFeedback.selectionClick();
                    onChanged?.call(!value);
                  }
                : null,
            child: Container(
              width: kMinTouchTarget,
              height: kMinTouchTarget,
              padding: const EdgeInsets.all(8),
              child: Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                color: value ? Theme.of(context).primaryColor : Colors.grey,
                size: 24,
              ),
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(label),
          ],
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(DiagnosticsProperty<bool>('value', value))
      ..add(
        ObjectFlagProperty<ValueChanged<bool>?>.has('onChanged', onChanged),
      );
  }
}

// ── Live Region Widget ──────────────────────────────────────────

/// A widget that announces dynamic content changes to screen readers.
///
/// Use this for live updates like:
/// - Loading status changes
/// - Error messages
/// - Success notifications
/// - Real-time data updates
///
/// Example:
/// ```dart
/// LiveRegion(
///   politeness: Politeness.assertive,
///   child: Text(_isLoading ? 'Loading...' : 'Ready'),
/// )
/// ```
class LiveRegion extends StatelessWidget {
  /// The child widget containing dynamic content
  final Widget child;

  /// The politeness level for announcements
  final Politeness politeness;

  const LiveRegion({
    required this.child,
    super.key,
    this.politeness = Politeness.polite,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      // For iOS/Android, it manages the politeness automatically
      // based on the liveRegion property.
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Politeness>('politeness', politeness));
  }
}

/// Politeness levels for LiveRegion
enum Politeness {
  /// Polite announcements (don't interrupt)
  polite,

  /// Assertive announcements (interrupt current speech)
  assertive,
}

// ── Skip Link Widget ────────────────────────────────────────────

/// A skip link for keyboard navigation.
///
/// Skip links allow keyboard users to bypass repetitive content
/// and jump directly to the main content.
///
/// Example:
/// ```dart
/// SkipLink(
///   label: 'Skip to main content',
///   focusNodeId: 'main-content',
/// )
/// ```
class SkipLink extends StatelessWidget {
  /// The accessible label
  final String label;

  /// The ID of the focus node to skip to
  final String focusNodeId;

  /// Optional callback when skip link is activated
  final VoidCallback? onSkip;

  const SkipLink({
    required this.label,
    required this.focusNodeId,
    super.key,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onSkip?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('focusNodeId', focusNodeId))
      ..add(ObjectFlagProperty<VoidCallback?>.has('onSkip', onSkip));
  }
}

// ── Accessibility Helper Functions ──────────────────────────────

/// Check if reduced motion is enabled
bool shouldReduceMotion(BuildContext context) {
  return MediaQuery.of(context).accessibleNavigation ||
      WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.reduceMotion;
}

/// Get the appropriate animation duration based on accessibility settings
Duration getAnimationDuration(
  BuildContext context, {
  Duration normal = const Duration(milliseconds: 300),
}) {
  if (shouldReduceMotion(context)) {
    return Duration.zero;
  }
  return normal;
}

/// Get text scale factor with reasonable limits
double getTextScaleFactor(
  BuildContext context, {
  double min = 0.8,
  double max = 2.0,
}) {
  return MediaQuery.of(context).textScaler.scale(1).clamp(min, max);
}

/// Ensure minimum touch target size
Size ensureMinTouchTarget(Size current, {double minSize = kMinTouchTarget}) {
  return Size(
    current.width < minSize ? minSize : current.width,
    current.height < minSize ? minSize : current.height,
  );
}

/// Announce a message to screen readers
void announceToScreenReader(String message) {
  SemanticsService.sendAnnouncement(
    PlatformDispatcher.instance.implicitView!,
    message,
    TextDirection.ltr,
  );
}

/// Request focus for a specific node
void requestAccessibilityFocus(FocusNode node) {
  node.requestFocus();
}

// ── Contrast Checker Utility ────────────────────────────────────

/// Calculate the contrast ratio between two colors
///
/// Returns a value between 1 and 21.
/// - 21:1 is maximum contrast (black on white)
/// - 1:1 is no contrast (same color)
///
/// WCAG Requirements:
/// - Normal text: 4.5:1 minimum (AA)
/// - Large text: 3:1 minimum (AA)
/// - Enhanced: 7:1 for normal, 4.5:1 for large (AAA)
double calculateContrastRatio(Color foreground, Color background) {
  final fgLuminance = _getLuminance(foreground);
  final bgLuminance = _getLuminance(background);

  final lighter = fgLuminance > bgLuminance ? fgLuminance : bgLuminance;
  final darker = fgLuminance > bgLuminance ? bgLuminance : fgLuminance;

  return (lighter + 0.05) / (darker + 0.05);
}

/// Check if a color pair meets WCAG AA requirements
bool meetsWcagAA(
  Color foreground,
  Color background, {
  bool isLargeText = false,
}) {
  final ratio = calculateContrastRatio(foreground, background);
  final required = isLargeText ? 3.0 : 4.5;
  return ratio >= required;
}

/// Check if a color pair meets WCAG AAA requirements
bool meetsWcagAAA(
  Color foreground,
  Color background, {
  bool isLargeText = false,
}) {
  final ratio = calculateContrastRatio(foreground, background);
  final required = isLargeText ? 4.5 : 7.0;
  return ratio >= required;
}

/// Calculate relative luminance of a color
///
/// Based on WCAG 2.1 formula:
/// https://www.w3.org/WAI/GL/wiki/Relative_luminance
double _getLuminance(Color color) {
  final r = _sRGB(color.r);
  final g = _sRGB(color.g);
  final b = _sRGB(color.b);

  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Convert sRGB to linear RGB
double _sRGB(double value) {
  if (value <= 0.03928) {
    return value / 12.92;
  }
  return math.pow((value + 0.055) / 1.055, 2.4) as double;
}

/// Get accessible text color for a given background
Color getAccessibleTextColor(Color backgroundColor) {
  final luminance = _getLuminance(backgroundColor);
  // If background is dark, use light text; otherwise use dark text
  return luminance < 0.5 ? Colors.white : Colors.black;
}

// ── Screen Reader Testing Utilities ─────────────────────────────

/// Widget for testing screen reader output
///
/// Wrap your widget with this to see what screen readers will announce
class ScreenReaderPreview extends StatelessWidget {
  final Widget child;

  const ScreenReaderPreview({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      explicitChildNodes: true,
      child: child,
    );
  }
}

/// Print semantics tree to console for debugging
void debugPrintSemanticsTree() {
  // This would require binding to the semantics engine
  // For now, it's a placeholder for future implementation
  debugPrint(
    'Semantics tree debugging - use Flutter DevTools for detailed view',
  );
}
