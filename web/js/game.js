import * as THREE from 'three';
import { World } from './world.js';
import { Player } from './player.js';
import { Input } from './input.js';
import { UI } from './ui.js';
import { Combat } from './combat.js';
import { NPC, Enemy } from './entities.js';
import { RNG, clamp } from './util.js';
import { ITEMS, CROPS, QUESTS, ROLES, LORE, NAMES, ENEMIES } from './data.js';
import { checkForUpdate } from './update.js';
import { Assets } from './assets.js';
import { EffectComposer } from './vendor/addons/postprocessing/EffectComposer.js';
import { RenderPass } from './vendor/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from './vendor/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from './vendor/addons/postprocessing/OutputPass.js';
import { ShaderPass } from './vendor/addons/postprocessing/ShaderPass.js';
import { mergeGeometries } from './vendor/addons/utils/BufferGeometryUtils.js';

// Final colour grade: gentle warmth, contrast, saturation and a vignette.
const GradeShader = {
  uniforms: { tDiffuse: { value: null }, uVignette: { value: 0.32 }, uSat: { value: 1.1 }, uNight: { value: 0 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uVignette, uSat, uNight; varying vec2 vUv;
    void main(){ vec4 c = texture2D(tDiffuse, vUv); vec3 col = c.rgb;
      float l = dot(col, vec3(0.299, 0.587, 0.114));
      col = mix(vec3(l), col, uSat);
      col = (col - 0.5) * 1.06 + 0.5;
      col *= mix(vec3(1.03, 1.0, 0.95), vec3(0.9, 0.95, 1.08), uNight);
      vec2 d = vUv - 0.5; col *= 1.0 - dot(d, d) * uVignette * 2.2;
      gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a); }`,
};

const SAVE_KEY = 'hollowmere_save_v1';
const SEC_PER_HOUR = 30;

export class Game {
  constructor({ seed, saveData, settings, audio, version, onProgress }) {
    this.settings = settings; this.audio = audio; this.version = version;
    this.running = false; this.day = 1; this.hours = 8;
    const q = settings.quality;
    const r = this.renderer = new THREE.WebGLRenderer({ canvas: document.getElementById('c'), antialias: q !== 'low', powerPreference: 'high-performance' });
    r.setPixelRatio(q === 'low' ? Math.min(devicePixelRatio, 1) : q === 'med' ? Math.min(devicePixelRatio, 1.5) : Math.min(devicePixelRatio, 2));
    r.shadowMap.enabled = q !== 'low'; r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.toneMapping = THREE.ACESFilmicToneMapping; r.toneMappingExposure = 1.05;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(settings.fov, innerWidth / innerHeight, 0.08, 620);
    this.scene.add(this.camera);
    this.clock = new THREE.Clock();

    if (saveData) seed = saveData.seed;
    this.seed = seed;
    onProgress?.('Shaping the land...');
    this.world = new World(this.scene, r, seed, q);
    this.setupPost();
    this.combat = new Combat(this);
    this.player = new Player(this);
    this.ui = new UI(this);
    this.input = new Input(this);
    this.applySettings();

    // NPCs
    const R = new RNG(seed + 99);
    const used = new Set();
    const nameFor = () => { let n; for (let i = 0; i < 50; i++) { n = R.pick(R.chance(0.5) ? NAMES.m : NAMES.f); if (!used.has(n)) break; } used.add(n); return n; };
    this.npcs = [];
    const spots = [...this.world.npcSpots];
    for (const b of this.world.buildings) spots.push(...(b.npcs || []));
    for (const s of spots) this.npcs.push(new NPC(this, s, R, nameFor()));
    const W = this.world;
    for (let i = 0; i < 7; i++) {
      const wi = R.int(0, W.waypoints.length - 1); const wp = W.waypoints[wi];
      this.npcs.push(new NPC(this, { role: 'villager', x: wp.x, z: wp.z, wander: true, wp: wi }, R, nameFor()));
    }
    // enemies
    this.enemies = W.spawns.map((s) => new Enemy(this, s));
    // farm plots
    this.farm = new Farm(this);
    // quests
    this.quests = {}; for (const id of Object.keys(QUESTS)) this.quests[id] = { state: 'available', progress: 0 };

    // spawn / load
    if (saveData) this.loadSave(saveData);
    else {
      const sp = W.spawnPoint; this.player.pos.set(sp.x, W.groundAt(sp.x, sp.z), sp.z); this.player.yaw = sp.yaw;
    }
    this.player.vm.set(this.player.held());
    this.player.updateCamera(0, 0);
    addEventListener('resize', () => this.resize()); this.resize();
    this.autosaveT = 60; this.focus = null; this.markerT = 0;
    window.game = this;
  }

  start(isNew) {
    this.running = true;
    this.clock.getDelta();
    this.renderer.setAnimationLoop(() => this.frame());
    document.getElementById('hud').classList.remove('hidden');
    document.getElementById('touchUI').classList.remove('hidden');
    if (isNew) {
      setTimeout(() => this.ui.banner('Hollowmere', 'Your family farm awaits. Speak with the old farmer.'), 600);
      setTimeout(() => this.ui.toast('Tip: talk to villagers with a ❗ above their heads'), 4500);
    }
    this.checkUpdate(false);
  }

  setupPost() {
    const q = this.settings.quality, r = this.renderer;
    if (q === 'low') { this.composer = null; return; }
    const size = r.getDrawingBufferSize(new THREE.Vector2());
    const rt = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: q === 'high' ? 4 : 2 });
    const c = this.composer = new EffectComposer(r, rt);
    c.addPass(new RenderPass(this.scene, this.camera));
    this.vmPass = new RenderPass(null, null); this.vmPass.clear = false; this.vmPass.clearDepth = true;
    c.addPass(this.vmPass);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(size.x / 2, size.y / 2), 0.32, 0.55, 0.88);
    c.addPass(this.bloom);
    c.addPass(new OutputPass());
    this.grade = new ShaderPass(GradeShader);
    c.addPass(this.grade);
  }

  resize() {
    const w = innerWidth, h = innerHeight;
    this.renderer.setSize(w, h);
    if (this.composer) { this.composer.setPixelRatio(this.renderer.getPixelRatio()); this.composer.setSize(w, h); }
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
    this.combat.setScale(this.renderer.domElement.height / 2 / Math.tan((this.camera.fov * Math.PI) / 360));
    const mm = document.getElementById('minimap'); const s = Math.round(clamp(Math.min(w, h) * 0.26, 100, 190));
    mm.width = mm.height = s * Math.min(devicePixelRatio, 2); mm.style.width = mm.style.height = `${s}px`;
  }
  applySettings() {
    const s = this.settings;
    this.input && (this.input.sens = s.sens);
    this.audio.setVolume(s.vol); this.audio.setMusic(s.music * 0.6);
    this.camera.fov = s.fov; this.camera.updateProjectionMatrix();
    if (this.combat) this.combat.setScale(this.renderer.domElement.height / 2 / Math.tan((s.fov * Math.PI) / 360));
    this.saveSettings();
  }
  saveSettings() { try { localStorage.setItem('hollowmere_settings', JSON.stringify(this.settings)); } catch (e) { /* ignore */ } }

  // ---------- main loop ----------
  frame() {
    const dt = Math.min(0.05, this.clock.getDelta());
    const t = this.clock.elapsedTime;
    const P = this.player, W = this.world;
    this.input.update();
    const frozen = this.ui.modalOpen;
    // time of day
    this.hours += dt / SEC_PER_HOUR;
    if (this.hours >= 24) { this.hours -= 24; this.day++; }
    P.update(dt, this.input, frozen);
    for (const n of this.npcs) n.update(dt, t, P.pos);
    let danger = false;
    for (const e of this.enemies) { e.update(dt, t, P); if (!e.dead && e.state === 'chase' && e.pos.distanceTo(P.pos) < 25) danger = true; }
    this.combat.update(dt);
    this.farm.update(dt);
    W.update(dt, this.hours, P.pos, this.camera);
    this.updateFocus();
    this.updateHerbs(dt);
    this.markerT -= dt; if (this.markerT <= 0) { this.markerT = 0.5; this.updateMarkers(); }
    this.ui.update(dt);
    this.audio.updateMusic(danger ? 'danger' : W.night > 0.6 ? 'night' : 'day');
    this.autosaveT -= dt; if (this.autosaveT <= 0) { this.autosaveT = 60; this.save(true); }
    // render world, then the held item on top
    const r = this.renderer;
    P.vm.scene.environment = this.scene.environment;
    if (this.composer) {
      this.vmPass.scene = P.vm.scene; this.vmPass.camera = P.vm.camera; this.vmPass.enabled = !P.dead;
      this.grade.uniforms.uNight.value = W.night;
      this.bloom.strength = 0.25 + W.night * 0.35;
      this.composer.render(dt);
    } else {
      r.render(this.scene, this.camera);
      if (!P.dead) { r.autoClear = false; r.clearDepth(); r.render(P.vm.scene, P.vm.camera); r.autoClear = true; }
    }
  }

  // ---------- interaction ----------
  updateFocus() {
    const P = this.player; if (P.dead) { this.focus = null; return; }
    const f = P.forward; let best = null, bs = 1e9;
    for (const it of this.world.interactables) {
      if (it.type === 'herb' && it.respawn > 0) continue;
      const dx = it.x - P.pos.x, dz = it.z - P.pos.z, d = Math.hypot(dx, dz);
      if (d > it.r || Math.abs(it.y - (P.pos.y + 1)) > 2.5) continue;
      const dot = (dx * f.x + dz * f.z) / (d || 1);
      if (dot < 0.25 && d > 1.2) continue;
      const s = d - dot * 1.5;
      if (s < bs) { bs = s; best = it; }
    }
    // farm plots
    if (!best || best.type !== 'npc') {
      const p = P.targetPlot();
      if (p) {
        const h = P.held();
        let label = null;
        if (p.state === 'planted' && this.farm.ripe(p)) label = `Harvest ${ITEMS[p.crop].name}`;
        else if (p.state === 'planted') label = `${ITEMS[p.crop].name} growing (${Math.floor(this.farm.progress(p) * 100)}%)`;
        else if (p.state === 'grass') label = h?.id === 'hoe' ? 'Till soil' : 'Weedy soil - use your Hoe';
        else if (p.state === 'tilled') label = h?.kind === 'seed' ? `Plant ${h.name}` : 'Tilled soil - select seeds to plant';
        if (label && (!best || bs > 0.5)) best = { type: 'plot', plot: p, label, x: p.x, y: p.y, z: p.z };
      }
    }
    this.focus = best;
  }
  interact() {
    this.audio.unlock();
    const it = this.focus; if (!it || this.player.dead) return;
    const P = this.player, U = this.ui;
    switch (it.type) {
      case 'npc': this.talkTo(it.npc); break;
      case 'plot': {
        const p = it.plot, h = P.held();
        if (p.state === 'planted' && this.farm.ripe(p)) this.farm.harvest(p);
        else if (p.state === 'grass' && h?.id === 'hoe') this.farm.till(p);
        else if (p.state === 'tilled' && h?.kind === 'seed') this.farm.plant(p, h.id);
        else U.toast(it.label);
        break;
      }
      case 'bed': {
        const night = this.hours >= 19 || this.hours < 5;
        P.hp = P.maxHp; P.mp = P.maxMp;
        if (night) { this.sleep(); U.banner('You slept soundly', `Day ${this.day} · Game saved`); }
        else { U.toast('You rest a moment. Health restored. Game saved.'); }
        this.save();
        break;
      }
      case 'board': U.open('board'); break;
      case 'well': {
        if ((this.wellT || 0) > this.clock.elapsedTime) { U.toast('The water is cool and refreshing.'); break; }
        this.wellT = this.clock.elapsedTime + 30;
        P.hp = Math.min(P.maxHp, P.hp + 20); P.mp = Math.min(P.maxMp, P.mp + 10);
        this.combat.healFx(P.pos.clone().setY(P.pos.y + 1)); this.audio.drink(); U.toast('You drink from the well. +20 Health');
        break;
      }
      case 'herb': {
        P.addItem('moonpetal', 1); it.respawn = 180; it.mesh.visible = false;
        P.gainXP('nature', 4); this.audio.pickup(); U.toast('Picked a Moonpetal 🌸', '#8ad8ff');
        this.checkCollectQuests();
        break;
      }
      case 'chest': {
        if (it.openedDay === this.day) { U.toast('Empty. Maybe it refills tomorrow...'); break; }
        it.openedDay = this.day; it.lid.rotation.x = -1.9;
        const R = Math.random;
        const gold = 15 + Math.floor(R() * 35); P.gold += gold;
        const pool = ['hp_potion', 'mp_potion', 'old_coin', 'hp_potion', 'leather', 'hunting_bow', 'iron_sword', 'tome_thorns', 'tome_sparks', 'pumpkin_seed'];
        const item = pool[Math.floor(R() * pool.length)];
        P.addItem(item, 1); this.audio.chest();
        U.toast(`Found ${gold} gold and ${ITEMS[item].name}!`, '#ffd23a'); U.dirty = true;
        this.combat.levelFx(new THREE.Vector3(it.x, it.y + 0.4, it.z), '#ffd23a');
        break;
      }
      case 'crypt': U.toast('The crypt is sealed by an ancient ward. (Coming in a future update)', '#66ffcc'); break;
      case 'mine': U.banner('The Collapsed Mine', 'Rubble blocks the way. A new region will open here in a future update.'); break;
    }
  }
  sleep() {
    if (this.hours >= 19) this.day++;
    this.hours = 7;
    for (const c of this.world.chests) if (c.openedDay < this.day) c.lid.rotation.x = 0;
  }
  updateHerbs(dt) {
    for (const h of this.world.herbs) if (h.respawn > 0) { h.respawn -= dt; if (h.respawn <= 0) h.mesh.visible = true; }
    for (const c of this.world.chests) if (c.openedDay !== this.day && c.lid.rotation.x !== 0) c.lid.rotation.x = 0;
  }
  quickPotion(kind) {
    const P = this.player;
    const order = kind === 'hp' ? ['hp_potion', 'stew', 'bread', 'carrot'] : ['mp_potion', 'stew'];
    const id = order.find((i) => P.count(i) > 0);
    if (!id) { this.ui.toast(kind === 'hp' ? 'No healing items' : 'No mana potions'); return; }
    P.consume(id);
  }

  // ---------- dialogue & quests ----------
  talkTo(npc, text) {
    npc.talking = true;
    const role = ROLES[npc.role];
    const greet = text || (this.player.cls.line !== 'farming' && Math.random() < 0.35 ? `Well met, ${this.player.cls.title}. ${role.lines[Math.floor(Math.random() * role.lines.length)]}` : role.lines[Math.floor(Math.random() * role.lines.length)]);
    this.ui.open('dialog', { npc, text: greet });
  }
  questReady(id) {
    const q = this.quests[id], d = QUESTS[id];
    if (q.state !== 'active') return false;
    return d.type === 'kill' ? q.progress >= d.count : this.player.count(d.item) >= d.count;
  }
  dialogOptions(npc) {
    const role = ROLES[npc.role], P = this.player, opts = [];
    const say = (text) => this.ui.open('dialog', { npc, text });
    if (role.quest) {
      const id = role.quest, q = this.quests[id], d = QUESTS[id];
      if (q.state === 'available') opts.push({ label: `❗ ${d.title}`, cls: 'quest', fn: () => this.ui.open('dialog', { npc, text: d.offer, offer: id }) });
      else if (this.questReady(id)) opts.push({ label: `✅ Complete: ${d.title}`, cls: 'quest', fn: () => { this.completeQuest(id); say(d.thanks); } });
      else if (q.state === 'active') opts.push({ label: `… ${d.title}`, fn: () => say(`${d.desc} ${d.type === 'kill' ? `(${q.progress}/${d.count})` : `(${P.count(d.item)}/${d.count})`}`) });
    }
    if (this.ui.data?.offer && this.ui.data.npc === npc) {
      const id = this.ui.data.offer;
      return [
        { label: '✔ Accept', cls: 'quest', fn: () => { this.quests[id].state = 'active'; this.quests[id].progress = 0; this.audio.quest(); this.ui.toast(`New quest: ${QUESTS[id].title}`, '#ffd23a'); this.ui.dirty = true; say('Good. Come back to me when it\'s done.'); this.checkCollectQuests(); } },
        { label: 'Not now', fn: () => say('Suit yourself.') },
      ];
    }
    if (role.shop) opts.push({ label: '🛒 Trade', fn: () => { this.ui.shopTab = 'buy'; this.ui.open('shop', { shop: role.shop, npc }); } });
    if (role.service === 'rest') opts.push({ label: '🛏️ Rent a room (10 gold)', fn: () => {
      if (P.gold < 10) return say('Ten gold for a room, love. Come back when you have it.');
      P.gold -= 10; P.hp = P.maxHp; P.mp = P.maxMp; this.sleep(); this.save(); this.ui.dirty = true; this.audio.coin();
      this.ui.close(); this.ui.banner('A good night\'s rest', `Day ${this.day} · Game saved`);
    } });
    if (role.service === 'heal') opts.push({ label: '✨ Heal me', fn: () => { P.hp = P.maxHp; P.mp = P.maxMp; this.combat.healFx(P.pos.clone().setY(P.pos.y + 1)); this.audio.heal(); say('Go with the Light, child. You are mended.'); } });
    opts.push({ label: '💬 Chat', fn: () => say(role.lines[Math.floor(Math.random() * role.lines.length)]) });
    opts.push({ label: '📜 Any news?', fn: () => say(LORE[Math.floor(Math.random() * LORE.length)]) });
    opts.push({ label: 'Goodbye', fn: () => this.ui.close() });
    return opts;
  }
  completeQuest(id) {
    const q = this.quests[id], d = QUESTS[id], P = this.player;
    if (d.type === 'collect' && d.consume) P.removeItem(d.item, d.count);
    q.state = 'done';
    P.gold += d.reward.gold;
    for (const [it, n] of d.reward.items) P.addItem(it, n);
    for (const [sk, xp] of Object.entries(d.reward.xp || {})) P.gainXP(sk, xp);
    this.audio.quest();
    this.ui.banner('Quest Complete', `${d.title} · +${d.reward.gold} gold${d.reward.items.map(([i]) => ', ' + ITEMS[i].name).join('')}`);
    this.ui.dirty = true; this.save(true);
  }
  checkCollectQuests() {
    for (const [id, q] of Object.entries(this.quests)) if (q.state === 'active' && QUESTS[id].type === 'collect' && this.questReady(id) && !q.notified) { q.notified = true; this.ui.toast(`${QUESTS[id].title}: ready to turn in!`, '#ffd23a'); }
    this.ui.dirty = true;
  }
  updateMarkers() {
    for (const n of this.npcs) {
      if (!n.marker) continue;
      const id = ROLES[n.role].quest; const q = this.quests[id];
      n.setMarker(q.state === 'available' ? '!' : this.questReady(id) ? '?' : null);
    }
  }
  onKill(e, skill) {
    const d = e.def, P = this.player, U = this.ui;
    P.gainXP(skill, d.xp);
    const gold = d.gold[0] + Math.floor(Math.random() * (d.gold[1] - d.gold[0] + 1));
    P.gold += gold; this.audio.coin();
    const loot = [];
    for (const [id, ch] of d.drops) if (Math.random() < ch) { P.addItem(id, 1); loot.push(ITEMS[id].name); }
    U.toast(`${d.name} defeated · +${gold} gold${loot.length ? ' · ' + loot.join(', ') : ''}`, d.boss ? '#ff8a1a' : undefined);
    for (const [id, q] of Object.entries(this.quests)) {
      const qd = QUESTS[id];
      if (q.state === 'active' && qd.type === 'kill' && qd.target === d.group) {
        q.progress++;
        if (q.progress <= qd.count) U.toast(`${qd.title}: ${q.progress}/${qd.count}`, '#ffd23a');
      }
    }
    if (d.boss) U.banner('The Warchief has fallen!', 'Return to the Mayor with the news');
    this.checkCollectQuests();
    U.dirty = true;
  }
  onDeath() {
    this.audio.die();
    const d = document.getElementById('death'); d.classList.remove('hidden');
    const lost = Math.floor(this.player.gold * 0.1);
    d.querySelector('p').textContent = `You lost ${lost} gold. You'll wake up at home.`;
    setTimeout(() => {
      const P = this.player, W = this.world;
      P.gold -= lost; P.dead = false; P.hp = P.maxHp; P.mp = P.maxMp;
      const bp = W.bedPoint; P.pos.set(bp.x, W.groundAt(bp.x, bp.z, 99), bp.z); P.yaw = bp.yaw; P.pitch = 0; P.vy = 0;
      for (const e of this.enemies) if (!e.dead) { e.state = 'return'; }
      d.classList.add('hidden'); this.ui.dirty = true;
    }, 3500);
  }

  // ---------- save/load ----------
  save(silent) {
    if (!this.running) return;
    try {
      const data = {
        v: 1, seed: this.seed, day: this.day, hours: this.hours, player: this.player.serialize(), quests: this.quests,
        plots: this.world.plots.map((p) => ({ s: p.state, c: p.crop, t: p.t })), chests: this.world.chests.map((c) => c.openedDay), savedAt: Date.now(),
      };
      localStorage.setItem(SAVE_KEY, JSON.stringify(data));
      if (!silent) this.ui.toast('💾 Game saved');
    } catch (e) { if (!silent) this.ui.toast('Could not save!'); }
  }
  loadSave(d) {
    this.day = d.day; this.hours = d.hours;
    this.player.load(d.player);
    if (d.player.y < this.world.heightAt(d.player.x, d.player.z) - 1) this.player.pos.y = this.world.groundAt(d.player.x, d.player.z, 99);
    for (const [id, q] of Object.entries(d.quests || {})) if (this.quests[id]) this.quests[id] = q;
    (d.plots || []).forEach((s, i) => { const p = this.world.plots[i]; if (p) { p.state = s.s; p.crop = s.c; p.t = s.t; this.farm.refresh(p); } });
    (d.chests || []).forEach((o, i) => { if (this.world.chests[i]) this.world.chests[i].openedDay = o; });
  }
  static loadData() { try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch (e) { return null; } }
  static clearSave() { try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ignore */ } }

  async checkUpdate(manual) {
    const res = await checkForUpdate(this.version);
    if (res && res.available) {
      const b = document.getElementById('updateBanner');
      b.innerHTML = `<span>⬆️ Update <b>v${res.version}</b> is available!</span><button id="updGet">Download</button><button id="updX">✕</button>`;
      b.classList.remove('hidden');
      document.getElementById('updGet').onclick = () => { this.save(true); res.open(); };
      document.getElementById('updX').onclick = () => b.classList.add('hidden');
    } else if (manual) this.ui.toast(res?.error ? 'Could not check for updates (offline?)' : `You have the latest version (v${this.version})`);
  }
}

