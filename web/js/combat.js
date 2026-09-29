import * as THREE from 'three';
import { glowTexture } from './textures.js';

// ---------- particles ----------
class Particles {
  constructor(scene, max, additive, tex) {
    this.max = max; this.n = 0;
    this.pos = new Float32Array(max * 3); this.col = new Float32Array(max * 4); this.size = new Float32Array(max);
    this.vel = new Float32Array(max * 3); this.life = new Float32Array(max); this.maxLife = new Float32Array(max); this.grav = new Float32Array(max); this.baseSize = new Float32Array(max);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('pcolor', new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    this.uScale = { value: 400 };
    const m = new THREE.ShaderMaterial({
      uniforms: { map: { value: tex }, uScale: this.uScale },
      vertexShader: `attribute float size; attribute vec4 pcolor; varying vec4 vC; uniform float uScale;
        void main(){ vC = pcolor; vec4 mv = modelViewMatrix * vec4(position,1.0); float d = -mv.z; vC.a *= smoothstep(0.4, 1.6, d); gl_PointSize = min(size * uScale / max(0.1, d), uScale * 0.08); gl_Position = projectionMatrix * mv; }`,
      fragmentShader: `uniform sampler2D map; varying vec4 vC; void main(){ vec4 t = texture2D(map, gl_PointCoord); gl_FragColor = vec4(vC.rgb, vC.a * t.a); if (gl_FragColor.a < 0.01) discard; }`,
      transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, m); this.points.frustumCulled = false;
    scene.add(this.points); this.geo = g;
  }
  emit(p, count, o = {}) {
    const c = new THREE.Color(o.color || '#ffffff');
    for (let k = 0; k < count; k++) {
      if (this.n >= this.max) return;
      const i = this.n++;
      const sp = (o.speed ?? 3) * (0.4 + Math.random() * 0.6);
      const th = Math.random() * Math.PI * 2, ph = Math.acos(2 * Math.random() - 1);
      let vx = Math.sin(ph) * Math.cos(th) * sp, vy = Math.abs(Math.cos(ph)) * sp * (o.up ?? 1), vz = Math.sin(ph) * Math.sin(th) * sp;
      if (o.dir) { vx += o.dir.x; vy += o.dir.y; vz += o.dir.z; }
      this.pos[i * 3] = p.x + (Math.random() - 0.5) * (o.spread || 0); this.pos[i * 3 + 1] = p.y + (Math.random() - 0.5) * (o.spread || 0); this.pos[i * 3 + 2] = p.z + (Math.random() - 0.5) * (o.spread || 0);
      this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
      const v = o.vary ?? 0.15;
      this.col[i * 4] = c.r * (1 - v + Math.random() * v * 2); this.col[i * 4 + 1] = c.g * (1 - v + Math.random() * v * 2); this.col[i * 4 + 2] = c.b * (1 - v + Math.random() * v * 2); this.col[i * 4 + 3] = 1;
      this.life[i] = this.maxLife[i] = (o.life || 0.6) * (0.6 + Math.random() * 0.8);
      this.grav[i] = o.gravity ?? 6;
      this.baseSize[i] = (o.size || 0.15) * (0.6 + Math.random() * 0.8);
    }
  }
  update(dt) {
    for (let i = 0; i < this.n; i++) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) { // swap-remove
        const j = --this.n;
        this.pos.copyWithin(i * 3, j * 3, j * 3 + 3); this.vel.copyWithin(i * 3, j * 3, j * 3 + 3); this.col.copyWithin(i * 4, j * 4, j * 4 + 4);
        this.life[i] = this.life[j]; this.maxLife[i] = this.maxLife[j]; this.grav[i] = this.grav[j]; this.baseSize[i] = this.baseSize[j];
        i--; continue;
      }
      this.vel[i * 3 + 1] -= this.grav[i] * dt;
      this.vel[i * 3] *= 0.98; this.vel[i * 3 + 2] *= 0.98;
      this.pos[i * 3] += this.vel[i * 3] * dt; this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt; this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      const f = this.life[i] / this.maxLife[i];
      this.col[i * 4 + 3] = Math.min(1, f * 1.5);
      this.size[i] = this.baseSize[i] * (0.5 + f * 0.5);
    }
    for (let i = this.n; i < this.max; i++) this.size[i] = 0;
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.pcolor.needsUpdate = true; this.geo.attributes.size.needsUpdate = true;
    this.geo.setDrawRange(0, this.n);
  }
}

