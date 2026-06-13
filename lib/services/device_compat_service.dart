import 'device_compat_service_stub.dart'
    if (dart.library.html) 'device_compat_service_web.dart' as impl;

enum DeviceOs { android, ios, pc, unknown }

enum CpuArchitecture { arm64, armeabiV7a, x86_64, universal, unknown }

enum PerformanceTier { low, medium, high, unknown }

class DeviceCompatProfile {
  const DeviceCompatProfile({
    required this.appVariant,
    required this.os,
    required this.architecture,
    required this.performanceTier,
    required this.deviceMemoryGb,
    required this.hardwareConcurrency,
    required this.isDetectionConfident,
    required this.primaryDownloadUrl,
    required this.universalDownloadUrl,
    required this.primaryFileLabel,
  });

  final String appVariant;
  final DeviceOs os;
  final CpuArchitecture architecture;
  final PerformanceTier performanceTier;
  final double? deviceMemoryGb;
  final int? hardwareConcurrency;
  final bool isDetectionConfident;
  final String primaryDownloadUrl;
  final String universalDownloadUrl;
  final String primaryFileLabel;

  String get osLabel {
    switch (os) {
      case DeviceOs.android:
        return 'Android';
      case DeviceOs.ios:
        return 'iPhone / iPad';
      case DeviceOs.pc:
        return 'PC';
      case DeviceOs.unknown:
        return 'Unknown';
    }
  }

  String get architectureLabel {
    switch (architecture) {
      case CpuArchitecture.arm64:
        return 'ARM64';
      case CpuArchitecture.armeabiV7a:
        return 'armeabi-v7a';
      case CpuArchitecture.x86_64:
        return 'x86_64';
      case CpuArchitecture.universal:
        return 'Universal';
      case CpuArchitecture.unknown:
        return 'Unknown';
    }
  }

  String get performanceLabel {
    switch (performanceTier) {
      case PerformanceTier.low:
        return 'Low';
      case PerformanceTier.medium:
        return 'Balanced';
      case PerformanceTier.high:
        return 'High';
      case PerformanceTier.unknown:
        return 'Unknown';
    }
  }

  bool get isAndroidLike => os == DeviceOs.android || os == DeviceOs.unknown;
}

class DeviceCompatService {
  DeviceCompatService._();

  static final DeviceCompatService instance = DeviceCompatService._();

  Future<DeviceCompatProfile> detectCustomerApkProfile() {
    return impl.detectCustomerApkProfile();
  }

  Future<DeviceCompatProfile> detectHeroApkProfile() {
    return impl.detectHeroApkProfile();
  }
}
