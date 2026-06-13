import 'device_compat_service.dart';

const String _customerArm64Url =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-arm64.apk';
const String _customerUniversalUrl =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-armeabi-v7a.apk';

Future<DeviceCompatProfile> detectCustomerApkProfile() async {
  return const DeviceCompatProfile(
    appVariant: 'customer',
    os: DeviceOs.unknown,
    architecture: CpuArchitecture.universal,
    performanceTier: PerformanceTier.unknown,
    deviceMemoryGb: null,
    hardwareConcurrency: null,
    isDetectionConfident: false,
    primaryDownloadUrl: _customerArm64Url,
    universalDownloadUrl: _customerUniversalUrl,
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
    primaryDownloadUrl:
        'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-armeabi-v7a.apk',
    universalDownloadUrl:
        'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-armeabi-v7a.apk',
    primaryFileLabel: 'Hero Universal APK',
  );
}
