classdef ScanSequence
    properties
        isActive = false;
        isAblation = false;
        isAblationTest = false;
        LocalFramesREQ = 1
        LocalFramesCUR = 0% frames done at that location.
        StagePath
        PathIdx
        hStacks
        CountVolumes = 0;
        CountStacks = 0;
        CountFrames = 0;
        ZoomFactor
        ImageDir

    end

    methods
        function obj = ScanSequence(StagePath, ZoomFactor)
            if nargin < 2 || isempty(ZoomFactor)
                ZoomFactor = [];
            end
            if nargin < 1 || isempty(StagePath)
                return;
            end
            obj.StagePath = StagePath;
            obj.ZoomFactor = ZoomFactor;

        end
    end
end
