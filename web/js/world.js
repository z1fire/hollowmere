import * as THREE from 'three';
import { RNG, makeNoise2D, fbm, clamp, lerp, smoothstep, distToSeg, angleDiff, mtx, Batcher, cylGeo, compoundGeometry } from './util.js';
import { makeTextures } from './textures.js';
import { Assets, PropField, propSize } from './assets.js';
import { planVillage, buildVillage } from './village.js';
import { buildWilds, herbsAndChests } from './wilds.js';

export const polar = (a, r) => ({ x: Math.sin(a) * r, z: Math.cos(a) * r });

// Builder: places geometry in a local frame (rotations in 90° steps) and registers colliders.
export class Builder {
  constructor(world, batch, m) {
    this.w = world; this.b = batch; this.m = m;
    this.y = m.elements[13];
    this.ang = Math.atan2(m.elements[8], m.elements[0]);
  }
  static at(world, batch, x, y, z, ang = 0) {
    return new Builder(world, batch, new THREE.Matrix4().makeRotationY(ang).setPosition(x, y, z));
  }
  sub(x, z, ry = 0, y = 0) { return new Builder(this.w, this.b, this.m.clone().multiply(new THREE.Matrix4().makeRotationY(ry).setPosition(x, y, z))); }
  P(lx, lz, ly = 0) { const v = new THREE.Vector3(lx, ly, lz).applyMatrix4(this.m); return v; }
  add(key, geo, local, color) { this.b.add(key, geo, new THREE.Matrix4().multiplyMatrices(this.m, local), color); }
  box(key, lx, ly, lz, sx, sy, sz, color, col = true, ry = 0) {
    this.add(key, BOX, mtx(lx, ly, lz, ry, sx, sy, sz), color);
    if (col) this.colBox(lx, lz, sx, sz, ly - sy / 2, ly + sy / 2, ry);
  }
  colBox(lx, lz, sx, sz, y0, y1, ry = 0) {
    if (Math.abs(Math.sin(ry)) > 0.7) [sx, sz] = [sz, sx];
    const a = this.P(lx - sx / 2, lz - sz / 2), b = this.P(lx + sx / 2, lz + sz / 2);
    this.w.addBox(Math.min(a.x, b.x), Math.max(a.x, b.x), Math.min(a.z, b.z), Math.max(a.z, b.z), this.y + y0, this.y + y1);
  }
  cyl(key, lx, ly, lz, r, h, color, col = true, seg = 10, rt) {
    this.add(key, cylGeo(rt ?? r, r, h, seg), mtx(lx, ly, lz), color);
    if (col) { const p = this.P(lx, lz); this.w.addCircle(p.x, p.z, Math.max(r, rt ?? 0), this.y + ly - h / 2, this.y + ly + h / 2); }
  }
  geo(key, g, lx, ly, lz, ry = 0, color, sx = 1, sy = 1, sz = 1, rx = 0, rz = 0) { this.add(key, g, mtx(lx, ly, lz, ry, sx, sy, sz, rx, rz), color); }
  // place a model prop in this local frame (ry multiples of 90° keep box colliders tight)
  prop(bundle, name, lx, ly, lz, ry = 0, s = 1, opts = {}) {
    const local = mtx(lx, ly, lz, ry, opts.sx ?? s, opts.sy ?? s, opts.sz ?? s);
    const m = new THREE.Matrix4().multiplyMatrices(this.m, local);
    this.w.props.add(bundle, name, m, opts.tint);
    if (opts.collide !== false) {
      const z = propSize(bundle, name);
      const sx = z.sx * (opts.sx ?? s), sz = z.sz * (opts.sz ?? s), sy = z.maxY * (opts.sy ?? s);
      const cx = z.cx * (opts.sx ?? s), cz = z.cz * (opts.sz ?? s);
      const c = Math.cos(ry), sn = Math.sin(ry);
      const px = lx + cx * c + cz * sn, pz = lz - cx * sn + cz * c;
      if (Math.abs(Math.sin(2 * ry)) < 0.1) this.colBox(px, pz, sx * (opts.shrink ?? 0.9), sz * (opts.shrink ?? 0.9), ly, ly + Math.max(0.3, sy), ry);
      else { const p = this.P(px, pz); this.w.addCircle(p.x, p.z, Math.max(sx, sz) * 0.42, this.y + ly, this.y + ly + sy); }
    }
  }
  floor(minX, maxX, minZ, maxZ, ly) {
    const a = this.P(minX, minZ), b = this.P(maxX, maxZ);
    this.w.addFloor(Math.min(a.x, b.x), Math.max(a.x, b.x), Math.min(a.z, b.z), Math.max(a.z, b.z), this.y + ly);
  }
}
const BOX = new THREE.BoxGeometry(1, 1, 1);

export class World {
  constructor(scene, renderer, seed, quality) {
    this.scene = scene; this.seed = seed; this.quality = quality; this.renderer = renderer;
    this.rng = new RNG(seed);
    this.noise = makeNoise2D(seed); this.noise2 = makeNoise2D(seed + 71); this.noise3 = makeNoise2D(seed + 913);
    this.flats = []; this.cells = new Map(); this.stamp = 0; this._q = []; this._q2 = [];
    this.floors = []; this.buildings = []; this.interactables = []; this.spawns = []; this.roads = [];
    this.excl = []; this.pois = {}; this.npcSpots = []; this.waypoints = []; this.animated = []; this.mapLabels = [];
    this.wind = { value: 0 };
    this.props = new PropField();
    this.tex = makeTextures(Math.min(8, renderer.capabilities.getMaxAnisotropy()));
    const steps = [['materials', () => this.makeMaterials()], ['layout', () => this.planLayout()], ['plan village', () => planVillage(this)],
      ['terrain', () => this.buildTerrain()], ['roads', () => this.buildRoads()], ['village', () => buildVillage(this)], ['wilds', () => buildWilds(this)],
      ['vegetation', () => this.scatterVegetation()], ['herbs', () => herbsAndChests(this)], ['sky', () => this.buildSky()], ['lights', () => this.buildLights()], ['props', () => { this.propMeshes = this.props.build(this.scene); }]];
    for (const [name, fn] of steps) { const t0 = performance.now(); fn(); console.log(`[gen] ${name}: ${Math.round(performance.now() - t0)}ms`); }
  }

