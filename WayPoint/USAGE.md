# WayPoint + ScanImage Usage Guide

## 1) Startup

1. Start ScanImage first so `hSI` and `hSICtl` exist in the MATLAB base workspace.
2. Open WayPoint app (`WP.mlapp`).
3. On startup, WayPoint links to:
   - `hSI` and `hSICtl` from base workspace.
   - Serial stage port at `COM5` (9600 baud) for XY stage movement.

## 2) Basic UI Workflow

1. `Import File`
   - Supported: `.stl`, `.txt`.
   - `.stl`: mesh import, optional size correction + rotation, slicing is prepared.
   - `.txt`: can be mask nodes (2D/3D) or previously exported scan paths.
2. Position content
   - Use movement panel with object switch (`stage` or `mask`).
   - Stage movement updates physical XY via serial command; Z uses ScanImage motor move during scan.
3. `Prep Galvo Paths`
   - Builds stage tile path (`aPath`) from geometry and overlap/FOV settings.
   - Builds per-tile/per-Z scan paths (`hStacks.ScanPaths`).
4. `Start Line Scans`
   - Runs tile loop and Z loop.
   - Moves stage to tile center.
   - Moves objective Z to slice.
   - Plays precomputed XY path through galvos.
5. `Pause` / `Resume` / `Cancel`
   - Pause halts between completed path plays.
   - Cancel exits the sequence.

## 3) Recommended Settings Before Running

- `Zoom Factor`: controls FOV estimate used for tiling.
- `Tile Overlap (um)`: overlap between stage tiles.
- `Quant Factor XY (um)`: XY discretization for path generation.
- `Quant Factor Z (um)`: Z step for slicing.
- `Beam Waist Diameter (um)`: resampling spacing reference for generated paths.
- `Power (%)`: converted to beam power fraction 0..1.
- `Pixel Dwell Time (ms)`: sets playback sample rate (`Fs = 1/PDT`).

## 4) Import Modes

## STL mesh

1. Parse STL to triangulation.
2. Confirm/correct scale (microns) and optional 3D rotation.
3. Slice mesh by Z into contours.
4. Convert contours into scanable XY line segments and ordered paths.

## TXT

- 2 columns: treated as 2D mask, promoted to 3D at current stage Z.
- 3 columns: treated as 3D node volume.
- ScanPath export format (`NumTiles`, `NumZs`, `Z-Index`, etc.): imported directly as scan paths.

## 5) How Path Generation Works

1. **Stage path generation**
   - `prepSequence` calls `getStagePath(...)`.
   - Stage tile centers are computed from geometry bounds and tile spacing.
   - Mask XY offset is added to stage path.

2. **Scan path generation**
   - Mesh mode:
     - `sliceTriangulationToScanPaths` intersects mesh with each Z plane.
     - Segments are stitched into contours.
     - Contours are resampled at `xySpacing`.
     - Horizontal scan segments are extracted (`contoursToScanSegments`).
     - Segment midpoints are ordered (`getHamiltonianPath`) to reduce travel jumps.
   - Node/mask mode:
     - Builds powerbox masks per tile/Z.
     - Converts each mask image to XY scan path (`getPathXYfromImg`).
   - Optional auto-extrusion duplicates 2D paths through configured Z range.

## 6) How It Communicates With ScanImage Galvos

1. WayPoint acquires galvo resources from `hSI.hResourceStore.hResources`:
   - Preferred by resource name containing `"x galvo"` / `"y galvo"`.
   - Fallback to fixed resource indices `118/119`.
2. For each XY path, `playPreexistingPath(...)`:
   - Resamples path to uniform arc-length spacing.
   - Converts XY microns to galvo angles via `micronsToDegrees`.
   - Converts galvo angles to volts via each galvo handle (`position2Volts`).
   - Builds one finite 2-channel NI AO waveform task.
   - Temporarily unreserves SI AO control, runs waveform, then re-reserves it.
   - Optionally sets beam power before/after playback (`setPowerFraction`).

This is direct NI DAQ playback through ScanImage-owned galvo resources, not point-by-point `pointScannerRef` calls in the current path.

## 7) Practical Review Notes (Current Implementation)

- XY stage movement is not through ScanImage motors:
  - It sends serial commands (`x..., y...`) to `COM5`.
- Z movement is through ScanImage:
  - Uses `hSI.hMotors.moveSample([0 0 zWorld])`.
- Scan path coordinate safety checks are present:
  - XY bounds check (`+-500 um`).
  - Galvo travel range and AO voltage range checks.
  - Z move guardrails and arrival tolerance checks.

## 8) Known Risks / Things To Validate On Hardware

1. Fixed galvo fallback indices (`118/119`) may be wrong on other ScanImage configs.
2. `Pixel Dwell Time (ms)` is converted to seconds and used as sample interval; very small values can demand very high AO sample rates.
3. Stage XY serial scaling (`2.5 um/step`) is hard-coded and should be calibrated for your stage controller.
4. Mask/scanpath offset handling has comments about possible double-translation; validate absolute coordinates after import.
5. `startScanMapping` hard-asserts XY path within `+-500 um`; this may reject valid coordinates if your calibrated FOV exceeds this range.

