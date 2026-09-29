import * as THREE from 'three';
import { mulberry32 } from './util.js';

// All textures are generated procedurally on canvases (no image assets needed).
function canvas(size = 256) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  return [c, c.getContext('2d')];
}
function toTex(c, anis = 4) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = anis;
  return t;
}
function speckle(ctx, size, rnd, n, colors, rmin = 0.5, rmax = 2) {
  for (let i = 0; i < n; i++) {
    ctx.fillStyle = colors[Math.floor(rnd() * colors.length)];
    const r = rmin + rnd() * (rmax - rmin);
    ctx.fillRect(rnd() * size, rnd() * size, r, r);
  }
}

export function makeTextures(anis) {
  const rnd = mulberry32(1234);
  const T = {};

  { // plaster
    const [c, x] = canvas(256);
    x.fillStyle = '#e8dcc4'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, rnd, 6000, ['#ddd0b5', '#f0e6d2', '#d6c8ab', '#e2d5bb'], 1, 4);
    for (let i = 0; i < 40; i++) { x.fillStyle = 'rgba(150,130,100,0.06)'; x.beginPath(); x.arc(rnd() * 256, rnd() * 256, 10 + rnd() * 30, 0, 7); x.fill(); }
    T.plaster = toTex(c, anis);
  }
  { // stone blocks
    const [c, x] = canvas(256);
    x.fillStyle = '#6d6a64'; x.fillRect(0, 0, 256, 256);
    const rows = 8, h = 256 / rows;
    for (let r = 0; r < rows; r++) {
      let px = r % 2 ? -20 : 0;
      while (px < 256) {
        const w = 36 + rnd() * 34;
        const v = 110 + rnd() * 50;
        x.fillStyle = `rgb(${v},${v - 3},${v - 8})`;
        x.fillRect(px + 2, r * h + 2, w - 4, h - 4);
        x.fillStyle = 'rgba(255,255,255,0.08)'; x.fillRect(px + 2, r * h + 2, w - 4, 3);
        x.fillStyle = 'rgba(0,0,0,0.12)'; x.fillRect(px + 2, r * h + h - 5, w - 4, 3);
        px += w;
      }
    }
    speckle(x, 256, rnd, 3000, ['rgba(0,0,0,0.1)', 'rgba(255,255,255,0.07)'], 1, 3);
    T.stone = toTex(c, anis);
  }
  { // cobblestone
    const [c, x] = canvas(256);
    x.fillStyle = '#4e4a44'; x.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 140; i++) {
      const cx = rnd() * 256, cy = rnd() * 256, r = 9 + rnd() * 9, v = 105 + rnd() * 60;
      for (const [ox, oy] of [[0, 0], [256, 0], [-256, 0], [0, 256], [0, -256]]) {
        x.fillStyle = `rgb(${v},${v - 4},${v - 10})`;
        x.beginPath(); x.ellipse(cx + ox, cy + oy, r, r * 0.8, rnd() * 3, 0, 7); x.fill();
        x.fillStyle = 'rgba(255,255,255,0.08)';
        x.beginPath(); x.ellipse(cx + ox - 2, cy + oy - 2, r * 0.6, r * 0.4, 0, 0, 7); x.fill();
      }
    }
    T.cobble = toTex(c, anis);
  }
  { // wood planks
    const [c, x] = canvas(256);
    const rows = 6, h = 256 / rows;
    for (let r = 0; r < rows; r++) {
      const v = 150 + rnd() * 40;
      x.fillStyle = `rgb(${v},${v * 0.72},${v * 0.45})`; x.fillRect(0, r * h, 256, h);
      for (let i = 0; i < 30; i++) {
        x.strokeStyle = `rgba(70,40,20,${0.08 + rnd() * 0.12})`; x.lineWidth = 1;
        const y = r * h + rnd() * h; x.beginPath(); x.moveTo(0, y);
        x.bezierCurveTo(80, y + rnd() * 6 - 3, 170, y + rnd() * 6 - 3, 256, y); x.stroke();
      }
      x.fillStyle = 'rgba(40,20,10,0.55)'; x.fillRect(0, r * h, 256, 2);
      const seam = rnd() * 256; x.fillRect(seam, r * h, 2, h);
    }
    T.planks = toTex(c, anis);
  }
  { // logs (horizontal)
    const [c, x] = canvas(256);
    const rows = 5, h = 256 / rows;
    for (let r = 0; r < rows; r++) {
      const g = x.createLinearGradient(0, r * h, 0, r * h + h);
      g.addColorStop(0, '#3e2a18'); g.addColorStop(0.2, '#7a5634'); g.addColorStop(0.55, '#8c6640'); g.addColorStop(0.9, '#5a3d22'); g.addColorStop(1, '#2e1f12');
      x.fillStyle = g; x.fillRect(0, r * h, 256, h);
      for (let i = 0; i < 25; i++) {
        x.strokeStyle = 'rgba(30,18,8,0.2)'; const y = r * h + 6 + rnd() * (h - 12);
        x.beginPath(); x.moveTo(rnd() * 256, y); x.lineTo(rnd() * 256, y + rnd() * 2); x.stroke();
      }
    }
    T.log = toTex(c, anis);
  }
  { // thatch
    const [c, x] = canvas(256);
    x.fillStyle = '#9c8047'; x.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 2600; i++) {
      const v = 120 + rnd() * 90;
      x.strokeStyle = `rgba(${v},${v * 0.82},${v * 0.45},0.8)`; x.lineWidth = 1 + rnd();
      const px = rnd() * 256, py = rnd() * 256;
      x.beginPath(); x.moveTo(px, py); x.lineTo(px + rnd() * 4 - 2, py + 14 + rnd() * 16); x.stroke();
    }
    for (let r = 0; r < 8; r++) { x.fillStyle = 'rgba(40,30,10,0.18)'; x.fillRect(0, r * 32 + 28, 256, 4); }
    T.thatch = toTex(c, anis);
  }
  { // shingles
    const [c, x] = canvas(256);
    x.fillStyle = '#3a2a24'; x.fillRect(0, 0, 256, 256);
    const rows = 8, h = 32;
    for (let r = 0; r < rows; r++) {
      let px = r % 2 ? -16 : 0;
      while (px < 256) {
        const v = 90 + rnd() * 40;
        x.fillStyle = `rgb(${v * 1.05},${v * 0.55},${v * 0.45})`;
        x.beginPath(); x.roundRect(px + 1, r * h, 30, h + 4, [0, 0, 8, 8]); x.fill();
        x.fillStyle = 'rgba(0,0,0,0.25)'; x.fillRect(px + 1, r * h + h, 30, 3);
        px += 32;
      }
    }
    T.shingle = toTex(c, anis);
  }
  { // terrain detail (grayscale-ish, multiplied by vertex color)
    const [c, x] = canvas(256);
    x.fillStyle = '#d8d8d8'; x.fillRect(0, 0, 256, 256);
    speckle(x, 256, rnd, 9000, ['#bfbfbf', '#ececec', '#b0b0b0', '#ffffff', '#cfcfcf'], 1, 3);
    for (let i = 0; i < 400; i++) {
      x.strokeStyle = rnd() < 0.5 ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.12)';
      const px = rnd() * 256, py = rnd() * 256;
      x.beginPath(); x.moveTo(px, py); x.lineTo(px + rnd() * 3 - 1.5, py - 4 - rnd() * 6); x.stroke();
    }
    T.ground = toTex(c, anis);
  }
  { // bark
    const [c, x] = canvas(128);
    x.fillStyle = '#5b412b'; x.fillRect(0, 0, 128, 128);
    for (let i = 0; i < 300; i++) { x.fillStyle = rnd() < 0.5 ? 'rgba(20,12,5,0.35)' : 'rgba(140,110,80,0.2)'; x.fillRect(rnd() * 128, rnd() * 128, 1 + rnd() * 2, 6 + rnd() * 20); }
    T.bark = toTex(c, anis);
  }
  return T;
}

// Painted wooden sign with text
export function signTexture(text) {
  const c = document.createElement('canvas'); c.width = 512; c.height = 128;
  const x = c.getContext('2d');
  const g = x.createLinearGradient(0, 0, 0, 128); g.addColorStop(0, '#6b4524'); g.addColorStop(1, '#4a2e16');
  x.fillStyle = g; x.fillRect(0, 0, 512, 128);
  x.strokeStyle = '#2a1a0c'; x.lineWidth = 10; x.strokeRect(5, 5, 502, 118);
  x.fillStyle = '#f3d98b'; x.font = 'bold 54px Georgia, serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
  let size = 54; while (x.measureText(text).width > 470 && size > 20) { size -= 2; x.font = `bold ${size}px Georgia, serif`; }
  x.shadowColor = 'rgba(0,0,0,0.6)'; x.shadowBlur = 4; x.fillText(text, 256, 68);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export function glowTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.3, 'rgba(255,255,255,0.6)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c); return t;
}
