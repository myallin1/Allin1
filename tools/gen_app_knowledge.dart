// ================================================================
// tools/gen_app_knowledge.dart
// ================================================================
// Generates lib/config/app_knowledge.dart — a machine-written,
// always-current description of this app that gets injected into every
// AI persona's system prompt.
//
// WHY THIS IS GENERATED AND NOT HAND-WRITTEN
// (Aug 17 2026 — Nizam: "app oda a to z namma ai ku knowledge theriyanum
// ... namma oru new update vittalum athuvum namma ai ku theriyanum apo
// than admin yenna sonnalum athu help pannum".)
//
// A hand-written "here is what the app does" prompt is correct for
// exactly one day. This codebase has already proved that twice: the
// landing page's copy of the campaign numbers has to be hand-synced and
// drifts, and the seller dashboard listened to a collection nobody
// wrote to for weeks without anyone noticing. An AI briefed from a
// stale hand-written summary does not merely become less useful — it
// confidently gives the admin wrong answers about their own system,
// which is worse than having no AI at all.
//
// So this reads the repository itself. Every fact below is derived from
// code that must be true for the app to compile and run:
//   * version            -> pubspec.yaml
//   * Firestore collections / RTDB nodes -> actual .collection('x') and
//                           .ref('y') call sites
//   * routes             -> the route tables in each main_*.dart
//   * screens / services -> the files that exist
//
// Run it from deploy_web.ps1 (already wired) so a deploy can never ship
// app code and stale AI knowledge together.
//
// USAGE
//   dart run tools/gen_app_knowledge.dart
// ================================================================

import 'dart:io';

const _outPath = 'lib/config/app_knowledge.dart';

void main() {
  final root = Directory.current;
  final libDir = Directory('${root.path}/lib');
  if (!libDir.existsSync()) {
    stderr.writeln('Run this from the project root (lib/ not found).');
    exit(1);
  }

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final collections = <String>{};
  final rtdbNodes = <String>{};
  final routes = <String>{};

  final collectionRe = RegExp(r"""\.collection\(\s*'([A-Za-z0-9_]+)'""");
  final rtdbRe = RegExp(r"""\.ref\(\s*'([A-Za-z0-9_]+)""");
  final routeRe = RegExp(r"""'(/[a-z0-9\-/]*)'\s*:\s*\(""");

  for (final f in dartFiles) {
    final src = f.readAsStringSync();
    for (final m in collectionRe.allMatches(src)) {
      collections.add(m.group(1)!);
    }
    for (final m in rtdbRe.allMatches(src)) {
      rtdbNodes.add(m.group(1)!);
    }
    if (f.path.contains('main_')) {
      for (final m in routeRe.allMatches(src)) {
        routes.add(m.group(1)!);
      }
    }
  }

  // Version straight out of pubspec — this is what the admin sees in
  // the app's own update checker, so the AI quoting a different number
  // would be immediately confusing.
  var version = 'unknown';
  final pubspec = File('${root.path}/pubspec.yaml');
  if (pubspec.existsSync()) {
    for (final line in pubspec.readAsLinesSync()) {
      final m = RegExp(r'^version:\s*(\S+)').firstMatch(line);
      if (m != null) {
        version = m.group(1)!;
        break;
      }
    }
  }

  String namesIn(String dir, {String? suffix}) {
    final d = Directory('${root.path}/lib/$dir');
    if (!d.existsSync()) return '';
    final names = d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.dart', ''))
        .where((n) => suffix == null || n.endsWith(suffix))
        .toList()
      ..sort();
    return names.join(', ');
  }

  final screens = namesIn('screens');
  final services = namesIn('services');
  final sortedCollections = collections.toList()..sort();
  final sortedNodes = rtdbNodes.toList()..sort();
  final sortedRoutes = routes.toList()..sort();

  final generatedAt = DateTime.now().toUtc().toIso8601String();

  final buf = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('// Produced by tools/gen_app_knowledge.dart, which is run')
    ..writeln('// automatically by deploy_web.ps1 on every deploy.')
    ..writeln('//')
    ..writeln('// Editing this by hand will work until the next deploy and')
    ..writeln('// then be silently overwritten. Change the GENERATOR instead.')
    ..writeln('//')
    ..writeln('// Generated: $generatedAt')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('/// Machine-generated description of this app, injected into')
    ..writeln('/// every AI persona so the assistant is briefed on the real,')
    ..writeln('/// current system rather than a stale hand-written summary.')
    ..writeln('class AppKnowledge {')
    ..writeln('  AppKnowledge._();')
    ..writeln()
    ..writeln("  static const String version = '$version';")
    ..writeln("  static const String generatedAt = '$generatedAt';")
    ..writeln()
    ..writeln('  /// Firestore collections this codebase actually reads/writes.')
    ..writeln('  static const List<String> firestoreCollections = <String>[')
    ..writeln(sortedCollections.map((c) => "    '$c',").join('\n'))
    ..writeln('  ];')
    ..writeln()
    ..writeln('  /// Realtime Database top-level nodes in use.')
    ..writeln('  static const List<String> realtimeNodes = <String>[')
    ..writeln(sortedNodes.map((c) => "    '$c',").join('\n'))
    ..writeln('  ];')
    ..writeln()
    ..writeln('  /// Named routes registered across the four app flavors.')
    ..writeln('  static const List<String> routes = <String>[')
    ..writeln(sortedRoutes.map((c) => "    '$c',").join('\n'))
    ..writeln('  ];')
    ..writeln()
    ..writeln('  static const String screenIndex =')
    ..writeln("      '${_esc(screens)}';")
    ..writeln()
    ..writeln('  static const String serviceIndex =')
    ..writeln("      '${_esc(services)}';")
    ..writeln('}');
  // NOTE: this generator emits DATA ONLY — plain consts, no string
  // interpolation and no methods. The human-readable briefing is
  // assembled in lib/config/app_knowledge_briefing.dart, which is
  // hand-written and never overwritten.
  //
  // That split is deliberate. An earlier draft had the generator emit
  // the briefing() method too, which meant generating Dart string
  // interpolation from inside Dart string literals — several layers of
  // escaping whose only purpose was to produce text a human could just
  // write once. Generators should emit facts; prose belongs in code a
  // person maintains.

  final out = File('${root.path}/$_outPath');
  out.writeAsStringSync(buf.toString());

  stdout.writeln('  app_knowledge.dart regenerated:');
  stdout.writeln('    version      $version');
  stdout.writeln('    collections  ${sortedCollections.length}');
  stdout.writeln('    rtdb nodes   ${sortedNodes.length}');
  stdout.writeln('    routes       ${sortedRoutes.length}');
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
