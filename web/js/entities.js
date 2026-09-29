import * as THREE from 'three';
import { RNG, angleDiff, clamp } from './util.js';
import { makeHumanoid, makeWolf, makeGoblin, makeGoblinArcher, makeSkeleton, animate } from './characters.js';
import { ROLES, NAMES, ENEMIES } from './data.js';

const SKIN = ['#f1c9a5', '#e0b48a', '#c68e5e', '#a86f45', '#8a5a36', '#f5d6b8'];
const HAIR = ['#2a1a0a', '#5a3a1a', '#8a5a2a', '#c8a050', '#1a1a1a', '#8a2a1a', '#aaaaaa'];
const SHIRTS = ['#8a3a3a', '#3a5a8a', '#5a7a3a', '#8a6a3a', '#6a3a6a', '#3a6a6a', '#a07040', '#4a4a6a'];

// ---------------- NPC ----------------
export class NPC {
  constructor(game, spot, rng, name) {
    this.game = game; this.role = spot.role; this.def = ROLES[spot.role];
    const female = rng.chance(0.5);
    this.name = name || rng.pick(female ? NAMES.f : NAMES.m);
    const look = { ...(this.def.look || {}) };
    const o = {
      skin: rng.pick(SKIN), hair: look.hat === 'hood' || look.hat === 'wizard' ? undefined : rng.pick(HAIR), longHair: female,
      shirt: look.shirt || rng.pick(SHIRTS), pants: look.pants || rng.pick(['#3a2a1a', '#2a3a4a', '#4a4a3a']), ...look,
    };
    if (female) o.beard = false;
    if (o.beard && !o.beardColor) o.beardColor = o.hair;
    if (!o.hair && !['wizard', 'hood', 'helmet'].includes(o.hat)) o.hair = rng.pick(HAIR);
    this.model = makeHumanoid(o);
    this.obj = this.model.group;
    this.pos = new THREE.Vector3(spot.x, spot.y ?? game.world.groundAt(spot.x, spot.z), spot.z);
    this.home = this.pos.clone(); this.homeYaw = spot.yaw || 0;
    this.yaw = this.homeYaw;
    this.obj.position.copy(this.pos); this.obj.rotation.y = this.yaw;
    game.scene.add(this.obj);
    this.speed = 0; this.wander = spot.wander; this.target = null; this.wait = rng.range(1, 5); this.rng = rng; this.wpIndex = spot.wp ?? 0;
    this.interact = { type: 'npc', npc: this, x: this.pos.x, y: this.pos.y + 1.2, z: this.pos.z, r: 2.6, label: `Talk to ${this.name}` };
    game.world.interactables.push(this.interact);
    this.marker = null;
    if (this.def.quest) this.makeMarker();
  }
  makeMarker() {
    const c = document.createElement('canvas'); c.width = 64; c.height = 128;
    this.markerCanvas = c;
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), depthTest: true, transparent: true }));
    sp.scale.set(0.35, 0.7, 1); sp.position.y = 2.45;
    this.obj.add(sp); this.marker = sp; this.markerState = null;
  }
  setMarker(state) { // '!', '?', 'done' or null
    if (!this.marker || state === this.markerState) return;
    this.markerState = state;
    const x = this.markerCanvas.getContext('2d'); x.clearRect(0, 0, 64, 128);
    if (state) {
      x.font = 'bold 110px Georgia'; x.textAlign = 'center'; x.textBaseline = 'middle';
      x.lineWidth = 8; x.strokeStyle = '#2a1a00'; x.fillStyle = state === '?' ? '#ffe45a' : state === '!' ? '#ffd23a' : '#aaaaaa';
      const ch = state === '...' ? '?' : state; x.strokeText(ch, 32, 66); x.fillText(ch, 32, 66);
    }
    this.marker.material.map.needsUpdate = true; this.marker.visible = !!state;
  }
  update(dt, t, playerPos) {
    const W = this.game.world;
    const dp = Math.hypot(playerPos.x - this.pos.x, playerPos.z - this.pos.z);
    let moving = 0;
    if (this.wander && !this.talking) {
      if (!this.target) {
        this.wait -= dt;
        if (this.wait <= 0) {
          const wp = W.waypoints; const cur = wp[this.wpIndex];
          const next = this.rng.pick(cur.n);
          this.wpIndex = next; this.target = { x: wp[next].x + this.rng.range(-1, 1), z: wp[next].z + this.rng.range(-1, 1) };
        }
      } else {
        const dx = this.target.x - this.pos.x, dz = this.target.z - this.pos.z, d = Math.hypot(dx, dz);
        if (d < 0.6 || dp < 1.4) { if (d < 0.6) { this.target = null; this.wait = this.rng.range(2, 8); } }
        else {
          const ty = Math.atan2(dx, dz);
          this.yaw += angleDiff(this.yaw, ty) * Math.min(1, dt * 5);
          const sp = 1.4;
          this.pos.x += Math.sin(this.yaw) * sp * dt; this.pos.z += Math.cos(this.yaw) * sp * dt;
          const before = this.pos.x + this.pos.z;
          W.resolve(this.pos, 0.3, this.pos.y);
          moving = sp;
          this.stuck = (this.stuck || 0) + (Math.abs(before - (this.pos.x + this.pos.z)) > 0.001 ? dt : 0);
          if (this.stuck > 3) { this.target = null; this.stuck = 0; this.wait = 1; }
        }
      }
      this.pos.y = W.groundAt(this.pos.x, this.pos.z, this.pos.y);
    }
    // face the player when close
    if (dp < 4.5 && !moving) {
      const ty = Math.atan2(playerPos.x - this.pos.x, playerPos.z - this.pos.z);
      this.yaw += angleDiff(this.yaw, ty) * Math.min(1, dt * 4);
    } else if (!this.wander) this.yaw += angleDiff(this.yaw, this.homeYaw) * Math.min(1, dt * 2);
    this.obj.position.copy(this.pos); this.obj.rotation.y = this.yaw;
    this.model.talking = this.talking;
    if (dp < 60) animate(this.model, dt, moving, t);
    this.obj.visible = dp < 90;
    this.interact.x = this.pos.x; this.interact.z = this.pos.z; this.interact.y = this.pos.y + 1.2;
  }
}

