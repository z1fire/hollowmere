import * as THREE from 'three';
import { ITEMS, SKILLS, QUESTS, SHOPS, ROLES, LORE, CLASS_GUIDE, xpToNext, COMBAT_SKILLS } from './data.js';
import { fmtTime, clamp } from './util.js';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const sellPrice = (id) => { const it = ITEMS[id]; return ['crop', 'material'].includes(it.kind) ? it.price : Math.max(1, Math.floor(it.price * 0.4)); };

export class UI {
  constructor(game) {
    this.game = game; this.dirty = true; this.modalOpen = false; this.panel = null; this.floats = []; this.mapT = 0;
    this.els = { hpFill: $('hpFill'), mpFill: $('mpFill'), hpText: $('hpText'), mpText: $('mpText'), gold: $('gold'), clock: $('clock'), className: $('className'), classLvl: $('classLvl'),
      prompt: $('prompt'), hotbar: $('hotbar'), toasts: $('toasts'), floats: $('floats'), tracker: $('tracker'), interact: $('btnInteract'), mini: $('minimap') };
    this.mini = this.els.mini.getContext('2d');
    $('panelClose').onclick = () => this.close();
    $('modal').addEventListener('pointerdown', (e) => { if (e.target.id === 'modal') this.close(); });
    document.querySelectorAll('[data-panel]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); this.toggle(b.dataset.panel); }));
    this.els.mini.addEventListener('click', () => this.toggle('map'));
    this.els.hotbar.addEventListener('pointerdown', (e) => { const s = e.target.closest('.slot'); if (s) { e.stopPropagation(); this.game.player.select(+s.dataset.i); } });
  }

  // ---------- HUD ----------
  update(dt) {
    const G = this.game, P = G.player, E = this.els;
    E.hpFill.style.width = `${(P.hp / P.maxHp) * 100}%`; E.mpFill.style.width = `${(P.mp / P.maxMp) * 100}%`;
    E.hpText.textContent = `${Math.ceil(P.hp)} / ${P.maxHp}`; E.mpText.textContent = `${Math.floor(P.mp)} / ${P.maxMp}`;
    E.clock.textContent = `${G.world.night > 0.5 ? '🌙' : '☀️'} Day ${G.day} · ${fmtTime(G.hours)}`;
    if (this.dirty) {
      this.dirty = false;
      E.gold.textContent = `🪙 ${P.gold}`;
      E.className.textContent = P.cls.title; E.classLvl.textContent = `Lv ${Math.max(1, P.cls.level)}`;
      E.hotbar.innerHTML = P.hotbar.map((id, i) => {
        const it = id && ITEMS[id]; const c = id ? P.count(id) : 0;
        const q = it && ['seed', 'consumable', 'crop'].includes(it.kind) ? `<b>${c}</b>` : '';
        return `<div class="slot ${i === P.sel ? 'sel' : ''} ${id && !c ? 'empty' : ''}" data-i="${i}"><i>${i + 1}</i>${it ? `<span>${it.icon}</span>${q}` : ''}</div>`;
      }).join('');
      const h = P.held(); $('heldName').textContent = h ? h.name : 'Bare hands';
      this.renderTracker();
      if (this.panel && !['dialog'].includes(this.panel)) this.refresh();
    }
    // interaction prompt
    const t = G.focus;
    const label = t ? t.label : null;
    if (label !== this._label) { this._label = label; E.prompt.innerHTML = label ? `<kbd>${G.input.isTouch ? '✋' : 'E'}</kbd> ${esc(label)}` : ''; E.prompt.classList.toggle('show', !!label); E.interact.classList.toggle('ready', !!label); }
    // floating texts
    const cam = G.camera, w = innerWidth, hgt = innerHeight;
    for (let i = this.floats.length - 1; i >= 0; i--) {
      const f = this.floats[i]; f.t += dt; f.pos.y += dt * 0.9;
      if (f.t > 1.1) { f.el.remove(); this.floats.splice(i, 1); continue; }
      const v = _v.copy(f.pos).project(cam);
      if (v.z > 1) { f.el.style.opacity = 0; continue; }
      f.el.style.transform = `translate(${(v.x * 0.5 + 0.5) * w}px, ${(-v.y * 0.5 + 0.5) * hgt}px) translate(-50%,-50%) scale(${f.big ? 1.4 : 1})`;
      f.el.style.opacity = f.t < 0.8 ? 1 : 1 - (f.t - 0.8) / 0.3;
    }
    this.mapT -= dt;
    if (this.mapT <= 0) { this.mapT = 0.1; this.drawMinimap(); }
  }
  renderTracker() {
    const G = this.game; const rows = [];
    for (const [id, q] of Object.entries(G.quests)) {
      if (q.state !== 'active' && q.state !== 'ready') continue;
      const d = QUESTS[id];
      const prog = d.type === 'kill' ? `${Math.min(q.progress, d.count)}/${d.count}` : `${Math.min(G.player.count(d.item), d.count)}/${d.count}`;
      rows.push(`<div class="${q.state === 'ready' || G.questReady(id) ? 'ready' : ''}">◆ ${esc(d.title)} <b>${prog}</b></div>`);
    }
    this.els.tracker.innerHTML = rows.slice(0, 4).join('');
  }
  toast(msg, color = '#f3e3b5') {
    const d = document.createElement('div'); d.className = 'toast'; d.style.borderColor = color; d.innerHTML = esc(msg);
    this.els.toasts.appendChild(d);
    while (this.els.toasts.children.length > 4) this.els.toasts.firstChild.remove();
    setTimeout(() => d.classList.add('out'), 2600); setTimeout(() => d.remove(), 3200);
  }
  banner(title, sub) {
    const b = $('banner'); b.querySelector('h2').textContent = title; b.querySelector('p').textContent = sub || '';
    b.classList.remove('show'); void b.offsetWidth; b.classList.add('show');
  }
  floatText(pos, text, color = '#fff', big = false) {
    const el = document.createElement('div'); el.className = 'float'; el.textContent = text; el.style.color = color;
    this.els.floats.appendChild(el);
    this.floats.push({ el, pos: pos.clone(), t: 0, big });
  }
  hurtFlash() { const h = $('hurt'); h.classList.remove('on'); void h.offsetWidth; h.classList.add('on'); }

  // ---------- minimap ----------
  buildMapImage() {
    const W = this.game.world; const S = 400, c = document.createElement('canvas'); c.width = c.height = S;
    const x = c.getContext('2d');
    const img = x.createImageData(S, S);
    for (let j = 0; j < S; j += 2) for (let i = 0; i < S; i += 2) {
      const wx = i - 200, wz = j - 200; const h = W.heightAt(wx, wz); const r = Math.hypot(wx, wz);
      let col = [78, 120, 50];
      if (h > 14 || r > 188) col = [110, 105, 98];
      else if (W.noise3(wx * 0.013 + 3, wz * 0.013) > 0.1 && r > 66) col = [52, 88, 40];
      const shade = 1 + (W.heightAt(wx + 2, wz) - h) * -0.08;
      for (let dj = 0; dj < 2; dj++) for (let di = 0; di < 2; di++) { const k = ((j + dj) * S + i + di) * 4; img.data[k] = col[0] * shade; img.data[k + 1] = col[1] * shade; img.data[k + 2] = col[2] * shade; img.data[k + 3] = 255; }
    }
    x.putImageData(img, 0, 0);
    x.translate(200, 200);
    x.fillStyle = '#3a7aa8'; x.beginPath(); x.arc(W.water.x, W.water.z, W.water.r, 0, 7); x.fill();
    x.lineCap = 'round';
    for (const r of W.roads) { x.strokeStyle = '#b8a078'; x.lineWidth = r.w; x.beginPath(); r.pts.forEach((p, i) => i ? x.lineTo(p.x, p.z) : x.moveTo(p.x, p.z)); x.stroke(); }
    x.fillStyle = '#9a9488'; x.beginPath(); x.arc(0, 0, 12.5, 0, 7); x.fill();
    x.strokeStyle = '#6a4a2a'; x.lineWidth = 1; x.beginPath(); x.arc(0, 0, W.fenceR, 0, 7); x.stroke();
    for (const b of W.buildings) {
      const W2 = b.rot % 2 ? b.d : b.w, D2 = b.rot % 2 ? b.w : b.d;
      x.fillStyle = b.type === 'farmhouse' ? '#e0b050' : '#c8683a'; x.fillRect(b.x - W2 / 2, b.z - D2 / 2, W2, D2);
      x.strokeStyle = '#3a2210'; x.strokeRect(b.x - W2 / 2, b.z - D2 / 2, W2, D2);
    }
    if (W.farm) { const f = W.farm.fRect; x.fillStyle = '#7a5a30'; x.fillRect(f.minX + 1.5, f.minZ + 1.5, f.maxX - f.minX - 3, f.maxZ - f.minZ - 3); }
    x.fillStyle = '#5a4a3a'; x.beginPath(); x.arc(W.pois.camp.x, W.pois.camp.z, 15, 0, 7); x.fill();
    x.fillStyle = '#6a6a5a'; x.fillRect(W.pois.grave.x - 12, W.pois.grave.z - 12, 24, 24);
    x.fillStyle = '#222'; x.beginPath(); x.arc(W.pois.mine.x, W.pois.mine.z, 4, 0, 7); x.fill();
    this.mapImg = c;
  }
  drawMinimap() {
    const G = this.game, P = G.player, ctx = this.mini, c = this.els.mini;
    if (!this.mapImg) this.buildMapImage();
    const S = c.width, R = 48, k = S / (R * 2);
    ctx.save(); ctx.clearRect(0, 0, S, S);
    ctx.beginPath(); ctx.arc(S / 2, S / 2, S / 2 - 2, 0, 7); ctx.clip();
    ctx.fillStyle = '#20301a'; ctx.fillRect(0, 0, S, S);
    ctx.translate(S / 2, S / 2); ctx.rotate(P.yaw); ctx.scale(k, k); ctx.translate(-P.pos.x, -P.pos.z);
    ctx.drawImage(this.mapImg, -200, -200);
    for (const n of G.npcs) { ctx.fillStyle = n.marker && n.markerState ? '#ffd23a' : '#f0f0f0'; ctx.beginPath(); ctx.arc(n.pos.x, n.pos.z, n.marker && n.markerState ? 1.6 : 0.9, 0, 7); ctx.fill(); }
    for (const e of G.enemies) { if (e.dead || Math.abs(e.pos.x - P.pos.x) > R * 1.5 || Math.abs(e.pos.z - P.pos.z) > R * 1.5) continue; ctx.fillStyle = e.def.boss ? '#ff8a1a' : '#e02a2a'; ctx.beginPath(); ctx.arc(e.pos.x, e.pos.z, e.def.boss ? 2 : 1.1, 0, 7); ctx.fill(); }
    ctx.restore();
    ctx.save(); ctx.translate(S / 2, S / 2);
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(0, -7); ctx.lineTo(5, 6); ctx.lineTo(0, 3); ctx.lineTo(-5, 6); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.restore();
    ctx.save(); ctx.translate(S / 2, S / 2); ctx.rotate(P.yaw); ctx.fillStyle = '#ffd23a'; ctx.font = 'bold 13px Georgia'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('N', 0, -(S / 2 - 12)); ctx.restore();
  }

  // ---------- panels ----------
  open(name, data) {
    this.panel = name; this.data = data; this.modalOpen = true;
    $('modal').classList.remove('hidden');
    $('panel').className = `panel-${name}`;
    if (document.pointerLockElement) document.exitPointerLock();
    this.game.input.attack = false;
    this.refresh();
    this.game.audio.click();
  }
  close() {
    if (!this.modalOpen) return;
    if (this.panel === 'dialog' && this.data?.npc) this.data.npc.talking = false;
    this.panel = null; this.modalOpen = false; $('modal').classList.add('hidden');
    this.game.save(true);
  }
  toggle(name) { if (this.panel === name) this.close(); else if (this.game.running) this.open(name); }
  back() { if (this.modalOpen) this.close(); else if (this.game.running) this.open('menu'); }
  set(title, html) { $('panelTitle').innerHTML = title; const b = $('panelBody'); const st = b.scrollTop; b.innerHTML = html; b.scrollTop = st; }
  refresh() {
    const fn = this['p_' + this.panel]; if (fn) fn.call(this, this.data);
  }
  bind(sel, fn) { $('panelBody').querySelectorAll(sel).forEach((el) => el.addEventListener('click', (e) => { e.stopPropagation(); fn(el.dataset, el); })); }

  itemDetail(id, extra = '') {
    const it = ITEMS[id]; const P = this.game.player; let stats = '';
    if (it.dmg) stats += `<span>Damage ${it.dmg[0]}–${it.dmg[1]}</span>`;
    if (it.rate) stats += `<span>Speed ${(1 / it.rate).toFixed(1)}/s</span>`;
    if (it.mana && it.kind === 'weapon') stats += `<span>Mana ${it.mana}</span>`;
    if (it.heal) stats += `<span>Heals ${it.heal}</span>`;
    if (it.def) stats += `<span>Armor ${it.def}</span>`;
    if (it.kind === 'armor' && it.mana) stats += `<span>+${it.mana} Mana</span>`;
    if (it.skill && it.kind === 'weapon') stats += `<span style="color:${SKILLS[it.skill].color}">${SKILLS[it.skill].name}</span>`;
    return `<div class="detail"><div class="big">${it.icon}</div><div><h3>${esc(it.name)}</h3><p>${esc(it.desc || '')}</p><div class="stats">${stats}</div>${extra}</div></div>`;
  }

  p_inventory() {
    const P = this.game.player; const sel = this.invSel;
    const grid = P.inv.map((s, i) => `<button class="islot ${sel === i ? 'on' : ''} ${P.armor === s.id ? 'eq' : ''}" data-i="${i}"><span>${ITEMS[s.id].icon}</span>${s.qty > 1 ? `<b>${s.qty}</b>` : ''}${P.hotbar.includes(s.id) ? '<i>' + (P.hotbar.indexOf(s.id) + 1) + '</i>' : ''}</button>`).join('');
    let detail = '<p class="hint">Tap an item to see what it does.</p>';
    const s = P.inv[sel];
    if (s) {
      const it = ITEMS[s.id]; const btns = [];
      if (it.kind === 'armor') btns.push(P.armor === s.id ? '<button disabled>Equipped</button>' : `<button data-act="equip">Wear</button>`);
      if (it.kind === 'consumable' || (it.kind === 'crop' && it.heal)) btns.push(`<button data-act="use">Use</button>`);
      if (['weapon', 'tool', 'seed', 'consumable'].includes(it.kind) || (it.kind === 'crop' && it.heal)) {
        btns.push(`<div class="assign">Hotbar: ${[0, 1, 2, 3, 4, 5].map((k) => `<button data-slot="${k}" class="${P.hotbar[k] === s.id ? 'on' : ''}">${k + 1}</button>`).join('')}</div>`);
      }
      detail = this.itemDetail(s.id, `<div class="acts">${btns.join('')}</div>`);
    }
    this.set('🎒 Inventory', `<div class="invtop"><span>🪙 ${P.gold} gold</span><span>🛡️ Armor: ${esc(ITEMS[P.armor].name)} (${P.def})</span></div><div class="igrid">${grid}</div>${detail}`);
    this.bind('.islot', (d) => { this.invSel = +d.i; this.refresh(); });
    this.bind('[data-act=equip]', () => { P.equipArmor(P.inv[sel].id); this.refresh(); });
    this.bind('[data-act=use]', () => { P.consume(P.inv[sel].id); if (!P.inv[sel]) this.invSel = null; this.refresh(); });
    this.bind('[data-slot]', (d) => {
      const id = P.inv[sel].id, k = +d.slot;
      const prev = P.hotbar.indexOf(id); if (prev >= 0) P.hotbar[prev] = null;
      if (prev !== k) P.hotbar[k] = id;
      P.vm.set(P.held()); this.dirty = true; this.refresh();
    });
  }
  p_skills() {
    const P = this.game.player; const c = P.cls;
    const rows = Object.entries(SKILLS).map(([k, s]) => {
      const sk = P.skills[k]; const need = xpToNext(sk.lvl);
      return `<div class="skill"><div class="sico" style="background:${s.color}">${s.icon}</div><div class="sinfo"><div><b>${s.name}</b> <span class="lvl">${sk.lvl}</span></div><div class="xpbar"><div style="width:${(sk.xp / need) * 100}%;background:${s.color}"></div></div><small>${Math.floor(sk.xp)} / ${need} XP · ${s.desc}</small></div></div>`;
    }).join('');
    const G = CLASS_GUIDE;
    const lines = COMBAT_SKILLS.map((k) => `<div><b style="color:${SKILLS[k].color}">${SKILLS[k].name}:</b> ${G.LINES[k].map(([l, n]) => `${n}<sup>${l}</sup>`).join(' → ')}</div>`).join('');
    const hy = Object.entries(G.HYBRIDS).map(([k, v]) => `<span class="chip">${k.split('+').map((s) => SKILLS[s].name.split(' ')[0]).join(' + ')} = ${v[0]} / ${v[1]}</span>`).join('');
    this.set('📜 Character', `
      <div class="classcard"><div class="cname">${esc(c.title)}</div><div class="csub">Level ${Math.max(1, c.level)} · ${c.line === 'farming' ? 'Humble beginnings' : c.line.includes('+') ? 'Hybrid class' : SKILLS[c.line].name + ' specialist'}</div></div>
      <div class="statrow"><div><b>${P.stats.str}</b>Strength</div><div><b>${P.stats.dex}</b>Dexterity</div><div><b>${P.stats.int}</b>Intelligence</div><div><b>${P.maxHp}</b>Health</div><div><b>${P.maxMp}</b>Mana</div><div><b>${P.def}</b>Armor</div></div>
      ${rows}
      <details class="guide"><summary>How classes work</summary><p>There are no class choices in Hollowmere - you become what you do. Every hit you land trains the skill of the weapon you used. Your class is named after your strongest combat skill, and if two skills are close you become a hybrid.</p>${lines}<div class="chips">${hy}</div></details>`);
  }
  p_quests() {
    const G = this.game;
    const list = Object.entries(G.quests).filter(([, q]) => q.state !== 'available');
    const html = list.length ? list.map(([id, q]) => {
      const d = QUESTS[id]; const giver = G.npcs.find((n) => n.role === d.giver);
      const prog = d.type === 'kill' ? `${Math.min(q.progress, d.count)}/${d.count}` : `${Math.min(G.player.count(d.item), d.count)}/${d.count}`;
      const st = q.state === 'done' ? '<span class="done">Complete</span>' : G.questReady(id) ? '<span class="ready">Return to ' + esc(giver?.name || '') + '</span>' : `<span>${prog}</span>`;
      return `<div class="quest ${q.state}"><h3>${esc(d.title)} ${st}</h3><p>${esc(d.desc)}</p><small>From ${esc(giver ? giver.name + ' the ' + ROLES[d.giver].title : '')} · Reward: ${d.reward.gold} gold${d.reward.items.map(([i]) => ', ' + ITEMS[i].name).join('')}</small></div>`;
    }).join('') : '<p class="hint">No quests yet. Look for villagers with a <b style="color:#ffd23a">!</b> over their heads, or check the Quest Board in the plaza.</p>';
    this.set('📖 Quest Journal', html);
  }
  p_board() {
    const G = this.game;
    const html = Object.entries(QUESTS).map(([id, d]) => {
      const q = G.quests[id]; const giver = G.npcs.find((n) => n.role === d.giver);
      const st = q.state === 'done' ? '✅ Completed' : q.state === 'available' ? `❗ See ${esc(giver?.name || '')} the ${ROLES[d.giver].title}` : '📌 In progress';
      return `<div class="quest ${q.state}"><h3>${esc(d.title)}</h3><p>${esc(d.desc)}</p><small>${st} · ${d.reward.gold} gold</small></div>`;
    }).join('');
    this.set('📋 Quest Board', `<p class="hint">Notices pinned by the good folk of Hollowmere.</p>${html}`);
  }
  p_map() {
    if (!this.mapImg) this.buildMapImage();
    const W = this.game.world, P = this.game.player;
    this.set('🗺️ Map of Hollowmere', `<div class="bigmap"><canvas id="bigmap" width="800" height="800"></canvas></div><p class="hint">More regions will open beyond the collapsed mine in future updates.</p>`);
    const c = $('bigmap'), x = c.getContext('2d');
    x.imageSmoothingEnabled = true; x.drawImage(this.mapImg, 0, 0, 800, 800);
    x.save(); x.scale(2, 2); x.translate(200, 200);
    x.font = 'bold 7px Georgia'; x.textAlign = 'center';
    for (const l of W.mapLabels) { x.lineWidth = 2.5; x.strokeStyle = 'rgba(0,0,0,0.8)'; x.fillStyle = l.danger ? '#ff8a6a' : '#fff4d0'; x.strokeText(l.text, l.x, l.z); x.fillText(l.text, l.x, l.z); }
    for (const n of this.game.npcs) if (n.markerState) { x.fillStyle = '#ffd23a'; x.font = 'bold 9px Georgia'; x.strokeText('!', n.pos.x, n.pos.z - 2); x.fillText(n.markerState, n.pos.x, n.pos.z - 2); }
    x.translate(P.pos.x, P.pos.z); x.rotate(-P.yaw);
    x.fillStyle = '#fff'; x.strokeStyle = '#000'; x.lineWidth = 1; x.beginPath(); x.moveTo(0, -5); x.lineTo(3.5, 4); x.lineTo(0, 2); x.lineTo(-3.5, 4); x.closePath(); x.fill(); x.stroke();
    x.restore();
  }
  p_dialog(d) {
    const G = this.game, n = d.npc; const role = ROLES[n.role];
    const opts = G.dialogOptions(n);
    this.set(`<span class="npcname">${esc(n.name)}</span> <small>${esc(role.title)}</small>`,
      `<div class="dialog"><p class="say">“${esc(d.text)}”</p><div class="opts">${opts.map((o, i) => `<button data-o="${i}" class="${o.cls || ''}">${o.label}</button>`).join('')}</div></div>`);
    this.bind('[data-o]', (x) => opts[+x.o].fn());
  }
  p_shop(d) {
    const G = this.game, P = G.player, shop = SHOPS[d.shop];
    const tab = this.shopTab || 'buy';
    let list;
    if (tab === 'buy') {
      list = shop.stock.map((id) => { const it = ITEMS[id]; const own = P.count(id); return `<div class="srow"><span class="ico">${it.icon}</span><div class="sn"><b>${esc(it.name)}</b><small>${esc(it.desc)}${own ? ` · You have ${own}` : ''}</small></div><button data-buy="${id}" ${P.gold < it.price ? 'disabled' : ''}>🪙 ${it.price}</button></div>`; }).join('');
    } else {
      const rows = P.inv.map((s, i) => ({ s, i })).filter(({ s }) => !(P.armor === s.id && P.count(s.id) <= 1) && s.id !== 'farm_clothes');
      list = rows.length ? rows.map(({ s, i }) => { const it = ITEMS[s.id]; return `<div class="srow"><span class="ico">${it.icon}</span><div class="sn"><b>${esc(it.name)}${s.qty > 1 ? ' ×' + s.qty : ''}</b><small>${esc(it.desc)}</small></div><button data-sell="${s.id}">+🪙 ${sellPrice(s.id)}</button>${s.qty > 1 ? `<button data-sellall="${s.id}">All</button>` : ''}</div>`; }).join('') : '<p class="hint">Nothing to sell.</p>';
    }
    this.set(`🛒 ${esc(shop.name)}`, `<div class="tabs"><button data-tab="buy" class="${tab === 'buy' ? 'on' : ''}">Buy</button><button data-tab="sell" class="${tab === 'sell' ? 'on' : ''}">Sell</button><span class="gold">🪙 ${P.gold}</span></div><div class="slist">${list}</div><div class="acts"><button data-back>← Back to ${esc(d.npc.name)}</button></div>`);
    this.bind('[data-tab]', (x) => { this.shopTab = x.tab; this.refresh(); });
    this.bind('[data-buy]', (x) => { const it = ITEMS[x.buy]; if (P.gold >= it.price) { P.gold -= it.price; P.addItem(x.buy, 1); G.audio.coin(); this.toast(`Bought ${it.name}`); this.dirty = true; this.refresh(); } });
    const sell = (id, n) => { for (let k = 0; k < n; k++) { P.gold += sellPrice(id); P.removeItem(id, 1); } G.audio.coin(); this.dirty = true; this.refresh(); };
    this.bind('[data-sell]', (x) => sell(x.sell, 1));
    this.bind('[data-sellall]', (x) => sell(x.sellall, P.count(x.sellall)));
    this.bind('[data-back]', () => G.talkTo(d.npc));
  }
  p_menu() {
    const G = this.game;
    this.set('⚙️ Menu', `<div class="menu">
      <button data-m="resume" class="primary">Resume</button>
      <button data-m="save">💾 Save Game</button>
      <button data-m="settings">🎛️ Settings</button>
      <button data-m="help">❓ How to Play</button>
      <button data-m="update">⬆️ Check for Updates</button>
      <button data-m="title">🏠 Save & Quit to Title</button>
      <p class="hint">Hollowmere v${esc(G.version)} · World seed ${G.world.seed}</p></div>`);
    this.bind('[data-m]', (x) => {
      if (x.m === 'resume') this.close();
      if (x.m === 'save') { G.save(); this.toast('Game saved'); }
      if (x.m === 'settings') this.open('settings');
      if (x.m === 'help') this.open('help');
      if (x.m === 'update') G.checkUpdate(true);
      if (x.m === 'title') { G.save(); location.reload(); }
    });
  }
  p_settings() {
    const s = this.game.settings;
    this.set('🎛️ Settings', `<div class="settings">
      <label>Graphics quality <select id="sQ"><option value="low">Low (fastest)</option><option value="med">Medium</option><option value="high">High</option></select></label>
      <label>Look sensitivity <input type="range" id="sS" min="0.3" max="2.5" step="0.1" value="${s.sens}"></label>
      <label>Sound volume <input type="range" id="sV" min="0" max="1" step="0.05" value="${s.vol}"></label>
      <label>Music volume <input type="range" id="sM" min="0" max="1" step="0.05" value="${s.music}"></label>
      <label>Field of view <input type="range" id="sF" min="60" max="95" step="1" value="${s.fov}"></label>
      <p class="hint">Graphics quality applies after restarting the game.</p>
      <div class="acts"><button data-back>← Back</button></div></div>`);
    $('sQ').value = s.quality;
    const G = this.game;
    $('sQ').onchange = (e) => { s.quality = e.target.value; G.saveSettings(); this.toast('Restart to apply graphics quality'); };
    $('sS').oninput = (e) => { s.sens = +e.target.value; G.applySettings(); };
    $('sV').oninput = (e) => { s.vol = +e.target.value; G.applySettings(); };
    $('sM').oninput = (e) => { s.music = +e.target.value; G.applySettings(); };
    $('sF').oninput = (e) => { s.fov = +e.target.value; G.applySettings(); };
    this.bind('[data-back]', () => this.open(this.game.running ? 'menu' : 'menu'));
  }
  p_help() {
    this.set('❓ How to Play', `<div class="help">
      <p>You're a farmer in the village of <b>Hollowmere</b>. There are no classes to pick: <b>you become what you do</b>. Swing swords and you'll grow into a Fighter. Loose arrows and you'll become a Ranger. Cast spells and the world will call you Mage. Mix two and you become a hybrid like a Paladin or Spellblade.</p>
      <h3>Controls</h3>
      <table><tr><th></th><th>Touch</th><th>Keyboard / Mouse</th></tr>
      <tr><td>Move</td><td>Left thumb joystick (push fully to run)</td><td>WASD · Shift to run</td></tr>
      <tr><td>Look</td><td>Drag the right side of the screen</td><td>Mouse (click to lock)</td></tr>
      <tr><td>Attack / Use</td><td>⚔️ button (drag it to aim)</td><td>Left click</td></tr>
      <tr><td>Talk / Interact</td><td>✋ button</td><td>E</td></tr>
      <tr><td>Jump</td><td>⤒ button</td><td>Space</td></tr>
      <tr><td>Items</td><td>Tap hotbar</td><td>1–6 / mouse wheel</td></tr>
      <tr><td>Potions</td><td>❤ / 💧</td><td>H / G</td></tr>
      <tr><td>Menus</td><td>Top-right buttons</td><td>I, K, J, M, Esc</td></tr></table>
      <h3>Getting started</h3>
      <ol><li>Talk to the old farmer by your field.</li><li>Select the hoe and use it on the field to till the soil.</li><li>Select wheat seeds and plant them on tilled soil. Harvest ripe crops with ✋.</li><li>Sell crops at the General Store, buy weapons, and venture beyond the fence.</li><li>Sleep in your bed to save and pass the night.</li></ol></div>`);
  }
}
const _v = new THREE.Vector3();
