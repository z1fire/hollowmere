import * as THREE from 'three';
import { RNG, mtx, Batcher, cylGeo, distToSeg, angleDiff } from './util.js';
import { Builder, polar } from './world.js';
import { signTexture } from './textures.js';

const DARK = '#8a6a52', MID = '#b89878', LIGHT = '#d8c0a0';

export const BTYPES = {
  townhall:  { w: 12, d: 9, h: 4.2, wall: 'plaster', roof: 'shingle', name: 'Town Hall', role: 'mayor' },
  tavern:    { w: 12, d: 10, h: 4, wall: 'plaster', roof: 'thatch', name: 'The Tipsy Turnip', role: 'innkeeper', chimney: true },
  smithy:    { w: 9, d: 8, h: 3.6, wall: 'stone', roof: 'shingle', name: 'Smithy', role: 'smith', chimney: true },
  store:     { w: 9, d: 8, h: 3.6, wall: 'plaster', roof: 'shingle', name: 'General Store', role: 'merchant' },
  herbalist: { w: 7, d: 7, h: 3.3, wall: 'plaster', roof: 'thatch', name: 'Herbalist', role: 'herbalist', chimney: true },
  magetower: { w: 7, d: 7, h: 9, wall: 'stone', roof: 'cone', name: 'Mage Tower', role: 'mage' },
  hunter:    { w: 8, d: 7, h: 3.3, wall: 'log', roof: 'thatch', name: 'Hunter\'s Lodge', role: 'hunter' },
  chapel:    { w: 8, d: 13, h: 5, wall: 'stone', roof: 'shingle', name: 'Chapel', role: 'priest' },
  house:     { w: 7, d: 6, h: 3.1, wall: 'plaster', roof: 'thatch', name: 'Cottage', chimney: true },
  farmhouse: { w: 9, d: 7, h: 3.3, wall: 'plaster', roof: 'thatch', name: 'Your Farmhouse', chimney: true },
};

const facingRot = (x, z) => { const t = Math.atan2(-x, -z); return ((Math.round(t / (Math.PI / 2)) % 4) + 4) % 4; };

function rectOf(x, z, w, d, rot, m = 0) {
  const W = rot % 2 ? d : w, D = rot % 2 ? w : d;
  return { minX: x - W / 2 - m, maxX: x + W / 2 + m, minZ: z - D / 2 - m, maxZ: z + D / 2 + m };
}
const overlap = (a, b) => a.minX < b.maxX && a.maxX > b.minX && a.minZ < b.maxZ && a.maxZ > b.minZ;

// ---------------- PLAN ----------------
export function planVillage(W) {
  const R = new RNG(W.seed + 11);
  const placed = [];
  const roadHits = (rect) => {
    for (const r of W.roads) for (let i = 0; i < r.pts.length - 1; i++) {
      const a = r.pts[i], b = r.pts[i + 1];
      const cx = (rect.minX + rect.maxX) / 2, cz = (rect.minZ + rect.maxZ) / 2;
      const hd = Math.hypot(rect.maxX - rect.minX, rect.maxZ - rect.minZ) / 2;
      if (distToSeg(cx, cz, a.x, a.z, b.x, b.z) < hd + r.w / 2 + 0.5) {
        // finer check by sampling
        const L = Math.hypot(b.x - a.x, b.z - a.z);
        for (let t = 0; t <= L; t += 0.8) {
          const x = a.x + (b.x - a.x) * t / L, z = a.z + (b.z - a.z) * t / L;
          if (x > rect.minX - r.w / 2 && x < rect.maxX + r.w / 2 && z > rect.minZ - r.w / 2 && z < rect.maxZ + r.w / 2) return true;
        }
      }
    }
    return false;
  };
  const inside = (rect, maxR) => [[rect.minX, rect.minZ], [rect.maxX, rect.minZ], [rect.minX, rect.maxZ], [rect.maxX, rect.maxZ]].every(([x, z]) => Math.hypot(x, z) < maxR);
  const nearPlaza = (rect) => { const cx = Math.max(rect.minX, Math.min(0, rect.maxX)), cz = Math.max(rect.minZ, Math.min(0, rect.maxZ)); return Math.hypot(cx, cz) < 14; };

  // farm: between gate 0 and gate 1
  const g0 = W.gates[0], g1 = W.gates[1];
  let farmA = g0 + angleDiff(g0, g1) / 2;
  let farm = null;
  for (let t = 0; t < 60 && !farm; t++) {
    const a = farmA + R.range(-0.35, 0.35), r = R.range(36, 42);
    const p = polar(a, r); const rot = facingRot(p.x, p.z);
    const def = BTYPES.farmhouse;
    const rect = rectOf(p.x, p.z, def.w, def.d, rot, 2);
    // field to local +x side of the house
    const ang = rot * Math.PI / 2, c = Math.cos(ang), s = Math.sin(ang);
    const lx = def.w / 2 + 6.5, lz = 0.5;
    const fx = p.x + lx * c + lz * s, fz = p.z - lx * s + lz * c;
    const fRect = rectOf(fx, fz, 10, 8.5, rot, 1.5);
    if (roadHits(rect) || roadHits(fRect) || !inside(rect, 55) || !inside(fRect, 56)) continue;
    farm = { x: p.x, z: p.z, rot, fx, fz, rect, fRect };
  }
  if (!farm) { const p = polar(farmA, 38); const rot = facingRot(p.x, p.z); farm = { x: p.x, z: p.z, rot, fx: p.x + 10, fz: p.z, rect: rectOf(p.x, p.z, 9, 7, rot, 2), fRect: rectOf(p.x + 10, p.z, 10, 8.5, rot, 1.5) }; }
  W.farm = farm;
  placed.push(farm.rect, farm.fRect);
  W.buildings.push({ type: 'farmhouse', x: farm.x, z: farm.z, rot: farm.rot, ...BTYPES.farmhouse });

  const order = ['townhall', 'tavern', 'smithy', 'store', 'chapel', 'herbalist', 'magetower', 'hunter', 'house', 'house', 'house', 'house', 'house'];
  for (const type of order) {
    const def = BTYPES[type];
    let done = false;
    for (let t = 0; t < 400 && !done; t++) {
      const relax = t / 400;
      const minR = type === 'townhall' || type === 'tavern' ? 17 : type === 'magetower' || type === 'hunter' ? 28 : 18;
      const maxR = type === 'townhall' || type === 'tavern' ? 30 + relax * 20 : 50;
      const a = R.range(0, Math.PI * 2), r = R.range(minR, maxR);
      const p = polar(a, r); const rot = facingRot(p.x, p.z);
      const rect = rectOf(p.x, p.z, def.w, def.d, rot, 2.5);
      if (!inside(rect, 56) || nearPlaza(rect) || roadHits(rect) || placed.some((o) => overlap(o, rect))) continue;
      placed.push(rect);
      W.buildings.push({ type, x: p.x, z: p.z, rot, ...def });
      done = true;
    }
  }
  // per-building flats, exclusions, door paths
  for (const b of W.buildings) {
    b.floorY = W.baseHeight(b.x, b.z) * 0 + W.plazaY + 0.32;
    const hd = Math.hypot(b.w, b.d) / 2;
    W.flats.push({ x: b.x, z: b.z, r: hd + 0.8, fall: 5, h: W.plazaY });
    const rr = rectOf(b.x, b.z, b.w, b.d, b.rot, 1.5);
    W.excl.push({ t: 'r', ...rr });
    const ang = b.rot * Math.PI / 2, c = Math.cos(ang), s = Math.sin(ang);
    const lz = b.d / 2 + 1.3;
    const door = { x: b.x + lz * s, z: b.z + lz * c };
    b.doorFront = door;
    const da = Math.atan2(door.x, door.z);
    if (b.type !== 'farmhouse' || true) W.roads.push({ pts: [door, polar(da, 11)], w: 1.6, main: false });
  }
  W.flats.push({ x: farm.fx, z: farm.fz, r: 7, fall: 5, h: W.plazaY });
  W.excl.push({ t: 'r', ...farm.fRect });
}

