function initializeApp(hWP)
    hWP.plotAxes.plotStyle.stage2D = {'EdgeColor', 'g', 'LineWidth', 2};
    hWP.plotAxes.plotStyle.stage3D = {'Color', 'g', 'LineWidth', 4};
    hWP.plotAxes.plotStyle.nodes   = {'Color', 'r', 'LineStyle', 'none', 'Marker', '.'};
    hWP.plotAxes.plotStyle.path    = {'Color', 'k', 'LineStyle', 'none', 'Marker', 'o'};
    hWP.plotAxes.axisLimits        = struct('XY', [], 'YZ', [], 'ZX', []);
    

    % SETTINGS:
    hWP.Settings.ZoomFactor             = hWP.Zoom_Factor_Spinner.Value;
    hWP.Settings.FOVSize_um             = zoom2microns(hWP.Settings.ZoomFactor);
    hWP.Settings.TileOverlap_um         = hWP.Tile_Overlap_Edit_Field.Value;
    if isprop(hWP, 'Power_Pct_Edit_Field')
        hWP.Settings.Power_pct = hWP.Power_Pct_Edit_Field.Value;
    elseif isprop(hWP, 'Power_Edit_Field')
        hWP.Settings.Power_pct = hWP.Power_Edit_Field.Value;
    else
        hWP.Settings.Power_pct = NaN;
    end
    if isprop(hWP, 'Power_mW_Edit_Field')
        hWP.Settings.Power_mW = hWP.Power_mW_Edit_Field.Value;
    else
        hWP.Settings.Power_mW = NaN;
    end
    hWP.Settings.PockelsCalibration     = struct();
    hWP.Settings.PixelDwellTime_ms      = hWP.Pixel_Dwell_Time_Edit_Field.Value;
    hWP.Settings.QuantFactorXY_um       = hWP.XY_Quant_Factor_Edit_Field.Value;
    hWP.Settings.QuantFactorZ_um        = hWP.Z_Quant_Factor_Edit_Field.Value;
    hWP.Settings.BeamWaistDiameter_um   = hWP.Beam_Waist_Diameter_Edit_Field.Value;
    hWP.Settings.FramesPerSlice         = 1;
    hWP.Settings.ZTraversalMode         = queryZTraversalMode(hWP);

    init3Dplot(hWP);
    
    hWP.hStage = Stage(hWP, [0 0 0]);
    
    hWP.hSI = evalin('base', 'hSI');
    hWP.hSICtl = evalin('base', 'hSICtl');

    hWP.serialPort.address = 'COM5';
    hWP.serialPort.baudRate = 9600;
    
    try
        hWP.serialPort.COM = serialport(hWP.serialPort.address, hWP.serialPort.baudRate);
    catch
        warning('SerialPort connection failed.')
    end


    hWP.hStacks = Stacks.empty;
    
    hWP.hStacks = Stacks;
    hWP.hMask = Mask();
    hWP.aPath = Path();
    hWP.iPath = Path();


    hWP.slices = struct( ...
        'nodes', struct('XY',[], 'YZ',[], 'ZX',[]), ...
        'plot',  struct('XY',[], 'YZ',[], 'ZX',[])  ...
    );

    hWP.plotAxes.plotStyle.stage2D = {'EdgeColor', 'g', 'LineWidth', 2};
    hWP.plotAxes.plotStyle.stage3D = {'Color', 'g', 'LineWidth', 4};
    hWP.plotAxes.plotStyle.nodes   = {'Color', 'r', 'LineStyle', 'none', 'Marker', '.'};
    hWP.plotAxes.plotStyle.path    = {'Color', 'k', 'LineStyle', 'none', 'Marker', '.'};
    hWP.plotAxes.axisLimits        = struct('XY', [], 'YZ', [], 'ZX', []);
    init3Dplot(hWP);


   
    refreshPlot(hWP);
    axis(hWP.Axes_XYZ, 'equal');
end
