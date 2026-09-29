import * as THREE from 'three';

const matCache = new Map();
export function cmat(color, extra) {
  const key = color + (extra ? JSON.stringify(extra) : '');
  let m = matCache.get(key);
  if (!m) { m = new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0, ...extra }); matCache.set(key, m); }
  return m;
}
const geoCache = new Map();
function boxGeo(w, h, d) {
  const k = `${w}|${h}|${d}`;
  let g = geoCache.get(k); if (!g) { g = new THREE.BoxGeometry(w, h, d); geoCache.set(k, g); }
  return g;
}
function box(w, h, d, color, x = 0, y = 0, z = 0, own = false) {
  const m = new THREE.Mesh(boxGeo(w, h, d), own ? new THREE.MeshStandardMaterial({ color, roughness: 0.85 }) : cmat(color));
  m.position.set(x, y, z); m.castShadow = true;
  return m;
}
function mesh(geo, color, x = 0, y = 0, z = 0, own = false) {
  const m = new THREE.Mesh(geo, own ? new THREE.MeshStandardMaterial({ color, roughness: 0.85 }) : cmat(color));
  m.position.set(x, y, z); m.castShadow = true; return m;
}

export function heldItem(type) {
  const g = new THREE.Group();
  switch (type) {
    case 'hammer': g.add(box(0.05, 0.45, 0.05, '#6b4a2b', 0, 0.1, 0)); g.add(box(0.1, 0.1, 0.22, '#555', 0, 0.32, 0)); break;
    case 'mug': g.add(mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.16, 8), '#8a6a3a', 0, 0.05, 0.05)); break;
    case 'staff': g.add(box(0.05, 1.6, 0.05, '#5a3a1a', 0, 0.35, 0)); g.add(mesh(new THREE.OctahedronGeometry(0.08), '#66ddff', 0, 1.18, 0)); break;
    case 'bow': { const t = mesh(new THREE.TorusGeometry(0.45, 0.02, 4, 12, Math.PI), '#6b4a2b', 0, 0, 0); t.rotation.z = -Math.PI / 2; g.add(t); break; }
    case 'book': g.add(box(0.2, 0.26, 0.06, '#6a1a1a', 0, 0, 0.08)); break;
    case 'spear': g.add(box(0.04, 2.0, 0.04, '#6b4a2b', 0, 0.5, 0)); g.add(box(0.06, 0.22, 0.02, '#bbb', 0, 1.6, 0)); break;
    case 'hoe': g.add(box(0.04, 1.4, 0.04, '#7a5a3a', 0, 0.3, 0)); g.add(box(0.05, 0.05, 0.22, '#666', 0, 1.0, 0.1)); break;
    case 'sword': g.add(box(0.04, 0.12, 0.04, '#3a2a1a', 0, 0, 0)); g.add(box(0.2, 0.03, 0.05, '#888', 0, 0.07, 0)); g.add(box(0.06, 0.7, 0.015, '#c8ccd0', 0, 0.43, 0)); break;
    case 'club': g.add(mesh(new THREE.CylinderGeometry(0.08, 0.04, 0.7, 6), '#5a3a1a', 0, 0.25, 0)); break;
    case 'rusty': g.add(box(0.04, 0.12, 0.04, '#3a2a1a', 0, 0, 0)); g.add(box(0.07, 0.6, 0.015, '#8a7a6a', 0, 0.36, 0)); break;
    case 'shortbow': { const t = mesh(new THREE.TorusGeometry(0.35, 0.02, 4, 10, Math.PI), '#4a3a1a', 0, 0, 0); t.rotation.z = -Math.PI / 2; g.add(t); break; }
  }
  return g;
}

