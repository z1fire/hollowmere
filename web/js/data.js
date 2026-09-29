// ---------------- ITEMS ----------------
// kind: weapon (skill: melee|ranged|nature|combat), tool, seed, crop, consumable, armor, material, quest
export const ITEMS = {
  // tools / starter
  hoe:          { name: 'Rusty Hoe', kind: 'tool', icon: '⛏️', vm: 'hoe', skill: 'melee', dmg: [2, 4], rate: 0.7, range: 2.2, price: 5, desc: 'Tills soil on your farm. Can whack things in a pinch.' },
  pitchfork:    { name: 'Pitchfork', kind: 'weapon', skill: 'melee', icon: '🔱', vm: 'pitchfork', dmg: [4, 7], rate: 0.8, range: 2.6, price: 8, desc: 'A farmer\'s best friend. Long reach.' },
  // melee
  rusty_sword:  { name: 'Rusty Sword', kind: 'weapon', skill: 'melee', icon: '🗡️', vm: 'sword', dmg: [6, 10], rate: 0.6, range: 2.2, price: 30, desc: 'Seen better days, still sharp at the tip.' },
  iron_sword:   { name: 'Iron Sword', kind: 'weapon', skill: 'melee', icon: '⚔️', vm: 'sword', dmg: [10, 15], rate: 0.6, range: 2.3, price: 110, tint: '#cfd6dd', desc: 'Well-balanced blade forged in Hollowmere.' },
  war_axe:      { name: 'War Axe', kind: 'weapon', skill: 'melee', icon: '🪓', vm: 'axe', dmg: [16, 25], rate: 0.95, range: 2.3, price: 220, desc: 'Heavy, slow, devastating.' },
  knight_blade: { name: 'Knight\'s Blade', kind: 'weapon', skill: 'melee', icon: '⚔️', vm: 'sword', dmg: [20, 28], rate: 0.55, range: 2.4, price: 400, tint: '#ffe08a', desc: 'An heirloom of the old guard. Gleams gold.' },
  // ranged
  short_bow:    { name: 'Short Bow', kind: 'weapon', skill: 'ranged', icon: '🏹', vm: 'bow', dmg: [5, 9], rate: 0.8, speed: 38, price: 40, desc: 'Light hunting bow. Arrows are free - fletched by you.' },
  hunting_bow:  { name: 'Hunting Bow', kind: 'weapon', skill: 'ranged', icon: '🏹', vm: 'bow', dmg: [9, 14], rate: 0.8, speed: 44, price: 120, tint: '#8a5a2b', desc: 'Sturdy yew bow favored by trappers.' },
  longbow:      { name: 'Longbow', kind: 'weapon', skill: 'ranged', icon: '🏹', vm: 'bow', dmg: [15, 23], rate: 1.0, speed: 55, price: 260, tint: '#3d2614', desc: 'Tall bow with tremendous range.' },
  // nature magic
  tome_thorns:  { name: 'Tome of Thorns', kind: 'weapon', skill: 'nature', icon: '🌿', vm: 'tome', school: 'nature', dmg: [6, 10], rate: 0.65, mana: 4, speed: 26, price: 55, desc: 'Nature Magic: hurl a bolt of razor thorns.' },
  tome_heal:    { name: 'Tome of Mending', kind: 'weapon', skill: 'nature', icon: '💚', vm: 'tome', school: 'heal', heal: 30, rate: 1.2, mana: 10, price: 140, desc: 'Nature Magic: restore your health.' },
  // combat magic
  tome_sparks:  { name: 'Tome of Sparks', kind: 'weapon', skill: 'combat', icon: '⚡', vm: 'tome', school: 'spark', dmg: [7, 11], rate: 0.5, mana: 4, speed: 34, price: 55, desc: 'Combat Magic: crackling bolts of lightning.' },
  tome_fireball:{ name: 'Tome of Fireball', kind: 'weapon', skill: 'combat', icon: '🔥', vm: 'tome', school: 'fire', dmg: [18, 28], rate: 1.2, mana: 12, speed: 24, splash: 3.2, price: 260, desc: 'Combat Magic: an exploding ball of flame.' },
  // armor
  farm_clothes: { name: 'Farm Clothes', kind: 'armor', icon: '👕', def: 1, price: 2, desc: 'Patched and comfortable.' },
  leather:      { name: 'Leather Jerkin', kind: 'armor', icon: '🦺', def: 4, price: 50, desc: 'Boiled leather. Stops a wolf bite.' },
  chainmail:    { name: 'Chain Shirt', kind: 'armor', icon: '🛡️', def: 8, price: 170, desc: 'Riveted rings of iron.' },
  plate:        { name: 'Plate Armor', kind: 'armor', icon: '🛡️', def: 14, price: 420, desc: 'Full plate. You clank when you walk.' },
  mage_robe:    { name: 'Mystic Robe', kind: 'armor', icon: '🥋', def: 3, mana: 30, price: 150, desc: 'Woven with runes. +30 max mana.' },
  // seeds
  wheat_seed:   { name: 'Wheat Seeds', kind: 'seed', icon: '🌾', crop: 'wheat', price: 2, desc: 'Plant on tilled soil. Grows fast.' },
  carrot_seed:  { name: 'Carrot Seeds', kind: 'seed', icon: '🥕', crop: 'carrot', price: 5, desc: 'Plant on tilled soil.' },
  pumpkin_seed: { name: 'Pumpkin Seeds', kind: 'seed', icon: '🎃', crop: 'pumpkin', price: 12, desc: 'Slow growing, sells well.' },
  // crops
  wheat:        { name: 'Wheat', kind: 'crop', icon: '🌾', price: 7, desc: 'Golden grain.' },
  carrot:       { name: 'Carrot', kind: 'crop', icon: '🥕', price: 14, desc: 'Crunchy. Restores a little health.', heal: 8 },
  pumpkin:      { name: 'Pumpkin', kind: 'crop', icon: '🎃', price: 40, desc: 'A prize-worthy gourd.' },
  // consumables
  hp_potion:    { name: 'Health Potion', kind: 'consumable', icon: '🧪', heal: 50, price: 18, desc: 'Restores 50 health.' },
  mp_potion:    { name: 'Mana Potion', kind: 'consumable', icon: '🔮', mana: 50, price: 18, desc: 'Restores 50 mana.' },
  bread:        { name: 'Bread', kind: 'consumable', icon: '🍞', heal: 20, price: 4, desc: 'Fresh from the tavern oven.' },
  stew:         { name: 'Hearty Stew', kind: 'consumable', icon: '🍲', heal: 45, mana: 20, price: 12, desc: 'Greta\'s famous stew.' },
  // materials / loot
  wolf_pelt:    { name: 'Wolf Pelt', kind: 'material', icon: '🐺', price: 8, desc: 'Thick grey fur.' },
  goblin_ear:   { name: 'Goblin Ear', kind: 'material', icon: '👂', price: 6, desc: 'Gross. Proof of a goblin slain.' },
  bone_dust:    { name: 'Bone Dust', kind: 'material', icon: '🦴', price: 10, desc: 'Mages pay well for this.' },
  moonpetal:    { name: 'Moonpetal', kind: 'material', icon: '🌸', price: 9, desc: 'A softly glowing herb.' },
  old_coin:     { name: 'Ancient Coin', kind: 'material', icon: '🪙', price: 35, desc: 'Minted before Hollowmere was founded.' },
};

