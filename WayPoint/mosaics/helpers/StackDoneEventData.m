classdef StackDoneEventData < event.EventData
    properties
        WellIdx
        PathIdx
    end
    
    methods
        function obj = StackDoneEventData(WellIdx, PathIdx)
            obj.WellIdx = WellIdx;
            obj.PathIdx = PathIdx;
        end
    end
end