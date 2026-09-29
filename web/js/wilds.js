import * as THREE from 'three';
import { RNG, mtx, Batcher, cylGeo } from './util.js';
import { Builder, polar } from './world.js';

const DARK = '#4a3220';

export function buildWilds(W) {
  const R = new RNG(W.seed + 41);
  const batch = new Batcher();
  goblinCamp(W, R, batch);
  graveyard(W, R, batch);
  mine(W, R, batch);
  pond(W, R, batch);
  W.scene.add(batch.build(W.M));

  wolfSpawns(W, R);
}

function goblinCamp(W, R, batch) {
  const c = W.pois.camp; const y = W.heightAt(c.x, c.z);
  const face = Math.atan2(-c.x, -c.z); // toward village
  const B = Builder.at(W, batch, c.x, y, c.z, face);
  W.mapLabels.push({ x: c.x, z: c.z, text: 'Goblin Camp', danger: true });
  // campfire
  for (let i = 0; i < 9; i++) { const a = i / 9 * Math.PI * 2; B.geo('color', new THREE.DodecahedronGeometry(0.22, 0), Math.sin(a) * 0.8, 0.12, Math.cos(a) * 0.8, a, '#6a6660'); }
  for (let i = 0; i < 3; i++) B.add('wood', cylGeo(0.1, 0.1, 1.3, 6), mtx(0, 0.2, 0, i * 1.05, 1, 1, 1, Math.PI / 2 - 0.3), DARK);
  B.geo('fire', new THREE.ConeGeometry(0.45, 1.0, 6), 0, 0.6, 0, 0, '#ff7a1a');
  B.geo('fire', new THREE.ConeGeometry(0.25, 0.7, 5), 0.05, 0.6, 0.05, 1, '#ffd35a');
  W.addCircle(c.x, c.z, 0.9, y - 1, y + 1);
  // tents in ring (opening to the front)
  const tents = [];
  for (let i = 0; i < 6; i++) {
    const a = Math.PI * 0.35 + i / 5 * Math.PI * 1.3;
    const r = i === 3 ? 10.5 : R.range(7.5, 9.5), s = i === 3 ? 1.6 : R.range(0.9, 1.2);
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    B.geo('color', new THREE.ConeGeometry(1.8 * s, 2.6 * s, 6), x, 1.3 * s, z, R.range(0, 6), R.pick(['#8a6a4a', '#7a5a3a', '#6a5a3a', '#9a7a5a']));
    B.geo('color', new THREE.ConeGeometry(0.2, 0.9, 4), x, 2.8 * s, z, 0, DARK);
    B.geo('color', new THREE.PlaneGeometry(0.9 * s, 1.3 * s), x - Math.sin(a) * 1.55 * s, 0.65 * s, z - Math.cos(a) * 1.55 * s, a, '#1a1410');
    const p = B.P(x, z); W.addCircle(p.x, p.z, 1.5 * s);
    tents.push({ x, z, s, a });
  }
  // palisade arc behind the camp
  for (let a = Math.PI * 0.25; a < Math.PI * 1.75; a += 0.075) {
    const r = 15;
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    const h = R.range(2.0, 2.8);
    B.cyl('wood', x, h / 2, z, 0.2, h, '#6a4a2a', false, 6);
    B.geo('wood', new THREE.ConeGeometry(0.2, 0.5, 6), x, h + 0.25, z, 0, '#6a4a2a');
    const p = B.P(x, z); W.addCircle(p.x, p.z, 0.32);
  }
  // totems & crates
  for (const s of [-1, 1]) {
    const x = s * 3.2, z = 13;
    B.cyl('wood', x, 1.4, z, 0.22, 2.8, '#5a3a1a', true, 6);
    B.geo('color', new THREE.SphereGeometry(0.28, 8, 6), x, 2.9, z, 0, '#e6e0cc');
    B.box('color', x - 0.1, 2.92, z + 0.22, 0.08, 0.08, 0.05, '#111', false); B.box('color', x + 0.1, 2.92, z + 0.22, 0.08, 0.08, 0.05, '#111', false);
    B.box('color', x, 2.2, z, 0.9, 0.1, 0.1, '#c83a3a', false);
  }
  for (let i = 0; i < 4; i++) { const a = R.range(0, 6.28), r = R.range(4, 6); B.box('wood', Math.sin(a) * r, 0.35, Math.cos(a) * r, 0.7, 0.7, 0.7, '#8a6a3a', true, R.range(0, 1)); }
  // bones
  for (let i = 0; i < 8; i++) { const a = R.range(0, 6.28), r = R.range(2, 7); B.box('color', Math.sin(a) * r, 0.05, Math.cos(a) * r, 0.5, 0.08, 0.08, '#e6e0cc', false, R.range(0, 3)); }
  // spawns
  const sp = (type, lx, lz) => { const p = B.P(lx, lz); W.spawns.push({ type, x: p.x, z: p.z, leash: 26 }); };
  const big = tents[3];
  sp('goblin_chief', big.x * 0.7, big.z * 0.7);
  for (let i = 0; i < 5; i++) { const a = R.range(0, 6.28), r = R.range(3, 7); sp('goblin', Math.sin(a) * r, Math.cos(a) * r); }
  sp('goblin_archer', -5, 10); sp('goblin_archer', 5, 10);
  // scouts along the road
  for (let i = 0; i < 2; i++) sp('goblin', R.range(-8, 8), R.range(18, 26));
}

