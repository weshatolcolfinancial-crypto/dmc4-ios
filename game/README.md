# Devil May Cry 4 Game Assets Directory

Place your legally acquired Xbox 360 *Devil May Cry 4* game files here:

```text
game/
├── default.xex         <-- Main Xbox 360 game executable
├── nativeXenon/        <-- Extracted MT Framework Xbox 360 asset folder (or nativePC/)
│   ├── rom/
│   │   ├── id/title/   <-- Authentic title screen & UI archives
│   │   ├── system/     <-- Game common archives
│   │   ├── enemy/      <-- Character and boss assets
│   │   └── room/       <-- Stage environments
│   └── system/
└── (or DevilMayCry4.iso)
```

### How to Extract Your ISO:
You can use the included GDFX extractor tool:
```bash
python tools/extract_iso.py /path/to/DevilMayCry4.iso -o game/
```
Or to extract only `default.xex`:
```bash
python tools/extract_iso.py /path/to/DevilMayCry4.iso --solo-xex -o game/
```

### Recompiled Code Placement:
Place any recompiled PowerPC translation units (`.cpp` or `.c` files) into:
```text
src/recompiled/
```
The CMake build system automatically discovers and compiles every `.cpp` and `.c` file located in `src/recompiled/` and links them directly into the iOS executable.

### On iOS Device:
Copy the extracted `game/` folder or `DevilMayCry4.iso` directly to:
**Files App > On My iPhone / iPad > Devil May Cry 4 > game/**
(or directly into **On My iPhone / iPad > Devil May Cry 4/**)

The app automatically detects the files in real time, mounts the VFS, attaches the 512MB guest memory sandbox, and launches the game loop with 120Hz ProMotion support.

