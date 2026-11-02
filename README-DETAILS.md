# Bigfoot Mod Kit

A host-controlled mod menu and tuning toolkit for **BIGFOOT**. It is intended for experimentation and extra replay value after completing the game, especially in private sessions with players who know that modifications are enabled.

I created the kit to make a large set of runtime values accessible from one organized interface instead of repeatedly editing commands or files by hand.

## What it can do

- Tune Bigfoot health, endurance, senses, attention, and movement
- Adjust hunter health, stamina, fall behavior, and attack pacing
- Change day and night length or move the session clock
- Apply global and per-item loot multipliers
- Control session rules, invulnerability, reveal aids, and weather-related options
- Change local FOV, third-person view, mouse sensitivity, and performance variables
- Run one-shot actions such as healing players, rescanning objects, or affecting Bigfoot
- Inspect players and use per-player health or action controls
- Save and load presets
- Search more than one hundred individual settings
- Apply one row, one section, or all selected settings

The interface is English by default. Czech is available from the language selector in the Mod Manager.

## Important limitations

- Most gameplay changes require you to be the session host.
- View and performance settings are local to your own game.
- Loot multipliers should be applied before creating the session, because existing map loot has already been generated.
- The global loot multiplier stacks with individual item multipliers.
- Preset application is less reliable than applying individual rows. If a preset appears incomplete, load values from the game again and apply the affected section or rows manually.
- Game updates can change Unreal Engine objects and may temporarily break some settings.
- Use the kit only where every affected player agrees. It is not intended to disrupt public games or bypass ownership checks.

## Requirements

- Windows x64
- A legitimate Steam installation of **BIGFOOT**
- Steam running for game launch
- Microsoft **.NET 10 Desktop Runtime x64** for the Mod Manager

The required UE4SS loader and Lua runtime files are bundled. No Node.js, Python, compilation, or separate mod-loader download is required. The launchers check for .NET 10 and offer the [official Microsoft download page](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) if it is missing.

## Installation

1. Download and extract the release ZIP.
2. Close BIGFOOT completely.
3. Run `1-Install.bat`.
4. The installer locates the Steam game folder and adds the loader and mod.
5. Run `3-Play.bat` to start BIGFOOT through Steam together with the Mod Manager.

The installer refuses to overwrite an existing `dwmapi.dll` or `ue4ss` folder. This protects other mod-loader installations. Back up and resolve an existing UE4SS setup manually before installing this kit.

For a non-standard installation, set `BIGFOOT_DIR` to the directory containing `Bigfoot-Win64-Shipping.exe`, then run the installer:

```bat
set BIGFOOT_DIR=D:\Games\Bigfoot\Bigfoot\Binaries\Win64
1-Install.bat
```

## Basic use

1. Create or enter a game session as the host.
2. Wait until the Mod Manager reports **hosting - changes apply**.
3. Select **Load from game** before sending any values.
4. Change a setting and use the **Apply** button on its row.

Each row is independent. Grey means it has never been sent, green means the game currently holds that value, and orange means the value was sent and then edited again. **Reset** returns a row to the value initially read from the game, or to its neutral value when the game does not report one.

## Presets

**Save as...** stores the currently enforced values. **Load** sends a saved preset to the game. **Game defaults** is a built-in reset to the values read when the session was loaded; it is not a preset file.

Because presets affect many values at once, confirm the result after loading one. Individual row and section controls are the safer fallback when a preset does not apply completely.

## Uninstall or disable

1. Close BIGFOOT.
2. Run `Uninstall.bat`.

Nothing is permanently deleted. The script moves the loader, the complete `ue4ss` folder, generated state files, and the installation marker into a timestamped `BigfootModKit-Backup-*` folder beside the game executable. This disables the mod while keeping the files recoverable.

The uninstaller acts only when its installation marker exists. It will not remove an unknown UE4SS setup.

## Troubleshooting

- **game not running**: launch the game with the installed loader.
- **in menu**: enter a session first.
- **client**: most gameplay settings can only be changed by the host.
- **Mod error**: read the message at the bottom of the manager.
- Strange values after a map change: use **Actions → Rescan game objects**.
- Loader log: `<game folder>\Bigfoot\Binaries\Win64\ue4ss\UE4SS.log`.

## Package contents

- `BigfootModManager/` — compiled Windows Mod Manager application
- `GameFiles/` — UE4SS loader and the BigfootTweaks Lua mod
- `1-Install.bat` — guarded installer
- `2-Mod-Manager.bat` — manager-only launcher
- `3-Play.bat` — Steam game and manager launcher
- `Uninstall.bat` — recoverable disable-and-backup tool

The selected latest local revision contains the compiled Mod Manager, but not its C# project source. The custom `BigfootTweaks` Lua bridge source is included.

## Third-party software

The release bundles [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), distributed under its included MIT license. See `THIRD_PARTY_NOTICES.md` and `GameFiles/ue4ss/LICENSE`.

BIGFOOT and its assets are not included. This is an unofficial community project and is not affiliated with CyberLight Game Studio, Steam, Epic Games, or the UE4SS project.

## Credits

Created by FajkPes with assistance from ChatGPT Codex and Claude Code.