export const CROPS = {
  wheat:   { grow: 90,  color: '#e2c35a', yield: [1, 2], xp: 6 },
  carrot:  { grow: 150, color: '#f08a24', yield: [1, 2], xp: 10 },
  pumpkin: { grow: 300, color: '#e8781c', yield: [1, 1], xp: 20 },
};

// ---------------- SKILLS & CLASSES ----------------
export const SKILLS = {
  melee:   { name: 'Melee',        color: '#e05a3a', icon: '⚔️', desc: 'Swords, axes, pitchforks. Raises Strength.' },
  ranged:  { name: 'Ranged',       color: '#5ac05a', icon: '🏹', desc: 'Bows. Raises Dexterity.' },
  nature:  { name: 'Nature Magic', color: '#48c9a0', icon: '🌿', desc: 'Thorns and healing. Raises Intelligence.' },
  combat:  { name: 'Combat Magic', color: '#9a6cff', icon: '🔥', desc: 'Lightning and fire. Raises Intelligence.' },
  farming: { name: 'Farming',      color: '#d9b050', icon: '🌾', desc: 'Tilling, planting, harvesting. Raises Strength a little.' },
};
export const COMBAT_SKILLS = ['melee', 'ranged', 'nature', 'combat'];

export const xpToNext = (lvl) => Math.floor(30 + 22 * Math.pow(lvl + 1, 1.55));