// ---------- HUMANOID ----------
export function makeHumanoid(o = {}) {
  const own = !!o.ownMats;
  const B = (w, h, d, c, x, y, z) => box(w, h, d, c, x, y, z, own);
  const skin = o.skin || '#e0b48a';
  const shirt = o.shirt || '#886644';
  const pants = o.pants || '#443322';
  const limbW = o.thin ? 0.07 : 0.13;
  const g = new THREE.Group();
  const root = new THREE.Group(); g.add(root);
  const s = (o.scale || 1) * (o.big ? 1.08 : 1);
  root.scale.setScalar(s);

  const hip = new THREE.Group(); hip.position.y = 0.86; root.add(hip);
  const mkLeg = (x) => {
    const leg = new THREE.Group(); leg.position.set(x, 0, 0); hip.add(leg);
    leg.add(B(limbW + 0.01, 0.8, limbW + 0.03, o.thin ? skin : pants, 0, -0.4, 0));
    if (!o.thin) leg.add(B(0.16, 0.14, 0.24, o.boots || '#3b2a1a', 0, -0.79, 0.03));
    return leg;
  };
  const legL = mkLeg(-0.11), legR = mkLeg(0.11);

  const torso = new THREE.Group(); hip.add(torso);
  const tw = o.thin ? 0.3 : (o.big ? 0.5 : 0.42);
  if (o.thin) { // skeleton ribcage
    torso.add(B(0.06, 0.6, 0.06, skin, 0, 0.3, -0.05));
    for (let i = 0; i < 4; i++) torso.add(B(0.3, 0.04, 0.2, skin, 0, 0.25 + i * 0.1, 0));
    torso.add(B(0.26, 0.08, 0.14, skin, 0, 0.02, 0));
  } else {
    torso.add(B(tw, 0.62, 0.25, shirt, 0, 0.31, 0));
    torso.add(B(tw + 0.02, 0.07, 0.27, o.belt || '#3a2616', 0, 0.04, 0));
    if (o.apron) torso.add(B(tw - 0.08, 0.7, 0.03, o.apron, 0, 0.12, 0.14));
  }
  if (o.robe) { // robe skirt covering legs
    const robe = mesh(new THREE.CylinderGeometry(0.24, 0.36, 0.84, 8), o.robe, 0, -0.4, 0, own);
    hip.add(robe);
  }
  if (o.armor) torso.add(B(tw + 0.04, 0.4, 0.29, o.armor, 0, 0.42, 0));

  const head = new THREE.Group(); head.position.y = 0.64; torso.add(head);
  const hs = o.headSize || 0.27;
  head.add(B(hs, hs + 0.02, hs, skin, 0, hs / 2 + 0.02, 0));
  const eyeC = o.eyes || '#1a1a1a';
  head.add(B(0.05, 0.04, 0.02, eyeC, -0.065, hs * 0.6, hs / 2 + 0.005));
  head.add(B(0.05, 0.04, 0.02, eyeC, 0.065, hs * 0.6, hs / 2 + 0.005));
  if (o.nose) head.add(B(0.05, 0.08, 0.1, o.nose, 0, hs * 0.42, hs / 2 + 0.04));
  if (o.ears) { head.add(B(0.14, 0.06, 0.04, skin, -hs / 2 - 0.06, hs * 0.6, 0)); head.add(B(0.14, 0.06, 0.04, skin, hs / 2 + 0.06, hs * 0.6, 0)); }
  if (o.hair) {
    head.add(B(hs + 0.03, 0.08, hs + 0.03, o.hair, 0, hs + 0.04, 0));
    head.add(B(hs + 0.03, o.longHair ? 0.4 : 0.18, 0.06, o.hair, 0, o.longHair ? hs * 0.35 : hs * 0.72, -hs / 2 - 0.02));
  }
  if (o.beard) head.add(B(hs - 0.02, 0.14, 0.06, o.beardColor || o.hair || '#5a3a1a', 0, 0.06, hs / 2 + 0.02));
  switch (o.hat) {
    case 'wizard': head.add(mesh(new THREE.ConeGeometry(0.22, 0.5, 8), o.hatColor || '#2a2a6a', 0, hs + 0.28, 0, own)); head.add(mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.03, 12), o.hatColor || '#2a2a6a', 0, hs + 0.04, 0, own)); break;
    case 'tophat': head.add(mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.25, 10), '#1a1a1a', 0, hs + 0.16, 0, own)); head.add(mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.02, 12), '#1a1a1a', 0, hs + 0.04, 0, own)); break;
    case 'cap': head.add(B(hs + 0.04, 0.08, hs + 0.04, '#6a3a2a', 0, hs + 0.05, 0)); head.add(B(hs, 0.02, 0.12, '#6a3a2a', 0, hs + 0.02, hs / 2 + 0.05)); break;
    case 'hood': head.add(B(hs + 0.06, hs + 0.1, hs + 0.04, o.hood || '#4a4a2a', 0, hs / 2 + 0.06, -0.03)); break;
    case 'straw': head.add(mesh(new THREE.CylinderGeometry(0.14, 0.17, 0.12, 10), '#d8b860', 0, hs + 0.08, 0, own)); head.add(mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.02, 12), '#d8b860', 0, hs + 0.03, 0, own)); break;
    case 'helmet': head.add(B(hs + 0.05, 0.16, hs + 0.05, '#8a8a8a', 0, hs + 0.02, 0)); head.add(B(0.03, 0.14, 0.04, '#8a8a8a', 0, hs * 0.55, hs / 2 + 0.03)); break;
    case 'horns': head.add(mesh(new THREE.ConeGeometry(0.05, 0.25, 5), '#ddd', -0.13, hs + 0.1, 0, own).rotateZ(0.5)); head.add(mesh(new THREE.ConeGeometry(0.05, 0.25, 5), '#ddd', 0.13, hs + 0.1, 0, own).rotateZ(-0.5)); break;
  }

  const mkArm = (x) => {
    const arm = new THREE.Group(); arm.position.set(x, 0.56, 0); torso.add(arm);
    arm.add(B(limbW - 0.01, 0.56, limbW + 0.01, o.thin ? skin : (o.sleeve || shirt), 0, -0.27, 0));
    arm.add(B(0.1, 0.1, 0.1, skin, 0, -0.59, 0));
    return arm;
  };
  const armL = mkArm(-(tw / 2 + 0.07)), armR = mkArm(tw / 2 + 0.07);
  if (o.held) {
    const it = heldItem(o.held);
    it.position.set(0, -0.6, 0.04); it.rotation.x = Math.PI / 2 * 0.9;
    if (o.held === 'staff' || o.held === 'spear' || o.held === 'hoe') it.rotation.x = 0.1;
    if (o.held === 'bow' || o.held === 'shortbow') { armL.add(it); it.rotation.set(0, 0, 0); } else armR.add(it);
  }
  return { group: g, root, hip, legL, legR, torso, head, armL, armR, phase: Math.random() * 6, attack: 0, kind: 'humanoid', held: o.held };
}

