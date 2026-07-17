import 'dart:js' as js;

class AudioPlatform {
  static final AudioPlatform _instance = AudioPlatform._();
  factory AudioPlatform() => _instance;
  AudioPlatform._();

  bool _unlocked = false;

  void unlock() {
    if (_unlocked) return;
    try {
      final jsWindow = js.context;
      final audioCtxConstructor =
          jsWindow['AudioContext'] ?? jsWindow['webkitAudioContext'];
      if (audioCtxConstructor == null) return;

      final ctx = js.JsObject(audioCtxConstructor as js.JsFunction, []);
      ctx.callMethod('resume');
      final src = ctx.callMethod('createOscillator') as js.JsObject;
      src['type'] = 'sine';
      final freq = src['frequency'] as js.JsObject;
      freq['value'] = 440;
      src.callMethod('start', [0]);
      src.callMethod('stop', [0.05]);
      _unlocked = true;
    } catch (_) {}
  }

  void playAlert() {
    if (!_unlocked) return;
    try {
      final jsWindow = js.context;
      final audioCtxConstructor =
          jsWindow['AudioContext'] ?? jsWindow['webkitAudioContext'];
      if (audioCtxConstructor == null) return;

      final ctx = js.JsObject(audioCtxConstructor as js.JsFunction, []);
      final now = ctx['currentTime'] as num;
      _beep(ctx, 880, 0.3, now);
      _beep(ctx, 660, 0.25, now + 0.3);
      _beep(ctx, 880, 0.3, now + 0.6);
    } catch (_) {}
  }

  void _beep(js.JsObject ctx, num freq, num vol, num startTime) {
    try {
      final osc = ctx.callMethod('createOscillator') as js.JsObject;
      osc['type'] = 'sine';
      (osc['frequency'] as js.JsObject)['value'] = freq;
      final gain = ctx.callMethod('createGain') as js.JsObject;
      (gain['gain'] as js.JsObject)['value'] = vol;
      osc.callMethod('connect', [gain]);
      gain.callMethod('connect', [ctx['destination']]);
      osc.callMethod('start', [startTime]);
      osc.callMethod('stop', [startTime + 0.2]);
    } catch (_) {}
  }
}
