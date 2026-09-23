/// Build environment flag, shared across all app flavors.
///
/// Set at build time with `--dart-define=APP_ENV=staging` (or `prod`).
/// Because [env] and [isStaging] are `const`, a prod build (no flag, or
/// `APP_ENV=prod`) folds `AppEnv.isStaging` to a compile-time `false`, so any
/// `if (AppEnv.isStaging) { ... }` block and the tester-only widgets are
/// tree-shaken out of the release binary entirely.
///
/// This file is intentionally self-contained so it can be copy-pasted as-is
/// into the other apps (Vida Key, Accounting AI) - same pattern everywhere.
class AppEnv {
  const AppEnv._();

  /// The raw environment name. Defaults to 'prod' when no flag is passed.
  static const String env = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'prod',
  );

  /// True only in staging/tester builds. Compile-time const → dead-code
  /// eliminated in prod.
  static const bool isStaging = env == 'staging';

  /// True in production builds (the default).
  static const bool isProd = !isStaging;
}
