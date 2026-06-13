import 'audio_platform_stub.dart'
    if (dart.library.js) 'audio_platform_web.dart';

class HeroWebAudioService {
  static final HeroWebAudioService _instance = HeroWebAudioService._();
  factory HeroWebAudioService() => _instance;
  HeroWebAudioService._();

  void unlock() => AudioPlatform().unlock();
  void playAlert() => AudioPlatform().playAlert();
}
