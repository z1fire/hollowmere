// Unified input: keyboard+mouse (pointer lock) and touch (virtual joystick + drag-look + buttons).
export class Input {
  constructor(game) {
    this.game = game;
    this.move = { x: 0, y: 0 }; this.look = { x: 0, y: 0 };
    this.attack = false; this.jump = false; this.sprint = false; this.touch = false;
    this.keys = new Set();
    this.sens = 1;
    this.isTouch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
    document.body.classList.toggle('touch', this.isTouch);
    this.bindKeys(); this.bindMouse(); this.bindTouch();
  }
  get blocked() { return this.game.ui.modalOpen || !this.game.running; }

  bindKeys() {
    addEventListener('keydown', (e) => {
      if (e.target.tagName === 'INPUT') return;
      this.keys.add(e.code);
      const G = this.game;
      if (e.code === 'Escape') { G.ui.back(); return; }
      if (!G.running) return;
      if (e.code === 'KeyI' || e.code === 'KeyB' || e.code === 'Tab') { e.preventDefault(); G.ui.toggle('inventory'); }
      if (e.code === 'KeyK' || e.code === 'KeyC') G.ui.toggle('skills');
      if (e.code === 'KeyJ' || e.code === 'KeyL') G.ui.toggle('quests');
      if (e.code === 'KeyM') G.ui.toggle('map');
      if (this.blocked) return;
      if (e.code === 'KeyE' || e.code === 'KeyF') G.interact();
      if (e.code === 'Space') { this.jump = true; e.preventDefault(); }
      if (e.code === 'KeyH') G.quickPotion('hp');
      if (e.code === 'KeyG') G.quickPotion('mp');
      if (/^Digit[1-6]$/.test(e.code)) G.player.select(+e.code.slice(5) - 1);
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => { this.keys.clear(); this.attack = false; });
  }
  bindMouse() {
    const cv = this.game.renderer.domElement;
    cv.addEventListener('click', () => { if (!this.isTouch && this.game.running && !this.blocked && document.pointerLockElement !== cv) cv.requestPointerLock?.(); });
    addEventListener('mousemove', (e) => {
      if (document.pointerLockElement !== cv || this.blocked) return;
      this.look.x += e.movementX * 0.0022 * this.sens; this.look.y += e.movementY * 0.0022 * this.sens;
    });
    addEventListener('mousedown', (e) => { if (document.pointerLockElement === cv && e.button === 0) this.attack = true; });
    addEventListener('mouseup', (e) => { if (e.button === 0) this.attack = false; });
    addEventListener('wheel', (e) => {
      if (document.pointerLockElement !== cv) return;
      const p = this.game.player; p.select((p.sel + (e.deltaY > 0 ? 1 : 5)) % 6);
    });
  }
  bindTouch() {
    const joy = document.getElementById('joyZone'), knob = document.getElementById('joyKnob'), base = document.getElementById('joyBase');
    const look = document.getElementById('lookZone');
    let joyId = null, jx = 0, jy = 0;
    const R = () => Math.min(70, innerHeight * 0.12);
    joy.addEventListener('pointerdown', (e) => {
      if (joyId !== null || this.blocked) return;
      e.preventDefault(); joyId = e.pointerId; joy.setPointerCapture(e.pointerId);
      jx = e.clientX; jy = e.clientY; this.touch = true;
      base.style.left = `${jx}px`; base.style.top = `${jy}px`; base.classList.add('on');
      knob.style.transform = 'translate(-50%,-50%)';
    });
    joy.addEventListener('pointermove', (e) => {
      if (e.pointerId !== joyId) return;
      let dx = e.clientX - jx, dy = e.clientY - jy; const r = R(), l = Math.hypot(dx, dy);
      if (l > r) { dx *= r / l; dy *= r / l; }
      this.move.x = dx / r; this.move.y = -dy / r;
      knob.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px))`;
    });
    const joyEnd = (e) => { if (e.pointerId !== joyId) return; joyId = null; this.move.x = 0; this.move.y = 0; base.classList.remove('on'); };
    joy.addEventListener('pointerup', joyEnd); joy.addEventListener('pointercancel', joyEnd);

    const lookIds = new Map();
    look.addEventListener('pointerdown', (e) => {
      if (this.blocked) return;
      e.preventDefault(); look.setPointerCapture(e.pointerId); lookIds.set(e.pointerId, { x: e.clientX, y: e.clientY }); this.touch = true;
    });
    look.addEventListener('pointermove', (e) => {
      const p = lookIds.get(e.pointerId); if (!p) return;
      const k = 0.0048 * this.sens * (900 / Math.max(600, Math.min(innerWidth, 1400)));
      this.look.x += (e.clientX - p.x) * k; this.look.y += (e.clientY - p.y) * k;
      p.x = e.clientX; p.y = e.clientY;
    });
    const lookEnd = (e) => lookIds.delete(e.pointerId);
    look.addEventListener('pointerup', lookEnd); look.addEventListener('pointercancel', lookEnd);

    // action buttons: attack also lets you look while holding it (drag on the button)
    const hold = (id, on, off) => {
      const el = document.getElementById(id);
      let pid = null, lx = 0, ly = 0;
      el.addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); pid = e.pointerId; el.setPointerCapture(pid); lx = e.clientX; ly = e.clientY; el.classList.add('down'); on(); });
      el.addEventListener('pointermove', (e) => {
        if (e.pointerId !== pid || id !== 'btnAttack') return;
        const k = 0.0048 * this.sens * (900 / Math.max(600, Math.min(innerWidth, 1400)));
        this.look.x += (e.clientX - lx) * k; this.look.y += (e.clientY - ly) * k; lx = e.clientX; ly = e.clientY;
      });
      const end = (e) => { if (e.pointerId !== pid) return; pid = null; el.classList.remove('down'); off && off(); };
      el.addEventListener('pointerup', end); el.addEventListener('pointercancel', end);
    };
    hold('btnAttack', () => { this.attack = true; }, () => { this.attack = false; });
    hold('btnJump', () => { this.jump = true; });
    hold('btnInteract', () => this.game.interact());
    hold('btnHp', () => this.game.quickPotion('hp'));
    hold('btnMp', () => this.game.quickPotion('mp'));
  }
  update() {
    if (this.blocked) { this.move.x = this.move.y = 0; this.attack = this.attack && !this.game.ui.modalOpen; return; }
    if (this.keys.size) this.touch = false;
    if (!this.touch) {
      const k = this.keys; let x = 0, y = 0;
      if (k.has('KeyW') || k.has('ArrowUp')) y += 1; if (k.has('KeyS') || k.has('ArrowDown')) y -= 1;
      if (k.has('KeyD') || k.has('ArrowRight')) x += 1; if (k.has('KeyA') || k.has('ArrowLeft')) x -= 1;
      this.move.x = x; this.move.y = y;
      this.sprint = k.has('ShiftLeft') || k.has('ShiftRight');
    }
  }
}