function graveyard(W, R, batch) {
  const c = W.pois.grave; const y = W.heightAt(c.x, c.z);
  const face = Math.atan2(-c.x, -c.z);
  const B = Builder.at(W, batch, c.x, y, c.z, face);
  W.mapLabels.push({ x: c.x, z: c.z, text: 'Old Graveyard', danger: true });
  const hw = 13, hd = 11;
  // low broken stone wall, gate toward village (+z)
  const wall = (x0, z0, x1, z1) => {
    const L = Math.hypot(x1 - x0, z1 - z0), n = Math.ceil(L / 1.2);
    for (let i = 0; i < n; i++) {
      if (R.chance(0.12)) continue;
      const t = (i + 0.5) / n; const x = x0 + (x1 - x0) * t, z = z0 + (z1 - z0) * t;
      const h = R.range(0.7, 1.3);
      B.box('stone', x, h / 2, z, x0 === x1 ? 0.5 : 1.25, h, x0 === x1 ? 1.25 : 0.5, '#aaa59a', true);
    }
  };
  wall(-hw, -hd, hw, -hd); wall(-hw, -hd, -hw, hd); wall(hw, -hd, hw, hd); wall(-hw, hd, -2, hd); wall(2, hd, hw, hd);
  for (const s of [-1, 1]) { B.box('stone', s * 2, 1.1, hd, 0.7, 2.2, 0.7, '#9a958a'); B.geo('color', new THREE.SphereGeometry(0.3, 8, 6), s * 2, 2.4, hd, 0, '#8a8a80'); }
  // tombstones
  for (let i = -4; i <= 4; i++) for (let j = -3; j <= 2; j++) {
    if (Math.abs(i) < 1 || R.chance(0.3)) continue;
    const x = i * 2.6 + R.range(-0.3, 0.3), z = j * 2.8 + R.range(-0.3, 0.3);
    const t = R.int(0, 2);
    const tilt = R.range(-0.2, 0.2);
    if (t === 0) { B.add('stone', BOX, mtx(x, 0.45, z, R.range(-0.2, 0.2), 0.6, 0.9, 0.18, tilt), '#b8b4aa'); B.geo('stone', new THREE.CylinderGeometry(0.3, 0.3, 0.18, 10, 1, false, 0, Math.PI), x, 0.9, z, 0, '#b8b4aa', 1, 1, 1, Math.PI / 2, Math.PI / 2); }
    else if (t === 1) { B.box('stone', x, 0.55, z, 0.12, 1.1, 0.12, '#9a968c', false); B.box('stone', x, 0.8, z, 0.6, 0.12, 0.12, '#9a968c', false); }
    else B.box('stone', x, 0.2, z, 0.8, 0.4, 0.5, '#a8a49a', false);
    B.box('color', x, 0.02, z + 0.8, 0.7, 0.05, 1.4, '#5a4a36', false);
    B.colBox(x, z, 0.6, 0.3, 0, 1);
  }
  // crypt at the back
  const K = B.sub(0, -hd + 3.5, 0);
  K.box('stone', 0, 1.6, 0, 5, 3.2, 4, '#9a968c');
  K.geo('stone', new THREE.ConeGeometry(3.6, 1.6, 4), 0, 4.0, 0, Math.PI / 4, '#8a867c', 1, 1, 0.8);
  for (const s of [-1, 1]) K.cyl('stone', s * 1.6, 1.5, 2.2, 0.25, 3.0, '#c8c4ba', true, 10);
  K.box('stone', 0, 3.1, 2.2, 4.2, 0.35, 0.8, '#b8b4aa', false);
  K.box('color', 0, 1.1, 2.02, 1.4, 2.2, 0.06, '#2a241c', false);
  K.box('metal', 0, 1.1, 2.06, 0.1, 2.0, 0.04, '#555', false);
  const kp = K.P(0, 2.8);
  W.interactables.push({ type: 'crypt', x: kp.x, y: y + 1, z: kp.z, r: 2.4, label: 'Crypt Door' });
  // eerie green glow
  for (let i = 0; i < 6; i++) { const x = R.range(-hw + 2, hw - 2), z = R.range(-hd + 2, hd - 2); B.geo('glow', new THREE.SphereGeometry(0.08, 6, 4), x, 0.6, z, 0, '#66ffcc'); }
  const sp = (type, lx, lz) => { const p = B.P(lx, lz); W.spawns.push({ type, x: p.x, z: p.z, leash: 24 }); };
  for (let i = 0; i < 5; i++) sp('skeleton', R.range(-9, 9), R.range(-6, 6));
  sp('skeleton_archer', -7, -6); sp('skeleton_archer', 7, -6);
  sp('skeleton', 0, 16);
}

