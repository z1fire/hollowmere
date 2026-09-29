import { NodeIO } from '@gltf-transform/core'; import { ALL_EXTENSIONS } from '@gltf-transform/extensions'; import { MeshoptDecoder } from 'meshoptimizer';
await MeshoptDecoder.ready; const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
for (const b of process.argv.slice(2)) { const d = await io.read(`../web/assets/${b}.glb`); const res = [];
  for (const n of d.getRoot().getDefaultScene().listChildren()) { let t = 0, mats = new Set(); n.traverse((x) => { const m = x.getMesh(); if (m) for (const p of m.listPrimitives()) { t += (p.getIndices()?.getCount() ?? p.getAttribute('POSITION').getCount()) / 3; mats.add(p.getMaterial()?.getName()); } }); res.push(`${n.getName()}=${t}t/${mats.size}m`); }
  console.log(b + ': ' + res.join(' ')); }
