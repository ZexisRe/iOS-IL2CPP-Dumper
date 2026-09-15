# Fluck External

**Fluck External** (`com.fluck.org`) is an iOS app for **jailbroken / TrollStore** devices that finds Unity IL2CPP games, optionally **decrypts App Store `UnityFramework` from memory**, and writes **`dump.cs`** (plus `script.json`, `il2cpp.h`, DummyDll, etc.) to a folder you choose.

Maintainer: **zexisyy** (Zexis)  
Telegram: [@zexisyy](https://t.me/zexisyy) · Discord: `zexisyy_`

---

## Requirements

- iPhone/iPad on **iOS 16+** (tested on rootless jb + TrollStore)
- **TrollStore** (full) or rootless jailbreak with broad file access
- Unity game installed (IL2CPP — `global-metadata.dat` + `UnityFramework`)
- For **App Store / FairPlay** builds: **open the game first**, enable **Decrypt from memory first**, then dump

---

## Install

1. Build on Mac: `bash build.sh` → `build/FluckDumper.tipa`
2. Install with **TrollStore** (`trollstorehelper install …`) or your usual `.tipa` workflow.

Entitlements expect a **platform app** with filesystem access and `task_for_pid` (see `entitlements.plist`).

---

## How to use

1. Open **Fluck External**.
2. **Refresh installed apps** — Unity targets are detected automatically.
3. **Choose app**: tap a row, **swipe the top card**, or swipe a row → **Select** / **Next**.
4. **App Store / encrypted**: turn on **Decrypt from memory first**, **launch the game**, then dump.
5. Set **output folder** (default `/var/mobile/Documents/FluckDump`).
6. Tap **Dump IL2CPP** — large games can take 1–3 minutes.
7. Output is under `…/YourGame_<timestamp>/Dump0/dump.cs` (or `dump.cs` in the run folder for legacy engine).

Logs: `fluck_dump.log` in the same run directory if something fails.

---

## Build from source

```bash
git clone https://github.com/ZexisRe/FluckExternal.git
cd FluckExternal
bash build.sh
```

### Bundled IL2CPP engine

Release builds include a cross-compiled **`il2cpp_dumper`** binary (Rust). To rebuild it:

```bash
bash scripts/build-il2cpp-dumper-ios.sh
cp …/target/aarch64-apple-ios/release/il2cpp_dumper FluckDumper/iOS-Dump/
```

See [CREDITS.md](CREDITS.md) for upstream licenses.

---

## Fork & third-party credits

This project is a **Fluck-branded** app inspired by the general approach of on-device Unity dump tools. It does **not** ship those projects’ UI or private assets — only **Fluck logo** branding and open components listed in **CREDITS.md**.

---

## License

MIT — see [LICENSE](LICENSE). Third-party binaries and scripts remain under their respective licenses.