  // ---------- materials ----------
  makeMaterials() {
    const T = this.tex, P = Assets.tex;
    const std = (o, uv, ud = {}) => { const m = new THREE.MeshStandardMaterial({ roughness: 0.9, metalness: 0, vertexColors: true, ...o }); m.userData = { uvScale: uv, ...ud }; return m; };
    const pbr = (set, uv, o = {}, ud = {}) => std({ map: set.map, normalMap: set.normalMap, roughnessMap: set.roughnessMap, normalScale: new THREE.Vector2(0.8, 0.8), roughness: 1, ...o }, uv, ud);
    const basic = (o) => { const m = new THREE.MeshBasicMaterial(o); m.userData = { castShadow: false, receiveShadow: false }; return m; };
    this.M = {
      plaster: pbr(P.plaster, 2.2), stone: pbr(P.stone, 2.4), log: pbr(P.planks, 2.2),
      wood: pbr(P.floor, 2.0), beam: pbr(P.beam, 1.4), thatch: pbr(P.thatch, 2.6), shingle: pbr(P.tiles, 2.2),
      cobble: pbr(P.cobble, 3.0, {}, { castShadow: false }), color: std({}, null), bark: std({ map: T.bark }, 1),
      road: pbr(P.dirt, 3.2, { polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 }, { castShadow: false }),
      metal: std({ metalness: 0.6, roughness: 0.45 }, null),
      fire: basic({ vertexColors: true }),
      glow: basic({ vertexColors: true }),
      window: basic({ color: '#2b3848' }),
    };
  }

  // ---------- height ----------
  baseHeight(x, z) {
    const r = Math.hypot(x, z);
    let h = fbm(this.noise, x * 0.007, z * 0.007, 4) * 11 + this.noise2(x * 0.045, z * 0.045) * 1.0;
    h = lerp(this.noise2(x * 0.02, z * 0.02) * 0.5, h, smoothstep(60, 90, r));
    const m = smoothstep(150, 195, r);
    h += m * m * 50 * (0.75 + 0.35 * this.noise3(x * 0.02, z * 0.02));
    return h;
  }
  heightAt(x, z) {
    let h = this.baseHeight(x, z);
    for (const f of this.flats) {
      const dx = x - f.x, dz = z - f.z;
      const lim = f.r + f.fall;
      if (dx > lim || dx < -lim || dz > lim || dz < -lim) continue;
      const d = Math.hypot(dx, dz);
      if (d < lim) {
        let fh = f.h;
        if (f.bowl) { const k = d / f.r; fh = f.h - f.bowl * Math.max(0, 1 - k * k); }
        h = lerp(fh, h, smoothstep(f.r, lim, d));
      }
    }
    return h;
  }
  addFloor(minX, maxX, minZ, maxZ, y) { this.floors.push({ minX, maxX, minZ, maxZ, y }); }
  groundAt(x, z, feetY = Infinity) {
    let h = this.heightAt(x, z);
    for (const f of this.floors) if (x >= f.minX && x <= f.maxX && z >= f.minZ && z <= f.maxZ && f.y > h && f.y <= feetY + 0.6) h = f.y;
    return h;
  }

