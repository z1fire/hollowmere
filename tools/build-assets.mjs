// Hollowmere asset pipeline.
// Downloads CC0 source assets (KayKit, Quaternius, Poly Haven), strips/merges/compresses them,
// and writes game-ready files to game/assets (the Godot project). Run:  cd tools && npm install && npm run assets
//
// Sources (all CC0 / public domain):
//  - KayKit by Kay Lousberg            https://github.com/KayKit-Game-Assets
//  - Quaternius                        https://quaternius.com  (glb mirrors: trebeljahr/quaternius-showcase, arabold/rogue-gauntlet)
//  - Poly Haven textures               https://polyhaven.com
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { Document, NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, EXTTextureWebP } from '@gltf-transform/extensions';
import { dedup, prune, resample, weld, unpartition, mergeDocuments, meshopt, simplify } from '@gltf-transform/functions';
import { MeshoptEncoder, MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, '$1')), '..');
const OUT = path.join(ROOT, 'game', 'assets');
const CACHE = path.join(ROOT, 'tools', '.cache');
fs.mkdirSync(CACHE, { recursive: true });
await MeshoptEncoder.ready; await MeshoptSimplifier.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.encoder': MeshoptEncoder });

// ---------------- sources ----------------
const KAYKIT = ['KayKit-Character-Pack-Adventures-1.0', 'KayKit-Character-Pack-Skeletons-1.0', 'KayKit-Dungeon-Remastered-1.0', 'KayKit-Furniture-Bits-1.0', 'KayKit-Halloween-Bits-1.0'];
for (const r of KAYKIT) {
  const dir = path.join(CACHE, r);
  if (!fs.existsSync(dir)) { console.log('clone', r); execSync(`git clone -q --depth 1 https://github.com/KayKit-Game-Assets/${r}.git "${dir}"`); }
}
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
const kayFiles = KAYKIT.flatMap((r) => walk(path.join(CACHE, r))).filter((f) => /\.(glb|gltf)$/.test(f));
const kay = (name) => {
  const f = kayFiles.find((p) => { const b = path.basename(p); return b === `${name}.glb` || b === `${name}.gltf` || b === `${name}.gltf.glb`; });
  if (!f) throw new Error('KayKit asset not found: ' + name);
  return f;
};
async function fetchTo(url, file) {
  if (fs.existsSync(file)) return file;
  const r = await fetch(url); if (!r.ok) throw new Error(`${r.status} ${url}`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
  return file;
}
const QS = 'https://raw.githubusercontent.com/trebeljahr/quaternius-showcase/main/public/glb';
const quat = (pack, name) => fetchTo(`${QS}/${pack}/${name}.glb`, path.join(CACHE, 'quaternius', pack, `${name}.glb`));
const monster = (name) => fetchTo(`https://raw.githubusercontent.com/arabold/rogue-gauntlet/main/assets/quaternius-monsters/${name}`, path.join(CACHE, 'monsters', name));

// ---------------- helpers ----------------
// Re-encode every texture as WebP (normalizing odd PNG colour spaces first).
const webp = (size) => async (doc) => {
  const tex = doc.getRoot().listTextures(); if (!tex.length) return;
  let converted = 0;
  for (const t of tex) {
    const img = t.getImage(); if (!img) continue;
    try {
      const buf = await sharp(Buffer.from(img), { ignoreIcc: true }).resize(size, size, { fit: 'inside', withoutEnlargement: true }).webp({ quality: 88 }).toBuffer();
      t.setImage(new Uint8Array(buf)).setMimeType('image/webp');
      if (t.getURI()) t.setURI(t.getURI().replace(/[.]\w+$/, '.webp'));
      converted++;
    } catch (e) { console.warn('   (kept original texture', t.getName() || t.getURI(), '-', e.message + ')'); }
  }
  if (!converted) return;
  doc.createExtension(EXTTextureWebP).setRequired(true);
};
// Fully remove an animation, including its samplers/channels (a plain dispose leaves the keyframe data behind).
function killAnim(a) {
  for (const c of a.listChannels()) c.dispose();
  for (const smp of a.listSamplers()) smp.dispose(); // orphaned accessors are removed by prune()
  a.dispose();
}
const kb = (f) => `${(fs.statSync(f).size / 1024).toFixed(0)}KB`;
async function write(doc, rel) {
  const f = path.join(OUT, rel); fs.mkdirSync(path.dirname(f), { recursive: true });
  // (no meshopt/quantization: Godot's glTF importer reads plain float data)
  await io.write(f, doc); console.log('  ', rel, kb(f));
}

// Merge many models into one GLB; each model becomes a named root node (shared textures deduplicated).
// lods: { names: [...], ratio } -> also adds a simplified "<name>__lod" copy for distant rendering
async function bundle(rel, items, texSize = 512, lods = null) {
  const doc = new Document(); doc.createBuffer();
  const scene = doc.createScene('bundle'); doc.getRoot().setDefaultScene(scene);
  const all = [...items];
  if (lods) for (const [id, file] of items) if (lods.names.includes(id)) all.push([id + '__lod', file, lods.ratio]);
  for (const [id, file, ratio] of all) {
    const src = await io.read(file);
    if (ratio) {
      // flat-shaded models have split vertices; drop normals so the mesh welds into simplifiable topology
      for (const m of src.getRoot().listMeshes()) for (const prim of m.listPrimitives()) prim.setAttribute('NORMAL', null);
      await src.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio, error: 0.08, lockBorder: false }));
    }
    src.getRoot().listAnimations().forEach(killAnim);
    const before = new Set(doc.getRoot().listScenes());
    mergeDocuments(doc, src);
    const root = doc.createNode('P_' + id); // prefixed: Godot renames nodes that clash with their mesh children
    for (const s of doc.getRoot().listScenes().filter((s) => !before.has(s))) {
      for (const n of s.listChildren()) { s.removeChild(n); root.addChild(n); }
      s.dispose();
    }
    scene.addChild(root);
  }
  await doc.transform(unpartition(), dedup(), prune(), weld(), webp(texSize));
  await write(doc, rel);
}

