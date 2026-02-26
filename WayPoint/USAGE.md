# WayPoint Usage Protocol (with ScanImage)

## 1) Startup

### Assumptions
- ScanImage is already running and exposes `hSI` and `hSICtl` in base workspace.
- XY stage is reachable on `COM5` at 9600 baud.

### Mechanics
1. Start ScanImage first.
2. Open `WP.mlapp`.
3. WayPoint binds to `hSI`, `hSICtl`, and serial XY stage control.

## 2) End-to-End Workflow

### Assumptions
- Geometry or scan paths are available as `.stl` or `.txt`.
- Settings are configured before running (`Zoom`, overlap, XY/Z quantization, beam waist, power, PDT).

### Mechanics
1. `Import File`.
2. Optional transform step (`applyScaleRotateAndCenter`): scale correction + 3D orientation.
3. `Prep Galvo Paths`: build stage tile path + per-tile/per-Z scan paths.
4. `Start Line Scans`: loop over tile and Z, move stage/objective, then play XY galvo paths.
5. `Pause/Resume/Cancel` controls execution boundaries between completed plays.

## 3) 3D Orientation Orbit (Discrete 90 deg)

### Assumptions
- Orientation is intentionally constrained to orthogonal 90 deg steps.
- Rotations are around global axes and compose in click order.

### Mechanics
- `rotate3DGui` now uses only `X +/-90`, `Y +/-90`, `Z +/-90` controls.
- Each click applies a fixed integer rotation matrix (`-1/0/1` entries), so there is no floating-angle drift.
- Example: `X +90` keeps `X` unchanged and swaps `Y/Z` with sign change (`[x y z] -> [x -z y]`).
- `Apply` commits the accumulated orientation matrix; `Cancel` returns identity/no change.

## 4) Z Transversal

### Assumptions
- Z is treated as the slicing/transversal axis for volumetric workflows.
- Objective Z movement is controlled through ScanImage motors, not the XY serial stage.

### Mechanics
- Convention with upright microscope is: +Z focuses deeper; -Z focuses superficially.
- STL/volume data is sliced by planes normal to Z (`sliceTriangulationToScanPaths`).
- Each Z layer produces XY scan geometry at that fixed Z.
- During scan execution, WayPoint moves objective Z (`hSI.hMotors.moveSample([0 0 zWorld])`), then plays XY galvo trajectories.
- Practically: XY defines in-plane exposure; Z traversal defines stack progression.

## 5) Resampling and Beam Waist

### Assumptions
- Path density should track optical spot size.
- Default beam waist diameter is 0.8 um.

### Mechanics
- UI setting `Beam Waist Diameter (um)` drives spacing used for generated paths (`cfg.xySpacing`).
- Tighter beam waist -> denser XY samples; larger beam waist -> sparser samples.
- In mask-image path conversion (`getPathXYfromImg`), fallback default is `0.8` when unspecified.
- Keep XY quantization and beam-waist spacing consistent; mismatched values can over/under-sample path detail.

## 6) Import Modes

### STL mesh
1. Parse mesh into triangulation.
2. Optionally scale + orient.
3. Slice by Z.
4. Convert contours to scanable XY line paths.

### TXT
- 2 columns: 2D mask, promoted to 3D at current stage Z.
- 3 columns: treated as 3D node volume.
- ScanPaths export format (`NumTiles`, `NumZs`, `Z-Index`, etc.): imported directly as prepared scan paths.

## 7) Galvo Playback and Hardware Interface

### Assumptions
- Galvo resources are available through ScanImage resource store.
- AO reserve/unreserve transitions are allowed in your SI setup.

### Mechanics
1. Acquire X/Y galvo resources by name (`"x galvo"`/`"y galvo"`), fallback indices `118/119`.
2. Resample XY path to uniform arc-length spacing.
3. Convert microns -> galvo degrees -> AO volts.
4. Run finite 2-channel NI AO waveform.
5. Optionally set beam power fraction during playback.

## 8) User Scripts

### Assumptions
- User-specific workflows may not belong in core app code.

### Mechanics
- Place user scripts/live scripts in `WayPoint/userscripts/`.
- Current repo includes example: `WayPoint/userscripts/ablatingStraightLine.mlx`.
- Recommended pattern: keep reusable user workflows here, version them, and call core WayPoint functions instead of patching app internals.

## 9) Known Bugs and Future Work

### Known bugs
1. **Forced discontinuity in scan-path generation (X or Y phase anchor)**
   - There is a discontinuity introduced during path binning/phase selection to avoid skipping a full line, but is not optimal.
   - Current behavior can break local pattern continuity and produce visible segmentation artifacts.
2. **Unexpected extra text box in transform flow (`applyScaleRotateAndCenter`)**
   - An extra UI text edit field appears during the normalization/rotation confirmation step.
   - This is unintended and should be removed.

### Future work
1. Decide whether always recentering geometry to `(0,0,0)` is desirable for all import/playback modes.
2. Add UI controls/menu actions for scale/rotate/center so transforms are discoverable and repeatable.
3. Make the normalize/scale/orient transform flow callable at any time, not only immediately after import.
4. Plot all Z layers of auto-extruded files in the 3D view (not just current slice/path subset).

## 10) Current Risk Notes

1. Fixed galvo fallback indices (`118/119`) may not match all ScanImage configurations.
2. Very small `Pixel Dwell Time (ms)` values can imply impractically high AO sample rates.
3. XY stage serial conversion (`2.5 um/step`) is hard-coded and should be calibrated per stage/controller.
4. Offset stacking and coordinate transforms should be validated after import to avoid double-translation.
5. Hard XY bounds checks may reject valid paths on larger calibrated FOVs.
