function [ZTraversalMode] = queryZTraversalMode(app)
% descending means going from high Z (deep) to low Z (superficial)
% named DEEP vs. SUPERFICIAL because it is consistent
    val = app.Start_Z_Stack_Drop_Down.Value;
    if strcmpi(val, "deep")
        ZTraversalMode = 'descending';
    elseif strcmpi(val, 'superficial')
        ZTraversalMode = 'ascending';
    end
end