async function character(rel, file, texSize = 512) {
  const doc = await io.read(file);
  doc.getRoot().listAnimations().forEach(killAnim);
  await doc.transform(dedup(), prune({ keepLeaves: true }), webp(texSize));
  await write(doc, rel);
}

async function animations(rel, files, keep) {
  // Animation-only file: all KayKit characters share one rig, so these clips drive every human/skeleton.
  const doc = await io.read(files[0]);
  const mainScene = doc.getRoot().listScenes()[0];
  const mainNodes = new Map();
  mainScene.traverse((n) => mainNodes.set(n.getName(), n));
  for (const extra of files.slice(1)) {
    mergeDocuments(doc, await io.read(extra));
    // clips from the extra file target its own (identically named) bones: retarget them onto the main rig
    for (const a of doc.getRoot().listAnimations()) for (const ch of a.listChannels()) {
      const tn = ch.getTargetNode();
      if (tn && mainNodes.get(tn.getName()) && mainNodes.get(tn.getName()) !== tn) ch.setTargetNode(mainNodes.get(tn.getName()));
      else if (tn && !mainNodes.get(tn.getName())) ch.dispose(); // bone only the extra model has (e.g. a jaw)
    }
  }
  const seen = new Set();
  for (const a of doc.getRoot().listAnimations()) {
    if (!keep.includes(a.getName()) || seen.has(a.getName())) killAnim(a); else seen.add(a.getName());
  }
  // keep only the first (Knight) scene: its skinned mesh makes Godot build a Skeleton3D whose bone
  // paths match every other KayKit character, so these clips can drive all of them
  doc.getRoot().listScenes().slice(1).forEach((s) => s.dispose());
  await doc.transform(unpartition(), resample(), dedup(), prune({ keepLeaves: true }));
  console.log('   clips:', doc.getRoot().listAnimations().map((a) => a.getName()).join(', '));
  await write(doc, rel);
}

async function animated(rel, file, keep) {
  const doc = await io.read(file);
  for (const a of doc.getRoot().listAnimations()) {
    const n = a.getName().replace(/^.*\|/, '');
    if (!keep.includes(n)) killAnim(a); else a.setName(n);
  }
  await doc.transform(resample(), dedup(), prune({ keepLeaves: true }), webp(512));
  await write(doc, rel);
}

// ---------------- textures (Poly Haven) ----------------
async function polyhaven(name, id, size = 1024, maps = ['Diffuse', 'nor_gl', 'Rough']) {
  const files = await (await fetch(`https://api.polyhaven.com/files/${id}`)).json();
  const suffix = { Diffuse: 'd', nor_gl: 'n', Rough: 'r' };
  for (const m of maps) {
    const url = files[m]?.['1k']?.jpg?.url; if (!url) { console.warn('   missing', id, m); continue; }
    const src = await fetchTo(url, path.join(CACHE, 'polyhaven', `${id}_${m}.jpg`));
    const out = path.join(OUT, 'tex', `${name}_${suffix[m]}.jpg`);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    await sharp(src).resize(size, size).jpeg({ quality: m === 'Diffuse' ? 84 : 80, mozjpeg: true }).toFile(out);
    console.log('  ', `tex/${name}_${suffix[m]}.jpg`, kb(out));
  }
}

