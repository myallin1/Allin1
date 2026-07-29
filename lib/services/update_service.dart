class UpdateService {
  factory UpdateService() => _instance;
  UpdateService._internal();

  static final UpdateService _instance = UpdateService._internal();

  // FIX (root cause of "update link shows the app isn't there"): these
  // used to point at customer-arm64.apk / customer-armeabi-v7a.apk /
  // hero-arm64.apk / hero-armeabi-v7a.apk — architecture-split filenames
  // that were never actually uploaded. The real release
  // (github.com/myallin1/Allin1-update-release) only ever contains one
  // universal APK per app: allin1-customer.apk, allin1-hero.apk,
  // allin1-admin.apk. Every download attempt 404'd against the real
  // release. Point at the filenames that are actually uploaded — see
  // NEW_RELEASE_CHECKLIST.md for the exact steps to publish a release
  // these URLs will find.
  static const String customerApkUrl =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-customer.apk';
  static const String heroApkUrl =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-hero.apk';
  static const String adminApkUrl =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-admin.apk';

  bool isUpdatePayload(Map<String, dynamic> data) {
    final explicit = _asBool(data['update_available']);
    return explicit ||
        _stringValue(data['apk_url']).isNotEmpty ||
        _stringValue(data['poster_url']).isNotEmpty ||
        _stringValue(data['new_version']).isNotEmpty ||
        _stringValue(data['version_name']).isNotEmpty;
  }

  String fallbackApkUrl(String appVariant) {
    switch (appVariant) {
      case 'hero':
        return heroApkUrl;
      case 'admin':
        return adminApkUrl;
      default:
        return customerApkUrl;
    }
  }

  Map<String, dynamic> buildNotificationPayload({
    required String userId,
    required Map<String, dynamic> data,
    required String defaultAppVariant, String? title,
    String? body,
    String? messageId,
  }) {
    final appVariant =
        _stringValue(data['app_variant']).isNotEmpty
            ? _stringValue(data['app_variant'])
            : defaultAppVariant;
    final apkUrl =
        _stringValue(data['apk_url']).isNotEmpty
            ? _stringValue(data['apk_url'])
            : fallbackApkUrl(appVariant);
    final versionName =
        _stringValue(data['version_name']).isNotEmpty
            ? _stringValue(data['version_name'])
            : _stringValue(data['new_version']);
    final featureList = _parseFeatureList(
      data['feature_list'] ?? data['release_notes'] ?? data['features'],
    );
    final isUpdate = isUpdatePayload(data);

    return <String, dynamic>{
      'userId': userId,
      'title': _stringValue(title).ifEmpty(
        _stringValue(data['title']).ifEmpty(
          isUpdate ? 'Update ready' : 'Allin1 Update',
        ),
      ),
      'message': _stringValue(body).ifEmpty(
        _stringValue(data['body']).ifEmpty(
          isUpdate
              ? 'A new build is ready. Open the bell to update.'
              : 'You have a new notification.',
        ),
      ),
      'type': _stringValue(data['type']).isNotEmpty
          ? _stringValue(data['type'])
          : isUpdate
              ? 'app_update'
              : 'promo',
      'apk_url': apkUrl,
      'poster_url': _stringValue(data['poster_url']),
      'app_variant': appVariant,
      'version_name': versionName,
      'distribution': _stringValue(data['distribution']).ifEmpty('direct_apk'),
      'feature_list': featureList,
      'binary_update_available': isUpdate,
      'update_available': isUpdate,
      'read': false,
      'createdAt': DateTime.now(),
      'messageId': messageId,
    };
  }

  List<String> _parseFeatureList(raw) {
    if (raw is List) {
      return raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = _stringValue(raw);
    if (text.isEmpty) {
      return const <String>[];
    }
    return text
        .split(RegExp(r'\r?\n|,|•|\|'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  bool _asBool(value) {
    if (value is bool) {
      return value;
    }
    final normalized = _stringValue(value).toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  String _stringValue(value) {
    return value?.toString().trim() ?? '';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