const LINES = {
  melee:  [[2, 'Brawler'], [5, 'Fighter'], [9, 'Warrior'], [14, 'Knight'], [20, 'Champion']],
  ranged: [[2, 'Slinger'], [5, 'Archer'], [9, 'Ranger'], [14, 'Marksman'], [20, 'Sharpshooter']],
  nature: [[2, 'Acolyte'], [5, 'Druid'], [9, 'Shaman'], [14, 'Sage'], [20, 'Archdruid']],
  combat: [[2, 'Apprentice'], [5, 'Mage'], [9, 'Sorcerer'], [14, 'Warlock'], [20, 'Archmage']],
};
const HYBRIDS = {
  'melee+ranged': ['Skirmisher', 'Vanguard'],
  'melee+nature': ['Templar', 'Paladin'],
  'combat+melee': ['Spellblade', 'Battlemage'],
  'nature+ranged': ['Warden', 'Beastmaster'],
  'combat+ranged': ['Arcane Archer', 'Spellbow'],
  'combat+nature': ['Magus', 'Elementalist'],
};
const FARMER = [[0, 'Farmhand'], [3, 'Farmer'], [7, 'Homesteader'], [12, 'Master Farmer']];

export function computeClass(skills) {
  const lv = (s) => skills[s].lvl;
  const sorted = [...COMBAT_SKILLS].sort((a, b) => lv(b) - lv(a));
  const top = sorted[0], L = lv(top), sec = sorted[1];
  if (L < 2 || lv('farming') >= L * 2 + 2) {
    let t = FARMER[0][1]; for (const [n, name] of FARMER) if (lv('farming') >= n) t = name;
    return { title: t, line: 'farming', level: Math.max(lv('farming'), L) };
  }
  if (lv(sec) >= 2 && lv(sec) >= L * 0.75) {
    const key = [top, sec].sort().join('+');
    const names = HYBRIDS[key];
    return { title: L >= 12 ? names[1] : names[0], line: key, level: L };
  }
  let t = LINES[top][0][1]; for (const [n, name] of LINES[top]) if (L >= n) t = name;
  return { title: t, line: top, level: L };
}
export const CLASS_GUIDE = { LINES, HYBRIDS, FARMER };