// ======================================================================
const ANIMS = ['Idle', 'Unarmed_Idle', 'Walking_A', 'Walking_B', 'Walking_C', 'Running_A', 'Running_B', '1H_Melee_Attack_Chop', '1H_Melee_Attack_Slice_Diagonal',
  '1H_Melee_Attack_Stab', '2H_Melee_Attack_Chop', '2H_Melee_Attack_Spin', '1H_Ranged_Shoot', '2H_Ranged_Shoot', 'Spellcast_Shoot', 'Spellcast_Long', 'Spellcast_Raise',
  'Hit_A', 'Hit_B', 'Death_A', 'Death_B', 'Sit_Chair_Idle', 'Interact', 'Cheer', 'Block', 'Use_Item', 'PickUp', 'Throw', 'Idle_Combat', 'Running_C',
  'Skeletons_Awaken_Standing', 'Death_C_Skeletons', 'Unarmed_Melee_Attack_Punch_A', 'Lie_Idle'];

const TEX_ONLY = process.argv.includes('--tex');
const ONLY = process.argv.includes('--only') ? process.argv[process.argv.indexOf('--only') + 1] : null;
if (!TEX_ONLY) {
console.log('Characters');
for (const c of ['Knight', 'Barbarian', 'Mage', 'Rogue', 'Rogue_Hooded', 'Skeleton_Minion', 'Skeleton_Warrior', 'Skeleton_Rogue', 'Skeleton_Mage'])
  if (!ONLY || 'chars/'.includes(ONLY)) await character(`chars/${c.toLowerCase()}.glb`, kay(c));
console.log('Animations');
if (!ONLY || 'chars/anims.glb'.includes(ONLY)) await animations('chars/anims.glb', [kay('Knight'), kay('Skeleton_Minion')], ANIMS);

console.log('Creatures');
if (!ONLY || 'chars/wolf.glb'.includes(ONLY)) await animated('chars/wolf.glb', await quat('animals_pack', 'Wolf'), ['Attack', 'Death', 'Gallop', 'Idle', 'Walk', 'Idle_HitReact_Left', 'Eating']);
if (!ONLY || 'chars/orc.glb'.includes(ONLY)) await animated('chars/orc.glb', await monster('orc.glb'), ['Death', 'HitReact', 'Idle', 'Punch', 'Run', 'Walk', 'Weapon', 'Wave']);
if (!ONLY || 'chars/spider.glb'.includes(ONLY)) await animated('chars/spider.glb', await monster('spider.glb'), ['Spider_Attack', 'Spider_Death', 'Spider_Idle', 'Spider_Walk']);

console.log('Prop bundles');
if (!ONLY || 'props/weapons.glb'.includes(ONLY)) await bundle('props/weapons.glb', ['sword_1handed', 'sword_2handed', 'axe_1handed', 'axe_2handed', 'crossbow_1handed', 'crossbow_2handed', 'staff', 'wand', 'spellbook_open', 'spellbook_closed', 'mug_full', 'shield_round', 'shield_badge', 'arrow', 'dagger', 'quiver'].map((n) => [n, kay(n)]));
if (!ONLY || 'props/dungeon.glb'.includes(ONLY)) await bundle('props/dungeon.glb', ['barrel_large', 'barrel_small', 'barrel_small_stack', 'keg', 'keg_decorated', 'box_large', 'box_small', 'box_stacked', 'crates_stacked', 'chair', 'stool',
  'table_long', 'table_long_decorated_A', 'table_long_tablecloth_decorated_A', 'table_medium', 'table_medium_decorated_A', 'table_medium_tablecloth_decorated_B', 'table_small', 'table_small_decorated_A',
  'shelf_large', 'shelf_small', 'shelf_small_candles', 'shelves', 'candle_lit', 'candle_triple', 'candle_thin_lit', 'torch_mounted', 'torch_lit',
  'banner_patternA_red', 'banner_patternB_blue', 'banner_shield_green', 'banner_thin_red', 'banner_triple_yellow', 'banner_patternC_white',
  'chest', 'chest_gold', 'trunk_large_A', 'trunk_medium_B', 'bed_decorated', 'bed_frame', 'bottle_A_brown', 'bottle_A_green', 'bottle_B_green', 'plate_food_A', 'plate_food_B',
  'sword_shield', 'coin_stack_large', 'pillar', 'column', 'rubble_large', 'rubble_half', 'keyring_hanging'].map((n) => [n, kay(n)]));
if (!ONLY || 'props/furniture.glb'.includes(ONLY)) await bundle('props/furniture.glb', ['bed_single_A', 'bed_single_B', 'bed_double_A', 'shelf_B_large_decorated', 'shelf_A_big', 'cabinet_medium_decorated', 'rug_rectangle_A', 'rug_rectangle_stripes_A',
  'rug_oval_A', 'rug_oval_B', 'chair_A_wood', 'chair_B_wood', 'chair_stool_wood', 'table_medium', 'table_medium_long', 'book_set', 'pictureframe_large_A', 'armchair_pillows', 'pillow_A'].map((n) => [n, kay(n)]));
if (!ONLY || 'props/halloween.glb'.includes(ONLY)) await bundle('props/halloween.glb', ['crypt', 'arch_gate', 'arch', 'fence', 'fence_broken', 'fence_gate', 'fence_pillar', 'fence_pillar_broken', 'grave_A', 'grave_A_destroyed', 'grave_B',
  'gravemarker_A', 'gravemarker_B', 'gravestone', 'lantern_standing', 'post_lantern', 'post_skull', 'candle_triple', 'coffin', 'coffin_decorated', 'shrine_candles', 'skull', 'skull_candle',
  'bone_A', 'bone_B', 'ribcage', 'tree_dead_large', 'tree_dead_medium', 'tree_dead_small', 'pumpkin_orange', 'pumpkin_orange_jackolantern', 'bench', 'lantern_hanging'].map((n) => [n, kay(n)]));

const q = async (pack, names) => Promise.all(names.map(async (n) => [n, await quat(pack, n)]));
if (!ONLY || 'props/nature.glb'.includes(ONLY)) await bundle('props/nature.glb', await q('nature_pack', ['CommonTree_1', 'CommonTree_2', 'CommonTree_3', 'CommonTree_4', 'CommonTree_5', 'PineTree_1', 'PineTree_2', 'PineTree_3', 'PineTree_4', 'PineTree_5',
  'BirchTree_1', 'BirchTree_2', 'BirchTree_3', 'Willow_1', 'Willow_2', 'CommonTree_Dead_1', 'CommonTree_Dead_2', 'Rock_Moss_1', 'Rock_Moss_2', 'Rock_Moss_3', 'Rock_Moss_4', 'Rock_Moss_5',
  'Rock_1', 'Rock_2', 'Rock_3', 'Rock_4', 'Bush_1', 'Bush_2', 'BushBerries_1', 'Plant_1', 'Plant_2', 'Plant_3', 'Flowers', 'Grass', 'Grass_2', 'Grass_Short', 'TreeStump_Moss', 'WoodLog_Moss', 'Lilypad']),
  512, { ratio: 0.12, names: ['CommonTree_1', 'CommonTree_2', 'CommonTree_3', 'CommonTree_5', 'PineTree_1', 'PineTree_2', 'PineTree_3', 'PineTree_4', 'BirchTree_1', 'BirchTree_2', 'BirchTree_3',
    'Willow_1', 'Willow_2', 'CommonTree_Dead_1', 'CommonTree_Dead_2', 'Bush_1', 'Bush_2', 'BushBerries_1', 'Plant_1', 'Plant_3', 'Flowers', 'WoodLog_Moss', 'TreeStump_Moss'] });
if (!ONLY || 'props/crops.glb'.includes(ONLY)) await bundle('props/crops.glb', await q('crops_pack', ['Wheat_1', 'Wheat_2', 'Wheat_3', 'Wheat_4', 'Carrot_1', 'Carrot_2', 'Carrot_3', 'Carrot_4', 'Pumpkin_1', 'Pumpkin_2', 'Pumpkin_3', 'Pumpkin_4']));
if (!ONLY || 'props/village.glb'.includes(ONLY)) await bundle('props/village.glb', [
  ...await q('medieval_village_pack', ['Barrel', 'Bench_1', 'Bonfire_Lit', 'Cart', 'Cauldron', 'Crate', 'Hay', 'MarketStand_1', 'MarketStand_2', 'Well', 'Bags', 'Bag', 'Package_1', 'Fence', 'Bell_Tower']),
  ...await q('modular_medieval_buildings_pack', ['Target', 'TargetWithArrows', 'Dummy', 'Watchtower', 'Banner']),
  ...await q('survival_pack', ['Tent', 'Bonfire_Fire', 'WoodenTorch_Fire', 'Pot', 'WoodLog', 'Shovel']),
  ...await q('rpg_items_pack', ['Bow_Wooden', 'Bow_Golden', 'Potion1_Filled', 'Potion2_Filled', 'Potion4_Filled', 'Chest_Closed', 'Chest_Open', 'Crystal1', 'Crystal3', 'Book1_Open', 'Scroll', 'Coin', 'Hammer_Double', 'Sword', 'Axe_small', 'Skull']),
]);

}
console.log('Textures');
const TEX = {
  plaster: 'white_plaster_02', stone: 'rustic_stone_wall', planks: 'weathered_plank_siding', floor: 'old_wood_floor', beam: 'weathered_planks', thatch: 'reed_roof_03',
  tiles: 'clay_roof_tiles_02', cobble: 'cobblestone_floor_08', grass: 'sparse_grass', dirt: 'stony_dirt_path', rock: 'rocky_terrain_02', forest: 'forest_leaves_02',
};
for (const [name, id] of Object.entries(TEX)) await polyhaven(name, id, ['grass', 'dirt', 'rock', 'forest'].includes(name) ? 1024 : 1024);

