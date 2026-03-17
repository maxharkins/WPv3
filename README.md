# WayPoint  
ScanImage-Integrated 2D/3D Galvo Path Execution

WayPoint is a MATLAB application that integrates with ScanImage to execute 2D and 3D galvo scan paths across tiled XY stage positions and volumetric Z stacks. It supports STL meshes, mask-derived geometry, point clouds, and precomputed ScanPaths.

---

# Overview

WayPoint separates motion and exposure into three layers:

- XY galvos — define in-plane exposure
- Objective Z motion — defines volumetric traversal
- XY stage tiling — moves between fields of view

All geometry is converted internally into:

    [ Tile ] × [ Z Layer ] × [ XY Galvo Path ]

Execution loops over tiles and Z layers.

---

# Requirements

Before launching WayPoint:

- ScanImage must already be running.
- `hSI` and `hSICtl` must exist in the MATLAB base workspace.
- XY stage must be reachable on COM5 at 9600 baud.
- Stage must be zeroed and physically safe to move.

---

# Environment Bootstrap

WayPoint uses a two-layer environment bootstrap so `setScanimage(...)` is
callable from any MATLAB session while keeping environment policy inside
WPv3.

- MATLAB user path is set to:

      C:\Users\SCIENTIFICA\Documents\MATLAB

- A lightweight wrapper lives there:

      C:\Users\SCIENTIFICA\Documents\MATLAB\setScanimage.m

- The wrapper adds WPv3 to path (if needed) and delegates to:

      C:\Users\SCIENTIFICA\Documents\MaxHarkins\WPv3\WayPoint\app\helpers\SIEnv.m

- `SIEnv.m` is the source of truth for environment switching logic.

Wrapper behavior:

    function setScanimage(varargin)
        wpRoot = 'C:\Users\SCIENTIFICA\Documents\MaxHarkins\WPv3';
        if ~contains(path, wpRoot)
            addpath(genpath(wpRoot));
        end
        SIEnv(varargin{:});
    end

Typical use:

    setScanimage("original")
    setScanimage("harkins")

When switching to `"harkins"`, WayPoint now auto-prepares today's experiment
folder tree under `.../Zhang&Brown/Experiments`.

---

# Launch

In MATLAB:

    WP

Recommended daily bootstrap:

    startWPDaily

`startWPDaily` runs:
1. `setScanimage("harkins")`
2. `scanimage` (if not already active)
3. Daily experiment folder creation
4. `WP`

WayPoint automatically binds to:
- ScanImage (`hSI`, `hSICtl`)
- XY stage serial interface

---

# Fast Z API (Single Motion Path)

WPv3 includes a Z-only API that uses existing ScanImage handles and does not
open a second serial connection:

- `WayPoint/movement/zfast/moveZaxis_fast.m`
- `WayPoint/movement/zfast/getZaxis_fast.m`
- `WayPoint/movement/zfast/waitZaxis_fast.m`

Signature:

    out = moveZaxis_fast(hSI_or_hSICtl, zValue, ...
        'Type', 'relative|absolute', ...
        'Frame', 'sample|axes', ...
        'QueryBefore', false, ...
        'QueryAfter', false, ...
        'Blocking', true, ...
        'PollInterval', 0.005, ...
        'Timeout', 5)

Integration notes:

- No `WP.mlapp` edits are required.
- Stage/manual moves and scanning both call `moveZaxis_fast(...)`.
- `hWP.hStage.Position(3)` is synchronized from measured/tracked Z so GUI state,
  imported 2D mask promotion Z, and scan execution stay consistent.
- Fast no-op path: for WP-wrapper calls in sample frame, if
  `hWP.hStage.Position(3)` already matches target and query flags are false,
  move command is skipped.
- Scan anchoring: scanning performs startup anchor, tile-first-layer anchor, and
  periodic/large-step re-anchors to keep tracked Z aligned while still using
  fast non-query moves for most layers.

Exact call:

    out = moveZaxis_fast(hSI, 100.00, ...
        'Type','relative', ...
        'QueryBefore',false, ...
        'QueryAfter',true);

---

# Standard Workflow

## 1. Import Geometry or Paths

Supported formats:

- `.stl` — triangulated surface mesh
- `.gcode` / `.gco` / `.nc` — extrusion G-code converted to ScanPaths
- `.txt`
  - 2 columns → treated as 2D mask (can be extruded before planning ScanPaths)
  - 3 columns → treated as 3D node volume
  - ScanPaths export format → imported directly

All units are assumed to be microns.

Imported-file naming context is tracked automatically:
- Example: `violin.STL` -> `violin_STL`
- This label is reused in default ScanPaths export filenames and run metadata.

---

## 2. Optional: Scale / Rotate / Center

If needed, apply:

- Global scaling
- Discrete 3D rotation (90° increments only)
- Recentering

Use Right Hand Rule for 3D rotation. Rotations are constrained to orthogonal global axes to prevent floating-point drift. 

Example:

    X +90° : [x y z] → [x -z y]

---

## 3. Configure Parameters (Before Generating ScanPaths)

These must be set before pressing **Plan ScanPaths**:

- Zoom
- Tile Overlap (µm)
- Quant Factor XY (µm)
- Quant Factor Z (µm)
- Beam Waist Diameter (µm)
- Extrusion Settings (for 2D inputs)
- XY mask position

These values determine discretization and slicing. Raster spacing is derived from beam waist.

For **2D Extrusion**, configure in **Extrusion Settings**:

- Z Start (µm)
- Z Step Size (µm)
- Z End (µm)

Note that `Z Start (µm)` and `Z End (µm)` are just for bounds and do not affect the Z Traversal direction. 

---

## 4. Generate ScanPaths

Click **Plan ScanPaths**. WayPoint will:

