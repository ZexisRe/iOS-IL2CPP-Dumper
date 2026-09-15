# iOS IL2CPP Dumper

On-device **`dump.cs`** for **Unity IL2CPP**, plus **decrypt any installed app → `.ipa`** on **jailbreak / TrollStore** iOS.

**Tags:** `#ios` `#jailbreak` `#trollstore` `#il2cpp` `#unity` `#dumpcs` `#ipa` `#decrypt` `#reverseengineering` `#iosdumper`

**Author:** **zexisyy** (Zexis) · Telegram [@zexisyy](https://t.me/zexisyy) · Discord: `zexisyy_`

**Fork of:** [34306/unitydump-iOS](https://github.com/34306/unitydump-iOS) — extended and maintained by zexisyy ([CREDITS.md](CREDITS.md))

---

## What it does

### IL2CPP dump
- Scans Unity apps for `global-metadata.dat` + `UnityFramework`
- **App icons** in lists; swipe card or rows to pick a target
- **FairPlay:** decrypt `UnityFramework` from memory (launch game first)
- Outputs **`dump.cs`**, `script.json`, `il2cpp.h`, DummyDll, etc.

### Decrypt to IPA
- Lists **all installed apps** (not only Unity)
- Copies the app bundle, decrypts **every encrypted Mach-O** from the running process, zips **`Payload/…` → `.ipa`**
- TrollStore / sideload builds with **cryptid 0** pack without launching

**Bundle ID:** `com.zexis.iosil2cppdumper`

---

## Requirements

- iOS **15+**
- **TrollStore** or rootless jb with filesystem + `task_for_pid` (see `entitlements.plist`)
- **`/usr/bin/zip`** on device (default on jailbreak)

---

## Install (release)

Download **`iOSIL2CPPDumper.tipa`** from [Releases](https://github.com/ZexisRe/iOS-IL2CPP-Dumper/releases) and install with TrollStore.

Or build: `bash build.sh` → `build/iOSIL2CPPDumper.tipa`

---

## How to use

1. Open **iOS IL2CPP Dumper**
2. **Refresh installed apps**
3. Top segment: **IL2CPP dump** or **Decrypt to IPA**
4. Pick an app (tap / swipe)
5. App Store encrypted → **open that app**, then run
6. Output folder (default `/var/mobile/Documents/iOSDumper`)

**IL2CPP:** **Dump IL2CPP** → `…/GameName_timestamp/Dump0/dump.cs`  
**IPA:** **Decrypt app to IPA** → `…/GameName_decrypted_timestamp/GameName_decrypted.ipa`

Log on IL2CPP failure: `ios_dumper.log` in the run folder.

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

Standalone open source — dumper UI, memory decrypt helper, and third-party tools listed in CREDITS only. No private cheat or external product code.
