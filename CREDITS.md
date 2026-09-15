# Credits & third-party software

## Fluck External

- **Author / maintainer:** [zexisyy](https://github.com/zexisyy) (Zexis)  
- **Contact:** Telegram [@zexisyy](https://t.me/zexisyy) · Discord `zexisyy_`  
- **Bundle ID:** `com.fluck.org`

App icon uses the **Fluck** product logo only (no third-party game or cheat branding).

---

## IL2CPP dump engine (bundled)

- **[rodroidmods/il2cpp-dumper-rs](https://github.com/rodroidmods/il2cpp-dumper-rs)** — MIT  
  Native `il2cpp_dumper` CLI used for metadata v31+ and Mach-O Unity games.  
  Built for `aarch64-apple-ios` via `scripts/build-il2cpp-dumper-ios.sh`.

---

## Ideas & prior art (not copied as source)

These projects informed the **on-device dump** workflow; **Fluck External** is independent Swift/ObjC code:

- **[34306/unitydump-iOS](https://github.com/34306/unitydump-iOS)** — MIT (Il2CppDumper packaging concept)  
- **[Perfare/Il2CppDumper](https://github.com/Perfare/Il2CppDumper)** — MIT (original .NET dumper & RE scripts)  
- **[Lakr233/AuxiliaryExecute](https://github.com/Lakr233/AuxiliaryExecute)** — Swift package for subprocess spawn  

Legacy Xamarin `Il2CppDumper` iOS bundle may remain in tree for fallback but is **not** required for current FF MAX–era metadata.

---

## RE helper scripts (in `FluckDumper/iOS-Dump/`)

Python scripts (`ida.py`, `ghidra.py`, etc.) originate from **Il2CppDumper** releases — see Perfare’s license in those files / [Il2CppDumper](https://github.com/Perfare/Il2CppDumper).

---

## Thanks

To the reverse-engineering and jailbreak communities for tooling that makes IL2CPP research possible on iOS.
