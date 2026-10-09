# OctoBG

All-in-one battleground addon for OctoWoW (1.12 client, 1.18.1 build) with SuperWoW, nampower
and UnitXP_SP3. Works in Warsong Gulch, Arathi Basin, Alterac Valley, Thorn Gorge and the arenas.

`/obg` opens the options. `/obg unlock` shows every panel with sample data so you can drag them
into place; `/obg lock` when done.

## What it shows

**Flag carriers (WSG)** - one row for the enemy carrier, one for ours: class colour, health,
time held, distance, a direction arrow and where they are in plain words ("Horde flag room",
"Horde base - lower level", "midfield (west)", "at heal buff (Horde side)").
The server sends both carriers' map positions to everyone, so the enemy carrier is found anywhere
on the map; up close SuperWoW's position adds the height (roof / lower level).

- left-click: target the carrier
- right-click: target and cast your flag spell (default Mind Vision for priests, Hunter's Mark
  for hunters, set your own in the options)
- Ctrl-click: post the carrier's health and position to /bg
- alerts when the enemy takes our flag and when the EFC drops below 30% health
- key bindings: target EFC, flag spell on EFC, target our FC

**Timers** - one panel of bars:
- spirit resurrection waves for every graveyard OctoBG has seen (spirit guides heal every 30 s)
- while dead in a battleground a big "Resurrection in N" (or "Release - next wave in N")
- Arathi Basin: all five bases with the map icon, 60 s capture timer after an assault
- Alterac Valley: 5 min timers on attacked towers and graveyards
- game start countdown
- Arathi Basin: who reaches 2000 first and when, from the measured resource rate

**INC calls (AB, AV, WSG)** - buttons that post `3 INC STABLES`, `STABLES SAFE`, `HELP STABLES`.
The base you stand nearest is picked automatically (click a base to pin it). **Auto** posts the
number of enemies OctoBG counts near the base. Guard alert: while you stand at a base, enemies
arriving there flash an alert on your screen. Posting those automatically is off and asks first.

**HUD** - a radar around you (rotates with your facing or north-up): enemies as class-coloured
dots, filled when in line of sight, hollow when not, fading at their last known spot; the EFC
with a flag, your target ringed, raid members as faint dots, enemies past range on the edge.

**Enemy list** - nearest enemies with health, distance, line of sight and their important
cooldowns from EnemyCooldowns (trinket, Divine Shield, Ice Block, fears, interrupts...).
Click a name to target.

**Tactical map** - the battleground map with you, your raid, every enemy OctoBG can place, both
flag carriers and the AB/AV objective icons. Enemies wear a bold ring in their faction colour;
"Map darkness" (or `/obg dim 40`) darkens the map so the markers stand out.

**Stealth marks** - when an enemy goes into Stealth, Prowl, Vanish or Shadowmeld while you can
still see them, a purple marker stays where they disappeared, with a circle growing at stealth
speed for where they could be now (20 s). Alert and sound when it happens within 60 yd.
Nothing can show a stealthed enemy beyond that: the server stops sending them to your client.

**Open world** - tick "Outside battlegrounds too" and the HUD, enemy list and tactical map work
in every zone (world PvP).

**View distance** - `/obg maxview` (or the Max view button) raises unit draw distance, horizon and
nameplate range; `/obg maxview off` puts them back. `/obg reach` shows how far away enemies were
actually picked up in each zone - that limit is the server's and no setting can raise it.

## Requirements

- SuperWoW: enemy positions (HUD, map, counted INC calls), GUID targeting
- nampower: enemy detection (the same events Spy uses), spirit guide casts
- UnitXP_SP3: distance and line of sight

Without them the flag rows, AB/AV timers, INC buttons and the map positions of carriers still
work; the HUD needs SuperWoW.

It reads (never writes) Spy's and EnemyCooldowns' enemy tables when they are loaded.

## Commands

`/obg` options, `/obg unlock` / `lock` layout mode, `/obg hud` HUD on/off, `/obg reset` default
positions, `/obg calib` relearn facing, `/obg status`, `/obg probe` (prints what the client
returns - paste it in a bug report), `/obg errors`.

The first time you run in a battleground (or with the HUD on) OctoBG learns which way your
facing turns; the options show "facing calibrated" when it is done (a few seconds of running).
