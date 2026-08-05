class PwaCachePlatform {
  Future<void> clearAndReload() async {
    // Android and iOS safe stub
  }

  // Native builds never set the web-only sessionStorage flag, so this
  // always reads as "no, we didn't just self-update" -- matches
  // pwa_cache_platform_web.dart's real implementation's contract.
  bool consumeJustUpdatedFlag() => false;
}
