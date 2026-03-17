# Z-Fast API for WPv3 / ScanImage

This module provides a Z-only motion API that reuses existing ScanImage objects (`hSI` / `hSICtl`) and does not open a second serial connection.

## Sample vs Axes

- `Frame='sample'`: Uses ScanImage sample-space coordinates (`hSI.hMotors.samplePosition(3)`), i.e. relative/sample coordinates.
- `Frame='axes'`: Uses controller-axis coordinates (`hSI.hMotors.axesPosition(3)`), i.e. absolute mapped motor-axis coordinates.

## Function Signature

```matlab
out = moveZaxis_fast(hSI_or_hSICtl, zValue, ...
    'Type', 'relative|absolute', ...
    'Frame', 'sample|axes', ...
    'QueryBefore', false, ...
    'QueryAfter', false, ...
    'Blocking', true, ...
    'PollInterval', 0.005, ...
    'Timeout', 5)
```

## Options and Defaults

- `Type` (default: `'absolute'`)
- `Frame` (default: `'sample'`)
- `QueryBefore` (default: `false`)
- `QueryAfter` (default: `false`)
- `Blocking` (default: `true`)
- `PollInterval` (default: `0.005` seconds)
- `Timeout` (default: `5` seconds)

Behavior:

- `Type='relative'`: `zTarget = currentZ + zValue`
- `Type='absolute'`: `zTarget = zValue`
- `QueryBefore=true`: forces `hMotors.queryPosition([false false true], true)` before reading `zBefore`
- `QueryAfter=true`: forces `hMotors.queryPosition([false false true], true)` before reading `zAfter`
- `Blocking=true`: waits for move completion by polling `queryMoving()`
- `Blocking=false`: sends move command and returns immediately

## Copy/Paste Examples

Relative sample blocking:

```matlab
out = moveZaxis_fast(hSI, 100.00, ...
    'Type','relative', ...
    'Frame','sample', ...
    'Blocking',true, ...
    'QueryAfter',true);
```

Absolute sample blocking:

```matlab
out = moveZaxis_fast(hSI, 2500.0, ...
    'Type','absolute', ...
    'Frame','sample', ...
    'Blocking',true, ...
    'QueryAfter',true);
```

Relative axes non-blocking:

```matlab
out = moveZaxis_fast(hSI, 50.0, ...
    'Type','relative', ...
    'Frame','axes', ...
    'Blocking',false);
```

`hSICtl` usage:

```matlab
out = moveZaxis_fast(hSICtl, 100.00, ...
    'Type','relative', ...
    'QueryBefore',false, ...
    'QueryAfter',true);
```

## Exact Call Requested

```matlab
out = moveZaxis_fast(hSI, 100.00, ...
    'Type','relative', ...
    'QueryBefore',false, ...
    'QueryAfter',true);
```

## Failure Modes

- Invalid SI handle (`hSI` / `hSICtl` / wrapper cannot be resolved)
- Missing Z motor mapping (`hMotorXYZ{3}` / `motorAxisXYZ(3)` invalid)
- Move already in progress (`queryMoving()` true at command start)
- Timeout while waiting for completion (`Blocking=true`, `Timeout` exceeded)

## Minimal Validation Workflow

With ScanImage open:

```matlab
z0 = hSI.hMotors.samplePosition(3);

out1 = moveZaxis_fast(hSI, 200, 'Type','relative', 'Frame','sample', 'QueryAfter',true);
out2 = moveZaxis_fast(hSI, z0, 'Type','absolute', 'Frame','sample', 'QueryAfter',true);

disp(out1)
disp(out2)
```

Expected:

- `out1.deltaActual` close to `+200`
- `out2.zAfter` close to `z0`