// ---------- WOLF ----------
export function makeWolf(color = '#77736c', own = true) {
  const B = (w, h, d, c, x, y, z) => box(w, h, d, c, x, y, z, own);
  const g = new THREE.Group(); const root = new THREE.Group(); g.add(root);
  const body = new THREE.Group(); body.position.y = 0.62; root.add(body);
  body.add(B(0.42, 0.42, 1.0, color, 0, 0, 0));
  body.add(B(0.46, 0.46, 0.4, color, 0, 0.03, 0.28)); // chest ruff
  const head = new THREE.Group(); head.position.set(0, 0.18, 0.58); body.add(head);
  head.add(B(0.32, 0.3, 0.32, color, 0, 0, 0));
  head.add(B(0.18, 0.15, 0.26, color, 0, -0.06, 0.26));
  head.add(B(0.07, 0.06, 0.05, '#111', 0, -0.03, 0.4));
  head.add(B(0.05, 0.04, 0.02, '#ffcc33', -0.09, 0.05, 0.165));
  head.add(B(0.05, 0.04, 0.02, '#ffcc33', 0.09, 0.05, 0.165));
  const earGeo = new THREE.ConeGeometry(0.06, 0.16, 4);
  head.add(mesh(earGeo, color, -0.1, 0.22, -0.04, own)); head.add(mesh(earGeo, color, 0.1, 0.22, -0.04, own));
  const tail = new THREE.Group(); tail.position.set(0, 0.1, -0.5); body.add(tail);
  const tm = B(0.1, 0.1, 0.5, color, 0, 0, -0.22); tail.add(tm); tail.rotation.x = 0.5;
  const legs = [];
  for (const [x, z] of [[-0.14, 0.36], [0.14, 0.36], [-0.14, -0.36], [0.14, -0.36]]) {
    const l = new THREE.Group(); l.position.set(x, -0.15, z); body.add(l);
    l.add(B(0.1, 0.5, 0.12, color, 0, -0.22, 0)); legs.push(l);
  }
  return { group: g, root, body, head, tail, legs, phase: Math.random() * 6, attack: 0, kind: 'wolf' };
}

