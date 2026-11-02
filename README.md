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

[Detailed documentation](README-DETAILS.md) · [All releases](https://github.com/FajkPes/Bigfoot-Mod-Kit/releases)