// ---------------- BUILD ----------------
export function buildVillage(W) {
  const R = new RNG(W.seed + 23);
  for (const b of W.buildings) buildBuilding(W, b, R);
  buildFarmField(W, R);
  buildPlaza(W, R);
  buildFence(W, R);
  buildVillageProps(W, R);
  buildWaypoints(W);
}

function buildBuilding(W, b, R) {
  const batch = new Batcher();
  const ang = b.rot * Math.PI / 2;
  const B = Builder.at(W, batch, b.x, b.floorY, b.z, ang);
  const { w, d, h } = b; const hw = w / 2, hd = d / 2, T = 0.3, DW = 1.7, DH = 2.5;
  const wallKey = b.wall;
  const wallColor = wallKey === 'plaster' ? R.pick(['#fff4e0', '#f4e8d0', '#ffeede', '#efe4d6', '#fbe9c9']) : wallKey === 'stone' ? R.pick(['#ffffff', '#e8e4dc', '#d8d4cc']) : '#ffffff';
  const trim = R.pick(['#3f6a8a', '#7a2f2f', '#3f7a4a', '#6a4a8a', '#8a6a2f']);
  b.npcs = [];

  // foundation + floor
  B.box('stone', 0, -0.33, 0, w + 0.3, 0.66, d + 0.3, '#9a958c', false);
  B.box('wood', 0, 0.02, 0, w - 0.2, 0.06, d - 0.2, '#c8a276', false);
  B.floor(-hw, hw, -hd, hd, 0.05);
  // step
  B.box('stone', 0, -0.2, hd + 0.55, DW + 0.8, 0.4, 0.9, '#8a867e', false);
  B.floor(-DW / 2 - 0.4, DW / 2 + 0.4, hd, hd + 1.0, 0.0);
  // walls
  B.box(wallKey, 0, h / 2, -hd + T / 2, w, h, T, wallColor);
  B.box(wallKey, -hw + T / 2, h / 2, 0, T, h, d - 2 * T, wallColor);
  B.box(wallKey, hw - T / 2, h / 2, 0, T, h, d - 2 * T, wallColor);
  const seg = hw - DW / 2;
  B.box(wallKey, -hw + seg / 2, h / 2, hd - T / 2, seg, h, T, wallColor);
  B.box(wallKey, hw - seg / 2, h / 2, hd - T / 2, seg, h, T, wallColor);
  B.box(wallKey, 0, (DH + h) / 2, hd - T / 2, DW, h - DH, T, wallColor, false);
  // timber framing
  if (wallKey === 'plaster') {
    for (const [x, z] of [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]) B.box('beam', x, h / 2, z, 0.34, h, 0.34, DARK, false);
    B.box('beam', 0, h - 0.1, -hd - 0.02, w, 0.22, T + 0.1, DARK, false);
    B.box('beam', 0, h - 0.1, hd + 0.02, w, 0.22, T + 0.1, DARK, false);
    B.box('beam', -hw - 0.02, h - 0.1, 0, T + 0.1, 0.22, d, DARK, false);
    B.box('beam', hw + 0.02, h - 0.1, 0, T + 0.1, 0.22, d, DARK, false);
    for (const s of [-1, 1]) for (let x = -hw + 2.2; x < hw - 1; x += 2.8) if (Math.abs(x) > 2.2) B.box('beam', x, h / 2, s * (hd + 0.03), 0.18, h, 0.06, DARK, false);
    for (const s of [-1, 1]) for (let z = -hd + 2.2; z < hd - 1; z += 2.8) B.box('beam', s * (hw + 0.03), h / 2, z, 0.06, h, 0.18, DARK, false);
  } else if (wallKey === 'stone') {
    for (const [x, z] of [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]) B.box('stone', x, h / 2, z, 0.5, h + 0.1, 0.5, '#bdb8ae', false);
  } else {
    for (const [x, z] of [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]) B.cyl('log', x, h / 2, z, 0.2, h + 0.2, '#ffffff', false, 8);
  }
  // door frame + open door
  B.box('beam', -DW / 2 - 0.08, DH / 2, hd, 0.16, DH, T + 0.14, DARK, false);
  B.box('beam', DW / 2 + 0.08, DH / 2, hd, 0.16, DH, T + 0.14, DARK, false);
  B.box('beam', 0, DH + 0.08, hd, DW + 0.32, 0.16, T + 0.14, DARK, false);
  B.box('wood', DW / 2 - 0.05, DH / 2 + 0.02, hd - T - 0.72, 0.08, DH - 0.06, 1.45, '#8a5a30', true);
  // windows
  const winY = [1.6];
  if (b.type === 'magetower') winY.push(4.6, 7.4);
  if (b.type === 'chapel') winY[0] = 2.2;
  const addWin = (x, z, rotated) => {
    for (const y of winY) {
      const wx = rotated ? T + 0.14 : 1.0, wz = rotated ? 1.0 : T + 0.14;
      B.box('beam', x, y, z, wx, 1.05, wz, DARK, false);
      B.box('window', x, y, z, rotated ? T + 0.16 : 0.8, 0.85, rotated ? 0.8 : T + 0.16, null, false);
      B.box('beam', x, y, z, rotated ? T + 0.18 : 0.06, 0.85, rotated ? 0.06 : T + 0.18, DARK, false);
      B.box('beam', x, y, z, rotated ? T + 0.18 : 0.8, 0.06, rotated ? 0.8 : T + 0.18, DARK, false);
      // shutters
      if (b.type !== 'magetower' && b.type !== 'chapel') {
        const out = rotated ? Math.sign(x) : Math.sign(z);
        if (rotated) { for (const s of [-1, 1]) B.box('color', x + out * (T / 2 + 0.06), y, z + s * 0.72, 0.05, 0.95, 0.42, trim, false); }
        else { for (const s of [-1, 1]) B.box('color', x + s * 0.72, y, z + out * (T / 2 + 0.06), 0.42, 0.95, 0.05, trim, false); }
      }
    }
  };
  const nx = Math.max(1, Math.floor(w / 3.5)), nz = Math.max(1, Math.floor(d / 3.5));
  for (let i = 0; i < nx; i++) addWin(-hw + (i + 0.5) * (w / nx), -hd + T / 2, false);
  for (let i = 0; i < nz; i++) { const z = -hd + (i + 0.5) * (d / nz); if (z < hd - 1.5) { addWin(-hw + T / 2, z, true); addWin(hw - T / 2, z, true); } }
  if (w >= 9) { addWin(-hw + 1.6, hd - T / 2, false); addWin(hw - 1.6, hd - T / 2, false); }

  // roof
  if (b.roof === 'cone') {
    B.geo('shingle', new THREE.ConeGeometry(w * 0.78, 4.8, 4), 0, h + 2.4, 0, Math.PI / 4, '#ffffff');
    B.geo('color', new THREE.OctahedronGeometry(0.25), 0, h + 5.0, 0, 0, '#ffd84a');
    B.box('stone', 0, h + 0.15, 0, w + 0.4, 0.3, d + 0.4, '#bdb8ae', false);
    // inner ceiling so interior feels closed
    B.box('wood', 0, h - 0.05, 0, w - 0.3, 0.1, d - 0.3, '#8a6a44', false);
  } else {
    gableRoof(B, b, wallKey, wallColor);
  }
  if (b.chimney) {
    const cx = hw - 1.4, cz = -hd + 1.2;
    B.box('stone', cx, h + 1.4, cz, 0.8, 2.8, 0.8, '#a09a90', false);
    B.box('stone', cx, h + 2.85, cz, 0.95, 0.15, 0.95, '#8a847a', false);
  }
  if (b.type === 'chapel') {
    B.box('stone', 0, h + 3.2, hd - 1.2, 1.8, 3.6, 1.8, '#dedad0', false);
    B.geo('shingle', new THREE.ConeGeometry(1.6, 2.4, 4), 0, h + 6.2, hd - 1.2, Math.PI / 4, '#ffffff');
    B.box('color', 0, h + 3.4, hd - 1.2, 1.85, 0.9, 0.5, '#222', false);
    B.box('color', 0, h + 8.0, hd - 1.2, 0.08, 0.9, 0.08, '#ffd84a', false);
    B.box('color', 0, h + 8.1, hd - 1.2, 0.5, 0.08, 0.08, '#ffd84a', false);
  }

  // sign
  if (b.type !== 'house') {
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 0.45), new THREE.MeshStandardMaterial({ map: signTexture(b.name), roughness: 0.8, side: THREE.DoubleSide }));
    const sp = B.P(0, hd + 0.2, Math.min(h - 0.3, DH + 0.55));
    sign.position.copy(sp); sign.rotation.y = ang;
    W.scene.add(sign);
    W.mapLabels.push({ x: b.x, z: b.z, text: b.name });
  }

  // interior
  b.inner = (() => { const a = B.P(-hw + T, -hd + T), c = B.P(hw - T, hd - T + 0.05); return { minX: Math.min(a.x, c.x), maxX: Math.max(a.x, c.x), minZ: Math.min(a.z, c.z), maxZ: Math.max(a.z, c.z) }; })();
  b.lightPos = B.P(0, 0, Math.min(h - 0.8, 3.2));
  b.B = B; b.ang = ang;
  const npc = (role, lx, lz, lyaw, extra = {}) => { const p = B.P(lx, lz); b.npcs.push({ role, x: p.x, z: p.z, y: b.floorY + 0.05, yaw: lyaw + ang, building: b, ...extra }); };
  INTERIORS[b.type]?.(B, b, R, npc, W);

  const grp = batch.build(W.M);
  W.scene.add(grp);
}

