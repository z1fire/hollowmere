// Loads the game's 3D models and textures (see tools/build-assets.mjs and assets/CREDITS.txt)
// and provides helpers to place them efficiently.
import * as THREE from 'three';
import { GLTFLoader } from './vendor/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from './vendor/addons/libs/meshopt_decoder.module.js';
import * as SkeletonUtils from './vendor/addons/utils/SkeletonUtils.js';
import { mergeGeometries } from './vendor/addons/utils/BufferGeometryUtils.js';

const BUNDLES = ['weapons', 'dungeon', 'furniture', 'halloween', 'nature', 'crops', 'village'];
const CHARS = ['knight', 'barbarian', 'mage', 'rogue', 'rogue_hooded', 'skeleton_minion', 'skeleton_warrior', 'skeleton_rogue', 'skeleton_mage', 'wolf', 'orc', 'spider', 'anims'];
const TEX = ['plaster', 'stone', 'planks', 'floor', 'beam', 'thatch', 'tiles', 'cobble', 'grass', 'dirt', 'rock', 'forest'];

// Per-pack scale so everything is in meters.
export const PACK_SCALE = { dungeon: 0.72, furniture: 0.62, halloween: 0.72, weapons: 1, nature: 1, crops: 1, village: 1 };

export const Assets = {
  bundles: {}, chars: {}, clips: {}, tex: {}, _geo: new Map(), _mats: new Map(),

  async load(onProgress, anisotropy = 4) {
    const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
    const tl = new THREE.TextureLoader();
    const jobs = [];
    let done = 0;
    const total = BUNDLES.length + CHARS.length + TEX.length * 3;
    const tick = () => onProgress?.(++done / total);
    for (const b of BUNDLES) jobs.push(loader.loadAsync(`assets/props/${b}.glb`).then((g) => { this.bundles[b] = g.scene; tick(); }));
    for (const c of CHARS) jobs.push(loader.loadAsync(`assets/chars/${c}.glb`).then((g) => { this.chars[c] = g; tick(); }));
    for (const t of TEX) {
      const set = (this.tex[t] = {});
      for (const [k, s] of [['map', 'd'], ['normalMap', 'n'], ['roughnessMap', 'r']]) {
        jobs.push(tl.loadAsync(`assets/tex/${t}_${s}.jpg`).then((tx) => {
          tx.wrapS = tx.wrapT = THREE.RepeatWrapping; tx.anisotropy = anisotropy;
          if (k === 'map') tx.colorSpace = THREE.SRGBColorSpace;
          set[k] = tx; tick();
        }));
      }
    }
    await Promise.all(jobs);
    this.clips.kaykit = this.chars.anims.animations;
    for (const c of ['wolf', 'orc', 'spider']) this.clips[c] = this.chars[c].animations;
  },

  node(bundle, name) {
    const n = this.bundles[bundle]?.getObjectByName(name);
    if (!n) throw new Error(`asset ${bundle}/${name} missing`);
    return n;
  },
  // Deep clone of a prop (shares geometry & materials). Use for anything that needs to move.
  clone(bundle, name) {
    const o = this.node(bundle, name).clone(true);
    o.position.set(0, 0, 0); o.rotation.set(0, 0, 0); o.scale.setScalar(PACK_SCALE[bundle] || 1);
    o.traverse((m) => { if (m.isMesh) { m.castShadow = true; m.receiveShadow = true; } });
    const g = new THREE.Group(); g.add(o); return g;
  },
  // Single merged geometry for a prop, with material colors baked into vertex colors.
  geom(bundle, name) {
    const key = bundle + '/' + name;
    if (this._geo.has(key)) return this._geo.get(key);
    const root = this.node(bundle, name);
    root.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
    const s = PACK_SCALE[bundle] || 1;
    const scaleM = new THREE.Matrix4().makeScale(s, s, s);
    const parts = []; let map = null;
    root.traverse((o) => {
      if (!o.isMesh) return;
      const m = o.material;
      if (m.map && !map) map = m.map;
      const g = cleanGeometry(o.geometry, m);
      g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(scaleM, new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld)));
      parts.push(g);
    });
    const geometry = parts.length === 1 ? parts[0] : mergeGeometries(parts, false);
    geometry.computeBoundingBox(); geometry.computeBoundingSphere();
    const res = { geometry, map, box: geometry.boundingBox };
    this._geo.set(key, res);
    return res;
  },
  material(map, opts = {}) {
    const key = (map ? map.uuid : 'none') + JSON.stringify(opts);
    if (!this._mats.has(key)) this._mats.set(key, new THREE.MeshStandardMaterial({ map, vertexColors: true, roughness: 0.85, metalness: 0, ...opts }));
    return this._mats.get(key);
  },
  character(name) {
    const src = this.chars[name].scene;
    return SkeletonUtils.clone(src);
  },
};

