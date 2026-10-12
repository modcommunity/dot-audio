/* dot-audio's ceiling for the browser. Load it before the engine's index.js:
 *
 *   <script src="dot_audio_ceiling.js"></script>
 *
 * A web export in sample playback (the default since 4.3) runs no bus effects, so the
 * HardLimiter dot-audio puts on Master does nothing in a browser, and a pile-up of sounds
 * clips at the speakers: a game measured +3.4 dBFS in Chromium with 187 clipped samples in
 * 40 s. The engine's Web Audio graph is out of a script's reach once it exists, so this
 * wraps the page's AudioContext before the engine makes one: whatever the engine connects to
 * `destination` goes through a limiter first. A fast compressor above -3 dBFS, with the
 * makeup gain Web Audio adds taken off again (or a browser would be louder than a desktop),
 * then a soft clip that never passes -1.5 dBFS. Below -3 dBFS it is exact unity.
 * Measured in dot-audio docs/loudness.md ("The browser's ceiling").
 */
(function () {
  var Base = window.AudioContext || window.webkitAudioContext;
  if (!Base || Base.dotCeiling) return;
  function chain(ctx, speakers) {
    var limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value = 0;
    limiter.ratio.value = 20;
    limiter.attack.value = 0.002;
    limiter.release.value = 0.1;
    // The spec's makeup gain is (1 / the curve's gain at 0 dBFS) ^ 0.6; this is its inverse.
    var trim = ctx.createGain();
    trim.gain.value = Math.pow(10, 0.6 * (-3 + 3 / 20) / 20);
    // A WaveShaper curve spans input -1..1, and input past it reads the end value: the ceiling.
    var clip = ctx.createWaveShaper();
    var n = 4097, curve = new Float32Array(n), ceil = Math.pow(10, -1.5 / 20), knee = Math.pow(10, -4 / 20);
    for (var i = 0; i < n; i++) {
      var x = (i / (n - 1)) * 2 - 1, a = Math.abs(x);
      var y = a <= knee ? a : knee + (ceil - knee) * Math.tanh((a - knee) / (ceil - knee));
      curve[i] = x < 0 ? -y : y;
    }
    clip.curve = curve;
    clip.oversample = '4x';
    limiter.connect(trim);
    trim.connect(clip);
    clip.connect(speakers);
    return limiter;
  }
  function Ceiling(options) {
    var ctx = options === undefined ? new Base() : new Base(options);
    var speakers = ctx.destination;
    var input = chain(ctx, speakers);
    try { Object.defineProperty(input, 'maxChannelCount', { get: function () { return speakers.maxChannelCount; } }); } catch (e) {}
    Object.defineProperty(ctx, 'destination', { configurable: true, get: function () { return input; } });
    return ctx;
  }
  Ceiling.prototype = Base.prototype;
  Ceiling.dotCeiling = true;
  // For a test that renders through the same chain offline.
  window.dotAudioCeiling = chain;
  window.AudioContext = Ceiling;
  if (window.webkitAudioContext) window.webkitAudioContext = Ceiling;
})();