function gableRoof(B, b, wallKey, wallColor) {
  const { w, d, h } = b;
  const alongX = w >= d;
  const L = alongX ? w : d, S = alongX ? d : w;
  const oh = 0.5, half = S / 2 + oh, rh = S * 0.42;
  const slope = rh / (S / 2), angR = Math.atan(slope);
  const slabLen = Math.hypot(half, half * slope);
  const frame = alongX ? new THREE.Matrix4() : new THREE.Matrix4().makeRotationY(Math.PI / 2);
  const key = b.roof, rc = b.roof === 'thatch' ? '#ffffff' : '#ffffff';
  for (const s of [1, -1]) {
    const zc = s * half / 2, yc = h + rh - slope * (half / 2);
    B.add(key, BOX, frame.clone().multiply(mtx(0, yc + 0.08, zc, 0, L + 2 * oh, 0.16, slabLen + 0.05, s * angR)), rc);
    // underside boards visible from inside
    B.add('wood', BOX, frame.clone().multiply(mtx(0, yc - 0.02, zc * 0.96, 0, L - 0.1, 0.04, slabLen * 0.93, s * angR)), '#6a4a2a');
  }
  const shape = new THREE.Shape([new THREE.Vector2(-S / 2, 0), new THREE.Vector2(S / 2, 0), new THREE.Vector2(0, rh)]);
  const tri = new THREE.ExtrudeGeometry(shape, { depth: 0.3, bevelEnabled: false }); tri.translate(0, 0, -0.15);
  for (const s of [1, -1]) B.add(wallKey, tri, frame.clone().multiply(mtx(s * (L / 2 - 0.15), h, 0, Math.PI / 2)), wallColor);
  B.add('beam', BOX, frame.clone().multiply(mtx(0, h + rh + 0.06, 0, 0, L + 2 * oh + 0.1, 0.2, 0.26)), '#6a5040');
  // rafters
  for (let x = -L / 2 + 1; x < L / 2 - 0.5; x += 2) B.add('beam', BOX, frame.clone().multiply(mtx(x, h - 0.05, 0, 0, 0.14, 0.14, S - 0.4)), DARK);
}
const BOX = new THREE.BoxGeometry(1, 1, 1);

