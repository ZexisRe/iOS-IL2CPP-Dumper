# iOS IL2CPP Dumper

On-device **`dump.cs`** generator for **Unity IL2CPP** games on **jailbroken / TrollStore** iOS.

**Tags:** `#ios` `#jailbreak` `#trollstore` `#il2cpp` `#unity` `#dumpcs` `#reverseengineering` `#gamehacking` `#iosdumper`

Maintainer: **zexisyy** (Zexis) · Telegram [@zexisyy](https://t.me/zexisyy) · Discord: `zexisyy_`

---

## What it does

- Scans installed apps for `global-metadata.dat` + `UnityFramework`
- **App icons** in the list; **swipe** the card or list rows to pick a game
- **App Store / FairPlay:** optional **decrypt from memory** (launch game first)
- Writes **`dump.cs`**, `script.json`, `il2cpp.h`, DummyDll, etc.

**Bundle ID:** `com.zexis.iosil2cppdumper`

---

## Requirements

- iOS **16+**
- **TrollStore** or rootless jb with filesystem + `task_for_pid` (see `entitlements.plist`)
- Unity **IL2CPP** title installed

---

## Install (release)

Download **`iOSIL2CPPDumper.tipa`** from [Releases](https://github.com/ZexisRe/iOS-IL2CPP-Dumper/releases) and install with TrollStore.

Or build: `bash build.sh` → `build/iOSIL2CPPDumper.tipa`

---

## How to use

1. Open **iOS IL2CPP Dumper**
2. **Refresh installed apps**
3. Select target (tap / swipe card / swipe row → Select)
4. Encrypted App Store build → enable **Decrypt from memory first**, **open the game**, then dump
5. Output folder (default `/var/mobile/Documents/iOSDumper`)
6. **Dump IL2CPP** — large games ~1–3 min
7. Find `dump.cs` under `…/GameName_timestamp/Dump0/dump.cs`

Log file on failure: `ios_dumper.log` in that run folder.

---

## Build from source

```bash
git clone https://github.com/ZexisRe/iOS-IL2CPP-Dumper.git
cd iOS-IL2CPP-Dumper
bash build.sh
```

Rebuild bundled engine: `bash scripts/build-il2cpp-dumper-ios.sh`

Credits: [CREDITS.md](CREDITS.md) · License: [MIT](LICENSE)

---

## Privacy / scope

This repo is **standalone open source**. It does **not** include any private cheat, game mod, or internal product code — only this dumper UI, memory decrypt helper, and open third-party dump tooling listed in CREDITS.