  // ---------- colliders (spatial hash) ----------
  _ins(c, minX, maxX, minZ, maxZ) {
    const C = 8;
    for (let i = Math.floor(minX / C); i <= Math.floor(maxX / C); i++)
      for (let j = Math.floor(minZ / C); j <= Math.floor(maxZ / C); j++) {
        const k = (i + 500) * 1000 + (j + 500);
        let a = this.cells.get(k); if (!a) { a = []; this.cells.set(k, a); } a.push(c);
      }
  }
  addBox(minX, maxX, minZ, maxZ, y0 = -1e9, y1 = 1e9) { this._ins({ t: 0, minX, maxX, minZ, maxZ, y0, y1, s: 0 }, minX, maxX, minZ, maxZ); }
  addCircle(x, z, r, y0 = -1e9, y1 = 1e9) { this._ins({ t: 1, x, z, r, y0, y1, s: 0 }, x - r, x + r, z - r, z + r); }
  query(x, z, r, out) {
    const C = 8; this.stamp++; out.length = 0;
    for (let i = Math.floor((x - r) / C); i <= Math.floor((x + r) / C); i++)
      for (let j = Math.floor((z - r) / C); j <= Math.floor((z + r) / C); j++) {
        const a = this.cells.get((i + 500) * 1000 + (j + 500)); if (!a) continue;
        for (const c of a) if (c.s !== this.stamp) { c.s = this.stamp; out.push(c); }
      }
    return out;
  }
  resolve(p, r, feetY, height = 1.7) {
    let hit = false;
    const list = this.query(p.x, p.z, r + 0.5, this._q);
    for (let it = 0; it < 2; it++) for (const c of list) {
      if (c.y1 < feetY + 0.45 || c.y0 > feetY + height) continue;
      if (c.t === 1) {
        const dx = p.x - c.x, dz = p.z - c.z, d = Math.hypot(dx, dz), m = r + c.r;
        if (d < m) { hit = true; if (d < 1e-5) { p.x += m; continue; } p.x = c.x + dx / d * m; p.z = c.z + dz / d * m; }
      } else {
        const cx = clamp(p.x, c.minX, c.maxX), cz = clamp(p.z, c.minZ, c.maxZ);
        const dx = p.x - cx, dz = p.z - cz, d2 = dx * dx + dz * dz;
        if (d2 < r * r) {
          hit = true;
          if (d2 > 1e-8) { const d = Math.sqrt(d2); p.x = cx + dx / d * r; p.z = cz + dz / d * r; }
          else {
            const l = p.x - c.minX, rr = c.maxX - p.x, b = p.z - c.minZ, t = c.maxZ - p.z, m = Math.min(l, rr, b, t);
            if (m === l) p.x = c.minX - r; else if (m === rr) p.x = c.maxX + r; else if (m === b) p.z = c.minZ - r; else p.z = c.maxZ + r;
          }
        }
      }
    }
    // world boundary
    const rr = Math.hypot(p.x, p.z);
    if (rr > 186) { p.x *= 186 / rr; p.z *= 186 / rr; hit = true; }
    return hit;
  }
  pointBlocked(x, y, z) {
    const list = this.query(x, z, 0.05, this._q2);
    for (const c of list) {
      if (y < c.y0 || y > c.y1) continue;
      if (c.t === 1) { if (Math.hypot(x - c.x, z - c.z) < c.r) return true; }
      else if (x >= c.minX && x <= c.maxX && z >= c.minZ && z <= c.maxZ) return true;
    }
    return false;
  }
  // line of sight between two points (sampled)
  lineClear(ax, ay, az, bx, by, bz) {
    const d = Math.hypot(bx - ax, bz - az); const n = Math.ceil(d / 0.5);
    for (let i = 1; i < n; i++) {
      const t = i / n; const x = lerp(ax, bx, t), y = lerp(ay, by, t), z = lerp(az, bz, t);
      if (this.pointBlocked(x, y, z) || y < this.heightAt(x, z)) return false;
    }
    return true;
  }

  // ---------- layout ----------
  planLayout() {
    const R = this.rng;
    this.fenceR = 60;
    const base = R.range(0, Math.PI * 2);
    this.gates = [0, 1, 2].map((i) => base + i * Math.PI * 2 / 3 + R.range(-0.22, 0.22));
    const camp = polar(this.gates[0] + R.range(-0.3, 0.3), 128);
    const grave = polar(this.gates[1] + R.range(-0.3, 0.3), 108);
    const mine = polar(this.gates[2] + R.range(-0.15, 0.15), 158);
    const pond = polar(this.gates[2] + Math.PI / 3 + R.range(-0.15, 0.15), R.range(88, 100));
    this.pois = { camp, grave, mine, pond };
    const bh = (p) => this.baseHeight(p.x, p.z);
    this.flats.push({ x: 0, z: 0, r: 13, fall: 8, h: bh({ x: 0, z: 0 }) });
    this.flats.push({ x: camp.x, z: camp.z, r: 18, fall: 12, h: bh(camp) });
    this.flats.push({ x: grave.x, z: grave.z, r: 19, fall: 12, h: bh(grave) });
    this.flats.push({ x: mine.x, z: mine.z, r: 10, fall: 10, h: bh(mine) });
    const ph = bh(pond);
    this.flats.push({ x: pond.x, z: pond.z, r: 14, fall: 9, h: ph, bowl: 2.6 });
    this.water = { x: pond.x, z: pond.z, r: 14, y: ph - 0.35 };
    this.plazaY = this.flats[0].h;
    this.excl.push({ t: 'c', x: 0, z: 0, r: 14 }, { t: 'c', x: camp.x, z: camp.z, r: 21 }, { t: 'c', x: grave.x, z: grave.z, r: 22 },
      { t: 'c', x: mine.x, z: mine.z, r: 12 }, { t: 'c', x: pond.x, z: pond.z, r: 16 });
    const targets = [camp, grave, mine];
    this.gates.forEach((g, i) => {
      const t = targets[i], tr = Math.hypot(t.x, t.z), ta = Math.atan2(t.x, t.z);
      const pts = [polar(g, 12), polar(g, this.fenceR), polar(g + angleDiff(g, ta) * 0.5 + R.range(-0.06, 0.06), (this.fenceR + tr) / 2), polar(ta, tr - (i === 2 ? 6 : 15))];
      this.roads.push({ pts, w: 2.8, main: true, gate: i });
    });
  }
  roadEdge(x, z) {
    let best = 1e9;
    for (const r of this.roads) for (let i = 0; i < r.pts.length - 1; i++) {
      const a = r.pts[i], b = r.pts[i + 1];
      const d = distToSeg(x, z, a.x, a.z, b.x, b.z) - r.w / 2;
      if (d < best) best = d;
    }
    return best;
  }
  isClear(x, z, roadPad = 2) {
    if (this.roadEdge(x, z) < roadPad) return false;
    for (const e of this.excl) {
      if (e.t === 'c') { if (Math.hypot(x - e.x, z - e.z) < e.r) return false; }
      else if (x > e.minX && x < e.maxX && z > e.minZ && z < e.maxZ) return false;
    }
    const r = Math.hypot(x, z);
    if (r > this.fenceR - 2 && r < this.fenceR + 2) return false;
    return true;
  }

