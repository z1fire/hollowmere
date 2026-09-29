import * as THREE from 'three';
import { clamp, lerp } from './util.js';
import { ITEMS, SKILLS, CROPS, xpToNext, computeClass } from './data.js';
import { heldModel } from './characters.js';
import { Assets } from './assets.js';

const STACK = ['seed', 'crop', 'consumable', 'material'];

export class Player {
  constructor(game) {
    this.game = game;
    this.pos = new THREE.Vector3(); this.yaw = 0; this.pitch = 0; this.vy = 0; this.onGround = true;
    this.radius = 0.35; this.eye = 1.62; this.bob = 0; this.cool = 0; this.hurtT = 99; this.dead = false;
    this.vm = new Viewmodel(game);
    this.reset();
  }
  reset() {
    this.skills = { melee: { lvl: 0, xp: 0 }, ranged: { lvl: 0, xp: 0 }, nature: { lvl: 0, xp: 0 }, combat: { lvl: 0, xp: 0 }, farming: { lvl: 1, xp: 0 } };
    this.gold = 25; this.inv = []; this.hotbar = [null, null, null, null, null, null]; this.sel = 0; this.armor = 'farm_clothes';
    this.addItem('pitchfork'); this.addItem('hoe'); this.addItem('wheat_seed', 8); this.addItem('bread', 2); this.addItem('farm_clothes');
    this.sel = 1;
    this.recompute(); this.hp = this.maxHp; this.mp = this.maxMp;
    this.className = this.cls.title;
  }
  serialize() {
    return { x: this.pos.x, y: this.pos.y, z: this.pos.z, yaw: this.yaw, skills: this.skills, gold: this.gold, inv: this.inv, hotbar: this.hotbar, sel: this.sel, armor: this.armor, hp: this.hp, mp: this.mp };
  }
  load(d) {
    Object.assign(this.skills, d.skills); this.gold = d.gold; this.inv = d.inv; this.hotbar = d.hotbar; this.sel = d.sel; this.armor = d.armor;
    this.pos.set(d.x, d.y, d.z); this.yaw = d.yaw;
    this.recompute(); this.hp = Math.min(d.hp, this.maxHp); this.mp = Math.min(d.mp, this.maxMp);
    this.className = this.cls.title;
    this.vm.set(this.held());
  }

  // ---------- stats ----------
  recompute() {
    const s = this.skills;
    const str = 10 + s.melee.lvl * 2 + s.farming.lvl * 0.8, dex = 10 + s.ranged.lvl * 2 + s.farming.lvl * 0.3, int = 10 + (s.nature.lvl + s.combat.lvl) * 1.6;
    this.stats = { str: Math.round(str), dex: Math.round(dex), int: Math.round(int) };
    const arm = ITEMS[this.armor] || {};
    this.maxHp = Math.round(30 + str * 2.2 + dex * 0.6 + int * 0.4);
    this.maxMp = Math.round(8 + int * 2.4 + (arm.mana || 0));
    this.def = arm.def || 0;
    this.cls = computeClass(s);
  }
  gainXP(skill, amt) {
    if (!this.skills[skill] || amt <= 0) return;
    const s = this.skills[skill];
    s.xp += amt;
    let leveled = false;
    while (s.xp >= xpToNext(s.lvl)) { s.xp -= xpToNext(s.lvl); s.lvl++; leveled = true; }
    if (leveled) {
      const oldMax = this.maxHp;
      this.recompute();
      this.hp += Math.max(0, this.maxHp - oldMax); this.mp = Math.min(this.maxMp, this.mp + 10);
      this.game.ui.toast(`${SKILLS[skill].icon} ${SKILLS[skill].name} increased to ${s.lvl}!`, SKILLS[skill].color);
      this.game.combat.levelFx(this.pos.clone().setY(this.pos.y + 1), SKILLS[skill].color);
      this.game.audio.levelup();
      if (this.cls.title !== this.className) {
        this.className = this.cls.title;
        this.game.ui.banner(`You are now a ${this.cls.title}`, 'Your class reflects the skills you use most');
      }
    }
    this.game.ui.dirty = true;
  }