console.log('Fonts');
const FONTS = {
  'Cinzel.ttf': 'https://github.com/google/fonts/raw/main/ofl/cinzel/Cinzel%5Bwght%5D.ttf',
  'AlegreyaSans-Regular.ttf': 'https://github.com/google/fonts/raw/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf',
  'AlegreyaSans-Bold.ttf': 'https://github.com/google/fonts/raw/main/ofl/alegreyasans/AlegreyaSans-Bold.ttf',
};
for (const [f, url] of Object.entries(FONTS)) {
  const out = path.join(OUT, 'fonts', f);
  await fetchTo(url, out); console.log('  ', 'fonts/' + f, kb(out));
}
// Colour emoji used as UI icons: subset Noto Color Emoji to just the glyphs the game uses (10MB -> ~100KB).
// Needs Python fonttools (pip install fonttools); falls back to the full font otherwise.
{
  const full = await fetchTo('https://github.com/googlefonts/noto-emoji/raw/main/2D/fonts/NotoColorEmoji-noflags.ttf', path.join(CACHE, 'NotoColorEmoji.ttf'));
  const EMOJI = '⛏️🔱🗡️⚔️🪓🏹🌿💚⚡🔥👕🦺🛡️🥋🌾🥕🎃🧪🔮🍞🍲🐺👂🦴🌸🪙🎒📜📖🗺️⚙️❤💧✋⤒☀️🌙❗✅✔💬📋🛒🛏️✨💾🎛️❓⬆️🏠📱⚜🧭🔒🌟🍺🐉👑⭐🎯🪨🍄🌲🏰🧙🗝️🕯️💀🪦🌕🌑';
  const cps = [...new Set([...EMOJI].map((c) => c.codePointAt(0)))].map((c) => 'U+' + c.toString(16).toUpperCase()).join(',');
  const out = path.join(OUT, 'fonts', 'Emoji.ttf');
  try {
    execSync(`python -m fontTools.subset "${full}" --unicodes="${cps},U+FE0F,U+200D" --output-file="${out}" --no-hinting`, { stdio: 'pipe' });
  } catch (e) { console.warn('   fonttools unavailable - using the full emoji font'); fs.copyFileSync(full, out); }
  console.log('  ', 'fonts/Emoji.ttf', kb(out));
}

// credits file
fs.writeFileSync(path.join(OUT, 'CREDITS.txt'), `Hollowmere uses the following CC0 (public domain) assets. Thank you!

KayKit by Kay Lousberg - www.kaylousberg.com
  Adventurers Character Pack, Skeletons Character Pack, Dungeon Remastered, Furniture Bits, Halloween Bits
Quaternius - quaternius.com
  Ultimate Nature, Crops, Medieval Village, Modular Medieval Buildings, Survival, RPG Items, Animals, Ultimate Monsters
Poly Haven - polyhaven.com
  Textures: ${Object.values(TEX).join(', ')}

Fonts (SIL Open Font License): Cinzel, Alegreya Sans, Noto Color Emoji - via Google Fonts
`);
console.log('Done. Total:', (walk(OUT).reduce((a, f) => a + fs.statSync(f).size, 0) / 1048576).toFixed(1), 'MB');
