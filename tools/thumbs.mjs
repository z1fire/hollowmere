import sharp from 'sharp'; import fs from 'fs';
const ids = process.argv.slice(2);
const tiles = [];
for (const id of ids) {
  const f = `.cache/thumbs/${id}.png`;
  if (!fs.existsSync(f)) { const r = await fetch(`https://cdn.polyhaven.com/asset_img/thumbs/${id}.png?width=200&height=200`); fs.writeFileSync(f, Buffer.from(await r.arrayBuffer())); }
  const label = Buffer.from(`<svg width="200" height="24"><rect width="200" height="24" fill="black"/><text x="4" y="17" font-size="14" fill="white" font-family="Arial">${id}</text></svg>`);
  tiles.push(await sharp(f).resize(200, 200).composite([{ input: label, top: 176, left: 0 }]).png().toBuffer());
}
const cols = 6, rows = Math.ceil(tiles.length / cols);
await sharp({ create: { width: cols * 200, height: rows * 200, channels: 3, background: '#222' } })
  .composite(tiles.map((t, i) => ({ input: t, left: (i % cols) * 200, top: Math.floor(i / cols) * 200 }))).png().toFile('.cache/sheet.png');
console.log('ok');
