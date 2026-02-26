classdef Listeners
    properties
        lFrameDone
        lVolumeDone
        lStackDone
    end
    
    methods (Access = public)
        function [obj] = Listeners(hWP)
            if nargin < 1 || isempty(hWP)
                return;
            end
            % Create listeners with anonymous functions that capture 'obj'
            obj.lFrameDone  = addlistener(hWP.hSI.hStackManager, 'nFrameDone',  @(src, evnt)  obj.fFrameDone(src, evnt));
            obj.lVolumeDone = addlistener(hWP.hSI.hStackManager, 'nVolumeDone', @(src, evnt) obj.fVolumeDone(src, evnt));
            %obj.lStackDone  = addlistener(hWP.hSI.hStackManager, 'nStackDone', @(src, evnt) obj.fStackDone(src, evnt));
        end
        
        function fFrameDone(~, src, ~)
            %disp('frame called')
            hWP = src.hWP;
            if ~hWP.ListenersONCheckBox.Value
                return;
            end

            hWP.Sequence.LocalFramesCUR = hWP.Sequence.LocalFramesCUR + 1;
                        
            if hWP.Sequence.LocalFramesCUR >= hWP.Sequence.LocalFramesREQ
                hWP.Sequence.PathIdx = hWP.Sequence.PathIdx +1;
                hWP.Sequence.LocalFramesCUR = 0;
            else
                return;
            end

            % a frame is taken at each stage path.
            if hWP.Sequence.PathIdx == size(hWP.Sequence.StagePath, 1)
                hWP.Sequence.CountFrames = 1;
                hWP.Sequence.CountVolumes = 0;
                hWP.Sequence.CountStacks = 0;
            elseif hWP.Sequence.PathIdx > size(hWP.Sequence.StagePath, 1)
                disp('Frames are all done');
                hWP.ListenersONCheckBox.Value = 0;
                hWP.Sequence.CountFrames = 0;
                hWP.Sequence.CountVolumes = 0;
                hWP.Sequence.CountStacks = 0;
                return;
            end
            globalDest = hWP.Sequence.StagePath(hWP.Sequence.PathIdx, :);
            movementRequest(hWP, 'stage', globalDest);
        end
        
        function fVolumeDone(~, src, ~)
            % hWP = src.hWP;
            % if ~hWP.Sequence.CountVolumes
            %     return;
            % end
            % hWP.Sequence.PathIdx = hWP.Sequence.PathIdx +1;
            % 
            % % a volume is taken at each stage path.
            % if hWP.Sequence.PathIdx > size(hWP.Sequence.StagePath, 1)
            %     disp('Volumes are all done.');
            %     hWP.Sequence.CountFrames = 0;
            %     hWP.Sequence.CountVolumes = 0;
            %     hWP.Sequence.CountStacks = 0;
            %     return;
            % end
            % globalDest = hWP.Sequence.StagePath(hWP.Sequence.PathIdx, :);
            % movementRequest(hWP, 'stage', globalDest);
        end
        
        function fStackDone(~, src, ~)
            disp('STACK DONE')
            hWP = src.hWP;
            if ~hWP.Sequence.CountStacks
                disp('Not counting stacks')
                return;
            end
            disp('counting stacks')
            hWP.Sequence.PathIdx = hWP.Sequence.PathIdx +1;
            if hWP.Sequence.PathIdx > size(hWP.Sequence.StagePath, 1)
                disp('Stacks are all done');
                hWP.Sequence.CountFrames = 0;
                hWP.Sequence.CountVolumes = 0;
                hWP.Sequence.CountStacks = 0;
                return;
            end
            globalDest = hWP.Sequence.StagePath(hWP.Sequence.PathIdx, :);
            movementRequest(hWP, 'stage', globalDest);
            
            disp('Pausing...')
            pause(8)
            disp('MIGHT WORK...')
            if hWP.Sequence.isAblation
                setAblationStack(hWP, hWP.Sequence.hStacks, hWP.Sequence.PathIdx);
            end
            pause(3)
            
            if 1==1
                notify(hWP.hSICtl.hGUIData.mainControlsV4.startLoopButton, 'Action');
                disp('SHOULD HAVE WORKED...')
            end
        end
    end
end
