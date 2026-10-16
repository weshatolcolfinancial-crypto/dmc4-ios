# Devil May Cry 4 (Xbox 360) Recompiled for iOS

**Devil May Cry 4 (Xbox 360 release), statically recompiled to run natively on iPhone and iPad with Apple ProMotion (120 Hz) support, custom DMC combat touch controls, and automated file detection.**

This is **not a slow emulator**. The game's PowerPC Xenon machine code is translated ahead-of-time (AOT) into native C++ using the **ReXGlue SDK** and compiled directly for Apple Silicon (`arm64`). The Xbox 360's ATI Xenos GPU commands are translated into Vulkan and rendered through Metal via MoltenVK.

---

## Key Features

* **Zero-Hassle Automated File Discovery**:
  * **No broken file picker modal**: You do *not* have to select files through iOS's system file picker dialog.
  * The app automatically monitors and detects files in your app's `Documents/` folder:
    * `/Documents/game/` (extracted folder)
    * `/Documents/dmc4.iso` (or any `.iso` placed in `Documents`)
    * `/Documents/dmc4.zip` (auto-extracts directly)
    * `/Documents/default.xex`
  * Real-time file system watcher: As soon as you copy your files into the folder via the iOS **Files** app, iTunes, Finder, or LiveContainer, the launcher detects it instantly!

* **Custom DMC Combat Touch HUD (Matching Mobile Port Layout)**:
  * **Action Buttons**:
    * **`Y`**: Melee Attack (**Rebellion / Red Queen Sword** icon)
    * **`X`**: Long-Range Firearm (**Handgun / Ebony & Ivory** icon)
    * **`B`**: Devil Bringer Snatch & Buster (**Claw Hand** icon)
    * **`A`**: Jump / Air Hike (**Double Chevron** icon)
  * **Combat Modifiers**:
    * **`RB`**: **Lock-On Target Reticle** with active crosshairs (crucial for executing Stinger, High Time, Streak, and Calibur)
    * **`LB`**: **Devil Trigger** (Blue wings emblem)
    * **`RT` / `LT`**: Exceed revving and weapon switching
  * **Movement & Styles**:
    * Metallic-glow Left Virtual Joystick with deadzone tuning
    * D-Pad for Dante's 4-style switching (Trickster, Swordmaster, Gunslinger, Royalguard)
    * Right camera touch trackpad zone
  * **Auto-Gamepad Detection**: Touch controls automatically fade out when an MFi, PlayStation DualSense, or Xbox Wireless controller is connected.

* **Apple ProMotion (120 Hz) Enabled**:
  * Configured via `CADisplayLink` with `CADisableMinimumFrameDurationOnPhone` enabled in `Info.plist`.
  * Dynamic physics delta scaling hooks: Runs the MT Framework engine at a locked 120 FPS without speeding up character movement or physics!
  * In-launcher switchable framerate: **30 FPS**, **60 FPS**, and **120 Hz ProMotion**.

* **Widescreen & Safe Area Support**:
  * Formatted for modern iPhones and iPads (16:9, 19.5:9, Dynamic Island, and notch safe areas).

---

## Where to Place Game Files (How It Works)

You do **not** need to browse through a file picker inside the app:

1. Install the app on your device (via **LiveContainer**, **SideStore**, **TrollStore**, or **AltStore**).
2. Open the app once to initialize the directory structure.
3. Open the iOS **Files** app (or connect to PC via iTunes / Finder):
   * Navigate to: `On My iPhone` (or `On My iPad`) $\to$ `Devil May Cry 4`
4. Copy your legal Xbox 360 DMC 4 game files into that folder:
   * **Option 1**: An uncompressed folder named `game/` containing the extracted game.
   * **Option 2**: An Xbox 360 ISO file (e.g. `dmc4.iso`).
   * **Option 3**: A ZIP archive (e.g. `dmc4.zip`).
5. Return to the app. The file watcher will automatically verify the game and enable the **⚔ PLAY** button!

---

## Building the IPA

### Option A: Cloud Build with GitHub Actions (No Mac Required)

1. Push this repository to your GitHub account.
2. Go to the **Actions** tab $\to$ **Build iOS IPA**.
3. (Optional) If you want the ahead-of-time translation bundled directly, place `default.xex` in `game/default.xex`.
4. Click **Run workflow**.
5. Once complete, download `DevilMayCry4-iOS-IPA` from the workflow artifacts.

### Option B: Local Build on macOS

```bash
# 1. Prepare dependencies and MoltenVK
python3 tools/prepare_sdk.py

# 2. Configure and build via CMake
cmake --preset ios
cmake --build --preset ios
```

The compiled `.ipa` is output to `build/DevilMayCry4.ipa`.

---

## Project Structure

```
├── .github/workflows/
│   └── build-ios.yml          # GitHub Actions automated IPA builder
├── CMakeLists.txt             # Root CMake build configuration
├── CMakePresets.json          # iOS arm64 build presets
├── dmc4_manifest.toml         # ReXGlue project manifest & memory layout
├── ios/
│   ├── CMakeLists.txt         # iOS app bundle & IPA packaging target
│   ├── Info.plist.in          # Metadata (ProMotion, File Sharing, GameController)
│   ├── dmc4.entitlements      # Mach VM memory & JIT entitlements
│   └── src/
│       ├── AppDelegate.mm     # App lifecycle & audio session setup
│       ├── GameViewController.mm # Launcher UI, auto-scan status & Metal viewport
│       ├── DMCAssetManager.mm # Automated game file detection engine
│       ├── DisplayLinkManager.mm # 120Hz ProMotion VSync display loop
│       ├── TouchOverlayView.mm # Custom DMC combat HUD (Sword, Gun, Buster, Lock-on)
│       └── ControllerManager.mm # Physical MFi/DualSense/Xbox controller mapping
├── src/
│   ├── dmc4_hooks.h           # MT Framework engine & 120 FPS delta scaling hooks
│   └── dmc4_hooks.cpp
├── renderer/
│   ├── vulkan_metal_bridge.h  # MoltenVK to CAMetalLayer bridge
│   └── vulkan_metal_bridge.cpp
└── tools/
    ├── extract_iso.py         # Standalone Xbox 360 ISO extractor
    ├── prepare_sdk.py         # Dependencies and MoltenVK setup
    └── generate_code.py       # Ahead-of-time XenonRecomp translator
```

---

## Credits & References

* **[ReXGlue SDK](https://github.com/rexglue/rexglue-sdk)** / **[Xenia](https://xenia.jp/)**: Xbox 360 static recompilation architecture.
* **[nfsmw-ios](https://github.com/bep1s69/nfsmw-ios)**: iOS platform harness, memory sandbox, and MoltenVK pipeline references.
* **[nfscarbon-ios](https://github.com/weshatolcolfinancial-crypto/nfscarbon-ios)**: ReXGlue iOS build setup and automation.
* **[nfsu2-ios](https://github.com/weshatolcolfinancial-crypto/nfsu2-ios)**: iOS touch controls and asset handling.
* **[MoltenVK](https://github.com/KhronosGroup/MoltenVK)**: Vulkan implementation on Apple Metal.
