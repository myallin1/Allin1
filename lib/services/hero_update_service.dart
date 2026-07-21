// ================================================================
// hero_update_service.dart — DEPRECATED, kept only as a pointer.
//
// This class was never actually called anywhere in the app (dead
// code). Its job — checking for a new APK and installing it with one
// tap — is now done by AppUpdateChecker (see app_update_checker.dart
// in this same folder), which is wired into both the hero app
// (hero_home_screen.dart) and the customer app (dashboard_screen.dart)
// with a real automatic version check in front of it, instead of
// requiring a manual trigger.
//
// This file is intentionally left empty of logic to avoid two
// competing "how do we install an update" implementations sitting
// side by side. If nothing imports HeroUpdateService anymore, this
// file can be deleted outright in a future cleanup pass.
// ================================================================
