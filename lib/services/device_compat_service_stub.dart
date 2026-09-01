import 'update_service.dart';
import 'device_compat_service.dart';

// FIX: same broken architecture-split filenames as
// device_compat_service_web.dart — pointed at customer-arm64.apk /
// customer-armeabi-v7a.apk / hero-armeabi-v7a.apk, none of which exist
// in the release. Only allin1-customer.apk / allin1-hero.apk are
// actually uploaded.
// SINGLE SOURCE OF TRUTH (Aug 17 2026 — Nizam: "dowload source git
// orey place ah than irukanum"). These were two more hardcoded copies of
// the release URLs. Every APK link in the app now resolves through
// UpdateService, so changing the release naming is a one-file edit
// instead of a hunt across five files — which is exactly how
// landing_page.dart ended up pointing at a filename that did not exist.
const String _customerApkUrl = UpdateService.customerApkUrl;
const String _heroApkUrl = UpdateService.heroApkUrl;

Future<DeviceCompatProfile> detectCustomerApkProfile() async {
  return const DeviceCompatProfile(
    appVariant: 'customer',
    os: DeviceOs.unknown,
    architecture: CpuArchitecture.universal,
    performanceTier: PerformanceTier.unknown,
    deviceMemoryGb: null,
    hardwareConcurrency: null,
    isDetectionConfident: false,
    primaryDownloadUrl: _customerApkUrl,
    universalDownloadUrl: _customerApkUrl,
    primaryFileLabel: 'Customer Universal APK',
  );
}

Future<DeviceCompatProfile> detectHeroApkProfile() async {
  return const DeviceCompatProfile(
    appVariant: 'hero',
    os: DeviceOs.unknown,
    architecture: CpuArchitecture.universal,
    performanceTier: PerformanceTier.unknown,
    deviceMemoryGb: null,
    hardwareConcurrency: null,
    isDetectionConfident: false,
    primaryDownloadUrl: _heroApkUrl,
    universalDownloadUrl: _heroApkUrl,
    primaryFileLabel: 'Hero Universal APK',
  );
}
