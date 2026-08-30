BIGFOOT MOD KIT
===============

What this is
------------
A tool for adjusting Bigfoot while it runs: the creature's health and senses,
loot amounts, day and night length, hunter traits, per-player health and more.

The app is in English by default. Czech is available from the language dropdown
in the top right. A Czech copy of this file is in README-cs.txt.

Order of steps
--------------
  1-Install.bat      installs the loader and the mod into the game (once)
  3-Play.bat         launches the game through Steam plus the Mod Manager
  2-Mod-Manager.bat  launches only the Mod Manager, when the game already runs

  Uninstall.bat      disables it and preserves the installation in a dated backup

The Mod Manager requires Microsoft .NET 10 Desktop Runtime x64. The launchers
check for it and offer the official Microsoft download page when it is missing.

How to use it
-------------
1. Start the game and create a session. You have to be the HOST.
2. Wait until the top right reads "hosting - changes apply".
3. Press "Load from game". Nothing can be sent until you do - the app has to
   know the game's real numbers before it is allowed to overwrite any of them.
4. Set a value and send it with the "Apply" button on that row.

Every row is sent on its own
----------------------------
Only what you explicitly sent reaches the game. Any setting you never touched
is one the mod never touches either, so changing one thing can no longer drag
twenty others with it.

The "Apply" button on a row sends that value. The colour of the row's left edge
and of the button's outline tells you where it stands:

  grey     never sent to the game
  green    the game is holding this value
  orange   you sent it, then changed the value again

"Reset" puts the row back to what the game reported when you loaded the values.
For things the game never reports - loot multipliers, weather, performance -
it goes back to the neutral value instead.

"apply section" sends a whole section. "Apply all" and "Reset all" at the bottom
cover everything and both ask first. Top right shows how many values are
currently enforced, and next to it is a search box - past a hundred rows,
scrolling is not a search tool.

Presets
-------
"Save as..." stores everything currently enforced under a name. "Load" sends a
saved preset to the game in one go. The first entry, "Game defaults", is not a
file - it puts everything back the way you found it.

Tabs
----
  Bigfoot     endurance, senses, attention, movement
  Hunters     health, stamina, falling, attack pacing
  Time        day and night length, winding the clock and the day directly
  Loot        pickup multipliers - global plus every item separately
  World       session rules, invulnerability, reveal aids
  View        FOV, third person, mouse sensitivity - yours only
  Performance engine console variables - yours only
  Fixes       workarounds for things the shipped game gets wrong
  Actions     one-shot commands (heal everyone, kill bigfoot, ...)
  Players     everyone in the session, with their health and per-player commands

View and Performance work even when you are not hosting. Nothing in them travels
over the network and none of it is a gameplay advantage.

Multiplayer
-----------
The host sets everything. The other player installs nothing - values reach them
through the game's own network replication. Confirmed for the clock; the rest
works through the same mechanism.

Set pickup multipliers BEFORE creating a session. Loot is generated when the map
loads, so a later change does nothing for items already placed.

The global "Everything at once" multiplier stacks with the per-item one:
everything x2 plus medkits x3 gives medkits x6.

Safety
------
- No game file is modified. Only dwmapi.dll and an ue4ss folder are added.
- The game still starts without the mod, and the Steam ownership check is
  untouched.
- The game ships no anticheat (only Steamworks and the EOS SDK).
- Every write into the game is guarded and clamped to a sane range.
- The mod does not touch the disk when nothing changed, and it keeps game
  objects in a short-lived cache, so it has no reason to slow the game down.

When something does not work
----------------------------
- "game not running": the game has to be started with the mod loaded.
- "in menu": you are not in a session yet.
- "client": the host sets these, not you.
- An error inside the mod appears at the bottom of the app as "Mod error: ...".
- If readings go strange after a map change, use Actions > "Rescan game objects".
- Loader log: <game folder>\Bigfoot\Binaries\Win64\ue4ss\UE4SS.log

Non-standard install
--------------------
If the scripts cannot find the game (another platform than Steam, a second copy),
set BIGFOOT_DIR to the folder holding Bigfoot-Win64-Shipping.exe first:

  set BIGFOOT_DIR=D:\Games\Bigfoot\Bigfoot\Binaries\Win64
  1-Install.bat