const SCHOOL = {
  nature: { color: '#6aff5a', core: '#d8ffb0' },
  spark:  { color: '#8ab8ff', core: '#ffffff' },
  fire:   { color: '#ff7a1a', core: '#ffe08a' },
  heal:   { color: '#7affb0', core: '#ffffff' },
};

export class Combat {
  constructor(game) {
    this.game = game; this.proj = [];
    const tex = glowTexture();
    this.fx = new Particles(game.scene, 900, true, tex);
    this.dust = new Particles(game.scene, 500, false, tex);
    this.arrowGeo = new THREE.CylinderGeometry(0.012, 0.012, 0.75, 4); this.arrowGeo.rotateX(Math.PI / 2);
    this.arrowMat = new THREE.MeshStandardMaterial({ color: '#8a6a44' });
    this.orbGeo = new THREE.SphereGeometry(0.14, 10, 8);
    this.glowTex = tex;
  }
  setScale(s) { this.fx.uScale.value = s; this.dust.uScale.value = s; }

  spawn(o) {
    let mesh;
    if (o.kind === 'arrow') {
      mesh = new THREE.Group();
      mesh.add(new THREE.Mesh(this.arrowGeo, this.arrowMat));
      const tip = new THREE.Mesh(new THREE.ConeGeometry(0.03, 0.1, 4), new THREE.MeshStandardMaterial({ color: '#555' })); tip.rotation.x = Math.PI / 2; tip.position.z = 0.4; mesh.add(tip);
      const fl = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.005, 0.12), new THREE.MeshStandardMaterial({ color: o.hostile ? '#222' : '#e8e0d0' })); fl.position.z = -0.32; mesh.add(fl);
    } else {
      const s = SCHOOL[o.school];
      mesh = new THREE.Mesh(this.orbGeo, new THREE.MeshBasicMaterial({ color: s.core }));
      const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.glowTex, color: s.color, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      glow.scale.setScalar(o.school === 'fire' ? 1.3 : 0.8); mesh.add(glow);
      if (o.school === 'fire') mesh.scale.setScalar(1.5);
    }
    mesh.position.copy(o.pos);
    this.game.scene.add(mesh);
    this.proj.push({ ...o, mesh, life: o.life || 3 });
  }

  playerShot(item, dmg, skill) {
    const P = this.game.player, cam = this.game.camera;
    const dir = new THREE.Vector3(0, 0, -1).applyQuaternion(cam.quaternion);
    const pos = cam.position.clone().addScaledVector(dir, 0.6);
    pos.y -= 0.12;
    const right = new THREE.Vector3(1, 0, 0).applyQuaternion(cam.quaternion); pos.addScaledVector(right, 0.12);
    if (item.skill === 'ranged') {
      const vel = dir.clone().multiplyScalar(item.speed || 40); vel.y += 1.2;
      this.spawn({ kind: 'arrow', pos, vel, gravity: 9, dmg, skill, item, hostile: false });
    } else {
      this.spawn({ kind: 'orb', school: item.school, pos, vel: dir.clone().multiplyScalar(item.speed || 28), gravity: 0, dmg, skill, item, hostile: false, splash: item.splash });
    }
  }
  enemyArrow(from, to, def, enemy) {
    const d = from.distanceTo(to), speed = 26, t = d / speed;
    const vel = to.clone().sub(from).divideScalar(t); vel.y += 0.5 * 9 * t;
    // slight inaccuracy
    vel.x += (Math.random() - 0.5) * 1.2; vel.z += (Math.random() - 0.5) * 1.2;
    this.spawn({ kind: 'arrow', pos: from.clone(), vel, gravity: 9, dmg: def.dmg[0] + Math.random() * (def.dmg[1] - def.dmg[0]), hostile: true, source: enemy });
  }

  hitEnemy(e, dmg, skill, src) {
    const G = this.game;
    const crit = Math.random() < 0.08 + G.player.stats.dex * 0.002;
    if (crit) dmg *= 1.8;
    dmg = Math.round(dmg);
    const killed = e.damage(dmg, src);
    const c = e.center.clone();
    const blood = e.def.model === 'skeleton' ? '#e8e4d0' : e.def.model === 'goblin' ? '#4a8a2a' : '#a01a1a';
    this.dust.emit(c, 10, { color: blood, speed: 3, life: 0.6, size: 0.12, gravity: 9 });
    G.ui.floatText(c, crit ? `${dmg}!` : `${dmg}`, crit ? '#ffd23a' : '#ffffff', crit);
    G.player.gainXP(skill, dmg * 0.55);
    G.audio.hit(e.def.model);
    if (killed) G.onKill(e, skill);
  }

  update(dt) {
    const G = this.game, W = G.world, P = G.player;
    for (let i = this.proj.length - 1; i >= 0; i--) {
      const p = this.proj[i];
      p.life -= dt;
      p.vel.y -= p.gravity * dt;
      const steps = 3;
      let done = false;
      for (let s = 0; s < steps && !done; s++) {
        p.mesh.position.addScaledVector(p.vel, dt / steps);
        const q = p.mesh.position;
        if (p.hostile) {
          if (!P.dead && Math.hypot(q.x - P.pos.x, q.z - P.pos.z) < 0.5 && q.y > P.pos.y && q.y < P.pos.y + 1.9) { P.hurt(p.dmg, p.source); done = true; }
        } else {
          for (const e of G.enemies) {
            if (e.dead) continue;
            if (Math.hypot(q.x - e.pos.x, q.z - e.pos.z) < e.radius + 0.25 && q.y > e.pos.y - 0.1 && q.y < e.pos.y + e.height + 0.2) {
              if (p.splash) this.explode(q, p);
              else this.hitEnemy(e, p.dmg, p.skill, q);
              done = true; break;
            }
          }
        }
        if (!done && (q.y < W.heightAt(q.x, q.z) || W.pointBlocked(q.x, q.y, q.z))) {
          if (p.splash) this.explode(q, p);
          else if (p.kind === 'orb') this.fx.emit(q, 10, { color: SCHOOL[p.school].color, speed: 2, life: 0.4, size: 0.2 });
          else this.dust.emit(q, 4, { color: '#8a7a5a', speed: 1.5, life: 0.4, size: 0.08 });
          done = true;
        }
      }
      if (p.kind === 'arrow') p.mesh.lookAt(_t.copy(p.mesh.position).add(p.vel));
      else {
        const s = SCHOOL[p.school];
        this.fx.emit(p.mesh.position, p.school === 'fire' ? 3 : 2, { color: s.color, speed: 0.6, life: 0.35, size: p.school === 'fire' ? 0.35 : 0.18, gravity: p.school === 'fire' ? -2 : 0, spread: 0.1 });
      }
      if (done || p.life <= 0) {
        if (done && p.kind === 'orb' && !p.splash) this.fx.emit(p.mesh.position, 14, { color: SCHOOL[p.school].color, speed: 3, life: 0.4, size: 0.2 });
        G.scene.remove(p.mesh); this.proj.splice(i, 1);
      }
    }
    this.fx.update(dt); this.dust.update(dt);
  }
  explode(pos, p) {
    const G = this.game;
    this.fx.emit(pos, 60, { color: '#ff7a1a', speed: 7, life: 0.7, size: 0.5, gravity: -1 });
    this.fx.emit(pos, 30, { color: '#ffe08a', speed: 3, life: 0.5, size: 0.4, gravity: -2 });
    this.dust.emit(pos, 20, { color: '#3a3a3a', speed: 2, life: 1.2, size: 0.5, gravity: -1.5 });
    G.audio.boom();
    for (const e of G.enemies) {
      if (e.dead) continue;
      const d = e.center.distanceTo(pos);
      if (d < p.splash + e.radius) this.hitEnemy(e, p.dmg * (1 - 0.5 * d / (p.splash + e.radius)), p.skill, pos);
    }
  }
  healFx(pos) {
    this.fx.emit(pos, 40, { color: '#7affb0', speed: 1.5, life: 1.0, size: 0.2, gravity: -2.5, spread: 1.2 });
  }
  levelFx(pos, color) {
    this.fx.emit(pos, 80, { color, speed: 2.5, life: 1.4, size: 0.22, gravity: -3, spread: 1.0 });
  }
}
const _t = new THREE.Vector3();