// ---------------- FURNITURE ----------------
const F = {
  table(B, x, z, w = 1.4, d = 0.8, ry = 0) {
    B.prop('dungeon', 'table_small', x, 0.04, z, ry, 1, { sx: w / 0.72, sy: 1.06, sz: d / 0.72 });
    return B.sub(x, z, ry);
  },
  roundTable(B, x, z, r = 0.6) {
    B.prop('dungeon', 'table_small', x, 0.04, z, 0, 1, { sx: r * 2 / 0.72, sy: 1.06, sz: r * 2 / 0.72 });
  },
  chair(B, x, z, ry = 0) { B.prop('dungeon', 'chair', x, 0.04, z, ry + Math.PI, 1); },
  stool(B, x, z) { B.prop('dungeon', 'stool', x, 0.04, z, 0, 1); },
  bed(B, x, z, ry = 0) { B.prop('furniture', 'bed_single_A', x, 0.04, z, ry + Math.PI, 1.12); return B.sub(x, z, ry); },
  barrel(B, x, z, r = 0.36) { B.prop('dungeon', 'barrel_small', x, 0.04, z, (x * 7 + z) % 6, r * 2 / 0.72); },
  crate(B, x, z, s = 0.7, y = 0, ry = 0) { B.prop('dungeon', 'box_small', x, y + 0.04, z, ry, s / 0.72); },
  shelf(B, x, z, ry = 0, w = 1.8) {
    B.prop('furniture', 'cabinet_medium_decorated', x, 0.04, z + 0, ry, 1, { sx: w / 1.26, sy: 1.25, sz: 0.85 });
  },
  bookshelf(B, x, z, ry = 0, w = 1.8) {
    const s = B.sub(x, z, ry);
    s.prop('furniture', 'cabinet_medium_decorated', 0, 0.04, 0.05, 0, 1, { sx: w / 1.26, sy: 1.25, sz: 0.85 });
    for (let k = -w / 2 + 0.35; k < w / 2 - 0.2; k += 0.55) s.prop('furniture', 'book_set', k, 1.46, 0.05, 0, 1, { collide: false });
  },
  counter(B, x, z, len, ry = 0) {
    const s = B.sub(x, z, ry);
    s.box('wood', 0, 0.5, 0, len, 1.0, 0.7, '#a07850');
    s.box('beam', 0, 1.03, 0, len + 0.1, 0.06, 0.8, LIGHT, false);
    s.prop('dungeon', 'candle_triple', len / 2 - 0.35, 1.06, 0, 0, 0.4, { collide: false });
    s.prop('dungeon', 'bottle_A_brown', -len / 2 + 0.4, 1.06, 0.05, 0, 0.3, { collide: false });
    s.prop('dungeon', 'bottle_B_green', -len / 2 + 0.7, 1.06, -0.1, 0, 0.3, { collide: false });
    return s;
  },
  fireplace(B, x, z, ry = 0, W) {
    const s = B.sub(x, z, ry);
    s.box('stone', 0, 0.9, 0, 1.8, 1.8, 0.8, '#d0c8bc');
    s.box('color', 0, 0.45, 0.41, 1.0, 0.8, 0.02, '#1a1410', false);
    s.box('fire', 0, 0.3, 0.3, 0.6, 0.35, 0.25, '#ff8a2a', false);
    s.box('fire', 0, 0.45, 0.3, 0.3, 0.3, 0.2, '#ffd35a', false);
    s.box('stone', 0, 2.5, -0.1, 1.0, 1.6, 0.5, '#c8c0b4', false);
    s.box('beam', 0, 1.85, 0.2, 2.0, 0.1, 0.5, DARK, false);
    s.prop('dungeon', 'candle_triple', 0.6, 1.9, 0.2, 0, 0.55, { collide: false });
    s.prop('dungeon', 'bottle_A_green', -0.6, 1.9, 0.25, 0, 0.45, { collide: false });
  },
  rug(B, x, z, w, d, color, ry = 0) {
    B.prop('furniture', (Math.abs(x * 13 + z * 7) | 0) % 2 ? 'rug_rectangle_A' : 'rug_rectangle_stripes_A', x, 0.05, z, ry, 1, { sx: w / 1.86, sy: 0.6, sz: d / 1.24, collide: false });
  },
  pew(B, x, z, len = 2.6) {
    B.box('wood', x, 0.45, z, len, 0.07, 0.45, '#a07850');
    B.box('beam', x, 0.8, z - 0.22, len, 0.6, 0.06, MID, false);
    for (const s of [-1, 1]) B.box('beam', x + s * (len / 2 - 0.05), 0.45, z, 0.06, 0.9, 0.5, DARK, false);
  },
  candle(B, x, y, z) { B.prop('dungeon', 'candle_lit', x, y, z, 0, 0.38, { collide: false }); },
  rack(B, x, z, ry, kind) {
    const s = B.sub(x, z, ry);
    if (kind === 'bow') {
      s.box('beam', 0, 1.3, -0.05, 1.8, 0.1, 0.1, DARK, false);
      for (const k of [-0.55, 0, 0.55]) s.prop('village', 'Bow_Wooden', k, 1.35, 0.05, 0, 0.55, { collide: false });
    } else s.prop('dungeon', 'sword_shield', 0, 1.9, 0.1, 0, 0.8, { collide: false });
  },
  banner(B, x, y, z, ry, name) { B.prop('dungeon', name, x, y - 2.3, z, ry, 0.8, { collide: false }); },
  torch(B, x, y, z, ry) { B.prop('dungeon', 'torch_mounted', x, y, z, ry, 0.8, { collide: false }); },
};