  // ---------- inventory ----------
  count(id) { return this.inv.filter((s) => s.id === id).reduce((a, s) => a + s.qty, 0); }
  addItem(id, qty = 1) {
    const it = ITEMS[id]; if (!it) return false;
    if (STACK.includes(it.kind)) {
      const s = this.inv.find((s) => s.id === id);
      if (s) s.qty += qty; else this.inv.push({ id, qty });
    } else for (let i = 0; i < qty; i++) this.inv.push({ id, qty: 1 });
    if (['weapon', 'tool', 'seed', 'consumable'].includes(it.kind) && !this.hotbar.includes(id)) {
      const free = this.hotbar.indexOf(null); if (free >= 0) this.hotbar[free] = id;
    }
    this.game.ui && (this.game.ui.dirty = true);
    return true;
  }
  removeItem(id, qty = 1) {
    for (let i = this.inv.length - 1; i >= 0 && qty > 0; i--) {
      const s = this.inv[i]; if (s.id !== id) continue;
      const take = Math.min(qty, s.qty); s.qty -= take; qty -= take;
      if (s.qty <= 0) this.inv.splice(i, 1);
    }
    if (this.count(id) === 0) { const h = this.hotbar.indexOf(id); if (h >= 0) { this.hotbar[h] = null; if (h === this.sel) this.vm.set(this.held()); } if (this.armor === id) this.equipArmor('farm_clothes'); }
    this.game.ui.dirty = true;
  }
  held() { const id = this.hotbar[this.sel]; return id && this.count(id) > 0 ? { id, ...ITEMS[id] } : null; }
  select(i) { if (i === this.sel) return; this.sel = i; this.vm.set(this.held()); this.cool = Math.max(this.cool, 0.2); this.game.ui.dirty = true; this.game.audio.click(); }
  equipArmor(id) { this.armor = id; this.recompute(); this.hp = Math.min(this.hp, this.maxHp); this.mp = Math.min(this.mp, this.maxMp); this.game.ui.dirty = true; }
  consume(id) {
    const it = ITEMS[id]; if (!it || this.count(id) <= 0) return;
    if (it.heal) { this.hp = Math.min(this.maxHp, this.hp + it.heal); this.game.combat.healFx(this.pos.clone().setY(this.pos.y + 1)); }
    if (it.mana) this.mp = Math.min(this.maxMp, this.mp + it.mana);
    this.removeItem(id, 1);
    this.game.audio.drink();
    this.game.ui.toast(`Used ${it.name}`);
  }