export function makeGoblin(chief = false) {
  const skin = chief ? '#5d8a3a' : '#6f9e44';
  return makeHumanoid({
    ownMats: true, scale: chief ? 1.55 : 0.78, skin, shirt: chief ? '#6a1a1a' : '#5a4630', pants: '#3a2e1e',
    headSize: 0.32, ears: true, nose: skin, eyes: '#ff3322', hat: chief ? 'horns' : undefined,
    held: chief ? 'club' : 'rusty', armor: chief ? '#444' : undefined, big: chief,
  });
}
export function makeGoblinArcher() {
  return makeHumanoid({ ownMats: true, scale: 0.78, skin: '#7aa24c', shirt: '#3e4a2a', pants: '#3a2e1e', headSize: 0.32, ears: true, nose: '#7aa24c', eyes: '#ff3322', hat: 'hood', hood: '#3a3a22', held: 'shortbow' });
}
export function makeSkeleton(archer = false) {
  return makeHumanoid({ ownMats: true, thin: true, skin: '#e6e0cc', eyes: '#66ffcc', held: archer ? 'shortbow' : 'rusty', hat: archer ? 'hood' : undefined, hood: '#2a2a2a' });
}

// ---------- ANIMATION ----------
export function animate(ch, dt, speed, t) {
  ch.phase += dt * (3 + speed * 1.6);
  const sw = Math.min(1, speed / 3);
  if (ch.kind === 'wolf') {
    const a = Math.sin(ch.phase * 1.4) * 0.7 * sw;
    ch.legs[0].rotation.x = a; ch.legs[3].rotation.x = a;
    ch.legs[1].rotation.x = -a; ch.legs[2].rotation.x = -a;
    ch.body.position.y = 0.62 + Math.abs(Math.sin(ch.phase * 1.4)) * 0.06 * sw;
    ch.tail.rotation.y = Math.sin(t * 4 + ch.phase) * 0.3;
    if (ch.attack > 0) { ch.attack -= dt; ch.head.rotation.x = -Math.sin((1 - ch.attack / 0.4) * Math.PI) * 0.6; ch.body.position.z = Math.sin((1 - ch.attack / 0.4) * Math.PI) * 0.3; }
    else { ch.head.rotation.x = Math.sin(t * 2 + ch.phase) * 0.05; ch.body.position.z = 0; }
    return;
  }
  const a = Math.sin(ch.phase) * 0.65 * sw;
  ch.legL.rotation.x = a; ch.legR.rotation.x = -a;
  ch.armL.rotation.x = -a * 0.8;
  ch.hip.position.y = 0.86 + Math.abs(Math.cos(ch.phase)) * 0.04 * sw;
  ch.torso.rotation.z = Math.sin(t * 1.3 + ch.phase) * 0.015;
  ch.head.rotation.x = Math.sin(t * 0.8 + ch.phase) * 0.04;
  if (ch.attack > 0) {
    ch.attack -= dt;
    const k = 1 - Math.max(0, ch.attack) / 0.45;
    ch.armR.rotation.x = -2.4 * Math.sin(k * Math.PI) ;
    ch.armR.rotation.z = -0.3 * Math.sin(k * Math.PI);
    if (ch.held === 'shortbow' || ch.held === 'bow') { ch.armL.rotation.x = -1.5; ch.armR.rotation.x = -1.5; }
  } else {
    ch.armR.rotation.x = a * 0.8; ch.armR.rotation.z = 0;
  }
  if (ch.talking) { ch.head.rotation.y = Math.sin(t * 3) * 0.08; }
}