// ---------------- FARMING ----------------
class Farm {
  constructor(game) {
    this.game = game; const W = game.world;
    this.soilGeo = new THREE.BoxGeometry(1.4, 0.1, 1.4);
    this.rowGeo = new THREE.BoxGeometry(1.3, 0.07, 0.2);
    const dirt = Assets.tex.dirt;
    this.soilMat = new THREE.MeshStandardMaterial({ color: '#8a6a4a', map: dirt.map, normalMap: dirt.normalMap, roughness: 1 });
    this.weedMat = new THREE.MeshLambertMaterial({ color: '#5a8a2a' });
    this.stemMat = new THREE.MeshLambertMaterial({ color: '#5aa03a' });
    for (const p of W.plots) {
      p.group = new THREE.Group(); p.group.position.set(p.x, p.y, p.z); game.scene.add(p.group);
      this.refresh(p);
    }
  }
  progress(p) { return clamp(p.t / CROPS[p.crop].grow, 0, 1); }
  ripe(p) { return p.state === 'planted' && p.t >= CROPS[p.crop].grow; }
  stage(p) { return p.state !== 'planted' ? -1 : this.ripe(p) ? 3 : Math.min(2, Math.floor(this.progress(p) * 3)); }
  // one merged mesh per plot (a single draw call) built from the crop / grass models
  plotMesh(parts) {
    const geos = parts.map(([bundle, name, x, z, ry, sc]) => {
      const g = Assets.geom(bundle, name).geometry.clone();
      g.applyMatrix4(new THREE.Matrix4().compose(new THREE.Vector3(x, 0.08, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(sc, sc, sc)));
      return g;
    });
    const m = new THREE.Mesh(mergeGeometries(geos), Assets.material(null));
    m.castShadow = true; m.receiveShadow = true;
    return m;
  }
  refresh(p) {
    const g = p.group; g.clear(); p.shownStage = this.stage(p);
    const rnd = (i) => ((Math.sin(p.id * 91.7 + i * 13.3) * 43758.5) % 1 + 1) % 1;
    if (p.state === 'grass') {
      const parts = [];
      for (let i = 0; i < 7; i++) parts.push(['nature', rnd(i) < 0.6 ? 'Grass' : 'Grass_Short', (rnd(i + 20) - 0.5) * 1.2, (rnd(i + 40) - 0.5) * 1.2, rnd(i + 60) * 6, 0.45 + rnd(i + 80) * 0.3]);
      g.add(this.plotMesh(parts));
      return;
    }
    const soil = new THREE.Mesh(this.soilGeo, this.soilMat); soil.position.y = 0.03; soil.receiveShadow = true; g.add(soil);
    for (let i = -1; i <= 1; i++) { const r = new THREE.Mesh(this.rowGeo, this.soilMat); r.position.set(0, 0.09, i * 0.42); r.receiveShadow = true; g.add(r); }
    if (p.state !== 'planted') return;
    const st = p.shownStage;
    const name = { wheat: 'Wheat', carrot: 'Carrot', pumpkin: 'Pumpkin' }[p.crop] + '_' + (st + 1);
    const parts = [];
    if (p.crop === 'pumpkin') parts.push(['crops', name, 0, 0, rnd(1) * 6, 0.85]);
    else for (let i = 0; i < 9; i++) {
      const x = ((i % 3) - 1) * 0.42 + (rnd(i) - 0.5) * 0.08, z = (Math.floor(i / 3) - 1) * 0.42 + (rnd(i + 9) - 0.5) * 0.08;
      if (p.crop === 'wheat') for (let k = 0; k < 3; k++) parts.push(['crops', name, x + (k - 1) * 0.08, z + (rnd(i * 3 + k) - 0.5) * 0.1, rnd(i + k) * 6, 0.9 + rnd(k + i) * 0.25]);
      else parts.push(['crops', name, x, z, rnd(i) * 6, 0.5]);
    }
    g.add(this.plotMesh(parts));
    if (st === 3) { const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.combat.glowTex, color: '#ffe08a', transparent: true, opacity: 0.45, depthWrite: false })); sp.position.y = 0.9; sp.scale.setScalar(0.6); g.add(sp); }
  }
  till(p) {
    const G = this.game; p.state = 'tilled'; this.refresh(p);
    G.audio.till(); G.player.gainXP('farming', 4);
    G.combat.dust.emit(new THREE.Vector3(p.x, p.y + 0.2, p.z), 14, { color: '#6a4a2a', speed: 2, life: 0.6, size: 0.12, gravity: 8 });
  }
  plant(p, seedId) {
    const G = this.game; const it = ITEMS[seedId];
    if (G.player.count(seedId) <= 0) return;
    p.state = 'planted'; p.crop = it.crop; p.t = 0;
    G.player.removeItem(seedId, 1); G.player.gainXP('farming', 3);
    this.refresh(p); G.audio.pickup();
  }
  harvest(p) {
    const G = this.game, c = CROPS[p.crop], P = G.player;
    let n = c.yield[0] + Math.floor(Math.random() * (c.yield[1] - c.yield[0] + 1));
    if (Math.random() < P.skills.farming.lvl * 0.04) n++;
    P.addItem(p.crop, n);
    if (Math.random() < 0.35 + P.skills.farming.lvl * 0.02) P.addItem(p.crop + '_seed', 1);
    P.gainXP('farming', c.xp);
    G.ui.toast(`Harvested ${n} ${ITEMS[p.crop].name}`, '#d9b050'); G.audio.pickup();
    G.combat.levelFx(new THREE.Vector3(p.x, p.y + 0.5, p.z), '#e2c35a');
    p.state = 'tilled'; p.crop = null; p.t = 0; this.refresh(p);
    G.checkCollectQuests();
  }
  update(dt) {
    const lvl = this.game.player.skills.farming.lvl;
    for (const p of this.game.world.plots) {
      if (p.state !== 'planted') continue;
      p.t += dt * (1 + lvl * 0.04);
      if (this.stage(p) !== p.shownStage) this.refresh(p);
    }
  }
}