// ---------------- ENEMIES ----------------
export const ENEMIES = {
  wolf:        { name: 'Grey Wolf',       hp: 32,  dmg: [4, 7],   speed: 5.6, range: 1.7, rate: 1.1, aggro: 17, xp: 14, gold: [1, 4],  drops: [['wolf_pelt', 0.55]], model: 'wolf', group: 'wolf' },
  goblin:      { name: 'Goblin Raider',   hp: 48,  dmg: [6, 9],   speed: 4.1, range: 1.8, rate: 1.2, aggro: 16, xp: 22, gold: [3, 9],  drops: [['goblin_ear', 0.6], ['hp_potion', 0.1], ['bread', 0.15]], model: 'goblin', group: 'goblin' },
  goblin_archer:{ name: 'Goblin Archer',  hp: 38,  dmg: [5, 8],   speed: 3.8, range: 16,  rate: 2.0, aggro: 20, xp: 24, gold: [3, 9],  drops: [['goblin_ear', 0.6], ['short_bow', 0.04]], model: 'goblin', ranged: true, group: 'goblin' },
  goblin_chief:{ name: 'Goblin Warchief', hp: 320, dmg: [13, 19], speed: 4.3, range: 2.3, rate: 1.4, aggro: 18, xp: 180, gold: [60, 90], drops: [['old_coin', 1], ['hp_potion', 1]], model: 'goblin', scale: 1.55, boss: true, group: 'goblin_chief', respawn: 600 },
  skeleton:    { name: 'Restless Skeleton', hp: 58, dmg: [8, 11], speed: 3.3, range: 1.9, rate: 1.3, aggro: 15, xp: 30, gold: [4, 10], drops: [['bone_dust', 0.6], ['old_coin', 0.06]], model: 'skeleton', group: 'skeleton' },
  skeleton_archer: { name: 'Skeleton Archer', hp: 44, dmg: [7, 10], speed: 3.0, range: 18, rate: 2.2, aggro: 20, xp: 32, gold: [4, 10], drops: [['bone_dust', 0.6]], model: 'skeleton', ranged: true, group: 'skeleton' },
};

// ---------------- SHOPS ----------------
export const SHOPS = {
  smith:     { name: 'Smithy', stock: ['rusty_sword', 'iron_sword', 'war_axe', 'leather', 'chainmail', 'plate'] },
  hunter:    { name: 'Hunter\'s Lodge', stock: ['short_bow', 'hunting_bow', 'longbow', 'leather', 'bread'] },
  herbalist: { name: 'Herbalist', stock: ['tome_thorns', 'tome_heal', 'hp_potion', 'mp_potion', 'carrot_seed'] },
  mage:      { name: 'Mage Tower', stock: ['tome_sparks', 'tome_fireball', 'mp_potion', 'mage_robe'] },
  general:   { name: 'General Store', stock: ['wheat_seed', 'carrot_seed', 'pumpkin_seed', 'hp_potion', 'bread', 'hoe', 'pitchfork'] },
  inn:       { name: 'The Tipsy Turnip', stock: ['bread', 'stew'] },
};

