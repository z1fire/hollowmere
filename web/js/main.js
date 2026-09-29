import { Game } from './game.js';
import { Audio } from './audio.js';
import { getVersion, isAndroid, openExternal, APK_URL } from './update.js';
import { Assets } from './assets.js';

const $ = (id) => document.getElementById(id);
const isTouch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
let saved = {};
try { saved = JSON.parse(localStorage.getItem('hollowmere_settings') || '{}'); } catch (e) { /* ignore */ }
const settings = Object.assign({ quality: isTouch ? 'med' : 'high', sens: 1, vol: 0.7, music: 0.5, fov: isTouch ? 72 : 75 }, saved);
const audio = new Audio();
const version = getVersion();
addEventListener('pointerdown', () => audio.unlock(), { capture: true });
addEventListener('keydown', () => audio.unlock(), { capture: true });

// ---- title screen ----
$('ver').textContent = `v${version}`;
$('tQuality').value = settings.quality;
$('tQuality').onchange = (e) => { settings.quality = e.target.value; try { localStorage.setItem('hollowmere_settings', JSON.stringify(settings)); } catch (err) { /* ignore */ } };
const save = Game.loadData();
if (save) {
  $('btnContinue').classList.remove('hidden');
  $('saveInfo').textContent = `Day ${save.day} · ${save.player.gold} gold`;
} else $('btnNew').classList.add('primary');
if (!isAndroid()) {
  $('apkLink').classList.remove('hidden');
  $('apkLink').onclick = (e) => { e.preventDefault(); openExternal(APK_URL); };
}

function begin(isNew) {
  if (isNew && save && !confirmNew()) return;
  $('title').classList.add('hidden');
  $('loading').classList.remove('hidden');
  audio.unlock();
  // let the loading screen paint before the heavy world generation
  setTimeout(async () => {
    try {
      if (!Assets.loaded) {
        await Assets.load((p) => { $('loadText').textContent = `Loading models & textures... ${Math.round(p * 100)}%`; }, 8);
        Assets.loaded = true;
      }
      $('loadText').textContent = 'Generating the world...';
      await new Promise((r) => setTimeout(r, 30));
      if (isNew) Game.clearSave();
      const seed = Math.floor(Math.random() * 1e9);
      const game = new Game({ seed, saveData: isNew ? null : save, settings, audio, version, onProgress: (t) => { $('loadText').textContent = t; } });
      $('loading').classList.add('hidden');
      game.start(isNew);
      if (isNew) game.save(true);
    } catch (err) {
      console.error(err);
      $('loadText').textContent = 'Something went wrong: ' + err.message;
    }
  }, 60);
}
let confirmArmed = false;
function confirmNew() {
  if (confirmArmed) return true;
  confirmArmed = true;
  $('btnNew').textContent = 'Tap again to overwrite save';
  setTimeout(() => { confirmArmed = false; $('btnNew').textContent = 'New Game'; }, 3000);
  return false;
}
$('btnNew').onclick = () => begin(true);
$('btnContinue').onclick = () => begin(false);

// Android hardware back button
window.onAndroidBack = () => { if (window.game) window.game.ui.back(); };
window.onAndroidPause = () => { if (window.game) window.game.save(true); };
document.addEventListener('visibilitychange', () => { if (document.hidden && window.game) window.game.save(true); });
// block context menu / long-press selection on mobile
addEventListener('contextmenu', (e) => e.preventDefault());