function mine(W, R, batch) {
  const c = W.pois.mine; const y = W.heightAt(c.x, c.z);
  const face = Math.atan2(-c.x, -c.z);
  const B = Builder.at(W, batch, c.x, y, c.z, face);
  W.mapLabels.push({ x: c.x, z: c.z, text: 'Collapsed Mine' });
  // rock mound behind the entrance
  for (let i = 0; i < 14; i++) {
    const a = R.range(-1.4, 1.4), r = R.range(5, 9);
    const s = R.range(2, 4);
    B.geo('stone', new THREE.DodecahedronGeometry(1, 0), Math.sin(a) * r, s * 0.5, -Math.cos(a) * r, R.range(0, 6), '#8a857c', s, s * R.range(0.8, 1.4), s);
    const p = B.P(Math.sin(a) * r, -Math.cos(a) * r); W.addCircle(p.x, p.z, s * 0.9);
  }
  B.geo('stone', new THREE.DodecahedronGeometry(1, 0), 0, 3.5, -5, 0, '#7a756c', 5, 4, 3);
  // timber frame
  B.box('color', 0, 1.6, -2.4, 3.4, 3.2, 0.3, '#0a0806', false);
  for (const s of [-1, 1]) B.box('wood', s * 1.7, 1.7, -2.2, 0.35, 3.4, 0.35, DARK);
  B.box('wood', 0, 3.4, -2.2, 4.2, 0.4, 0.4, DARK, false);
  for (let i = 0; i < 4; i++) B.box('wood', 0, 0.6 + i * 0.75, -2.0, 3.3, 0.22, 0.08, '#7a5634', false, 0);
  B.add('wood', BOX, mtx(0, 1.7, -1.95, 0, 3.6, 0.22, 0.08, 0, 0.7), '#6a4a2a');
  B.colBox(0, -2.2, 3.6, 0.6, 0, 3.4);
  // mine cart & rails
  for (const s of [-1, 1]) B.box('metal', s * 0.5, 0.05, 0.5, 0.08, 0.08, 5, '#555', false);
  for (let z = -1.5; z < 3; z += 0.6) B.box('wood', 0, 0.02, z, 1.4, 0.06, 0.2, DARK, false);
  B.box('metal', 0, 0.6, 1.2, 1.0, 0.6, 1.4, '#5a5048', true);
  B.box('color', 0, 0.93, 1.2, 0.85, 0.1, 1.2, '#4a4a4a', false);
  B.cyl('color', 2.4, 1.0, 0.3, 0.06, 2.0, '#2a2a2a', true, 6); B.box('window', 2.4, 2.0, 0.3, 0.22, 0.3, 0.22, null, false);
  const ip = B.P(0, -0.8);
  W.interactables.push({ type: 'mine', x: ip.x, y: y + 1.2, z: ip.z, r: 3, label: 'Mine Entrance' });
}

function pond(W, R, batch) {
  const p = W.water; const B = Builder.at(W, batch, 0, 0, 0, 0);
  W.mapLabels.push({ x: p.x, z: p.z, text: 'Mirror Pond' });
  for (let i = 0; i < 70; i++) {
    const a = R.range(0, 6.28), r = p.r * R.range(0.85, 1.1);
    const x = p.x + Math.sin(a) * r, z = p.z + Math.cos(a) * r;
    const y = W.heightAt(x, z);
    B.add('color', cylGeo(0.02, 0.03, 1.2, 3), mtx(x, y + 0.5, z, 0, 1, R.range(0.6, 1.4), 1, R.range(-0.15, 0.15), R.range(-0.15, 0.15)), '#6a8a3a');
    if (R.chance(0.3)) B.add('color', cylGeo(0.05, 0.05, 0.22, 5), mtx(x, y + 1.05, z), '#5a3a1a');
  }
  for (let i = 0; i < 10; i++) {
    const a = R.range(0, 6.28), r = p.r * R.range(0.2, 0.7);
    B.geo('glow', new THREE.CircleGeometry(R.range(0.3, 0.55), 8), p.x + Math.sin(a) * r, p.y + 0.02, p.z + Math.cos(a) * r, 0, '#3a7a2a', 1, 1, 1, -Math.PI / 2);
  }
  // small dock
  const a = Math.atan2(-p.x, -p.z);
  const D = B.sub(p.x + Math.sin(a) * (p.r - 1), p.z + Math.cos(a) * (p.r - 1), a + Math.PI, p.y + 0.35);
  D.box('wood', 0, 0, 0, 1.6, 0.12, 5, '#8a6a44', false);
  for (const s of [-1, 1]) for (const z of [-2, 0, 2]) D.box('wood', s * 0.7, -0.6, z, 0.15, 1.4, 0.15, '#5a3a1a', false);
  const d0 = D.P(-0.8, -2.5), d1 = D.P(0.8, 2.5);
  W.addFloor(Math.min(d0.x, d1.x), Math.max(d0.x, d1.x), Math.min(d0.z, d1.z), Math.max(d0.z, d1.z), p.y + 0.41);
}