// ---------------- INTERIORS ----------------
const INTERIORS = {
  townhall(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    F.rug(B, 0, 0.5, 2.2, d - 3, '#7a1a2a');
    F.table(B, 0, -hd + 2.3, 3.2, 1.0);
    F.chair(B, 0, -hd + 1.4, 0);
    for (const x of [-1, 1]) F.bookshelf(B, x * (hw - 1.5), -hd + 0.35, 0, 2);
    F.banner(B, -2.6, 3.7, -hd + 0.3, 0, 'banner_patternA_red'); F.banner(B, 2.6, 3.7, -hd + 0.3, 0, 'banner_patternB_blue');
    B.prop('dungeon', 'table_small_decorated_A', 0.9, 0.84, -hd + 2.3, 0, 0.5, { collide: false });
    B.prop('dungeon', 'chest_gold', hw - 0.8, 0.04, hd - 1.4, -Math.PI / 2, 0.6);
    for (const s of [-1, 1]) F.torch(B, s * (hw - 0.3), 2.2, 0.8, s > 0 ? -Math.PI / 2 : Math.PI / 2);
    for (const s of [-1, 1]) for (let z = -1; z <= 2; z += 1.6) F.pew(B, s * (hw - 1.4), z, 1.8);
    F.candle(B, -1.2, 0.8, -hd + 2.3); F.candle(B, 1.2, 0.8, -hd + 2.3);
    B.box('color', 0.3, 0.81, -hd + 2.3, 0.4, 0.02, 0.3, '#f4ecd8', false);
    npc('mayor', 0, -hd + 1.5, 0);
  },
  tavern(B, b, R, npc, W) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    F.counter(B, -hw + 2.3, -0.8, 5, Math.PI / 2);
    F.shelf(B, -hw + 0.35, -0.8, Math.PI / 2, 3.2, ['#6a3a1a', '#3a6a2a', '#8a2a2a', '#c8a040']);
    F.barrel(B, -hw + 0.7, hd - 1.0); F.barrel(B, -hw + 1.4, hd - 0.8); F.barrel(B, -hw + 0.7, -hd + 0.8);
    B.prop('weapons', 'mug_full', -hw + 2.3, 1.06, 0.8, 0, 0.3, { collide: false });
    B.prop('dungeon', 'keg_decorated', -hw + 0.9, 0.04, 2.2, Math.PI / 2, 0.55);
    B.prop('dungeon', 'barrel_small_stack', hw - 1.0, 0.04, hd - 1.2, 0, 0.6);
    F.banner(B, 0, 3.6, -hd + 0.3, 0, 'banner_triple_yellow');
    F.torch(B, hw - 0.3, 2.2, -1, -Math.PI / 2); F.torch(B, hw - 0.3, 2.2, 2.5, -Math.PI / 2);
    F.fireplace(B, hw - 2.2, -hd + 0.6, 0);
    const tables = [[1.2, -1.6], [3.4, 0.6], [0.6, 1.8], [3.6, 2.8]];
    for (const [x, z] of tables) {
      F.roundTable(B, x, z, 0.6);
      for (let k = 0; k < 3; k++) { const a = k * 2.1 + x; F.stool(B, x + Math.sin(a) * 0.95, z + Math.cos(a) * 0.95); }
      B.prop('dungeon', R.pick(['plate_food_A', 'plate_food_B']), x - 0.1, 0.84, z, R.range(0, 6), 0.3, { collide: false });
      B.prop('weapons', 'mug_full', x + 0.3, 0.84, z + 0.1, R.range(0, 6), 0.25, { collide: false });
    }
    F.rug(B, 2.2, 0.4, 3.5, 4.5, '#6a3a2a');
    npc('innkeeper', -hw + 1.3, -0.8, Math.PI / 2);
    npc('patron', 1.2, -0.6, Math.PI, { sit: true });
    npc('patron', 3.4, 1.55, 0.4 + Math.PI, { sit: true });
  },
  smithy(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    const f = B.sub(-hw + 1.4, -hd + 1.4, 0);
    f.box('stone', 0, 0.5, 0, 2.2, 1.0, 2.2, '#8a847a');
    f.box('fire', 0, 1.02, 0, 1.4, 0.06, 1.4, '#ff6a1a', false);
    f.box('fire', 0.2, 1.08, -0.2, 0.5, 0.08, 0.5, '#ffc34a', false);
    f.box('stone', 0, 2.6, -0.3, 1.6, 1.6, 1.4, '#7a746a', false);
    f.box('stone', 0, 3.6, -0.5, 0.8, 1.0, 0.8, '#7a746a', false);
    // anvil
    const a = B.sub(0.3, -0.6, 0.3);
    a.box('wood', 0, 0.3, 0, 0.5, 0.6, 0.5, DARK);
    a.box('metal', 0, 0.7, 0, 0.3, 0.2, 0.3, '#3a3a3a', false);
    a.box('metal', 0, 0.87, 0, 0.35, 0.14, 0.8, '#454545', false);
    a.geo('metal', new THREE.ConeGeometry(0.1, 0.3, 4), 0, 0.87, 0.52, 0, '#454545', 1, 1, 1, Math.PI / 2);
    F.barrel(B, -hw + 0.8, 0.8); B.cyl('color', -hw + 0.8, 0.88, 0.8, 0.3, 0.02, '#2a4a5a', false, 10);
    F.rack(B, hw - 0.4, -0.5, -Math.PI / 2, 'sword');
    F.table(B, hw - 1.2, -hd + 1.0, 1.6, 0.8);
    B.box('metal', hw - 1.4, 0.83, -hd + 1.0, 0.8, 0.04, 0.12, '#c8ccd0', false);
    F.crate(B, hw - 0.8, hd - 1.2);
    B.prop('village', 'Hammer_Double', hw - 1.1, 0.84, -hd + 1.2, 1.2, 0.3, { collide: false });
    B.prop('dungeon', 'box_stacked', hw - 1.0, 0.04, hd - 2.4, 0, 0.35);
    F.torch(B, -hw + 0.3, 2.2, 1.5, Math.PI / 2);
    npc('smith', 0.4, 0.4, 0);
  },
  store(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    F.counter(B, 0, -hd + 2.2, 4.4);
    for (const x of [-2.3, 0, 2.3]) F.shelf(B, x, -hd + 0.35, 0, 2.1, ['#c84', '#48c', '#8c4', '#cc4', '#a4a', '#e66']);
    F.barrel(B, -hw + 0.8, 0.6); F.barrel(B, -hw + 0.8, 1.5); F.crate(B, hw - 0.8, 0.8); F.crate(B, hw - 0.8, 1.6, 0.6); F.crate(B, hw - 0.8, 0.8, 0.5, 0.7);
    for (let k = 0; k < 3; k++) B.prop('village', 'Bags', -hw + 1.8, 0.04, 0.2 + k * 0.6, k, 2.2);
    B.prop('halloween', 'pumpkin_orange', 1.4, 1.06, -hd + 2.2, 0, 0.4, { collide: false });
    B.prop('village', 'Potion1_Filled', -1.2, 1.06, -hd + 2.2, 0, 0.25, { collide: false });
    B.prop('village', 'Potion2_Filled', -0.8, 1.06, -hd + 2.2, 0, 0.22, { collide: false });
    B.prop('village', 'Package_1', hw - 1.2, 0.04, -0.6, 0.4, 2.2);
    F.rug(B, 0, 1.2, 2.5, 2.4, '#2a5a4a');
    npc('merchant', 0, -hd + 1.3, 0);
  },
  herbalist(B, b, R, npc, W) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    B.prop('village', 'Cauldron', -1.0, 0.04, -0.8, 0, 3.2);
    B.cyl('glow', -1.0, 0.62, -0.8, 0.42, 0.04, '#5aff8a', false, 12);
    B.box('fire', -1.0, 0.05, -0.8, 0.6, 0.08, 0.6, '#ff7a2a', false);
    F.shelf(B, 0.8, -hd + 0.35, 0, 2.2, ['#3a8a3a', '#8a3a8a', '#3a6a8a', '#8a8a3a', '#aa5522']);
    F.table(B, hw - 0.9, 0.3, 1.4, 0.8, Math.PI / 2);
    for (let k = 0; k < 6; k++) B.box('color', -hw + 0.8 + k * 0.9, b.h - 0.5, 1.0, 0.12, 0.5, 0.12, R.pick(['#4a7a2a', '#6a8a2a', '#3a5a2a', '#8a6a3a']), false);
    for (let k = 0; k < 3; k++) B.prop('village', R.pick(['Potion1_Filled', 'Potion2_Filled', 'Potion4_Filled']), hw - 0.9, 0.84, -0.1 + k * 0.35, k, 0.22, { collide: false });
    F.rug(B, -0.4, 1, 2.2, 2.2, '#4a6a2a');
    npc('herbalist', 0.3, -0.5, 0);
  },
  magetower(B, b, R, npc, W) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    for (const [x, z, r] of [[-hw + 0.35, -0.5, Math.PI / 2], [hw - 0.35, -0.5, -Math.PI / 2]]) F.bookshelf(B, x, z, r, 2.8);
    F.bookshelf(B, 0, -hd + 0.35, 0, 2.6);
    B.cyl('stone', 1.6, 0.45, -1.6, 0.35, 0.9, '#8a8aa0', true, 8);
    const crystal = new THREE.Mesh(new THREE.OctahedronGeometry(0.35), new THREE.MeshStandardMaterial({ color: '#b98aff', emissive: '#7a3aff', emissiveIntensity: 2, roughness: 0.2 }));
    const cp = B.P(1.6, -1.6, 1.4); crystal.position.copy(cp); W.scene.add(crystal);
    W.animated.push((dt, t) => { crystal.rotation.y += dt; crystal.position.y = cp.y + Math.sin(t * 2) * 0.08; });
    F.table(B, -0.8, 0.8, 1.4, 0.8);
    B.prop('weapons', 'spellbook_open', -0.9, 0.84, 0.8, 0.3, 0.35, { collide: false });
    B.prop('village', 'Scroll', -0.4, 0.84, 0.6, 1, 0.3, { collide: false });
    F.candle(B, -0.3, 0.8, 0.8);
    B.geo('color', new THREE.CircleGeometry(1.6, 24), 0, 0.07, 0.4, 0, '#2a2a6a', 1, 1, 1, -Math.PI / 2);
    // ladder to the upper floors
    for (const s of [-1, 1]) B.box('wood', -hw + 1.2 + s * 0.3, b.h / 2, -hd + 0.45, 0.08, b.h, 0.08, DARK, false);
    for (let y = 0.4; y < b.h - 0.2; y += 0.4) B.box('wood', -hw + 1.2, y, -hd + 0.45, 0.6, 0.05, 0.05, MID, false);
    npc('mage', -0.2, -1.2, 0);
  },
  hunter(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    F.rack(B, -hw + 0.4, -0.4, Math.PI / 2, 'bow');
    F.table(B, 0.8, -0.6, 1.4, 0.8);
    F.bed(B, hw - 0.9, -hd + 1.4, 0, '#5a6a3a');
    F.rug(B, -0.3, 0.8, 2.4, 1.8, '#8a8580');
    B.prop('dungeon', 'trunk_large_A', 0.8, 0.04, hd - 1.0, 0, 0.7);
    B.prop('weapons', 'quiver', 1.2, 0.84, -0.6, 0.4, 0.5, { collide: false });
    F.barrel(B, -hw + 0.8, hd - 1.0);
    npc('hunter', 0.8, -1.4, 0);
    // archery targets outside
    for (const s of [-1, 1]) B.prop('village', s > 0 ? 'TargetWithArrows' : 'Target', s * (hw + 2.5), -0.04, 1.5, 0, 2.6);
    B.prop('village', 'Dummy', hw + 2.5, -0.04, 4.5, 0, 1.6);
  },
  chapel(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    for (let z = -hd + 4; z < hd - 1.5; z += 1.5) for (const s of [-1, 1]) F.pew(B, s * 1.9, z, 2.4);
    B.box('stone', 0, 0.5, -hd + 1.6, 2.0, 1.0, 0.9, '#e8e4dc');
    B.box('color', 0, 1.02, -hd + 1.6, 2.1, 0.03, 1.0, '#e8e0f0', false);
    B.box('color', 0, 0.7, -hd + 2.06, 0.6, 0.6, 0.02, '#c8a040', false);
    for (const x of [-0.8, -0.4, 0.4, 0.8]) F.candle(B, x, 1.03, -hd + 1.5);
    for (const s of [-1, 1]) { B.prop('halloween', 'candle_triple', s * 1.6, 0.04, -hd + 1.4, 0, 0.8, { collide: false }); F.banner(B, s * 2.4, 4.2, -hd + 0.3, 0, 'banner_patternC_white'); }
    // stained glass
    const cols = ['#ff5a5a', '#5a8aff', '#ffd84a', '#5aff8a'];
    for (let i = 0; i < 4; i++) B.box('glow', -0.6 + (i % 2) * 1.2, 2.6 + Math.floor(i / 2) * 1.0, -hd + 0.14, 1.1, 0.9, 0.04, cols[i], false);
    B.box('beam', 0, 3.1, -hd + 0.13, 0.08, 2.0, 0.06, DARK, false); B.box('beam', 0, 3.1, -hd + 0.13, 2.4, 0.08, 0.06, DARK, false);
    F.rug(B, 0, 0.5, 1.4, d - 3.5, '#6a1a2a');
    npc('priest', 0, -hd + 0.8, 0);
  },
  house(B, b, R, npc) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    F.bed(B, -hw + 0.9, -hd + 1.4, 0, R.pick(['#8a3a3a', '#3a5a8a', '#5a7a3a', '#8a6a3a']));
    F.table(B, 1.0, 0.3, 1.2, 0.8);
    F.chair(B, 1.0, -0.5, 0); F.chair(B, 1.0, 1.1, Math.PI);
    F.fireplace(B, hw - 1.4, -hd + 0.6, 0);
    F.crate(B, -hw + 0.6, hd - 1.2, 0.6);
    B.prop('dungeon', 'trunk_medium_B', -hw + 0.8, 0.04, -hd + 2.8, Math.PI / 2, 0.8);
    B.prop('dungeon', R.pick(['plate_food_A', 'plate_food_B']), 1.0, 0.84, 0.3, 0, 0.35, { collide: false });
    F.rug(B, 0, 0.5, 2, 1.6, R.pick(['#6a3a2a', '#3a4a6a', '#5a4a2a']));
  },
  farmhouse(B, b, R, npc, W) {
    const { w, d } = b, hw = w / 2, hd = d / 2;
    const bed = F.bed(B, -hw + 0.9, -hd + 1.4, 0, '#3a6a8a');
    const bp = B.P(-hw + 0.9, -hd + 1.4);
    W.interactables.push({ type: 'bed', x: bp.x, y: b.floorY + 0.6, z: bp.z, r: 1.8, label: 'Sleep & Save' });
    F.table(B, 0.8, 0.0, 1.4, 0.8); F.chair(B, 0.8, -0.8, 0); F.chair(B, 0.8, 0.8, Math.PI);
    B.prop('dungeon', 'plate_food_A', 0.8, 0.84, 0, 0, 0.35, { collide: false });
    B.prop('weapons', 'mug_full', 0.4, 0.84, 0.25, 0, 0.25, { collide: false });
    B.prop('dungeon', 'trunk_large_A', -hw + 0.9, 0.04, -hd + 3.2, Math.PI / 2, 0.6);
    F.fireplace(B, hw - 1.4, -hd + 0.6, 0);
    F.shelf(B, -1.0, -hd + 0.35, 0, 1.4, ['#c84', '#8c4', '#cc4']);
    F.crate(B, -hw + 0.6, hd - 1.2, 0.6); F.barrel(B, -hw + 0.6, hd - 2.2);
    F.rug(B, -0.6, 0.8, 2.2, 1.8, '#8a6a3a');
    const sp = B.P(0, hd + 4.5);
    W.spawnPoint = { x: sp.x, z: sp.z, yaw: b.ang };
    W.bedPoint = { x: B.P(-hw + 2.0, -hd + 1.4).x, z: B.P(-hw + 2.0, -hd + 1.4).z, yaw: b.ang };
    W.mapLabels.push({ x: b.x, z: b.z, text: 'Home' });
  },
};

