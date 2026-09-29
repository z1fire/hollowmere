// Animated characters built from the KayKit / Quaternius models.
import * as THREE from 'three';
import { Assets } from './assets.js';
import { mergeGeometries } from './vendor/addons/utils/BufferGeometryUtils.js';

const KAY_ANIMS = {
  idle: 'Idle', walk: 'Walking_A', run: 'Running_A', attack: '1H_Melee_Attack_Chop', attack2: '1H_Melee_Attack_Slice_Diagonal', stab: '1H_Melee_Attack_Stab',
  heavy: '2H_Melee_Attack_Chop', shoot: '2H_Ranged_Shoot', cast: 'Spellcast_Shoot', hit: 'Hit_A', death: 'Death_A', sit: 'Sit_Chair_Idle', talk: 'Interact',
  cheer: 'Cheer', use: 'Use_Item', block: 'Block', punch: 'Unarmed_Melee_Attack_Punch_A', lie: 'Lie_Idle',
};
// kind -> model file, animation rig, scale, clip-name overrides
const KINDS = {
  knight: { file: 'knight', rig: 'kaykit', scale: 0.95 }, barbarian: { file: 'barbarian', rig: 'kaykit', scale: 0.95 },
  mage: { file: 'mage', rig: 'kaykit', scale: 0.95 }, rogue: { file: 'rogue', rig: 'kaykit', scale: 0.95 }, rogue_hooded: { file: 'rogue_hooded', rig: 'kaykit', scale: 0.95 },
  skeleton_minion: { file: 'skeleton_minion', rig: 'kaykit', scale: 0.95, anims: { walk: 'Walking_C', run: 'Running_C', death: 'Death_C_Skeletons', idle: 'Idle_Combat' } },
  skeleton_warrior: { file: 'skeleton_warrior', rig: 'kaykit', scale: 0.98, anims: { walk: 'Walking_C', run: 'Running_C', death: 'Death_C_Skeletons', idle: 'Idle_Combat' } },
  skeleton_rogue: { file: 'skeleton_rogue', rig: 'kaykit', scale: 0.95, anims: { walk: 'Walking_C', run: 'Running_C', death: 'Death_C_Skeletons', idle: 'Idle_Combat' } },
  skeleton_mage: { file: 'skeleton_mage', rig: 'kaykit', scale: 0.95, anims: { walk: 'Walking_C', run: 'Running_C', death: 'Death_C_Skeletons', idle: 'Idle_Combat' } },
  orc: { file: 'orc', rig: 'orc', scale: 0.42, anims: { idle: 'Idle', walk: 'Walk', run: 'Run', attack: 'Weapon', attack2: 'Punch', hit: 'HitReact', death: 'Death', talk: 'Wave', shoot: 'Weapon' } },
  wolf: { file: 'wolf', rig: 'wolf', scale: 0.32, anims: { idle: 'Idle', walk: 'Walk', run: 'Gallop', attack: 'Attack', hit: 'Idle_HitReact_Left', death: 'Death' } },
  spider: { file: 'spider', rig: 'spider', scale: 0.26, anims: { idle: 'Spider_Idle', walk: 'Spider_Walk', run: 'Spider_Walk', attack: 'Spider_Attack', death: 'Spider_Death' } },
};