export function herbsAndChests(W, R = new RNG(W.seed + 43)) {
  W.herbs = []; W.chests = [];
  const herbGeo = new THREE.Group();
  let tries = 0;
  while (W.herbs.length < 26 && tries++ < 2000) {
    const a = R.range(0, 6.28), r = R.range(70, 170);
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    if (!W.isClear(x, z, 2)) continue;
    const y = W.heightAt(x, z);
    const g = new THREE.Group(); g.position.set(x, y, z);
    for (let i = 0; i < 5; i++) {
      const s = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.4, 3), new THREE.MeshLambertMaterial({ color: '#3a6a3a' }));
      const ox = R.range(-0.2, 0.2), oz = R.range(-0.2, 0.2); s.position.set(ox, 0.2, oz); g.add(s);
      const f = new THREE.Mesh(new THREE.OctahedronGeometry(0.09), new THREE.MeshBasicMaterial({ color: '#8ad8ff' })); f.position.set(ox, 0.42, oz); g.add(f);
    }
    W.scene.add(g);
    const it = { type: 'herb', x, y: y + 0.4, z, r: 1.8, label: 'Pick Moonpetal', mesh: g, respawn: 0 };
    W.herbs.push(it); W.interactables.push(it);
  }
  const spots = [...W.rockSpots].filter((p) => Math.hypot(p.x, p.z) > 80 && Math.hypot(p.x, p.z) < 170);
  R.shuffle(spots);
  let id = 0;
  for (const s of spots) {
    if (W.chests.length >= 6) break;
    const x = s.x + 1.8, z = s.z + 1.0;
    if (!W.isClear(x, z, 1)) continue;
    const y = W.heightAt(x, z);
    const g = new THREE.Group(); g.position.set(x, y, z); g.rotation.y = R.range(0, 6);
    const wood = new THREE.MeshStandardMaterial({ color: '#7a4a24', roughness: 0.8 });
    const gold = new THREE.MeshStandardMaterial({ color: '#d8a830', roughness: 0.4, metalness: 0.7 });
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.5, 0.6), wood); body.position.y = 0.25; body.castShadow = true; g.add(body);
    const lidPivot = new THREE.Group(); lidPivot.position.set(0, 0.5, -0.3); g.add(lidPivot);
    const lid = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.9, 10, 1, false, 0, Math.PI), wood); lid.rotation.z = Math.PI / 2; lid.position.set(0, 0, 0.3); lid.castShadow = true; lidPivot.add(lid);
    for (const bx of [-0.3, 0.3]) { const b = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.52, 0.62), gold); b.position.set(bx, 0.25, 0); g.add(b); }
    const lock = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.16, 0.04), gold); lock.position.set(0, 0.45, 0.31); g.add(lock);
    W.scene.add(g);
    W.addCircle(x, z, 0.5, y - 1, y + 0.6);
    const it = { type: 'chest', id: id++, x, y: y + 0.4, z, r: 2, label: 'Open Chest', mesh: g, lid: lidPivot, openedDay: -1 };
    W.chests.push(it); W.interactables.push(it);
  }
}

function wolfSpawns(W, R) {
  let n = 0, tries = 0;
  while (n < 13 && tries++ < 500) {
    const a = R.range(0, 6.28), r = R.range(78, 168);
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    if (Math.hypot(x - W.pois.camp.x, z - W.pois.camp.z) < 35 || Math.hypot(x - W.pois.grave.x, z - W.pois.grave.z) < 35) continue;
    if (!W.isClear(x, z, 0)) continue;
    const pack = R.int(1, 2);
    for (let i = 0; i < pack; i++) W.spawns.push({ type: 'wolf', x: x + R.range(-3, 3), z: z + R.range(-3, 3), leash: 30 });
    n++;
  }
}
const BOX = new THREE.BoxGeometry(1, 1, 1);
