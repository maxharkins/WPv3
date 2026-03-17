function z = zaxis_fast_readPosition(hMotors, frame, doQuery)
%ZAXIS_FAST_READPOSITION Read Z in requested coordinate frame.

    if doQuery
        hMotors.queryPosition([false false true], true);
    end

    switch frame
        case 'sample'
            z = double(hMotors.samplePosition(3));
        case 'axes'
            z = double(hMotors.axesPosition(3));
        otherwise
            error('moveZaxis_fast:InvalidFrame', 'Frame must be ''sample'' or ''axes''.');
    end

    if ~isscalar(z) || ~isfinite(z)
        error('moveZaxis_fast:InvalidPosition', ...
            'Read invalid Z position from hMotors.%sPosition(3).', frame);
    end
end