// ---------------- QUESTS ----------------
export const QUESTS = {
  harvest: {
    giver: 'farmer', title: 'A Farmer\'s Start',
    desc: 'Till soil on your field with the hoe, plant wheat seeds, and bring in 3 wheat.',
    type: 'collect', item: 'wheat', count: 3, consume: true,
    reward: { gold: 30, items: [['carrot_seed', 4], ['bread', 2]], xp: { farming: 40 } },
    offer: 'Your field\'s gone to weeds since your folks passed. Take the hoe, till a few rows, plant them wheat seeds. Bring me 3 wheat and I\'ll know you\'re serious.',
    thanks: 'Ha! Real farmer\'s hands. Here - carrot seeds, they sell better. And take some bread.',
  },
  wolves: {
    giver: 'hunter', title: 'Wolves at the Fence',
    desc: 'Slay 5 grey wolves in the wilds outside the village.',
    type: 'kill', target: 'wolf', count: 5,
    reward: { gold: 45, items: [['short_bow', 1]], xp: { ranged: 30 } },
    offer: 'The wolves grow bold - they\'ve been circling the fences at night. Thin the pack: five of them. Do it and I\'ll give you a bow of your own.',
    thanks: 'Clean work. Here, a short bow. Keep your elbow up and let the arrow fly.',
  },
  herbs: {
    giver: 'herbalist', title: 'Moonpetal Gathering',
    desc: 'Collect 5 glowing Moonpetal herbs from the wilderness.',
    type: 'collect', item: 'moonpetal', count: 5, consume: true,
    reward: { gold: 30, items: [['tome_heal', 1], ['hp_potion', 2]], xp: { nature: 30 } },
    offer: 'Moonpetals grow in the wild beyond the fence - they glow blue, you can\'t miss them. Bring me five and I\'ll teach you a mending spell.',
    thanks: 'Beautiful specimens! This Tome of Mending is yours. Nature provides for those who respect her.',
  },
  skeletons: {
    giver: 'mage', title: 'The Restless Dead',
    desc: 'Destroy 6 skeletons at the old graveyard.',
    type: 'kill', target: 'skeleton', count: 6,
    reward: { gold: 70, items: [['tome_fireball', 1]], xp: { combat: 40 } },
    offer: 'Something has stirred the old graveyard. The dead walk. Put six of them back to rest, and I shall reward you with true fire.',
    thanks: 'The graves are quieter. As promised - the Tome of Fireball. Try not to burn down the tavern.',
  },
  goblins: {
    giver: 'mayor', title: 'The Goblin Warchief',
    desc: 'Defeat the Goblin Warchief at the goblin camp.',
    type: 'kill', target: 'goblin_chief', count: 1,
    reward: { gold: 200, items: [['knight_blade', 1]], xp: { melee: 60 } },
    offer: 'Goblins have made camp outside our walls, and their Warchief grows bolder by the day. Hollowmere needs a hero. Even a farmer will do.',
    thanks: 'You did it! Hollowmere is in your debt. Take this blade - it belonged to the last knight of this village.',
  },
  pelts: {
    giver: 'smith', title: 'Fur for the Forge',
    desc: 'Bring 4 wolf pelts to the blacksmith.',
    type: 'collect', item: 'wolf_pelt', count: 4, consume: true,
    reward: { gold: 20, items: [['leather', 1]], xp: { melee: 15 } },
    offer: 'Need pelts to line my bellows and gloves. Bring me four wolf pelts and I\'ll fit you with a leather jerkin.',
    thanks: 'Fine pelts! Here, this jerkin should fit you.',
  },
};

