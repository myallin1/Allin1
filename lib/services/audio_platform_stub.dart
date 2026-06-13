class AudioPlatform {
  static final AudioPlatform _instance = AudioPlatform._();
  factory AudioPlatform() => _instance;
  AudioPlatform._();

  void unlock() {}
  void playAlert() {}
}
