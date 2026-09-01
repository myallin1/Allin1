// Android and iOS safe stub — native apps use Shorebird OTA instead,
// so this always reports no update and does nothing on tap.
class PwaUpdatePlatform {
  bool get isUpdateAvailable => false;
  void applyUpdate() {}
}
