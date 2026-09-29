import * as THREE from 'three';
import { RNG, mtx, Batcher, cylGeo } from './util.js';
import { Builder, polar } from './world.js';
import { Assets } from './assets.js';

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
  B.prop('village', 'Bonfire_Fire', 0, 0, 0, 0, 0.75, { collide: false });
  B.geo('fire', new THREE.ConeGeometry(0.35, 0.9, 6), 0, 0.55, 0, 0, '#ff7a1a');
  B.geo('fire', new THREE.ConeGeometry(0.2, 0.6, 5), 0.05, 0.5, 0.05, 1, '#ffd35a');
  W.addCircle(c.x, c.z, 0.9, y - 1, y + 1);
  // tents in ring (opening to the front)
  const tents = [];
  for (let i = 0; i < 6; i++) {
    const a = Math.PI * 0.35 + i / 5 * Math.PI * 1.3;
    const r = i === 3 ? 10.5 : R.range(7.5, 9.5), s = i === 3 ? 1.6 : R.range(0.9, 1.2);
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    B.prop('village', 'Tent', x, -0.05, z, a + Math.PI, 0.2 * s, { collide: false, tint: R.pick(['#ffffff', '#e8d8c0', '#d0c0a0']) });
    const p = B.P(x, z); W.addCircle(p.x, p.z, 1.6 * s);
    tents.push({ x, z, s, a });
  }
  // palisade arc behind the camp
  for (let a = Math.PI * 0.25; a < Math.PI * 1.75; a += 0.075) {
    const r = 15;
    const x = Math.sin(a) * r, z = Math.cos(a) * r;
    const h = R.range(2.0, 2.8);
    B.cyl('log', x, h / 2, z, 0.2, h, '#d8c0a0', false, 6);
    B.geo('log', new THREE.ConeGeometry(0.2, 0.5, 6), x, h + 0.25, z, 0, '#d8c0a0');
    const p = B.P(x, z); W.addCircle(p.x, p.z, 0.32);
  }
  // totems & crates
  for (const s of [-1, 1]) {
    const x = s * 3.2, z = 13;
    B.prop('halloween', 'post_skull', x, 0, z, s > 0 ? -Math.PI / 2 : Math.PI / 2, 1.1);
  }
  for (let i = 0; i < 5; i++) { const a = R.range(0, 6.28), r = R.range(4, 6); B.prop('dungeon', R.pick(['box_small', 'box_large', 'barrel_small', 'crates_stacked']), Math.sin(a) * r, 0, Math.cos(a) * r, R.int(0, 3) * Math.PI / 2, 0.6); }
  for (let i = 0; i < 10; i++) { const a = R.range(0, 6.28), r = R.range(2, 8); B.prop('halloween', R.pick(['bone_A', 'bone_B', 'skull', 'ribcage']), Math.sin(a) * r, 0.05, Math.cos(a) * r, R.range(0, 6), 0.5, { collide: false }); }
  B.prop('village', 'Pot', 1.6, 0, -1.2, 0.5, 0.5, { collide: false });
  B.prop('village', 'WoodLog', -1.8, 0, 0.8, 1.2, 0.45);
  B.prop('village', 'WoodLog', 0.6, 0, 1.9, 2.6, 0.45);
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
  // wrought-iron fence around the yard, gate facing the village (+z)
  const fenceRun = (x0, z0, x1, z1) => {
    const L = Math.hypot(x1 - x0, z1 - z0), n = Math.max(1, Math.round(L / 2.9)), ry = Math.atan2(x1 - x0, z1 - z0) - Math.PI / 2;
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n;
      B.prop('halloween', R.chance(0.2) ? 'fence_broken' : 'fence', x0 + (x1 - x0) * t, 0, z0 + (z1 - z0) * t, ry, 0.72 * (L / n) / 2.9 / 0.72 * 1.0);
      B.prop('halloween', 'fence_pillar', x0 + (x1 - x0) * i / n, 0, z0 + (z1 - z0) * i / n, 0, 1);
    }
  };
  fenceRun(-hw, -hd, hw, -hd); fenceRun(-hw, -hd, -hw, hd); fenceRun(hw, -hd, hw, hd); fenceRun(-hw, hd, -2.2, hd); fenceRun(2.2, hd, hw, hd);
  B.prop('halloween', 'arch_gate', 0, 0, hd, 0, 1.05, { collide: false });
  for (const s2 of [-1, 1]) B.colBox(s2 * 1.9, hd, 0.5, 0.6, 0, 3);
  // graves
  for (let i = -4; i <= 4; i++) for (let j = -3; j <= 2; j++) {
    if (Math.abs(i) < 1 || R.chance(0.3)) continue;
    const x = i * 2.6 + R.range(-0.3, 0.3), z = j * 2.8 + R.range(-0.3, 0.3);
    B.prop('halloween', R.pick(['grave_A', 'grave_B', 'grave_A_destroyed', 'gravestone', 'gravemarker_A', 'gravemarker_B', 'gravestone']), x, 0, z, R.range(-0.15, 0.15), R.range(0.8, 1.0));
  }
  // crypt at the back
  const K = B.sub(0, -hd + 4, 0);
  K.prop('halloween', 'crypt', 0, 0, 0, Math.PI, 1.05);
  const kp = K.P(0, 3.4);
  W.interactables.push({ type: 'crypt', x: kp.x, y: y + 1, z: kp.z, r: 2.6, label: 'Crypt Door' });
  // spooky dressing
  for (const [x, z] of [[-hw + 1.5, hd - 1.5], [hw - 1.5, hd - 1.5], [-hw + 1.5, -hd + 1.5], [hw - 1.5, -hd + 1.5]]) B.prop('halloween', 'post_lantern', x, 0, z, Math.atan2(-x, -z), 1);
  for (let i = 0; i < 5; i++) B.prop('halloween', R.pick(['tree_dead_large', 'tree_dead_medium', 'tree_dead_small']), R.pick([-1, 1]) * R.range(hw + 2, hw + 6), 0, R.range(-hd, hd), R.range(0, 6), 1.3);
  for (let i = 0; i < 6; i++) B.prop('halloween', R.pick(['pumpkin_orange', 'pumpkin_orange_jackolantern', 'skull_candle', 'candle_triple', 'bone_A']), R.range(-hw + 1, hw - 1), 0, R.range(-hd + 6, hd - 1), R.range(0, 6), 0.8, { collide: false });
  B.prop('halloween', 'coffin', 6, 0, -hd + 3, 0.3, 0.8);
  B.prop('halloween', 'shrine_candles', -6, 0, -hd + 3, 0, 0.9);
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
  B.prop('dungeon', 'rubble_large', 0, 0, -1.2, 0, 0.55, { collide: false });
  for (const s2 of [-1, 1]) B.prop('dungeon', 'torch_lit', s2 * 2.6, 0, -1.4, 0, 1.2, { collide: false });
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
    const closed = Assets.clone('village', 'Chest_Closed'), open = Assets.clone('village', 'Chest_Open');
    closed.scale.setScalar(1.1); open.scale.setScalar(1.1); open.visible = false;
    g.add(closed, open);
    const lidPivot = { rotation: { _x: 0, get x() { return this._x; }, set x(v) { this._x = v; closed.visible = v === 0; open.visible = v !== 0; } } };
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
