import { VERSION } from './version.js';

export const REPO = 'z1fire/hollowmere';
export const APK_URL = `https://github.com/${REPO}/releases/latest/download/Hollowmere.apk`;
export const isAndroid = () => !!window.HollowmereAndroid;

export function getVersion() {
  try { return window.HollowmereAndroid?.getVersionName?.() || VERSION; } catch (e) { return VERSION; }
}
export function openExternal(url) {
  if (window.HollowmereAndroid?.openUrl) window.HollowmereAndroid.openUrl(url);
  else window.open(url, '_blank', 'noopener');
}
const cmp = (a, b) => {
  const pa = a.split(/[.-]/).map((n) => parseInt(n, 10) || 0), pb = b.split(/[.-]/).map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) { const d = (pa[i] || 0) - (pb[i] || 0); if (d) return d; }
  return 0;
};

// Asks GitHub for the newest release. In the Android app, offers the new APK.
// (The web version on GitHub Pages always serves the latest build, so it never needs to update.)
export async function checkForUpdate(current) {
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' }, cache: 'no-store' });
    if (!r.ok) return { available: false, error: r.status !== 404 };
    const j = await r.json();
    const latest = String(j.tag_name || '').replace(/^v/, '');
    if (!latest || !isAndroid() || cmp(latest, current) <= 0) return { available: false, version: latest };
    const apk = (j.assets || []).find((a) => a.name.endsWith('.apk'));
    const url = apk ? apk.browser_download_url : j.html_url;
    return { available: true, version: latest, notes: j.body, open: () => openExternal(url) };
  } catch (e) {
    return { available: false, error: true };
  }
}