// ---------------- NPCS ----------------
export const NAMES = {
  m: ['Aldric', 'Brom', 'Osric', 'Thaddeus', 'Hobb', 'Gareth', 'Edwin', 'Rowan', 'Tobin', 'Cedric', 'Wendel', 'Merrick', 'Jory', 'Finn', 'Barnaby', 'Alaric'],
  f: ['Elara', 'Mirabel', 'Greta', 'Rosalind', 'Maude', 'Isolde', 'Wren', 'Tilda', 'Hazel', 'Brynn', 'Clover', 'Agnes', 'Nell', 'Sable', 'Juniper', 'Linnea'],
};
export const ROLES = {
  mayor:     { title: 'Mayor', building: 'townhall', shop: null, quest: 'goblins', look: { shirt: '#6a2c3a', pants: '#2b2b38', hat: 'tophat', beard: true }, lines: ['Welcome to Hollowmere, friend. We\'re simple folk, but proud.', 'The council meets on the first of every month. Nobody ever comes.', 'If only we still had a knight...'] },
  smith:     { title: 'Blacksmith', building: 'smithy', shop: 'smith', quest: 'pelts', look: { shirt: '#5a4a3a', pants: '#3a2a1a', apron: '#3b2f25', held: 'hammer', beard: true, big: true }, lines: ['Steel don\'t lie. Swing it enough and you\'ll learn what it wants.', 'Mind the forge, it bites.', 'The more you fight up close, the stronger your arm gets. That\'s just how it works.'] },
  innkeeper: { title: 'Innkeeper', building: 'tavern', shop: 'inn', service: 'rest', look: { shirt: '#a0522d', pants: '#4a3525', apron: '#e8e0d0', held: 'mug' }, lines: ['Welcome to the Tipsy Turnip! Mind the step, it\'s crooked.', 'A warm bed is 10 gold. You\'ll wake at dawn, fresh as a daisy.', 'Adventurers used to fill this place. Before the mine collapsed.'] },
  merchant:  { title: 'Merchant', building: 'store', shop: 'general', look: { shirt: '#2f6b4a', pants: '#3a3a2a', hat: 'cap' }, lines: ['Seeds, potions, tools! I\'ve got what you need.', 'I\'ll buy anything you grow. Pumpkins especially!', 'Prices are fair. Mostly.'] },
  herbalist: { title: 'Herbalist', building: 'herbalist', shop: 'herbalist', quest: 'herbs', look: { shirt: '#4a7a3a', pants: '#3a4a2a', hat: 'hood', hood: '#3a5a2a', robe: '#4a6a3a', held: 'staff' }, lines: ['The forest speaks, if you listen.', 'Nature magic grows with use - like any garden.', 'Moonpetals only glow for those who look.'] },
  mage:      { title: 'Court Mage', building: 'magetower', shop: 'mage', quest: 'skeletons', look: { shirt: '#2a2a6a', pants: '#1a1a3a', hat: 'wizard', hatColor: '#2a2a6a', robe: '#2a2a6a', beard: true, beardColor: '#dddddd', held: 'staff' }, lines: ['Magic is merely will, given shape.', 'Cast enough spells and the world will call you Mage. Cast more and they will call you worse.', 'Mind the crystal. It hums when it\'s hungry.'] },
  hunter:    { title: 'Huntress', building: 'hunter', shop: 'hunter', quest: 'wolves', look: { shirt: '#5a6a3a', pants: '#4a3a2a', hat: 'hood', hood: '#4a5a2a', held: 'bow' }, lines: ['Aim a little high. Arrows drop.', 'The wolves come from the north woods.', 'Every arrow you loose makes your eye sharper.'] },
  priest:    { title: 'Priest', building: 'chapel', service: 'heal', look: { shirt: '#e8e4d8', pants: '#bbb4a0', robe: '#e8e4d8', hat: 'none', held: 'book' }, lines: ['May the Light keep you, child.', 'Wounded? Come, let me mend you.', 'The graveyard was hallowed ground, once.'] },
  farmer:    { title: 'Old Farmer', building: 'farm', quest: 'harvest', look: { shirt: '#9c7a4a', pants: '#4a5a7a', hat: 'straw', beard: true, beardColor: '#bbbbbb', held: 'hoe' }, lines: ['Knew your father. Good man. Terrible at cards.', 'Wheat grows quick. Pumpkins take their sweet time.', 'A farmer can be anything, if they put their back into it.'] },
  guard:     { title: 'Gate Guard', building: 'gate', look: { shirt: '#7a2a2a', pants: '#3a3a3a', hat: 'helmet', held: 'spear' }, lines: ['Stay sharp out there. Goblins to one side, graveyard to the other.', 'The mine\'s been caved in for years. Someday someone will dig it out.', 'Move along, citizen.'] },
  villager:  { title: 'Villager', building: null, lines: ['Lovely day, isn\'t it?', 'Have you tried Greta\'s stew? It\'s legendary.', 'My cousin swears he saw a skeleton walking by the graveyard.', 'They say the old mine goes deep. Deeper than anyone\'s dared.', 'You\'re the farmer\'s kid! My, you\'ve grown.', 'The merchant overcharges for potions, but what can you do.', 'I heard the Warchief is twice the size of a man!'] },
  patron:    { title: 'Tavern Patron', building: 'tavern', lines: ['*hic* ...another round!', 'I used to be an adventurer like you.', 'Don\'t go near the mine. Trust me.'] },
};

export const LORE = [
  'Hollowmere was built on silver from the old mine - until the cave-in thirty years ago.',
  'The goblins came down from the eastern hills last spring.',
  'Folks say the graveyard stirred the night the comet passed.',
  'There\'s treasure out in the wilds - chests left by old prospectors.',
  'Train what you use. Swing a sword, you become a fighter. Cast spells, you become a mage. That\'s the Hollowmere way.',
];
