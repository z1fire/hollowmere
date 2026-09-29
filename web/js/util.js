import * as THREE from 'three';

// ---------- math ----------
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
export const dist2 = (ax, az, bx, bz) => Math.hypot(ax - bx, az - bz);
export const angleDiff = (a, b) => { let d = b - a; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2; return d; };

// distance from point to segment (2D)
export function distToSeg(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az;
  const l2 = dx * dx + dz * dz || 1;
  const t = clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1);
  return Math.hypot(px - (ax + dx * t), pz - (az + dz * t));
}

// ---------- seeded random ----------
export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export class RNG {
  constructor(seed) { this.r = mulberry32(seed); }
  next() { return this.r(); }
  range(a, b) { return a + (b - a) * this.r(); }
  int(a, b) { return Math.floor(this.range(a, b + 1)); }
  pick(arr) { return arr[Math.floor(this.r() * arr.length)]; }
  chance(p) { return this.r() < p; }
  shuffle(arr) { for (let i = arr.length - 1; i > 0; i--) { const j = Math.floor(this.r() * (i + 1)); [arr[i], arr[j]] = [arr[j], arr[i]]; } return arr; }
}

// ---------- perlin noise ----------
export function makeNoise2D(seed) {
  const rng = mulberry32(seed);
  const perm = [...Array(256).keys()];
  for (let i = 255; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [perm[i], perm[j]] = [perm[j], perm[i]]; }
  const p = new Uint8Array(512);
  for (let i = 0; i < 512; i++) p[i] = perm[i & 255];
  const grad = (h, x, y) => {
    switch (h & 7) {
      case 0: return x + y; case 1: return -x + y; case 2: return x - y; case 3: return -x - y;
      case 4: return x; case 5: return -x; case 6: return y; default: return -y;
    }
  };
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  return (x, y) => {
    let X = Math.floor(x), Y = Math.floor(y);
    x -= X; y -= Y; X &= 255; Y &= 255;
    const u = fade(x), v = fade(y);
    const a = p[X] + Y, b = p[X + 1] + Y;
    return lerp(
      lerp(grad(p[a], x, y), grad(p[b], x - 1, y), u),
      lerp(grad(p[a + 1], x, y - 1), grad(p[b + 1], x - 1, y - 1), u), v);
  };
}
export function fbm(noise, x, y, oct = 4) {
  let s = 0, a = 1, f = 1, n = 0;
  for (let i = 0; i < oct; i++) { s += noise(x * f, y * f) * a; n += a; a *= 0.5; f *= 2; }
  return s / n;
}

// ---------- geometry helpers ----------
const _o = new THREE.Object3D();
export function mtx(x, y, z, ry = 0, sx = 1, sy = 1, sz = 1, rx = 0, rz = 0) {
  _o.position.set(x, y, z); _o.rotation.set(rx, ry, rz, 'YXZ'); _o.scale.set(sx, sy, sz);
  _o.updateMatrix();
  return _o.matrix.clone();
}

export const UNIT_BOX = new THREE.BoxGeometry(1, 1, 1);
const cylCache = new Map();
export function cylGeo(rt, rb, h, seg = 8) {
  const k = `${rt}|${rb}|${h}|${seg}`;
  if (!cylCache.has(k)) cylCache.set(k, new THREE.CylinderGeometry(rt, rb, h, seg));
  return cylCache.get(k);
}

// Merge many (geometry, matrix, color) into one non-indexed geometry with vertex colors.
// If uvScale is given, UVs are generated from world position (box-projected) so textures tile evenly.
export function mergeGeometries(items, uvScale) {
  const parts = []; let total = 0;
  for (const it of items) {
    const g = it.geometry.index ? it.geometry.toNonIndexed() : it.geometry.clone();
    g.applyMatrix4(it.matrix);
    if (!g.attributes.normal) g.computeVertexNormals();
    parts.push([g, it.color]); total += g.attributes.position.count;
  }
  const pos = new Float32Array(total * 3), nor = new Float32Array(total * 3);
  const uv = new Float32Array(total * 2), col = new Float32Array(total * 3);
  let o = 0;
  for (const [g, c] of parts) {
    const p = g.attributes.position.array, n = g.attributes.normal.array;
    const u = g.attributes.uv ? g.attributes.uv.array : null;
    const cnt = g.attributes.position.count;
    pos.set(p, o * 3); nor.set(n, o * 3);
    const r = c ? c.r : 1, gg = c ? c.g : 1, b = c ? c.b : 1;
    for (let i = 0; i < cnt; i++) {
      const vi = o + i;
      if (uvScale) {
        const nx = Math.abs(n[i * 3]), ny = Math.abs(n[i * 3 + 1]), nz = Math.abs(n[i * 3 + 2]);
        const x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2];
        if (ny >= nx && ny >= nz) { uv[vi * 2] = x / uvScale; uv[vi * 2 + 1] = z / uvScale; }
        else if (nx >= nz) { uv[vi * 2] = z / uvScale; uv[vi * 2 + 1] = y / uvScale; }
        else { uv[vi * 2] = x / uvScale; uv[vi * 2 + 1] = y / uvScale; }
      } else if (u) { uv[vi * 2] = u[i * 2]; uv[vi * 2 + 1] = u[i * 2 + 1]; }
      col[vi * 3] = r; col[vi * 3 + 1] = gg; col[vi * 3 + 2] = b;
    }
    o += cnt; g.dispose();
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.computeBoundingSphere(); geo.computeBoundingBox();
  return geo;
}

// Collects static geometry per material key, then merges into few draw calls.
export class Batcher {
  constructor() { this.groups = new Map(); }
  add(key, geometry, matrix, color) {
    let g = this.groups.get(key);
    if (!g) { g = []; this.groups.set(key, g); }
    g.push({ geometry, matrix, color: color !== undefined && color !== null ? new THREE.Color(color) : null });
  }
  build(materials) {
    const group = new THREE.Group();
    for (const [key, items] of this.groups) {
      const mat = materials[key];
      if (!mat) { console.warn('missing material', key); continue; }
      const mesh = new THREE.Mesh(mergeGeometries(items, mat.userData.uvScale), mat);
      mesh.castShadow = mat.userData.castShadow !== false;
      mesh.receiveShadow = mat.userData.receiveShadow !== false;
      group.add(mesh);
    }
    this.groups.clear();
    return group;
  }
}

// Build a single vertex-colored geometry from parts (for instanced models like trees).
export function compoundGeometry(parts) {
  return mergeGeometries(parts.map((p) => ({ geometry: p[0], matrix: p[1], color: new THREE.Color(p[2]) })));
}

export function fmtTime(hours) {
  const h = Math.floor(hours) % 24, m = Math.floor((hours % 1) * 60);
  const ap = h >= 12 ? 'PM' : 'AM'; const hh = h % 12 === 0 ? 12 : h % 12;
  return `${hh}:${String(m).padStart(2, '0')} ${ap}`;
}