const merged = new Set();
// KayKit characters come as 6+ skinned parts sharing one skeleton and texture: merge them into one draw call.
function mergeSkinnedParts(root) {
  if (merged.has(root)) return; merged.add(root);
  const byMat = new Map();
  root.traverse((o) => { if (o.isSkinnedMesh) { const k = o.material.uuid; if (!byMat.has(k)) byMat.set(k, []); byMat.get(k).push(o); } });
  for (const parts of byMat.values()) {
    if (parts.length < 2) continue;
    const base = parts[0];
    const geos = parts.map((p) => {
      const g = new THREE.BufferGeometry(); const n = p.geometry.attributes.position.count;
      const f = (a, size, T = Float32Array) => { const out = new T(n * size); for (let i = 0; i < n; i++) for (let k = 0; k < size; k++) out[i * size + k] = a.getComponent(i, k); return new THREE.BufferAttribute(out, size); };
      g.setAttribute('position', f(p.geometry.attributes.position, 3));
      g.setAttribute('normal', f(p.geometry.attributes.normal, 3));
      g.setAttribute('uv', f(p.geometry.attributes.uv, 2));
      g.setAttribute('skinIndex', f(p.geometry.attributes.skinIndex, 4, Uint16Array));
      g.setAttribute('skinWeight', f(p.geometry.attributes.skinWeight, 4));
      g.setIndex(p.geometry.index ? Array.from(p.geometry.index.array) : [...Array(n).keys()]);
      return g;
    });
    const m = new THREE.SkinnedMesh(mergeGeometries(geos), base.material);
    m.name = 'Body'; m.position.copy(base.position); m.quaternion.copy(base.quaternion); m.scale.copy(base.scale);
    base.parent.add(m);
    m.bind(base.skeleton, base.bindMatrix);
    for (const p of parts) p.parent.remove(p);
  }
}

// Recolor clothing (keeps skin tones & greys) for NPC variety. Cached per texture+tint.
const recolorCache = new Map();
function recolor(tex, hueShift, satMul = 1, lightMul = 1) {
  const key = tex.uuid + hueShift + '|' + satMul + '|' + lightMul;
  if (recolorCache.has(key)) return recolorCache.get(key);
  // KayKit textures are palette atlases, so a 256px copy loses nothing
  const img = tex.image; const w = Math.min(256, img.width), h = Math.min(256, img.height);
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const x = c.getContext('2d'); x.imageSmoothingEnabled = false; x.drawImage(img, 0, 0, w, h);
  const d = x.getImageData(0, 0, w, h); const p = d.data;
  for (let i = 0; i < p.length; i += 4) {
    const r = p[i] / 255, g = p[i + 1] / 255, b = p[i + 2] / 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, dd = mx - mn;
    if (dd < 1e-4) continue;
    const sat = l > 0.5 ? dd / (2 - mx - mn) : dd / (mx + mn);
    let hh = mx === r ? (g - b) / dd + (g < b ? 6 : 0) : mx === g ? (b - r) / dd + 2 : (r - g) / dd + 4; hh /= 6;
    // keep skin, hair and leather (reds/oranges/browns) - only re-dye the other clothing colours
    const skin = (hh < 0.15 || hh > 0.97) && sat < 0.9;
    if (skin || sat < 0.12) continue;
    const H = (hh + hueShift + 1) % 1, S = Math.min(1, sat * satMul), L = Math.min(1, l * lightMul);
    const q = L < 0.5 ? L * (1 + S) : L + S - L * S, pp = 2 * L - q;
    const f = (t) => { t = (t + 1) % 1; return t < 1 / 6 ? pp + (q - pp) * 6 * t : t < 0.5 ? q : t < 2 / 3 ? pp + (q - pp) * (2 / 3 - t) * 6 : pp; };
    p[i] = f(H + 1 / 3) * 255; p[i + 1] = f(H) * 255; p[i + 2] = f(H - 1 / 3) * 255;
  }
  x.putImageData(d, 0, 0);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.flipY = tex.flipY; t.magFilter = THREE.NearestFilter; t.generateMipmaps = false; t.minFilter = THREE.LinearFilter;
  recolorCache.set(key, t);
  return t;
}

