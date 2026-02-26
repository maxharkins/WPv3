classdef PowerBox
    properties (SetObservable, AbortSet)
        rect
        powers
        name = '';
        oddLines = true;
        evenLines = true;
        mask = [];
        zs = [];
                
        useSampleAbsolute = false; %Whether the powerbox should be defined relative to the sample (true) or the focus (false)
        sampleAbsoluteLocation;    %Where the powerbox is located in sample relative space (microns)
        locked = false              %Whether the size and/or position of the powerbox is permitted to change.
    end
end