1. Compute XY stage tile centers
2. Slice geometry along Z
3. Generate XY galvo paths per Z layer
4. Quantize and resample paths for hardware playback

---

## 5. Configure Execution Settings (Before Executing Line Scan)

These must be set before pressing **Start Line Scan**:

- Power (%)
- Pixel Dwell Time (ms)
- Start Z Stack direction
- Z mask position

Important:

- Z-axis must be zeroed to desired level before execution.
- A safety check aborts motion if a single Z jump exceeds 800 µm.

---

## 6. Execute

Click **Start Line Scans**.

Execution order:

    for each tile
        for each Z layer
            move stage (XY)
            move objective (Z)
            play galvo path

Pause, resume, and cancel operate only between completed path plays.

Each run now writes a professional log bundle automatically:
- `log/<runid>_summary.txt` (human-readable run report)
- `log/<runid>_layers.csv` (tile/Z layer execution table)
- `metadata/<runid>_metadata.json` (full machine-readable metadata)
- `metadata/<runid>_metadata.mat` (full MATLAB struct snapshot)
- `processed/<runid>_scanpaths_snapshot.txt` (planned path snapshot for reproducibility)

Captured metadata includes execution settings (power, PDT, quantization, traversal),
stage path, Z plan, imported source context, per-layer timing/status, and run outcome.

---

# Z Traversal

- Z is the slicing axis for volumetric workflows.
- Objective Z is controlled through ScanImage motors.
- Upright microscope convention:
  - +Z → deeper focus
  - -Z → superficial focus

For refractive stability, begin deep and traverse superficially when possible.

Each Z layer produces a fixed-Z XY exposure path.

---

# Beam Waist and Resampling

Beam waist diameter sets the canonical raster spacing:

    Raster Spacing (µm) = Beam Waist Diameter (µm) / 2

This rule is used consistently for:

- Mesh contour resampling and raster lane spacing
- Image-mask scan-path generation
- Galvo playback path resampling
- Scan-time estimation

Default beam waist diameter: 0.8 µm (therefore default raster spacing: 0.4 µm)

---

# Import Behavior

## STL
1. Parse triangulation
2. Optional scale / orient / center
3. Slice along Z
4. Convert contours to XY scan paths

## TXT
- 2 columns → promoted to 3D at current Z
- 3 columns → treated as 3D volume
- ScanPaths format → imported directly

## G-code
- Parses linear moves (`G0/G1`) with common unit/mode commands (`G20/G21`, `G90/G91`, `M82/M83`, `G92`)
- Uses extrusion-positive moves as scan segments
- Clips segments at each tile FOV boundary and preserves discontinuities
- Tile spacing uses `FOV - 2*TileOverlap` and overlap regions are ownership-partitioned to avoid duplicate exposure
- Current default assumes Cura-style scaled workflow: `G21` numeric values are interpreted as `µm` (mm-as-µm), not multiplied by 1000

---

# Galvo Playback

Playback sequence:

1. Acquire X/Y galvo resources
2. Resample path to uniform arc length at `Beam Waist Diameter / 2`
3. Convert microns → galvo angle → AO voltage
4. Output finite 2-channel NI AO waveform
5. Apply laser power fraction during playback

---

# User Scripts

User-specific workflows should live in:

    WayPoint/userscripts/

Recommended practice:
- Keep reusable workflows here
- Call core WayPoint functions
- Avoid modifying app internals

---

# Experiment Directory + Repeatability Design

WayPoint now targets this structure:

    .../Zhang&Brown/Experiments/YYYY/YYYY-MM-DD_experiment-name/
        log/
        figures/
        metadata/
        processed/
        raw/

Behavior:
- `YYYY`, `MM`, `DD` are auto-filled each day.
- Suffix is preserved as `_experiment-name` by default (you can rename it later).
- If a folder already exists for the same day (`YYYY-MM-DD_*`), WayPoint reuses it.
- Subfolders are auto-created if missing.

Design choice for many trials in one day:
- Keep one day folder and create one run artifact bundle per scan run.
- This avoids forcing "one experiment per day" while keeping trials indexed and reproducible.
- If you split into multiple experiments the same day, create additional `YYYY-MM-DD_*`
  folders manually; WayPoint will use the most recent matching day folder.

Default ScanPaths export behavior:
- Save dialog opens in today's `processed/` folder.
- Suggested name uses imported source label:

      violin_STL_ScanPaths_YYYYMMDD_HHMMSS.txt

- You can edit before saving.

---

# Known Issues

- Scan-path discontinuity may introduce visible segmentation artifacts.
- Hardcoded galvo fallback indices may not match all ScanImage setups.
- Very small dwell times can imply impractical AO sample rates.
- XY stage conversion (2.5 µm/step) is hardcoded and uncalibrated.
- Current XY stage is lousy and WILL introduce unintended Z motion during XY travel.

---

# Planned Improvements (From Mar. 1, 2026)

- Include Z-dependent laser power tuning
- Make scale/rotate/center callable at any time
- Add persistent transform UI controls
- Visualize all Z layer extrusions in 3D view
- Visualize exactly what the current ScanPath is during execution.
- Convert dwell time units from ms to µs


# Planned Improvements (From Mar. 16, 2026)

- Make a folder within WayPoint\calibration\ that is the dedicated pockel cell calibration folder. fix the current log path in pockel cell calibartion and make it go there! and put all the other pockel cell calibration-related files in taht folder (you should have a histroical archive folder that contains the actual log things yk? dont just flood the folder taht also has files in it)

# Future works (far into the future)

- Replace serial stage control with proper hardware API

 
---

WayPoint is designed for controlled, repeatable galvo-based fabrication and volumetric workflows. Always verify stage zero, Z limits, and power settings before execution.
