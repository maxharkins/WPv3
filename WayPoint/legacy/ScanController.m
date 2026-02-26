classdef ScanController
    properties
        CurrentStageIndex   % Current stage waypoint index
        CurrentZIndex       % Current Z level being scanned
        GalvoX              % Galvo control for X axis
        GalvoY              % Galvo control for Y axis
        ObjectiveZ          % Objective lens position (Z control)

        hWP                 % Handle to WP class
        hSI                 % Handle to SI class
        hSICtl              % Hanlde to SICtl class

        hAblationSequence   % Handle to AblationSequence class
        hImagingSequence    % Handle to ImagingSequence class
    end
    
    methods
        function [obj] = ScanController(hWP, hSI, hSICtl)
            if nargin < 3
                hSICtl = evalin('base', 'hSICtl');
            end
            if nargin < 2
                hSI = evalin('base', 'hSI');
            end
            if nargin < 1
                hWP = evalin('base', 'hWP');
            end
            obj.hSICtl = hSICtl;
            obj.hSI = hSI;
            obj.hWP = hWP;
            obj.CurrentStageIndex = 1;
            obj.CurrentZIndex = 1;
        end

        function moveToNextZ(obj)
            % Move to the next Z level
            obj.CurrentZIndex = obj.CurrentZIndex +1;
            
            if obj.CurrentZIndex > numel(obj.hWP.hAblationSequence.hScanTiles{obj.CurrentZIndex}.UniqueZs)
                moveToNextStage(obj);
                return;
            end
            zDest = obj.hWP.hAblationSequence.hScanTiles.UniqueZs(obj.CurrentZIndex);
            obj.hSI.hMotors.moveSample([0 0 zDest]);
            % z movement done
        end
        
        function moveToNextStage(obj)
            % Move to the next stage waypoint
            obj.CurrentZIndex = 1;
            obj.CurrentStageIndex = obj.CurrentStageIndex +1;

            if obj.CurrentStageIndex > size(obj.hWP.hAblationSequence.StagePath, 1)
                disp('Ablation complete.') % All ablation ScanTiles are complete.
                return;
            end

            xDest = obj.hWP.hAblationSequence.StagePath(obj.CurrentStageIndex, 1);
            yDest = obj.hWP.hAblationSequence.StagePath(obj.CurrentStageIndex, 2);
            zDest = obj.hWP.hAblationSequence.hScanTiles{obj.CurrentZIndex}.UniqueZs(1);

            movementRequest(obj.hWP, 'stage', [xDest, yDest, zDest]);
            % x,y,z movement done
        end
        
        function scanCurrentZ(obj)
        

        end



    end
end