  // ---------- frame ----------
  get forward() { return new THREE.Vector3(-Math.sin(this.yaw), 0, -Math.cos(this.yaw)); }
  update(dt, input, frozen) {
    const W = this.game.world;
    this.cool -= dt; this.hurtT += dt;
    if (this.dead) { this.updateCamera(dt, 0); return; }
    // regen
    if (this.hurtT > 5) this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.012 * dt);
    this.mp = Math.min(this.maxMp, this.mp + (1.0 + this.stats.int * 0.03) * dt);
    // look
    if (!frozen) {
      this.yaw -= input.look.x; this.pitch = clamp(this.pitch - input.look.y, -1.45, 1.45);
    }
    input.look.x = 0; input.look.y = 0;
    // move
    let mx = frozen ? 0 : input.move.x, my = frozen ? 0 : input.move.y;
    const ml = Math.hypot(mx, my); if (ml > 1) { mx /= ml; my /= ml; }
    const inWater = Math.hypot(this.pos.x - W.water.x, this.pos.z - W.water.z) < W.water.r * 0.95 && this.pos.y < W.water.y;
    const sprint = input.sprint || ml > 0.95 && input.touch;
    const speed = 4.3 * (sprint ? 1.55 : 1) * (inWater ? 0.55 : 1);
    const f = this.forward, rX = Math.cos(this.yaw), rZ = -Math.sin(this.yaw);
    const vx = (f.x * my + rX * mx) * speed, vz = (f.z * my + rZ * mx) * speed;
    this.pos.x += vx * dt; this.pos.z += vz * dt;
    W.resolve(this.pos, this.radius, this.pos.y);
    // vertical
    if (input.jump && this.onGround && !frozen) { this.vy = 5.6; this.onGround = false; this.game.audio.jump(); }
    input.jump = false;
    this.vy -= 18 * dt; this.pos.y += this.vy * dt;
    const g = W.groundAt(this.pos.x, this.pos.z, this.pos.y);
    if (this.pos.y <= g || (this.onGround && this.vy <= 0 && this.pos.y - g < 0.4)) {
      if (!this.onGround && this.vy < -9) this.hurt((-this.vy - 9) * 3, null, true);
      this.pos.y = g; this.vy = 0; this.onGround = true;
    } else this.onGround = false;
    const moving = Math.hypot(vx, vz);
    // footsteps
    if (this.onGround && moving > 0.5) {
      const pb = this.bob; this.bob += dt * moving * 1.9;
      if (Math.floor(pb / Math.PI) !== Math.floor(this.bob / Math.PI)) this.game.audio.step(W.inside ? 'wood' : inWater ? 'water' : 'grass');
    }
    this.inVillage = Math.hypot(this.pos.x, this.pos.z) < W.fenceR - 0.5;
    this.updateCamera(dt, this.onGround ? moving : 0);
    // attacking
    if (!frozen && input.attack) this.primary();
    this.vm.update(dt, moving, this.game.camera);
  }
  updateCamera(dt, moving) {
    const cam = this.game.camera;
    const bobY = Math.sin(this.bob * 2) * 0.045 * Math.min(1, moving / 4);
    const eye = this.dead ? 0.35 : this.eye;
    cam.position.set(this.pos.x, this.pos.y + eye + bobY, this.pos.z);
    cam.rotation.set(this.pitch, this.yaw, this.dead ? 0.6 : 0, 'YXZ');
  }

  // ---------- actions ----------
  targetPlot() {
    const plots = this.game.world.plots; if (!plots) return null;
    const f = this.forward; const px = this.pos.x + f.x * 1.3, pz = this.pos.z + f.z * 1.3;
    let best = null, bd = 1.1;
    for (const p of plots) { const d = Math.hypot(p.x - px, p.z - pz); if (d < bd) { bd = d; best = p; } }
    return best;
  }
  damageRoll(it) {
    const s = this.stats;
    const stat = it.skill === 'melee' ? s.str : it.skill === 'ranged' ? s.dex : s.int;
    const lvl = this.skills[it.skill]?.lvl || 0;
    return lerp(it.dmg[0], it.dmg[1], Math.random()) * (1 + (stat - 10) * 0.03) + lvl * 0.35;
  }
  primary() {
    if (this.cool > 0 || this.dead) return;
    const G = this.game;
    const it = this.held() || { id: null, name: 'Fists', kind: 'weapon', skill: 'melee', dmg: [1, 3], rate: 0.5, range: 1.8, vm: 'fists' };
    if (it.kind === 'tool' && it.id === 'hoe') {
      const p = this.targetPlot();
      if (p && p.state === 'grass') { this.cool = 0.6; this.vm.swing('chop'); G.farm.till(p); return; }
    }
    if (it.kind === 'seed') {
      this.cool = 0.4;
      const p = this.targetPlot();
      if (!p) { G.ui.toast('Face a plot in your field to plant'); return; }
      if (p.state === 'tilled') { this.vm.swing('toss'); G.farm.plant(p, it.id); }
      else if (p.state === 'grass') G.ui.toast('Till the soil with your hoe first');
      else G.ui.toast('Something is already growing there');
      return;
    }
    if (it.kind === 'consumable' || (it.kind === 'crop' && it.heal)) { this.cool = 0.8; this.consume(it.id); return; }
    if (it.kind === 'crop' || it.kind === 'material') { this.cool = 0.4; return; }
    this.cool = it.rate;
    if (it.skill === 'melee') {
      this.vm.swing(it.vm === 'pitchfork' ? 'thrust' : 'slash');
      G.audio.swing(1);
      setTimeout(() => this.meleeHit(it), 130);
    } else if (it.skill === 'ranged') {
      this.vm.swing('bow');
      G.audio.bow();
      G.combat.playerShot(it, this.damageRoll(it), 'ranged');
    } else {
      if (this.mp < it.mana) { G.ui.toast('Not enough mana', '#7aa8ff'); this.cool = 0.3; G.audio.fizzle(); return; }
      this.mp -= it.mana;
      this.vm.swing('cast');
      if (it.school === 'heal') {
        const amt = it.heal * (1 + (this.stats.int - 10) * 0.03) + this.skills.nature.lvl;
        const gained = Math.min(this.maxHp - this.hp, amt);
        this.hp += gained; G.combat.healFx(this.pos.clone().setY(this.pos.y + 1)); G.audio.heal();
        this.gainXP('nature', Math.max(2, gained * 0.5));
        G.ui.floatText(this.pos.clone().setY(this.pos.y + 1.4).addScaledVector(this.forward, 1.2), `+${Math.round(gained)}`, '#7affb0');
      } else {
        G.combat.playerShot(it, this.damageRoll(it), it.skill);
        G.audio.spell(it.school);
      }
    }
  }
  meleeHit(it) {
    const G = this.game; if (this.dead) return;
    const f = this.forward; let hitAny = false;
    for (const e of G.enemies) {
      if (e.dead) continue;
      const dx = e.pos.x - this.pos.x, dz = e.pos.z - this.pos.z, d = Math.hypot(dx, dz);
      if (d > (it.range || 2) + e.radius || Math.abs(e.pos.y - this.pos.y) > 2.5) continue;
      const dot = (dx * f.x + dz * f.z) / (d || 1);
      if (dot < 0.45 && d > 0.9) continue;
      G.combat.hitEnemy(e, this.damageRoll(it), 'melee', this.pos);
      hitAny = true;
    }
    if (!hitAny && it.id === 'hoe') { const p = this.targetPlot(); if (p && p.state === 'grass') G.farm.till(p); }
  }
  hurt(dmg, src, fall) {
    if (this.dead) return;
    const d = fall ? dmg : Math.max(1, dmg - this.def * 0.6);
    this.hp -= d; this.hurtT = 0;
    this.game.ui.hurtFlash(); this.game.audio.hurt();
    if (src && !fall) { const dx = this.pos.x - src.pos.x, dz = this.pos.z - src.pos.z, l = Math.hypot(dx, dz) || 1; this.pos.x += dx / l * 0.25; this.pos.z += dz / l * 0.25; }
    if (this.hp <= 0) { this.hp = 0; this.dead = true; this.game.onDeath(); }
  }
}

