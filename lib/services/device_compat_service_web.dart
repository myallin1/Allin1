import 'package:flutter/foundation.dart';

import 'device_compat_service.dart';
import 'update_service.dart';

// FIX (root cause of the web "download the app" button 404'ing / "the
// GitHub link shows the app isn't there"): these used to point at
// architecture-split filenames (customer-arm64.apk,
// customer-armeabi-v7a.apk, etc.) that were never actually uploaded to
// the release. The real release only ever contains one universal APK
// per app — allin1-customer.apk / allin1-hero.apk. Since architecture
// detection below always resolves to CpuArchitecture.universal anyway
// (see _detectProfile), both the "primary" and "universal" slots now
// point at the same real, working URL.
// SINGLE SOURCE OF TRUTH (Aug 17 2026 — Nizam: "dowload source git
// orey place ah than irukanum"). These were two more hardcoded copies of
// the release URLs. Every APK link in the app now resolves through
// UpdateService, so changing the release naming is a one-file edit
// instead of a hunt across five files — which is exactly how
// landing_page.dart ended up pointing at a filename that did not exist.
const String _customerApkUrl = UpdateService.customerApkUrl;
const String _heroApkUrl = UpdateService.heroApkUrl;

Future<DeviceCompatProfile> detectCustomerApkProfile() async {
  return _detectProfile(
    appVariant: 'customer',
    arm64Url: _customerApkUrl,
    universalUrl: _customerApkUrl,
    labelPrefix: 'Customer',
  );
}

Future<DeviceCompatProfile> detectHeroApkProfile() async {
  return _detectProfile(
    appVariant: 'hero',
    arm64Url: _heroApkUrl,
    universalUrl: _heroApkUrl,
    labelPrefix: 'Hero',
  );
}

Future<DeviceCompatProfile> _detectProfile({
  required String appVariant,
  required String arm64Url,
  required String universalUrl,
  required String labelPrefix,
}) async {
  final os = _detectOs();

  final architecture = os == DeviceOs.android
      ? CpuArchitecture.universal
      : CpuArchitecture.universal;
  final primaryUrl = architecture == CpuArchitecture.arm64
      ? arm64Url
      : universalUrl;
  final primaryLabel = architecture == CpuArchitecture.arm64
      ? '$labelPrefix ARM64 APK'
      : '$labelPrefix Universal APK';

  return DeviceCompatProfile(
    appVariant: appVariant,
    os: os,
    architecture: architecture,
    performanceTier: PerformanceTier.unknown,
    deviceMemoryGb: null,
    hardwareConcurrency: null,
    isDetectionConfident: false,
    primaryDownloadUrl: primaryUrl,
    universalDownloadUrl: universalUrl,
    primaryFileLabel: primaryLabel,
  );
}

DeviceOs _detectOs() {
  if (!kIsWeb) {
    return DeviceOs.unknown;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return DeviceOs.android;
    case TargetPlatform.iOS:
      return DeviceOs.ios;
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return DeviceOs.pc;
    case TargetPlatform.fuchsia:
      return DeviceOs.unknown;
  }
}
