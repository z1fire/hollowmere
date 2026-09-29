import { NodeIO, getBounds } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { MeshoptDecoder } from 'meshoptimizer';
import fs from 'fs';
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
const out = {};
for (const b of ['weapons', 'dungeon', 'furniture', 'halloween', 'nature', 'crops', 'village']) {
  const d = await io.read(`../web/assets/props/${b}.glb`);
  out[b] = {};
  for (const n of d.getRoot().getDefaultScene().listChildren()) { const { min, max } = getBounds(n); out[b][n.getName()] = [max[0] - min[0], max[1] - min[1], max[2] - min[2], min[1], (min[0] + max[0]) / 2, (min[2] + max[2]) / 2].map((v) => +v.toFixed(2)); }
}
fs.writeFileSync('measure.json', JSON.stringify(out));
for (const [b, o] of Object.entries(out)) console.log(b + ': ' + Object.entries(o).map(([k, v]) => `${k}=${v[0]}x${v[1]}x${v[2]}${v[3] ? '@' + v[3] : ''}${v[4] || v[5] ? ' c(' + v[4] + ',' + v[5] + ')' : ''}`).join('  '));
