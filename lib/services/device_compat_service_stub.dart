import 'device_compat_service.dart';

// FIX: same broken architecture-split filenames as
// device_compat_service_web.dart — pointed at customer-arm64.apk /
// customer-armeabi-v7a.apk / hero-armeabi-v7a.apk, none of which exist
// in the release. Only allin1-customer.apk / allin1-hero.apk are
// actually uploaded.
const String _customerApkUrl =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-customer.apk';
const String _heroApkUrl =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-hero.apk';

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
