class UpdateService {
  factory UpdateService() => _instance;
  UpdateService._internal();

  static final UpdateService _instance = UpdateService._internal();

  static const String customerArm64Url =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-arm64.apk';
  static const String customerV7aUrl =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-armeabi-v7a.apk';
  static const String heroArm64Url =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-arm64.apk';
  static const String heroV7aUrl =
      'https://github.com/myallin1/Allin1-update-release/releases/latest/download/hero-armeabi-v7a.apk';

  bool isUpdatePayload(Map<String, dynamic> data) {
    final explicit = _asBool(data['update_available']);
    return explicit ||
        _stringValue(data['apk_url']).isNotEmpty ||
        _stringValue(data['poster_url']).isNotEmpty ||
        _stringValue(data['new_version']).isNotEmpty ||
        _stringValue(data['version_name']).isNotEmpty;
  }

  String fallbackApkUrl(String appVariant) {
    return appVariant == 'hero' ? heroV7aUrl : customerV7aUrl;
  }

  Map<String, dynamic> buildNotificationPayload({
    required String userId,
    required Map<String, dynamic> data,
    required String defaultAppVariant,
    String? title,
    String? body,
    String? messageId,
  }) {
    final appVariant = _stringValue(data['app_variant']).isNotEmpty
        ? _stringValue(data['app_variant'])
        : defaultAppVariant;
    final apkUrl = _stringValue(data['apk_url']).isNotEmpty
        ? _stringValue(data['apk_url'])
        : fallbackApkUrl(appVariant);
    final versionName = _stringValue(data['version_name']).isNotEmpty
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