// ---------------- FARM FIELD ----------------
function buildFarmField(W, R) {
  const f = W.farm; const batch = new Batcher();
  const ang = f.rot * Math.PI / 2;
  const B = Builder.at(W, batch, f.fx, W.plazaY, f.fz, ang);
  // low fence around the field with a gap
  const fw = 10, fd = 8.5;
  for (const s of [-1, 1]) {
    for (let x = -fw / 2; x <= fw / 2 + 0.01; x += 1.25) B.box('wood', x, 0.45, s * fd / 2, 0.12, 0.9, 0.12, DARK, false);
    B.box('wood', 0, 0.65, s * fd / 2, fw, 0.08, 0.06, MID, false);
    B.box('wood', 0, 0.35, s * fd / 2, fw, 0.08, 0.06, MID, false);
    B.colBox(0, s * fd / 2, fw, 0.2, 0, 0.9);
  }
  for (const s of [-1, 1]) {
    for (let z = -fd / 2; z <= fd / 2 + 0.01; z += 1.2) if (!(s < 0 && Math.abs(z) < 1.2)) B.box('wood', s * fw / 2, 0.45, z, 0.12, 0.9, 0.12, DARK, false);
    if (s > 0) { B.box('wood', s * fw / 2, 0.65, 0, 0.06, 0.08, fd, MID, false); B.box('wood', s * fw / 2, 0.35, 0, 0.06, 0.08, fd, MID, false); B.colBox(s * fw / 2, 0, 0.2, fd, 0, 0.9); }
    else for (const zz of [-1, 1]) { const L = fd / 2 - 1.2; B.box('wood', s * fw / 2, 0.65, zz * (1.2 + L / 2), 0.06, 0.08, L, MID, false); B.box('wood', s * fw / 2, 0.35, zz * (1.2 + L / 2), 0.06, 0.08, L, MID, false); B.colBox(s * fw / 2, zz * (1.2 + L / 2), 0.2, L, 0, 0.9); }
  }
  // plots
  W.plots = [];
  const cols = 5, rows = 4, sp = 1.65;
  let id = 0;
  for (let i = 0; i < cols; i++) for (let j = 0; j < rows; j++) {
    const lx = (i - (cols - 1) / 2) * sp + 0.3, lz = (j - (rows - 1) / 2) * sp;
    const p = B.P(lx, lz);
    W.plots.push({ id: id++, x: p.x, z: p.z, y: W.plazaY, state: 'grass', crop: null, t: 0 });
  }
  // scarecrow
  const sc = B.sub(fw / 2 - 1, -fd / 2 + 1, -0.6);
  sc.box('wood', 0, 1.0, 0, 0.1, 2.0, 0.1, DARK); sc.box('wood', 0, 1.5, 0, 1.4, 0.08, 0.08, DARK, false);
  sc.box('color', 0, 1.35, 0, 0.45, 0.6, 0.25, '#8a3a2a', false); sc.geo('color', new THREE.SphereGeometry(0.2, 8, 6), 0, 1.85, 0, 0, '#d8c090');
  sc.geo('color', new THREE.ConeGeometry(0.35, 0.3, 10), 0, 2.1, 0, 0, '#d8b860');
  // haystacks & barn-shed near the farmhouse
  const hB = Builder.at(W, batch, f.x, W.plazaY, f.z, ang);
  for (const [x, z] of [[-7.5, 1.5], [-7.5, -1.2], [-8.8, 0.2]]) hB.prop('village', 'Hay', x, 0, z, x + z, 7.5);
  hB.prop('village', 'Cart', -9.5, 0, -4, 0.6, 2.3);
  hB.prop('dungeon', 'barrel_small', -6, 0, 3.6, 0, 1);
  hB.box('wood', -7.5, 0.3, 4.5, 2.2, 0.6, 1.0, '#8a6038'); // trough
  hB.box('color', -7.5, 0.58, 4.5, 2.0, 0.04, 0.8, '#3a6a8a', false);
  W.scene.add(batch.build(W.M));
  W.mapLabels.push({ x: f.fx, z: f.fz, text: 'Field' });
  // farmer NPC stands by the field
  const fp = B.P(-fw / 2 - 1.2, 2.2);
  W.npcSpots.push({ role: 'farmer', x: fp.x, z: fp.z, y: W.plazaY, yaw: ang - Math.PI / 2 });
}