export class Actor {
  // opts: { show: [meshNames], right: weaponPropName, left: weaponPropName, hue, sat, light, scale, ownMaterials }
  constructor(kind, opts = {}) {
    const def = KINDS[kind]; if (!def) throw new Error('unknown actor ' + kind);
    this.kind = kind; this.def = def;
    if (def.rig === 'kaykit') mergeSkinnedParts(Assets.chars[def.file].scene);
    this.root = new THREE.Group();
    this.model = Assets.character(def.file);
    this.model.scale.setScalar(def.scale * (opts.scale || 1));
    this.root.add(this.model);
    const show = new Set(opts.show || []);
    this.materials = [];
    this.model.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = true; o.receiveShadow = false; o.frustumCulled = false;
      if (def.rig === 'kaykit' && !o.isSkinnedMesh) o.visible = show.has(o.name);
      if (opts.hue !== undefined || opts.sat !== undefined || opts.light !== undefined) {
        if (o.material.map) { o.material = o.material.clone(); o.material.map = recolor(o.material.map, opts.hue || 0, opts.sat ?? 1, opts.light ?? 1); }
      }
      if (opts.ownMaterials) { o.material = o.material.clone(); }
      this.materials.push(o.material);
    });
    // weapons from the prop bundle, attached to the hand bones
    for (const side of ['right', 'left']) {
      if (!opts[side]) continue;
      const bone = this.model.getObjectByName(side === 'right' ? 'handslot.r' : 'handslot.l');
      if (!bone) continue;
      const w = Assets.node('weapons', opts[side]).clone(true);
      w.position.set(0, 0, 0); w.rotation.set(0, 0, 0);
      w.traverse((m) => { if (m.isMesh) { m.castShadow = true; if (opts.ownMaterials) m.material = m.material.clone(); this.materials.push(m.material); } });
      bone.add(w);
    }
    this.mixer = new THREE.AnimationMixer(this.model);
    this.clips = Assets.clips[def.rig];
    this.actions = new Map();
    this.base = null; this.oneShot = null; this.dead = false;
    this.mixer.addEventListener('finished', (e) => {
      if (this.oneShot && e.action === this.oneShot.action) {
        const cb = this.oneShot.onDone; this.oneShot = null;
        if (!this.dead && this.base) { this.base.reset().fadeIn(0.2).play(); e.action.fadeOut(0.2); }
        cb?.();
      }
    });
    this.setBase('idle');
  }
  clipName(n) { return this.def.anims?.[n] ?? (this.def.rig === 'kaykit' ? KAY_ANIMS[n] : n); }
  action(n) {
    const name = this.clipName(n);
    if (!name) return null;
    if (!this.actions.has(name)) {
      const clip = this.clips.find((c) => c.name === name);
      this.actions.set(name, clip ? this.mixer.clipAction(clip) : null);
    }
    return this.actions.get(name);
  }
  setBase(n, timeScale = 1) {
    const a = this.action(n) || this.action('idle');
    if (!a) return;
    a.timeScale = timeScale;
    if (a === this.base) return;
    const prev = this.base; this.base = a;
    a.reset().setLoop(THREE.LoopRepeat).fadeIn(0.25).play();
    if (prev && !this.oneShot) prev.fadeOut(0.25);
    if (this.oneShot) a.weight = 0;
  }
  // locomotion by speed (m/s)
  move(speed) {
    if (this.dead) return;
    if (speed < 0.2) this.setBase('idle');
    else if (speed < 3.2) this.setBase('walk', Math.max(0.6, speed / 1.8));
    else this.setBase('run', Math.max(0.7, speed / 5));
  }
  play(n, { speed = 1, onDone, hold = false } = {}) {
    const a = this.action(n); if (!a) { onDone?.(); return 0; }
    if (this.oneShot?.action && this.oneShot.action !== a) this.oneShot.action.fadeOut(0.1);
    a.reset(); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.timeScale = speed;
    a.fadeIn(0.1).play();
    if (this.base && this.base !== a) this.base.fadeOut(0.1);
    this.oneShot = { action: a, onDone };
    if (hold) this.dead = true;
    return a.getClip().duration / speed;
  }
  die() { this.dead = true; this.play('death', { hold: true }); }
  revive() {
    this.dead = false; this.oneShot = null; this.mixer.stopAllAction(); this.base = null; this.setBase('idle');
  }
  flash(v) { for (const m of this.materials) if (m.emissive) m.emissive.setRGB(v, v * 0.15, v * 0.1); }
  update(dt) { this.mixer.update(dt); }
}

// First-person held item models (cloned from the prop bundles)
export function heldModel(bundle, name) {
  const o = Assets.node(bundle, name).clone(true);
  o.position.set(0, 0, 0); o.rotation.set(0, 0, 0);
  o.traverse((m) => { if (m.isMesh) { m.castShadow = false; m.frustumCulled = false; } });
  return o;
}
