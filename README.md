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

# Launch

In MATLAB:

    WP

WayPoint automatically binds to:
- ScanImage (`hSI`, `hSICtl`)
- XY stage serial interface

---

# Standard Workflow

## 1. Import Geometry or Paths

Supported formats:

- `.stl` — triangulated surface mesh
- `.txt`
  - 2 columns → treated as 2D mask (can be extruded before planning ScanPaths)
  - 3 columns → treated as 3D node volume
  - ScanPaths export format → imported directly

All units are assumed to be microns.

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

These values determine discretization, slicing, and raster spacing.

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

Beam waist diameter controls XY raster spacing.

Default: 0.8 µm

Guidelines:

- Smaller waist → denser sampling
- Larger waist → sparser sampling
- For highest resolution, keep beam waist spacing consistent with XY quantization

Image-based path generation defaults to 0.8 µm if unspecified.

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

---

# Galvo Playback

Playback sequence:

1. Acquire X/Y galvo resources
2. Resample path to uniform arc length
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

# Known Issues

- Scan-path discontinuity may introduce visible segmentation artifacts.
- Hardcoded galvo fallback indices may not match all ScanImage setups.
- Very small dwell times can imply impractical AO sample rates.
- XY stage conversion (2.5 µm/step) is hardcoded and uncalibrated.
- Current XY stage is lousy and WILL introduce unintended Z motion during XY travel.

---

# Planned Improvements (From Feb. 26, 2026)

- Make scale/rotate/center callable at any time
- Add persistent transform UI controls
- Visualize all Z layer extrusions in 3D view
- Visualize exactly what the current ScanPath is during execution.
- Convert dwell time units from ms to µs
- Replace serial stage control with proper hardware API

---

WayPoint is designed for controlled, repeatable galvo-based fabrication and volumetric workflows. Always verify stage zero, Z limits, and power settings before execution.