// ---------------- PLAZA ----------------
function buildPlaza(W, R) {
  const batch = new Batcher(); const y = W.plazaY;
  const B = Builder.at(W, batch, 0, y, 0, 0);
  B.geo('cobble', new THREE.CircleGeometry(12.5, 48), 0, 0.05, 0, 0, '#d8d0c4', 1, 1, 1, -Math.PI / 2);
  // well
  B.prop('village', 'Well', 0, 0.05, 0, 0, 2.6, { collide: false });
  W.addCircle(0, 0, 1.3, y - 1, y + 3);
  W.interactables.push({ type: 'well', x: 0, y: y + 1, z: 0, r: 2.3, label: 'Drink from well' });
  W.mapLabels.push({ x: 0, z: -3, text: 'Plaza' });
  // quest board
  const ga = W.gates[0] + Math.PI / 2 * 0.7;
  const bp = polar(ga, 8.5);
  const qb = B.sub(bp.x, bp.z, ga + Math.PI);
  qb.box('wood', 0, 1.3, 0, 2.0, 1.3, 0.12, MID); for (const s of [-1, 1]) qb.box('wood', s * 0.95, 1.0, 0, 0.14, 2.0, 0.14, DARK, false);
  qb.geo('shingle', new THREE.ConeGeometry(1.5, 0.5, 4), 0, 2.25, 0, Math.PI / 4, '#ffffff', 1, 1, 0.35);
  for (let k = 0; k < 5; k++) qb.box('color', -0.7 + k * 0.35 + R.range(-0.05, 0.05), 1.3 + R.range(-0.3, 0.3), 0.07, 0.25, 0.32, 0.01, '#f4ecd0', false);
  W.interactables.push({ type: 'board', x: bp.x, y: y + 1.3, z: bp.z, r: 2.4, label: 'Quest Board' });
  // market stalls between the roads
  for (let i = 0; i < 3; i++) {
    const a = W.gates[i] + Math.PI / 3 + R.range(-0.25, 0.25);
    const p = polar(a, 10.5);
    B.prop('village', i % 2 ? 'MarketStand_1' : 'MarketStand_2', p.x, 0.05, p.z, a + Math.PI, 2.3);
  }
  // benches
  for (let i = 0; i < 3; i++) {
    const a = W.gates[i] - Math.PI / 3 + R.range(-0.2, 0.2);
    const p = polar(a, 5.5); B.prop('village', 'Bench_1', p.x, 0.05, p.z, a, 2.6);
  }
  W.scene.add(batch.build(W.M));
}