// ---------------- VIEWMODEL (held item, rendered in its own pass) ----------------
class Viewmodel {
  constructor(game) {
    this.game = game;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(55, 1, 0.01, 10);
    this.hemi = new THREE.HemisphereLight('#ffffff', '#555544', 1.4); this.scene.add(this.hemi);
    this.dir = new THREE.DirectionalLight('#fff0d8', 1.6); this.dir.position.set(1, 2, 1); this.scene.add(this.dir);
    this.root = new THREE.Group(); this.scene.add(this.root);
    this.anim = null; this.t = 0; this.swayX = 0; this.swayY = 0; this.lastYaw = 0; this.lastPitch = 0; this.equipT = 0;
  }
  mat(c, o) { return new THREE.MeshStandardMaterial({ color: c, roughness: 0.7, ...o }); }
  set(item) {
    this.root.clear(); this.item = item; this.string = this.arrow = this.orb = null;
    const g = new THREE.Group(); this.model = g; this.root.add(g);
    const skin = this.mat('#e0b48a'), wood = this.mat('#7a5634'), metal = this.mat('#c8ccd0', { metalness: 0.7, roughness: 0.3 });
    const hand = new THREE.Mesh(new THREE.SphereGeometry(0.038, 12, 10), this.mat('#6a4a30', { roughness: 0.6 })); hand.scale.set(1, 0.9, 1.25);
    const sleeve = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.055, 0.22, 10), this.mat('#8a6a48', { roughness: 0.9 })); sleeve.rotation.x = Math.PI / 2;
    const kind = item ? item.vm || item.kind : 'fists';
    const tint = item?.tint ? this.mat(item.tint, { metalness: 0.7, roughness: 0.3 }) : metal;
    this.kind = kind;
    const addArm = (x, y, z) => { const h = hand.clone(); h.position.set(x, y, z); g.add(h); };
    // tint a cloned model (e.g. rusty or golden weapons)
    const tinted = (o, color) => { if (color) o.traverse((m) => { if (m.isMesh) { m.material = m.material.clone(); m.material.color.multiply(new THREE.Color(color)); } }); return o; };
    switch (kind) {
      case 'sword': case 'axe': {
        const name = { knight_blade: 'sword_2handed', war_axe: 'axe_2handed' }[item.id] || (kind === 'axe' ? 'axe_1handed' : 'sword_1handed');
        const w = tinted(heldModel('weapons', name), item.id === 'rusty_sword' ? '#b89878' : item.id === 'knight_blade' ? '#ffe6a0' : null);
        w.scale.setScalar(name.includes('2handed') ? 0.17 : 0.2);
        w.rotation.x = -0.35; g.add(w); addArm(0, 0, 0.02);
        g.userData.base = [0.36, -0.38, -0.62, 0.1, 0, -0.3]; break;
      }
      case 'pitchfork': case 'hoe': {
        const s = new THREE.Group(); const h = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 1.7, 6), wood); h.position.y = 0.35; s.add(h);
        if (kind === 'pitchfork') {
          const bar = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.03, 0.03), metal); bar.position.y = 1.2; s.add(bar);
          for (const x of [-0.1, 0, 0.1]) { const t = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.012, 0.3, 4), metal); t.position.set(x, 1.35, 0); s.add(t); }
        } else { const b = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.02, 0.11), this.mat('#8a8a8a', { metalness: 0.5 })); b.position.set(0, 1.2, 0.05); s.add(b); }
        s.rotation.x = -1.2; g.add(s); addArm(0, 0, 0.02); addArm(-0.05, 0.25, -0.35); g.userData.base = [0.3, -0.4, -0.5, 0, 0.15, -0.1]; break;
      }
      case 'bow': {
        const w = heldModel('village', item.id === 'longbow' ? 'Bow_Golden' : 'Bow_Wooden');
        tinted(w, item.id === 'short_bow' ? '#c8a888' : null);
        w.scale.setScalar(0.24); w.rotation.set(0, Math.PI / 2, 0.18); g.add(w);
        const arrow = heldModel('weapons', 'arrow'); arrow.scale.setScalar(0.45); arrow.rotation.set(-Math.PI / 2, 0, 0); arrow.position.set(0, 0.0, -0.05); g.add(arrow); this.arrow = arrow;
        addArm(0, -0.02, 0.05); g.userData.base = [0.2, -0.26, -0.6, 0, 0, 0]; break;
      }
      case 'tome': {
        const cols = { nature: '#9aff9a', heal: '#a0ffe0', spark: '#a8c0ff', fire: '#ffb0a0' };
        const glow = { nature: '#8aff6a', heal: '#8affc0', spark: '#9ac8ff', fire: '#ffa040' }[item.school];
        const b = tinted(heldModel('weapons', 'spellbook_open'), cols[item.school]);
        b.scale.setScalar(0.26); b.position.set(-0.34, -0.04, 0.0); b.rotation.set(-0.5, 0.35, 0.15); g.add(b);
        const orb = new THREE.Mesh(new THREE.SphereGeometry(0.06, 10, 8), new THREE.MeshBasicMaterial({ color: glow })); orb.position.set(0, 0.1, -0.05); g.add(orb); this.orb = orb;
        const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.game.combat.glowTex, color: glow, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false })); halo.scale.setScalar(0.16); orb.add(halo);
        addArm(0, 0, 0.02); addArm(-0.42, -0.08, 0.1); g.userData.base = [0.26, -0.36, -0.55, 0, 0, 0]; break;
      }
      case 'seed': case 'crop': case 'consumable': case 'material': {
        let m;
        if (kind === 'consumable' && item.id.includes('potion')) { m = heldModel('village', item.id === 'hp_potion' ? 'Potion1_Filled' : 'Potion4_Filled'); m.scale.setScalar(0.16); }
        else if (kind === 'seed') { m = heldModel('village', 'Bag'); m.scale.setScalar(0.9); }
        else if (kind === 'crop' && Assets.bundles.crops.getObjectByName({ wheat: 'Wheat_4', carrot: 'Carrot_4', pumpkin: 'Pumpkin_4' }[item.id] || '')) { m = heldModel('crops', { wheat: 'Wheat_4', carrot: 'Carrot_4', pumpkin: 'Pumpkin_4' }[item.id]); m.scale.setScalar(item.id === 'pumpkin' ? 0.18 : 0.3); }
        else m = new THREE.Mesh(new THREE.SphereGeometry(0.07, 8, 6), this.mat(item.id === 'pumpkin' ? '#e8781c' : item.id === 'carrot' ? '#f08a24' : '#d8b860'));
        m.position.set(0, 0.08, -0.02); g.add(m); addArm(0, 0, 0.02); g.userData.base = [0.3, -0.36, -0.5, 0.2, 0, 0]; break;
      }
      default: { addArm(0, 0, 0.02); addArm(-0.45, -0.05, 0.05); g.userData.base = [0.25, -0.4, -0.5, 0, 0, 0]; }
    }
    this.equipT = 0.25;
    this.apply(0);
  }
  swing(type) { this.anim = { type, t: 0, dur: type === 'bow' ? 0.35 : type === 'cast' ? 0.35 : type === 'thrust' ? 0.35 : 0.32 }; }
  apply(k) {
    const b = this.model.userData.base; const g = this.model;
    g.position.set(b[0] + this.swayX, b[1] + this.swayY - this.equipT * 1.2, b[2]); g.rotation.set(b[3], b[4], b[5]);
    if (!this.anim) return;
    const a = this.anim, t = a.t / a.dur, s = Math.sin(t * Math.PI);
    switch (a.type) {
      case 'slash': case 'chop': {
        const e = t < 0.3 ? -t / 0.3 : (t - 0.3) / 0.7; // wind-up then swing
        g.rotation.x += (t < 0.3 ? 0.5 * -e : -1.4 * Math.sin(e * Math.PI * 0.9));
        g.rotation.z += t < 0.3 ? -0.4 * -e : 1.1 * Math.sin(e * Math.PI * 0.8);
        g.position.x -= t < 0.3 ? 0 : 0.25 * Math.sin(e * Math.PI);
        break;
      }
      case 'thrust': g.position.z -= s * 0.45; g.position.y += s * 0.06; break;
      case 'bow': if (this.string) this.string.position.x = -0.13 - (t < 0.15 ? 0 : 0); g.position.z += s * 0.06; g.rotation.x += s * 0.12; if (this.arrow) this.arrow.visible = t > 0.6; break;
      case 'cast': g.position.z -= s * 0.2; g.position.y += s * 0.05; if (this.orb) this.orb.scale.setScalar(1 + s * 1.2); break;
      case 'toss': g.position.y += s * 0.1; g.rotation.x -= s * 0.6; break;
    }
  }
  update(dt, moving, cam) {
    this.t += dt;
    const dyaw = this.game.player.yaw - this.lastYaw, dpitch = this.game.player.pitch - this.lastPitch;
    this.lastYaw = this.game.player.yaw; this.lastPitch = this.game.player.pitch;
    this.swayX = lerp(this.swayX, clamp(dyaw * 0.6, -0.06, 0.06) + Math.sin(this.game.player.bob) * 0.012 * Math.min(1, moving / 3), Math.min(1, dt * 10));
    this.swayY = lerp(this.swayY, clamp(-dpitch * 0.6, -0.05, 0.05) + Math.abs(Math.cos(this.game.player.bob)) * 0.012 * Math.min(1, moving / 3) + Math.sin(this.t * 1.6) * 0.004, Math.min(1, dt * 10));
    this.equipT = Math.max(0, this.equipT - dt);
    if (this.anim) { this.anim.t += dt; if (this.anim.t >= this.anim.dur) this.anim = null; }
    if (this.orb) { this.orb.scale.setScalar(1 + Math.sin(this.t * 5) * 0.1); }
    this.apply();
    this.camera.aspect = cam.aspect; this.camera.updateProjectionMatrix();
    const W = this.game.world;
    this.hemi.intensity = W.hemi.intensity * 1.2 + (W.inside ? 0.5 : 0) + 0.2;
    this.dir.intensity = W.sun.intensity * 0.6;
  }
}
