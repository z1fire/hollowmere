// Tiny procedural audio engine (WebAudio). Everything is synthesized - no asset files.
export class Audio {
  constructor() { this.ctx = null; this.vol = 0.7; this.musicVol = 0.35; this.nextNote = 0; }
  unlock() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.master = this.ctx.createGain(); this.master.gain.value = this.vol; this.master.connect(this.ctx.destination);
      this.music = this.ctx.createGain(); this.music.gain.value = this.musicVol; this.music.connect(this.master);
      const len = this.ctx.sampleRate; const b = this.ctx.createBuffer(1, len, this.ctx.sampleRate); const d = b.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      this.noiseBuf = b;
      // reverb-ish delay for music
      this.delay = this.ctx.createDelay(); this.delay.delayTime.value = 0.32; const fb = this.ctx.createGain(); fb.gain.value = 0.3;
      this.delay.connect(fb); fb.connect(this.delay); this.delay.connect(this.music);
    } catch (e) { this.ctx = null; }
  }
  setVolume(v) { this.vol = v; if (this.master) this.master.gain.value = v; }
  setMusic(v) { this.musicVol = v; if (this.music) this.music.gain.value = v; }
  get ok() { return this.ctx && this.ctx.state === 'running'; }
  tone(freq, dur, type = 'sine', vol = 0.2, slide = 0, delay = 0, dest) {
    if (!this.ok) return;
    const t = this.ctx.currentTime + delay;
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t);
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, freq + slide), t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(dest || this.master); o.start(t); o.stop(t + dur + 0.05);
  }
  noise(dur, freq = 1000, q = 1, vol = 0.3, type = 'bandpass', slide = 0, delay = 0) {
    if (!this.ok) return;
    const t = this.ctx.currentTime + delay;
    const s = this.ctx.createBufferSource(); s.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (slide) f.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), t + dur);
    const g = this.ctx.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(this.master); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.05);
  }
  swing(v = 1) { this.noise(0.18, 600, 0.8, 0.25 * v, 'bandpass', 1800); }
  hit(kind) { if (kind === 'skeleton') { this.noise(0.1, 2500, 3, 0.35); this.tone(300, 0.08, 'square', 0.06, -150); } else { this.noise(0.12, 300, 1, 0.5, 'lowpass'); this.tone(90, 0.12, 'sine', 0.3, -40); } }
  bow() { this.tone(180, 0.15, 'triangle', 0.15, -80); this.noise(0.12, 3000, 2, 0.1, 'highpass'); }
  spell(school) {
    if (school === 'fire') { this.noise(0.5, 400, 1, 0.3, 'lowpass', 800); this.tone(120, 0.4, 'sawtooth', 0.06, 80); }
    else if (school === 'spark') { this.tone(1200, 0.2, 'square', 0.06, -900); this.noise(0.15, 4000, 1, 0.15, 'highpass'); }
    else { this.tone(500, 0.25, 'triangle', 0.1, 300); this.noise(0.2, 1500, 2, 0.1); }
  }
  boom() { this.noise(0.8, 200, 0.7, 0.8, 'lowpass', -150); this.tone(60, 0.6, 'sine', 0.4, -30); }
  heal() { [523, 659, 784].forEach((f, i) => this.tone(f, 0.4, 'sine', 0.1, 0, i * 0.08)); }
  fizzle() { this.noise(0.2, 800, 2, 0.15, 'bandpass', -500); }
  hurt() { this.tone(160, 0.2, 'sawtooth', 0.12, -80); this.noise(0.1, 500, 1, 0.2, 'lowpass'); }
  bite() { this.noise(0.1, 900, 2, 0.35); this.tone(200, 0.08, 'square', 0.06, -100); }
  growl(kind) { if (kind === 'wolf') this.tone(110, 0.5, 'sawtooth', 0.05, -30); else if (kind === 'skeleton') this.noise(0.4, 1200, 8, 0.1); else this.tone(220, 0.3, 'square', 0.04, -100); }
  step(surf) { if (surf === 'wood') this.noise(0.06, 400, 2, 0.12, 'bandpass'); else if (surf === 'water') this.noise(0.15, 900, 1, 0.08, 'lowpass'); else this.noise(0.07, 1400, 0.8, 0.05, 'bandpass'); }
  jump() { this.noise(0.1, 800, 1, 0.08); }
  coin() { this.tone(1320, 0.08, 'square', 0.05); this.tone(1760, 0.18, 'square', 0.05, 0, 0.07); }
  pickup() { this.tone(660, 0.1, 'triangle', 0.1); this.tone(990, 0.12, 'triangle', 0.1, 0, 0.06); }
  drink() { for (let i = 0; i < 3; i++) this.tone(300 + i * 60, 0.08, 'sine', 0.1, 100, i * 0.1); }
  click() { this.tone(900, 0.04, 'square', 0.03); }
  till() { this.noise(0.2, 300, 1, 0.3, 'lowpass'); this.noise(0.1, 1500, 1, 0.1, 'bandpass', 0, 0.05); }
  levelup() { [392, 523, 659, 784, 1046].forEach((f, i) => this.tone(f, 0.35, 'triangle', 0.12, 0, i * 0.09)); }
  quest() { [523, 659, 784, 1046, 784, 1046].forEach((f, i) => this.tone(f, 0.3, 'triangle', 0.1, 0, i * 0.12)); }
  die() { [392, 330, 262, 196].forEach((f, i) => this.tone(f, 0.6, 'triangle', 0.12, 0, i * 0.25)); }
  chest() { this.tone(200, 0.3, 'sawtooth', 0.04, 100); [784, 988, 1175].forEach((f, i) => this.tone(f, 0.3, 'triangle', 0.08, 0, 0.25 + i * 0.08)); }

  // gentle generative lute/harp music. mood: 'day' | 'night' | 'danger'
  updateMusic(mood) {
    if (!this.ok) return;
    const now = this.ctx.currentTime;
    if (now < this.nextNote) return;
    const scales = {
      day: [293.66, 329.63, 369.99, 440, 493.88, 587.33, 659.25, 739.99],
      night: [220, 261.63, 293.66, 329.63, 392, 440, 523.25],
      danger: [146.83, 155.56, 196, 207.65, 220, 293.66],
    };
    const sc = scales[mood] || scales.day;
    const n = sc[Math.floor(Math.random() * sc.length)];
    const pluck = (f, d, v) => {
      const t = this.ctx.currentTime + d;
      const o = this.ctx.createOscillator(), g = this.ctx.createGain(), fl = this.ctx.createBiquadFilter();
      o.type = mood === 'danger' ? 'sawtooth' : 'triangle'; o.frequency.value = f;
      fl.type = 'lowpass'; fl.frequency.setValueAtTime(2400, t); fl.frequency.exponentialRampToValueAtTime(400, t + 1.2);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(v, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + (mood === 'night' ? 2.5 : 1.6));
      o.connect(fl); fl.connect(g); g.connect(this.music); g.connect(this.delay); o.start(t); o.stop(t + 2.6);
    };
    pluck(n, 0, 0.12);
    if (Math.random() < 0.5) pluck(n * 1.5, 0.02, 0.05);
    if (Math.random() < 0.3) pluck(sc[0] / 2, 0, 0.1);
    this.nextNote = now + (mood === 'danger' ? 0.3 + Math.random() * 0.3 : mood === 'night' ? 0.9 + Math.random() * 1.5 : 0.35 + Math.random() * 0.7) * (Math.random() < 0.15 ? 3 : 1);
  }
}