// ---------------- FENCE & GATES ----------------
function buildFence(W, R) {
  const batch = new Batcher(); const FR = W.fenceR;
  const B = Builder.at(W, batch, 0, 0, 0, 0);
  const gateHalf = 3.2 / FR;
  const nearGate = (a) => W.gates.some((g) => Math.abs(angleDiff(a, g)) < gateHalf);
  const step = 2.4 / FR;
  for (let a = 0; a < Math.PI * 2; a += step) {
    const a2 = a + step;
    const p = polar(a, FR), q = polar(a2, FR);
    if (nearGate(a)) continue;
    const y = W.heightAt(p.x, p.z);
    B.box('wood', p.x, y + 0.7, p.z, 0.2, 1.5, 0.2, DARK, false, a);
    B.geo('wood', new THREE.ConeGeometry(0.14, 0.25, 4), p.x, y + 1.55, p.z, a, DARK);
    if (!nearGate(a2)) {
      const mx = (p.x + q.x) / 2, mz = (p.z + q.z) / 2, yq = W.heightAt(q.x, q.z); const my = (y + yq) / 2;
      const len = Math.hypot(q.x - p.x, q.z - p.z), ry = Math.atan2(q.x - p.x, q.z - p.z);
      const tilt = Math.atan2(yq - y, len);
      for (const hh of [0.45, 1.05]) B.add('wood', BOX, mtx(mx, my + hh, mz, ry, 0.08, 0.14, len + 0.1, -tilt), MID);
    }
  }
  // colliders every 0.6m
  const cs = 0.6 / FR;
  for (let a = 0; a < Math.PI * 2; a += cs) { if (nearGate(a)) continue; const p = polar(a, FR); W.addCircle(p.x, p.z, 0.25); }
  // gates
  const names = ['Goblin Hills', 'Old Graveyard', 'Collapsed Mine'];
  W.gates.forEach((g, i) => {
    const p = polar(g, FR); const y = W.heightAt(p.x, p.z);
    const G = B.sub(p.x, p.z, g, y);
    for (const s of [-1, 1]) G.prop('village', 'Watchtower', s * 4.0, -0.2, 0, 0, 2.3);
    G.box('log', 0, 3.9, 0, 5.2, 0.35, 0.35, '#ffffff', false);
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 0.65), new THREE.MeshStandardMaterial({ map: signTexture(`→ ${names[i]}`), side: THREE.DoubleSide, roughness: 0.8 }));
    sign.position.copy(G.P(0, 0.2, 3.2)); sign.rotation.y = g + Math.PI; W.scene.add(sign);
    const sign2 = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 0.65), new THREE.MeshStandardMaterial({ map: signTexture('Hollowmere'), side: THREE.DoubleSide, roughness: 0.8 }));
    sign2.position.copy(G.P(0, -0.2, 3.2)); sign2.rotation.y = g; W.scene.add(sign2);
    if (i === 0) { const gp = G.P(2.2, -1.5); W.npcSpots.push({ role: 'guard', x: gp.x, z: gp.z, y, yaw: g + Math.PI }); }
    // torches
    for (const s of [-1, 1]) { G.box('fire', s * 2.4, 3.3, -0.25, 0.12, 0.2, 0.12, '#ffb04a', false); }
  });
  W.scene.add(batch.build(W.M));
}

// ---------------- PROPS ----------------
function buildVillageProps(W, R) {
  const batch = new Batcher();
  const B = Builder.at(W, batch, 0, 0, 0, 0);
  // lamp posts along main roads
  for (const r of W.roads.filter((r) => r.main)) {
    const a = r.pts[0], b = r.pts[1];
    const L = Math.hypot(b.x - a.x, b.z - a.z);
    let side = 1;
    for (let t = 6; t < L - 3; t += 11) {
      const dx = (b.x - a.x) / L, dz = (b.z - a.z) / L;
      const x = a.x + dx * t - dz * 2.4 * side, z = a.z + dz * t + dx * 2.4 * side;
      const y = W.heightAt(x, z);
      B.cyl('color', x, y + 1.4, z, 0.08, 2.8, '#2a2a2a', true, 6);
      B.box('color', x, y + 2.85, z, 0.32, 0.08, 0.32, '#2a2a2a', false);
      B.box('window', x, y + 2.6, z, 0.24, 0.4, 0.24, null, false);
      side = -side;
    }
  }
  // random props beside buildings
  for (const b of W.buildings) {
    const S = Builder.at(W, batch, b.x, W.plazaY, b.z, b.rot * Math.PI / 2);
    const n = R.int(1, 3);
    for (let k = 0; k < n; k++) {
      const side = R.chance(0.5) ? -1 : 1;
      const x = side * (b.w / 2 + 0.7), z = R.range(-b.d / 2 + 0.8, b.d / 2 - 0.5);
      const t = R.int(0, 3);
      if (t === 0) F.barrel(S, x, z, 0.38);
      else if (t === 1) S.prop('dungeon', R.pick(['crates_stacked', 'box_large', 'box_small']), x, 0, z, R.int(0, 3) * Math.PI / 2, 0.55);
      else if (t === 2) { // wood pile
        for (let i = 0; i < 3; i++) for (let j = 0; j < 3 - i; j++) S.add('log', cylGeo(0.14, 0.14, 1.4, 7), mtx(x, 0.15 + i * 0.26, z - 0.3 + j * 0.3 + i * 0.15, 0, 1, 1, 1, Math.PI / 2), '#ffffff');
        S.colBox(x, z, 1.4, 1.0, 0, 0.8, 0);
      } else { // flower planter
        S.box('wood', x, 0.2, z, 0.5, 0.4, 1.4, MID);
        for (let i = 0; i < 5; i++) S.geo('color', new THREE.SphereGeometry(0.1, 5, 4), x + R.range(-0.12, 0.12), 0.48, z - 0.55 + i * 0.27, 0, R.pick(['#ff5a7a', '#ffd84a', '#ffffff', '#b58aff']));
      }
    }
  }
  // cart near plaza
  const cp = polar(W.gates[1] + Math.PI / 3 + 0.35, 14.5);
  B.sub(cp.x, cp.z, 0, W.plazaY).prop('village', 'Cart', 0, 0, 0, R.range(0, 6), 2.3);
  W.scene.add(batch.build(W.M));
}

function buildWaypoints(W) {
  const wp = [];
  for (let i = 0; i < 8; i++) { const p = polar(i / 8 * Math.PI * 2, 7.5); wp.push({ x: p.x, z: p.z, n: [] }); }
  for (let i = 0; i < 8; i++) { wp[i].n.push((i + 1) % 8, (i + 7) % 8); }
  const nearestRing = (x, z) => { let best = 0, bd = 1e9; for (let i = 0; i < 8; i++) { const d = Math.hypot(wp[i].x - x, wp[i].z - z); if (d < bd) { bd = d; best = i; } } return best; };
  const link = (a, b) => { wp[a].n.push(b); wp[b].n.push(a); };
  // door paths: ring -> plaza edge -> door
  for (const b of W.buildings) {
    const da = Math.atan2(b.doorFront.x, b.doorFront.z);
    const e = polar(da, 12.5);
    const ie = wp.push({ x: e.x, z: e.z, n: [] }) - 1; link(ie, nearestRing(e.x, e.z));
    const id = wp.push({ x: b.doorFront.x, z: b.doorFront.z, n: [], door: b }) - 1; link(ie, id);
  }
  // main roads toward the gates
  for (const g of W.gates) {
    let prev = nearestRing(polar(g, 7.5).x, polar(g, 7.5).z);
    for (const r of [16, 30, 44, 55]) { const p = polar(g, r); const i = wp.push({ x: p.x, z: p.z, n: [] }) - 1; link(prev, i); prev = i; }
  }
  W.waypoints = wp;
}