  // ---------- terrain ----------
  buildTerrain() {
    const S = 470, N = this.quality === 'low' ? 150 : 230;
    const g = new THREE.PlaneGeometry(S, S, N, N); g.rotateX(-Math.PI / 2);
    const pos = g.attributes.position, uv = g.attributes.uv;
    const col = new Float32Array(pos.count * 3);
    const splat = new Float32Array(pos.count * 4);
    const c = new THREE.Color(), white = new THREE.Color(1, 1, 1);
    const cA = new THREE.Color('#58872f'), cB = new THREE.Color('#7fa845'), cDry = new THREE.Color('#a09f55'), cDirt = new THREE.Color('#86704f'),
      cRock = new THREE.Color('#9a9488'), cDark = new THREE.Color('#40652a'), cSand = new THREE.Color('#b3a078'), cGrave = new THREE.Color('#5b6848'), cCamp = new THREE.Color('#7a6a4a');
    const W = this.water, P = this.pois;
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      const h = this.heightAt(x, z); pos.setY(i, h);
      const r = Math.hypot(x, z);
      const n = this.noise2(x * 0.05, z * 0.05), n2 = this.noise3(x * 0.012, z * 0.012);
      c.copy(cA).lerp(cB, clamp(n * 0.8 + 0.5, 0, 1));
      c.lerp(cDry, smoothstep(0.15, 0.55, n2) * 0.55);
      c.lerp(cDark, smoothstep(0.0, -0.4, n2) * 0.55 * smoothstep(60, 90, r));
      const sl = Math.abs(this.heightAt(x + 1, z) - this.heightAt(x - 1, z)) + Math.abs(this.heightAt(x, z + 1) - this.heightAt(x, z - 1));
      c.lerp(cRock, smoothstep(1.0, 2.0, sl));
      c.lerp(cRock, smoothstep(14, 26, h) * 0.85);
      c.lerp(cDirt, (1 - smoothstep(-0.6, 1.6, this.roadEdge(x, z))) * 0.8);
      c.lerp(cSand, 1 - smoothstep(W.r * 0.8, W.r + 3, Math.hypot(x - W.x, z - W.z)));
      c.lerp(cGrave, (1 - smoothstep(14, 24, Math.hypot(x - P.grave.x, z - P.grave.z))) * 0.7);
      c.lerp(cCamp, (1 - smoothstep(8, 20, Math.hypot(x - P.camp.x, z - P.camp.z))) * 0.75);
      // texture weights: grass, dirt, rock, forest floor
      let wr = Math.max(smoothstep(0.9, 1.8, sl), smoothstep(13, 24, h));
      let wd = Math.max(1 - smoothstep(-0.8, 1.4, this.roadEdge(x, z)), 1 - smoothstep(W.r * 0.8, W.r + 3, Math.hypot(x - W.x, z - W.z)),
        (1 - smoothstep(8, 18, Math.hypot(x - P.camp.x, z - P.camp.z))) * 0.8, smoothstep(0.35, 0.6, this.noise3(x * 0.05 + 7, z * 0.05)) * 0.35);
      let wf = smoothstep(0.0, -0.35, n2) * smoothstep(64, 90, r) + (1 - smoothstep(14, 24, Math.hypot(x - P.grave.x, z - P.grave.z))) * 0.6;
      wd = Math.min(1, wd); wr = Math.min(1, wr); wf = Math.min(1, wf) * (1 - wd) * (1 - wr);
      const wg = Math.max(0, 1 - wd - wr - wf);
      const sum = wg + wd + wr + wf || 1;
      splat[i * 4] = wg / sum; splat[i * 4 + 1] = wd / sum; splat[i * 4 + 2] = wr / sum; splat[i * 4 + 3] = wf / sum;
      // vertex colour = the stylized grass colour (the grass photo only adds detail)
      col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
      uv.setXY(i, x / 3, z / 3);
    }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    g.setAttribute('splat', new THREE.BufferAttribute(splat, 4));
    g.computeVertexNormals();
    const mesh = new THREE.Mesh(g, this.terrainMaterial());
    mesh.receiveShadow = true;
    this.scene.add(mesh);
    this.terrain = mesh;

