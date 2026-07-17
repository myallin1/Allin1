import 'package:flutter/foundation.dart';

import 'device_compat_service.dart';

const String _customerArm64Url =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-arm64.apk';
const String _customerArmeabiV7aUrl =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-armeabi-v7a.apk';
const String _heroArm64Url =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-arm64.apk';
const String _heroArmeabiV7aUrl =
    'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-armeabi-v7a.apk';

Future<DeviceCompatProfile> detectCustomerApkProfile() async {
  return _detectProfile(
    appVariant: 'customer',
    arm64Url: _customerArm64Url,
    universalUrl: _customerArmeabiV7aUrl,
    labelPrefix: 'Customer',
  );
}

Future<DeviceCompatProfile> detectHeroApkProfile() async {
  return _detectProfile(
    appVariant: 'hero',
    arm64Url: _heroArm64Url,
    universalUrl: _heroArmeabiV7aUrl,
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
  final primaryUrl =
      architecture == CpuArchitecture.arm64 ? arm64Url : universalUrl;
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
