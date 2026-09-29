# ⚜ Hollowmere — A Farmer's Tale

A first-person fantasy RPG for Android (and the browser) inspired by **Dungeon Siege**: there are no classes to pick — **you become what you do**. Start as a humble farmer; swing swords and you'll grow into a Fighter, loose arrows and you'll become a Ranger, cast spells and they'll call you Mage. Train two skills evenly and you become a hybrid like a Paladin or Spellblade.

## 📱 Download

**[⬇️ Download the latest APK](https://github.com/z1fire/hollowmere/releases/latest/download/Hollowmere.apk)** · [All releases](https://github.com/z1fire/hollowmere/releases) · [▶️ Play in your browser](https://z1fire.github.io/hollowmere/)

On Android, open the APK and allow "install unknown apps" for your browser when asked. The app checks for new versions on launch and offers the update; updates install over the old version and **keep your save**.

## ✨ Features

- **Procedurally generated world** — every new game builds a different village layout, terrain, forest, and wilderness from a random seed.
- **The village of Hollowmere** — every building is enterable with a furnished interior: tavern, smithy, general store, herbalist, mage tower, hunter's lodge, chapel, town hall, cottages, and your own farmhouse.
- **Living NPCs** — shopkeepers, quest givers, a gate guard, tavern patrons and wandering villagers with randomized names and looks.
- **Use-based skills** — Melee, Ranged, Nature Magic, Combat Magic, and Farming level up as you use them and raise Strength, Dexterity, and Intelligence.
- **Dynamic classes** — 20+ class titles (Brawler → Fighter → Warrior → Knight → Champion, Archer, Druid, Sorcerer, Paladin, Spellblade, Arcane Archer, Warden...).
- **Farming** — till, plant, and harvest wheat, carrots and pumpkins; sell crops for gold.
- **Combat** — pitchforks, swords, axes, bows, thorn bolts, lightning, fireballs and healing magic; wolves, goblins, skeletons, and the Goblin Warchief boss.
- **Quests, shops, loot chests, herbs, a day/night cycle**, a minimap and a full map, autosave.
- **Touch controls** built for phones and tablets (plus keyboard & mouse on desktop).

## 🗺️ Roadmap
The current release covers the first region: Hollowmere village and its surrounding wilds. The **collapsed mine** and the **sealed crypt** are the entrances to future regions.

## 🛠️ Project layout

```
web/                 The game (plain ES modules + three.js, no build step)
  js/world.js        terrain, collision, sky, vegetation
  js/village.js      procedural village + furnished interiors
  js/wilds.js        goblin camp, graveyard, mine, pond, chests, spawns
  js/player.js       first-person controller, skills, view model
  js/entities.js     NPC + enemy AI
  js/data.js         items, skills, classes, quests, enemies, shops
android/             Minimal native wrapper (WebView serving the bundled game offline)
.github/workflows/   release.yml → signed APK + GitHub Release, pages.yml → web version
```

Run locally: serve the `web/` folder with any static server (e.g. `npx serve web`) and open it in a browser.

## 🚀 Releasing an update

```
./release.sh 0.2.0      # or: git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions builds a signed APK and publishes it as the latest release. Installed apps will see the update the next time they open.

The signing key lives only in the repository's Actions secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and in a local backup. **Keep the backup safe** — without the same key, Android won't install updates over the existing app.