    // water
    const wg = new THREE.CircleGeometry(W.r * 1.02, 48); wg.rotateX(-Math.PI / 2);
    this.waterNormal = waterNormalTexture(); this.waterNormal.repeat.set(4, 4);
    this.waterMat = new THREE.MeshStandardMaterial({ color: '#1f4a5a', roughness: 0.05, metalness: 0.1, transparent: true, opacity: 0.86, normalMap: this.waterNormal, normalScale: new THREE.Vector2(0.35, 0.35), envMapIntensity: 1.4 });
    const wm = new THREE.Mesh(wg, this.waterMat); wm.position.set(W.x, W.y, W.z); wm.receiveShadow = true;
    this.scene.add(wm);
    this.addCircle(W.x, W.z, W.r * 0.62);
  }

  // PBR terrain: blends grass / dirt / rock / forest-floor photo textures by per-vertex weights,
  // sampling each at two scales to hide tiling.
  terrainMaterial() {
    const P = Assets.tex;
    const m = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95, metalness: 0, normalMap: P.grass.normalMap, normalScale: new THREE.Vector2(0.6, 0.6) });
    m.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, { tGrass: { value: P.grass.map }, tDirt: { value: P.dirt.map }, tRock: { value: P.rock.map }, tForest: { value: P.forest.map },
        nDirt: { value: P.dirt.normalMap }, nRock: { value: P.rock.normalMap } });
      sh.vertexShader = 'attribute vec4 splat; varying vec4 vSplat; varying vec2 vWuv;\n' + sh.vertexShader.replace('#include <uv_vertex>', '#include <uv_vertex>\n vSplat = splat; vWuv = position.xz / 3.0;');
      sh.fragmentShader = 'uniform sampler2D tGrass, tDirt, tRock, tForest, nDirt, nRock; varying vec4 vSplat; varying vec2 vWuv;\n' + sh.fragmentShader
        .replace('#include <map_fragment>', `
          vec3 gt = mix(texture2D(tGrass, vWuv).rgb, texture2D(tGrass, vWuv * 0.21 + 0.37).rgb, 0.45);
          vec3 cg = vColor.rgb * (0.35 + dot(gt, vec3(0.3, 0.59, 0.11)) * 2.6);
          vec3 cd = mix(texture2D(tDirt, vWuv * 0.8).rgb, texture2D(tDirt, vWuv * 0.19).rgb, 0.35);
          vec3 cr = mix(texture2D(tRock, vWuv * 0.5).rgb, texture2D(tRock, vWuv * 0.13).rgb, 0.4);
          vec3 cf = texture2D(tForest, vWuv * 0.9).rgb;
          diffuseColor.rgb *= cg * vSplat.x + cd * vSplat.y + cr * vSplat.z + cf * vSplat.w;`)
        .replace('#include <color_fragment>', '')
        .replace('#include <normal_fragment_maps>', `
          vec3 mapN = texture2D(normalMap, vWuv).xyz * vSplat.x + texture2D(nDirt, vWuv * 0.8).xyz * (vSplat.y + vSplat.w) + texture2D(nRock, vWuv * 0.5).xyz * vSplat.z;
          mapN = mapN * 2.0 - 1.0; mapN.xy *= normalScale;
          normal = normalize(tbn * mapN);`);
    };
    return m;
  }

  buildRoads() {
    const batch = new Batcher();
    for (const r of this.roads) {
      const verts = [], idx = [];
      const samples = [];
      for (let i = 0; i < r.pts.length - 1; i++) {
        const a = r.pts[i], b = r.pts[i + 1]; const L = Math.hypot(b.x - a.x, b.z - a.z); const n = Math.max(1, Math.ceil(L / 1.2));
        for (let k = 0; k < n; k++) samples.push({ x: lerp(a.x, b.x, k / n), z: lerp(a.z, b.z, k / n) });
      }
      samples.push(r.pts[r.pts.length - 1]);
      for (let i = 0; i < samples.length; i++) {
        const p = samples[i], q = samples[Math.min(i + 1, samples.length - 1)], o = samples[Math.max(i - 1, 0)];
        let tx = q.x - o.x, tz = q.z - o.z; const tl = Math.hypot(tx, tz) || 1; tx /= tl; tz /= tl;
        const nx = -tz * r.w / 2, nz = tx * r.w / 2;
        const wob = this.noise2(p.x * 0.3, p.z * 0.3) * 0.25;
        for (const s of [-1, 1]) {
          const x = p.x + nx * (s + wob * s), z = p.z + nz * (s + wob * s);
          verts.push(x, this.groundAt(x, z) + 0.06, z);
        }
        if (i > 0) { const b0 = (i - 1) * 2; idx.push(b0, b0 + 1, b0 + 2, b0 + 1, b0 + 3, b0 + 2); }
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3)); g.setIndex(idx);
      g.computeVertexNormals();
      // ensure up-facing
      const nrm = g.attributes.normal; if (nrm.getY(0) < 0) { g.setIndex(idx.map((v, k) => idx[k - (k % 3) + [0, 2, 1][k % 3]])); g.computeVertexNormals(); }
      batch.add('road', g, new THREE.Matrix4(), r.main ? '#f0e4d0' : '#e4d6c0');
    }
    this.scene.add(batch.build(this.M));
  }

  // ---------- vegetation ----------
  chunked(geo, mat, items, { shadow = true, receive = true } = {}) {
    // items: [{m: Matrix4, c: Color?}], split into spatial chunks for culling
    const chunks = new Map();
    const v = new THREE.Vector3();
    for (const it of items) {
      v.setFromMatrixPosition(it.m);
      const k = Math.floor((v.x + 240) / 80) * 10 + Math.floor((v.z + 240) / 80);
      if (!chunks.has(k)) chunks.set(k, []); chunks.get(k).push(it);
    }
    for (const list of chunks.values()) {
      const im = new THREE.InstancedMesh(geo, mat, list.length);
      list.forEach((it, i) => { im.setMatrixAt(i, it.m); if (it.c) im.setColorAt(i, it.c); });
      im.castShadow = shadow; im.receiveShadow = receive;
      im.computeBoundingSphere();
      this.scene.add(im);
    }
  }

  scatterVegetation() {
    const R = new RNG(this.seed + 5);
    const q = this.quality;
    const TREES = {
      common: ['CommonTree_1', 'CommonTree_2', 'CommonTree_5', 'CommonTree_3'], pine: ['PineTree_1', 'PineTree_2', 'PineTree_3', 'PineTree_4'],
      birch: ['BirchTree_1', 'BirchTree_2', 'BirchTree_3'], willow: ['Willow_1', 'Willow_2'], dead: ['CommonTree_Dead_1', 'CommonTree_Dead_2'],
    };
    const addTree = (type, x, z, s) => {
      const y = this.heightAt(x, z) - 0.15;
      const tint = new THREE.Color().setHSL(R.range(0.2, 0.32), R.range(0.0, 0.25), R.range(0.85, 1.05));
      this.props.add('nature', R.pick(TREES[type]), mtx(x, y, z, R.range(0, 6.28), s, s * R.range(0.9, 1.15), s), tint);
      this.addCircle(x, z, 0.14 * s, -1e9, 1e9);
    };
    // density scales with quality (these trees are detailed models)
    const step = q === 'low' ? 8 : q === 'med' ? 6.8 : 5.8;
    for (let x = -192; x < 192; x += step) for (let z = -192; z < 192; z += step) {
      const px = x + R.range(-2.2, 2.2), pz = z + R.range(-2.2, 2.2);
      const r = Math.hypot(px, pz);
      if (r > 192) continue;
      const dens = this.noise3(px * 0.013 + 3, pz * 0.013);
      let p;
      if (r < this.fenceR - 3) p = r > 16 ? 0.05 : 0;
      else if (r < 72) p = 0.14;
      else p = 0.22 + 0.62 * smoothstep(-0.25, 0.35, dens);
      if (r > 178) p *= 0.5;
      if (!R.chance(p) || !this.isClear(px, pz, 3)) continue;
      const nearGrave = Math.hypot(px - this.pois.grave.x, pz - this.pois.grave.z) < 42;
      const nearWater = Math.hypot(px - this.water.x, pz - this.water.z) < 30;
      const t = nearGrave && R.chance(0.65) ? 'dead' : nearWater && R.chance(0.5) ? 'willow' : (r > 150 || this.noise2(px * 0.02, pz * 0.02) > 0.15) ? 'pine' : R.chance(0.22) ? 'birch' : 'common';
      addTree(t, px, pz, R.range(2.3, 3.3));
    }
    // rocks
    this.rockSpots = [];
    for (let i = 0; i < 300; i++) {
      const a = R.range(0, 6.28), r = Math.sqrt(R.next()) * 120 + 68;
      const x = Math.sin(a) * r, z = Math.cos(a) * r;
      if (r > 190 || !this.isClear(x, z, 1.5)) continue;
      const big = r > 160 || R.chance(0.18);
      const s = big ? R.range(2.2, 4.5) : R.range(0.7, 1.6);
      const y = this.heightAt(x, z);
      this.props.add('nature', R.pick(['Rock_Moss_1', 'Rock_Moss_2', 'Rock_Moss_3', 'Rock_Moss_4', 'Rock_Moss_5', 'Rock_2', 'Rock_3']), mtx(x, y - 0.1 * s, z, R.range(0, 6), s, s * R.range(0.8, 1.2), s));
      if (s > 1.2) this.addCircle(x, z, s * 0.36, -1e9, y + s * 0.6);
      this.rockSpots.push(new THREE.Vector3(x, y, z));
    }
    // bushes, plants, stumps, logs, flowers
    const small = [['Bush_1', 1.1, 1.8], ['Bush_2', 1.1, 1.8], ['BushBerries_1', 1, 1.5], ['Plant_1', 1, 1.6], ['Plant_3', 0.9, 1.5], ['Plant_2', 0.7, 1.1]];
    for (let i = 0; i < (q === 'low' ? 350 : 800); i++) {
      const a = R.range(0, 6.28), r = R.range(15, 182);
      const x = Math.sin(a) * r, z = Math.cos(a) * r;
      if (!this.isClear(x, z, 1)) continue;
      const [n, s0, s1] = R.pick(small);
      this.props.add('nature', n, mtx(x, this.heightAt(x, z) - 0.05, z, R.range(0, 6.28), R.range(s0, s1)));
    }
    for (let i = 0; i < 70; i++) {
      const a = R.range(0, 6.28), r = R.range(70, 180); const x = Math.sin(a) * r, z = Math.cos(a) * r;
      if (!this.isClear(x, z, 2)) continue;
      const log = R.chance(0.5); const s = R.range(1.4, 2.0); const y = this.heightAt(x, z);
      this.props.add('nature', log ? 'WoodLog_Moss' : 'TreeStump_Moss', mtx(x, y - 0.05, z, R.range(0, 6.28), s));
      this.addCircle(x, z, log ? 0.8 : 0.6, -1e9, y + 0.9);
    }
    for (let i = 0; i < (q === 'low' ? 250 : 600); i++) {
      const a = R.range(0, 6.28), r = R.range(14, 110); const x = Math.sin(a) * r, z = Math.cos(a) * r;
      if (!this.isClear(x, z, 0.5) || this.noise3(x * 0.05, z * 0.05) < 0.05) continue;
      this.props.add('nature', 'Flowers', mtx(x, this.heightAt(x, z) - 0.03, z, R.range(0, 6.28), R.range(0.7, 1.1)));
    }

    // grass (wind-animated instanced blades)
    const blades = [];
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI + R.range(-0.2, 0.2), ox = R.range(-0.12, 0.12), oz = R.range(-0.12, 0.12), h = R.range(0.35, 0.6), w = 0.06;
      const cx = Math.cos(a) * w, cz = Math.sin(a) * w, lean = R.range(-0.08, 0.08);
      blades.push([ox - cx, 0, oz - cz, ox + cx, 0, oz + cz, ox + lean, h, oz + lean]);
    }
    const gp = new Float32Array(blades.flatMap((b) => [...b, b[3], b[4], b[5], b[0], b[1], b[2], b[6], b[7], b[8]])); // both windings, so both sides are lit from above
    const gn = new Float32Array(gp.length); const gc = new Float32Array(gp.length);
    for (let i = 0; i < gp.length / 3; i++) {
      gn[i * 3 + 1] = 1; const t = gp[i * 3 + 1] > 0.01 ? 1 : 0;
      gc[i * 3] = t ? 0.6 : 0.26; gc[i * 3 + 1] = t ? 0.82 : 0.44; gc[i * 3 + 2] = t ? 0.28 : 0.12;
    }
    const grassGeo = new THREE.BufferGeometry();
    grassGeo.setAttribute('position', new THREE.BufferAttribute(gp, 3)); grassGeo.setAttribute('normal', new THREE.BufferAttribute(gn, 3)); grassGeo.setAttribute('color', new THREE.BufferAttribute(gc, 3));
    const grassMat = new THREE.MeshLambertMaterial({ vertexColors: true, emissive: '#101a06' });
    grassMat.onBeforeCompile = (sh) => {
      sh.uniforms.uTime = this.wind;
      sh.vertexShader = 'uniform float uTime;\n' + sh.vertexShader.replace('#include <begin_vertex>', `#include <begin_vertex>
        vec4 wp = instanceMatrix * vec4(0.0,0.0,0.0,1.0);
        float w = sin(uTime*1.8 + wp.x*0.3 + wp.z*0.22)*0.14 + sin(uTime*3.3 + wp.x*0.9 + wp.z*0.5)*0.05;
        transformed.x += w*position.y*1.6; transformed.z += w*position.y;`);
    };
    const gcount = q === 'low' ? 6000 : q === 'med' ? 14000 : 26000;
    const grass = [];
    let tries = 0;
    while (grass.length < gcount && tries < gcount * 4) {
      tries++;
      const a = R.range(0, 6.28), r = Math.sqrt(R.next()) * 125;
      const x = Math.sin(a) * r, z = Math.cos(a) * r;
      if (!this.isClear(x, z, 0.4) && !(Math.hypot(x - this.pois.grave.x, z - this.pois.grave.z) < 22 && R.chance(0.5))) continue;
      if (Math.hypot(x - this.water.x, z - this.water.z) < this.water.r) continue;
      if (this.noise2(x * 0.08, z * 0.08) < -0.35) continue;
      const s = R.range(0.7, 1.35);
      grass.push({ m: mtx(x, this.heightAt(x, z) - 0.02, z, R.range(0, 6.28), s, s * R.range(0.8, 1.3), s), c: new THREE.Color().setHSL(R.range(0.2, 0.28), R.range(0.4, 0.6), R.range(0.7, 1.0)) });
    }
    this.chunked(grassGeo, grassMat, grass, { shadow: false, receive: false });

  }

  // ---------- sky ----------
  buildSky() {
    this.skyU = {
      top: { value: new THREE.Color() }, horizon: { value: new THREE.Color() }, bottom: { value: new THREE.Color('#3a4a3a') },
      sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunColor: { value: new THREE.Color('#fff2d0') }, starAlpha: { value: 0 }, uTime: this.wind,
    };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.skyU, side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: `varying vec3 vDir; void main(){ vDir = normalize(position); vec4 p = projectionMatrix*modelViewMatrix*vec4(position,1.0); gl_Position = p.xyww; }`,
      fragmentShader: `uniform vec3 top, horizon, bottom, sunDir, sunColor; uniform float starAlpha; uniform float uTime; varying vec3 vDir;
        float hash(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,45.164)))*43758.5453); }
        float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); float a=hash(vec3(i,1.0)), b=hash(vec3(i+vec2(1,0),1.0)), c=hash(vec3(i+vec2(0,1),1.0)), d=hash(vec3(i+vec2(1,1),1.0)); return mix(mix(a,b,f.x),mix(c,d,f.x),f.y); }
        void main(){ vec3 d = normalize(vDir); float y = d.y;
          vec3 col = y > 0.0 ? mix(horizon, top, pow(clamp(y,0.0,1.0), 0.55)) : mix(horizon, bottom, pow(clamp(-y,0.0,1.0), 0.35));
          float s = max(dot(d, sunDir), 0.0);
          col += sunColor * (pow(s, 900.0) * 6.0 + pow(s, 14.0) * 0.35 + pow(s, 3.0)*0.08);
          float m = max(dot(d, -sunDir), 0.0);
          col += vec3(0.8,0.85,1.0) * smoothstep(0.9993, 0.9996, m) * starAlpha * 1.5;
          vec3 sp = floor(d * 260.0); float h = hash(sp);
          col += vec3(step(0.9972, h)) * starAlpha * smoothstep(0.0, 0.2, y) * (0.6 + 0.4*sin(uTime*3.0 + h*100.0));
          if (y > 0.02) { vec2 cp = d.xz / (y + 0.15) * 1.6 + vec2(uTime*0.01, 0.0); float c = vnoise(cp) * 0.6 + vnoise(cp*2.3) * 0.3 + vnoise(cp*5.1)*0.1; c = smoothstep(0.55, 0.85, c) * smoothstep(0.02, 0.25, y);
            vec3 cc = mix(horizon, vec3(1.0), 0.6 * (1.0 - starAlpha)) ; col = mix(col, cc, c * 0.75); }
          gl_FragColor = vec4(col, 1.0);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.sky = new THREE.Mesh(new THREE.SphereGeometry(500, 32, 16), mat);
    this.sky.renderOrder = -1; this.sky.frustumCulled = false;
    this.scene.add(this.sky);
    // image-based lighting: the sky is re-baked into an environment map as the day progresses
    this.envScene = new THREE.Scene();
    this.envScene.add(new THREE.Mesh(new THREE.SphereGeometry(50, 32, 16), mat));
    this.pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envT = 0;
    this.scene.fog = new THREE.Fog('#bcd8ee', 50, 240);
  }

  buildLights() {
    const q = this.quality;
    this.hemi = new THREE.HemisphereLight('#cfe6ff', '#4a5a30', 1.0);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight('#fff0d8', 2.6);
    this.sun.castShadow = q !== 'low';
    const ss = q === 'high' ? 2048 : 1024;
    this.sun.shadow.mapSize.set(ss, ss);
    const sc = this.sun.shadow.camera; sc.left = -42; sc.right = 42; sc.top = 42; sc.bottom = -42; sc.near = 1; sc.far = 220;
    this.sun.shadow.bias = -0.0006; this.sun.shadow.normalBias = 0.04;
    this.scene.add(this.sun); this.scene.add(this.sun.target);
    this.interiorLight = new THREE.PointLight('#ffc47a', 0, 14, 1.6);
    this.scene.add(this.interiorLight);
    this.lantern = new THREE.PointLight('#ffb866', 0, 16, 1.5);
    this.scene.add(this.lantern);
    this.campLight = new THREE.PointLight('#ff8a3a', 30, 22, 1.6);
    const cp = this.pois.camp; this.campLight.position.set(cp.x, this.heightAt(cp.x, cp.z) + 1.5, cp.z);
    this.scene.add(this.campLight);
  }

  buildingAt(x, z) {
    for (const b of this.buildings) if (x > b.inner.minX && x < b.inner.maxX && z > b.inner.minZ && z < b.inner.maxZ) return b;
    return null;
  }

  // ---------- per-frame ----------
  update(dt, hours, playerPos, camera) {
    this.wind.value += dt;
    this.sky.position.copy(camera.position);
    const a = ((hours - 6) / 24) * Math.PI * 2;
    const sd = new THREE.Vector3(Math.cos(a) * 0.9, Math.sin(a), 0.42).normalize();
    this.skyU.sunDir.value.copy(sd);
    const day = smoothstep(-0.15, 0.25, sd.y);
    const dusk = Math.max(0, 1 - Math.abs(sd.y) * 4.5) * smoothstep(-0.25, 0.0, sd.y);
    const top = this.skyU.top.value.set('#070b1c').lerp(_c.set('#3d7bd0'), day);
    const hor = this.skyU.horizon.value.set('#121a30').lerp(_c.set('#b9d6ef'), day).lerp(_c.set('#ff9a5c'), dusk * 0.75);
    this.skyU.bottom.value.copy(hor).multiplyScalar(0.6);
    this.skyU.starAlpha.value = 1 - smoothstep(-0.2, 0.05, sd.y);
    this.skyU.sunColor.value.set('#fff3d6').lerp(_c.set('#ff8a40'), dusk);
    this.scene.fog.color.copy(hor);
    // sun or moon light
    const isDay = sd.y > -0.05;
    const L = isDay ? sd : _v.copy(sd).negate();
    this.sun.position.set(playerPos.x + L.x * 90, playerPos.y + Math.max(0.15, L.y) * 90, playerPos.z + L.z * 90);
    this.sun.target.position.set(playerPos.x, playerPos.y, playerPos.z);
    this.sun.intensity = isDay ? 2.8 * smoothstep(-0.05, 0.25, sd.y) : 0.35 * smoothstep(-0.05, -0.3, sd.y);
    this.sun.color.set(isDay ? '#fff0d8' : '#9fb4ff').lerp(_c.set('#ffa060'), isDay ? dusk : 0);
    this.hemi.intensity = 0.18 + 0.55 * day;
    this.hemi.color.set('#6a80b0').lerp(_c.set('#cfe6ff'), day);
    this.hemi.groundColor.set('#1a2018').lerp(_c.set('#4a5a30'), day);
    this.night = 1 - day;
    // glowing windows & lanterns at night
    this.M.window.color.set('#2b3848').lerp(_c.set('#ffb553'), smoothstep(0.35, 0.8, this.night));
    // interior light follows the building you are in
    const b = this.buildingAt(playerPos.x, playerPos.z);
    if (b) { this.interiorLight.position.copy(b.lightPos); this.interiorLight.intensity = 22 + Math.sin(this.wind.value * 9) * 1.5; this.interiorLight.distance = Math.max(b.w, b.d) * 1.4; }
    else this.interiorLight.intensity = 0;
    this.inside = b;
    this.lantern.position.set(playerPos.x, playerPos.y + 1.9, playerPos.z);
    this.lantern.intensity = b ? 0 : 14 * smoothstep(0.4, 0.8, this.night);
    this.campLight.intensity = 30 + Math.sin(this.wind.value * 11) * 5 + Math.sin(this.wind.value * 7.3) * 4;
    for (const o of this.animated) o(dt, this.wind.value);
    // level of detail for trees & plants
    this.lodT = (this.lodT || 0) - dt;
    if (this.lodT <= 0) {
      this.lodT = 0.25;
      const q = this.quality;
      this.props.updateLod(playerPos.x, playerPos.z, q === 'high' ? 55 : q === 'med' ? 40 : 28, q === 'high' ? 90 : q === 'med' ? 65 : 45);
    }
    // refresh environment lighting every few seconds
    this.envT -= dt;
    if (this.envT <= 0) {
      this.envT = 4;
      const old = this.envRT;
      this.envRT = this.pmrem.fromScene(this.envScene, 0, 0.1, 200);
      this.scene.environment = this.envRT.texture;
      old?.dispose();
    }
    this.scene.environmentIntensity = 0.25 + 0.55 * day;
    if (this.waterNormal) { this.waterNormal.offset.x += dt * 0.02; this.waterNormal.offset.y += dt * 0.013; }
  }
}
const _c = new THREE.Color(), _v = new THREE.Vector3();

// Procedural ripple normal map for the pond
function waterNormalTexture() {
  const S = 128, c = document.createElement('canvas'); c.width = c.height = S;
  const x = c.getContext('2d'); const img = x.createImageData(S, S);
  const k2 = Math.PI * 2 / S;
  const h = (i, j) => Math.sin(i * k2 * 3) * 0.5 + Math.sin((j * 2 + i) * k2 * 2) * 0.5 + Math.sin((i + j) * k2 * 5) * 0.3 + Math.sin((i - j) * k2 * 4) * 0.4;
  const v = new THREE.Vector3();
  for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) {
    v.set(-(h(i + 1, j) - h(i - 1, j)), 1.2, -(h(i, j + 1) - h(i, j - 1))).normalize();
    const k = (j * S + i) * 4;
    img.data[k] = (v.x * 0.5 + 0.5) * 255; img.data[k + 1] = (v.z * 0.5 + 0.5) * 255; img.data[k + 2] = v.y * 255; img.data[k + 3] = 255;
  }
  x.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; return t;
}