// Dequantize + keep only position/normal/uv/color, and bake the material color into vertex colors.
function cleanGeometry(src, material) {
  const g = new THREE.BufferGeometry();
  const count = src.attributes.position.count;
  const toF = (a, size) => {
    const out = new Float32Array(count * size);
    for (let i = 0; i < count; i++) for (let k = 0; k < size; k++) out[i * size + k] = a.getComponent(i, k);
    return new THREE.BufferAttribute(out, size);
  };
  g.setAttribute('position', toF(src.attributes.position, 3));
  if (src.attributes.normal) g.setAttribute('normal', toF(src.attributes.normal, 3));
  g.setAttribute('uv', src.attributes.uv ? toF(src.attributes.uv, 2) : new THREE.BufferAttribute(new Float32Array(count * 2), 2));
  const c = material.color ? material.color.clone() : new THREE.Color(1, 1, 1);
  if (material.emissive && (material.emissive.r + material.emissive.g + material.emissive.b) > 0.3) c.copy(material.emissive).multiplyScalar(1.6);
  if (material.map) c.setRGB(1, 1, 1).multiply(material.color || c);
  const col = new Float32Array(count * 3);
  const vc = src.attributes.color;
  for (let i = 0; i < count; i++) {
    const r = vc ? vc.getComponent(i, 0) : 1, gg = vc ? vc.getComponent(i, 1) : 1, b = vc ? vc.getComponent(i, 2) : 1;
    col[i * 3] = c.r * r; col[i * 3 + 1] = c.g * gg; col[i * 3 + 2] = c.b * b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  if (src.index) g.setIndex(Array.from(src.index.array));
  else g.setIndex([...Array(count).keys()]);
  if (!g.attributes.normal) g.computeVertexNormals();
  return g;
}

// Collects static prop placements, then builds one BatchedMesh per texture atlas:
// thousands of props in a handful of draw calls, with per-object frustum culling.
export class PropField {
  constructor() { this.groups = new Map(); this.lods = []; }
  add(bundle, name, matrix, tint) {
    const { geometry, map } = Assets.geom(bundle, name);
    const key = map ? map.uuid : 'none';
    let g = this.groups.get(key);
    if (!g) { g = { map, items: [], geos: new Map() }; this.groups.set(key, g); }
    if (!g.geos.has(geometry)) g.geos.set(geometry, -1);
    // simplified far-distance version, if the pipeline made one
    let lod = null;
    if (Assets.bundles[bundle].getObjectByName(name + '__lod')) {
      lod = Assets.geom(bundle, name + '__lod').geometry;
      if (!g.geos.has(lod)) g.geos.set(lod, -1);
    }
    const small = geometry.boundingSphere.radius * matrix.getMaxScaleOnAxis() < 1.2;
    g.items.push({ geometry, lod, matrix: matrix.clone(), tint, small });
  }
  build(scene, { castShadow = true } = {}) {
    const meshes = [];
    const v3 = new THREE.Vector3();
    for (const g of this.groups.values()) {
      let v = 0, idx = 0;
      for (const geo of g.geos.keys()) { v += geo.attributes.position.count; idx += geo.index.count; }
      const bm = new THREE.BatchedMesh(g.items.length, v, idx, Assets.material(g.map));
      for (const geo of g.geos.keys()) g.geos.set(geo, bm.addGeometry(geo));
      const c = new THREE.Color(), white = new THREE.Color(1, 1, 1);
      const anyTint = g.items.some((it) => it.tint);
      for (const it of g.items) {
        const id = bm.addInstance(g.geos.get(it.geometry));
        bm.setMatrixAt(id, it.matrix);
        if (anyTint) bm.setColorAt(id, it.tint ? c.set(it.tint) : white);
        if (it.lod || it.small) {
          v3.setFromMatrixPosition(it.matrix);
          this.lods.push({ mesh: bm, id, hi: g.geos.get(it.geometry), lo: it.lod ? g.geos.get(it.lod) : -1, x: v3.x, z: v3.z, small: it.small, state: 0 });
        }
      }
      bm.castShadow = castShadow; bm.receiveShadow = true;
      bm.perObjectFrustumCulled = true; bm.sortObjects = false;
      scene.add(bm); meshes.push(bm);
    }
    this.groups.clear();
    return meshes;
  }
  // swap distant props to their simplified versions and hide small far-away ones
  updateLod(x, z, lodDist, smallCull) {
    const l2 = lodDist * lodDist, c2 = smallCull * smallCull;
    for (const o of this.lods) {
      const d2 = (o.x - x) ** 2 + (o.z - z) ** 2;
      const state = o.small && d2 > c2 ? 2 : o.lo >= 0 && d2 > l2 ? 1 : 0;
      if (state === o.state) continue;
      if (state === 2) o.mesh.setVisibleAt(o.id, false);
      else {
        if (o.state === 2) o.mesh.setVisibleAt(o.id, true);
        if (o.lo >= 0) o.mesh.setGeometryIdAt(o.id, state === 1 ? o.lo : o.hi);
      }
      o.state = state;
    }
  }
}

// Bounding box of a prop (meters, unrotated) for colliders.
export function propSize(bundle, name) {
  const b = Assets.geom(bundle, name).box;
  return { sx: b.max.x - b.min.x, sy: b.max.y - b.min.y, sz: b.max.z - b.min.z, cx: (b.max.x + b.min.x) / 2, cz: (b.max.z + b.min.z) / 2, minY: b.min.y, maxY: b.max.y };
}
