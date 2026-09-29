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
- **High-quality stylized 3D** — fully animated characters and monsters, hand-crafted models for trees, props, furniture and crops, photo-scanned PBR materials, image-based sky lighting, bloom and colour grading, with automatic level-of-detail so it stays smooth on phones (Low / Medium / High graphics settings).

## 🗺️ Roadmap
The current release covers the first region: Hollowmere village and its surrounding wilds. The **collapsed mine** and the **sealed crypt** are the entrances to future regions.

## 🎨 Art credits
All 3D models and textures are CC0 (public domain) — thank you to their creators:
- **[KayKit](https://kaylousberg.com)** by Kay Lousberg — Adventurers & Skeletons character packs, Dungeon Remastered, Furniture Bits, Halloween Bits
- **[Quaternius](https://quaternius.com)** — Ultimate Nature, Crops, Medieval Village, Modular Medieval Buildings, Survival, RPG Items, Animals, Ultimate Monsters
- **[Poly Haven](https://polyhaven.com)** — PBR textures

See `web/assets/CREDITS.txt`. The optimized assets are produced by `tools/build-assets.mjs` (`cd tools && npm install && npm run assets`).

## 🛠️ Project layout

Hollowmere is built with **[Godot 4.7](https://godotengine.org)** (GDScript, Mobile renderer on Android, Compatibility renderer on the web).

```
game/                    Godot project (open game/project.godot in the Godot editor)
  scripts/world.gd       terrain, collision, sky & day/night, vegetation
  scripts/village.gd     procedural village + furnished, enterable buildings
  scripts/wilds.gd       goblin camp, graveyard, mine, pond, chests, spawns
  scripts/player.gd      first-person controller, skills & classes, inventory
  scripts/viewmodel.gd   held weapon in first person
  scripts/actor.gd       animated characters (shared KayKit rig)
  scripts/npc.gd, enemy.gd, combat.gd, farm.gd, game.gd, ui.gd, input_ctl.gd, audio.gd
  scripts/data.gd        items, skills, classes, quests, enemies, shops
  assets/                models (.glb), PBR textures, fonts
tools/                   asset pipeline (downloads CC0 sources, optimizes them into game/assets)
.github/workflows/       release.yml -> signed APK + GitHub Release, pages.yml -> web build
```

Run it: open `game/project.godot` in Godot 4.7 and press Play (F5).

## 🚀 Releasing an update

```
./release.sh 0.2.0      # or: git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions exports a signed APK with Godot and publishes it as the latest release. Installed apps will see the update the next time they open.

The signing key lives only in the repository's Actions secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and in a local backup. **Keep the backup safe** — without the same key, Android won't install updates over the existing app.