// ---------------- ENEMY ----------------
const _v = new THREE.Vector3();
export class Enemy {
  constructor(game, spawn) {
    this.game = game; this.spawn = spawn; this.type = spawn.type; this.def = ENEMIES[spawn.type];
    const d = this.def;
    this.model = d.model === 'wolf' ? makeWolf(Math.random() < 0.3 ? '#5a5650' : '#7a766e')
      : d.model === 'goblin' ? (d.ranged ? makeGoblinArcher() : makeGoblin(!!d.boss))
        : makeSkeleton(!!d.ranged);
    this.obj = this.model.group;
    game.scene.add(this.obj);
    this.radius = d.model === 'wolf' ? 0.5 : (d.scale || 1) * 0.4;
    this.height = d.model === 'wolf' ? 1.0 : 1.7 * (d.scale || (d.model === 'goblin' ? 0.78 : 1));
    // health bar
    const bg = new THREE.Mesh(new THREE.PlaneGeometry(1, 0.1), new THREE.MeshBasicMaterial({ color: '#200', depthWrite: false, transparent: true, opacity: 0.8 }));
    const fg = new THREE.Mesh(new THREE.PlaneGeometry(1, 0.1), new THREE.MeshBasicMaterial({ color: d.boss ? '#ff9a2a' : '#e03a2a', depthWrite: false }));
    fg.position.z = 0.001;
    this.bar = new THREE.Group(); this.bar.add(bg); this.bar.add(fg); this.barFg = fg;
    this.bar.scale.setScalar(d.boss ? 1.6 : 0.9);
    game.scene.add(this.bar);
    this.mats = [];
    this.obj.traverse((o) => { if (o.isMesh) { this.mats.push(o.material); } });
    this.respawn();
  }
  respawn() {
    const s = this.spawn, W = this.game.world;
    this.pos = new THREE.Vector3(s.x, W.heightAt(s.x, s.z), s.z);
    this.hp = this.def.hp; this.maxHp = this.def.hp;
    this.state = 'idle'; this.cool = 0; this.wait = Math.random() * 3; this.target = null;
    this.yaw = Math.random() * 6.28; this.dead = false; this.deadT = 0; this.flash = 0; this.vy = 0;
    this.obj.visible = true; this.obj.rotation.set(0, this.yaw, 0);
    this.obj.position.copy(this.pos); this.bar.visible = false;
    this.lastHit = 0;
  }
  get center() { return _v.set(this.pos.x, this.pos.y + this.height * 0.55, this.pos.z); }
  damage(amount, source) {
    if (this.dead) return false;
    this.hp -= amount; this.flash = 0.15; this.lastHit = 0;
    this.state = 'chase'; this.alerted = 6;
    // knockback
    if (source) { const dx = this.pos.x - source.x, dz = this.pos.z - source.z, d = Math.hypot(dx, dz) || 1; const k = this.def.boss ? 0.15 : 0.5; this.pos.x += dx / d * k; this.pos.z += dz / d * k; }
    if (this.hp <= 0) { this.die(); return true; }
    return false;
  }
  die() {
    this.dead = true; this.deadT = 0; this.bar.visible = false; this.hp = 0;
    this.respawnT = this.def.respawn || 75 + Math.random() * 45;
  }
  update(dt, t, player) {
    const W = this.game.world;
    if (this.dead) {
      this.deadT += dt;
      if (this.deadT < 1.2) { this.obj.rotation.z = Math.min(Math.PI / 2, this.deadT * 4) * (this.model.kind === 'wolf' ? 1 : 0); if (this.model.kind !== 'wolf') this.obj.rotation.x = -Math.min(Math.PI / 2, this.deadT * 4); }
      else this.obj.position.y = this.pos.y - (this.deadT - 1.2) * 0.6;
      if (this.deadT > 3) this.obj.visible = false;
      this.respawnT -= dt;
      if (this.respawnT <= 0) {
        // don't respawn in front of the player
        if (player.pos.distanceTo(new THREE.Vector3(this.spawn.x, player.pos.y, this.spawn.z)) > 30) this.respawn(); else this.respawnT = 5;
      }
      return;
    }
    const d = this.def, p = player.pos;
    const dx = p.x - this.pos.x, dz = p.z - this.pos.z, dist = Math.hypot(dx, dz);
    const far = dist > 110;
    this.obj.visible = !far;
    if (far && this.state === 'idle') return;
    const homeD = Math.hypot(this.pos.x - this.spawn.x, this.pos.z - this.spawn.z);
    this.cool -= dt; this.lastHit += dt;
    const night = this.game.world.night > 0.6;
    const aggro = d.aggro * (night ? 1.25 : 1) * (player.inVillage ? 0.4 : 1);
    let speed = 0;
    if (player.dead) this.state = 'return';
    switch (this.state) {
      case 'idle': {
        if (dist < aggro && !player.dead && Math.abs(p.y - this.pos.y) < 6) { this.state = 'chase'; this.game.audio.growl?.(this.def.model); break; }
        if (!this.target) { this.wait -= dt; if (this.wait < 0) { const a = Math.random() * 6.28, r = Math.random() * 8; this.target = { x: this.spawn.x + Math.sin(a) * r, z: this.spawn.z + Math.cos(a) * r }; } }
        else { const tx = this.target.x - this.pos.x, tz = this.target.z - this.pos.z; if (Math.hypot(tx, tz) < 0.7) { this.target = null; this.wait = 2 + Math.random() * 5; } else { this.face(tx, tz, dt); speed = d.speed * 0.3; } }
        break;
      }
      case 'chase': {
        if (homeD > this.spawn.leash + 8 || (dist > aggro * 2.2 && this.lastHit > 5) || player.inVillage && dist > 6) { this.state = 'return'; break; }
        this.face(dx, dz, dt);
        const range = d.range + (d.ranged ? 0 : player.radius);
        if (d.ranged) {
          const clear = dist < range && W.lineClear(this.pos.x, this.pos.y + 1.3, this.pos.z, p.x, p.y + 1.2, p.z);
          if (clear) { if (this.cool <= 0) this.attack(player); if (dist < 6) speed = -d.speed * 0.6; }
          else speed = d.speed;
        } else if (dist > range) speed = d.speed;
        else if (this.cool <= 0) this.attack(player);
        break;
      }
      case 'return': {
        const tx = this.spawn.x - this.pos.x, tz = this.spawn.z - this.pos.z;
        if (Math.hypot(tx, tz) < 1.5) { this.state = 'idle'; this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.5); break; }
        this.face(tx, tz, dt); speed = d.speed * 0.9;
        this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.1 * dt);
        if (dist < aggro * 0.6 && homeD < this.spawn.leash && !player.dead && !player.inVillage) this.state = 'chase';
        break;
      }
    }
    if (speed !== 0) {
      const sp = speed * (this.flash > 0 ? 0.3 : 1);
      this.pos.x += Math.sin(this.yaw) * sp * dt; this.pos.z += Math.cos(this.yaw) * sp * dt;
      W.resolve(this.pos, this.radius, this.pos.y, this.height);
      // stay out of the village
      const r = Math.hypot(this.pos.x, this.pos.z);
      if (r < W.fenceR + 1.5 && this.def.model !== 'none') { this.pos.x *= (W.fenceR + 1.5) / r; this.pos.z *= (W.fenceR + 1.5) / r; }
    }
    // separation from player
    if (dist < this.radius + player.radius && dist > 0.001) { const k = (this.radius + player.radius - dist) / dist; this.pos.x -= dx * k; this.pos.z -= dz * k; }
    this.pos.y = W.groundAt(this.pos.x, this.pos.z, this.pos.y);
    this.obj.position.copy(this.pos); this.obj.rotation.y = this.yaw;
    if (!far) animate(this.model, dt, Math.abs(speed), t);
    // hit flash
    if (this.flash > 0) { this.flash -= dt; for (const m of this.mats) m.emissive && m.emissive.setRGB(this.flash > 0 ? 0.6 : 0, 0, 0); }
    // health bar
    const show = this.hp < this.maxHp && dist < 35;
    this.bar.visible = show;
    if (show) {
      this.bar.position.set(this.pos.x, this.pos.y + this.height + 0.35, this.pos.z);
      this.bar.quaternion.copy(this.game.camera.quaternion);
      const f = clamp(this.hp / this.maxHp, 0, 1); this.barFg.scale.x = f; this.barFg.position.x = -(1 - f) / 2;
    }
  }
  face(dx, dz, dt) { const ty = Math.atan2(dx, dz); this.yaw += angleDiff(this.yaw, ty) * Math.min(1, dt * 7); }
  attack(player) {
    const d = this.def;
    this.cool = d.rate * (0.85 + Math.random() * 0.3);
    this.model.attack = 0.45;
    if (d.ranged) {
      const from = new THREE.Vector3(this.pos.x, this.pos.y + 1.3 * (d.scale || 1), this.pos.z);
      const to = new THREE.Vector3(player.pos.x, player.pos.y + 1.2, player.pos.z);
      this.game.combat.enemyArrow(from, to, d, this);
      this.game.audio.bow();
    } else {
      setTimeout(() => {
        if (this.dead) return;
        const dist = Math.hypot(player.pos.x - this.pos.x, player.pos.z - this.pos.z);
        if (dist < d.range + player.radius + 0.4) player.hurt(d.dmg[0] + Math.random() * (d.dmg[1] - d.dmg[0]), this);
      }, 220);
      if (d.model === 'wolf') this.game.audio.bite(); else this.game.audio.swing(0.6);
    }
  }
}
