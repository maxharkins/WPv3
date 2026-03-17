function [hSI, hMotors, hZMotor, zAxis] = zaxis_fast_resolve(hSI_or_hSICtl)
%ZAXIS_FAST_RESOLVE Resolve SI handle and Z-axis motor mapping.

    if hasMember(hSI_or_hSICtl, 'hMotors')
        hSI = hSI_or_hSICtl;
    elseif hasMember(hSI_or_hSICtl, 'hModel') && hasMember(getMember(hSI_or_hSICtl, 'hModel'), 'hMotors')
        hSI = getMember(hSI_or_hSICtl, 'hModel');
    elseif hasMember(hSI_or_hSICtl, 'hSI') && hasMember(getMember(hSI_or_hSICtl, 'hSI'), 'hMotors')
        hSI = getMember(hSI_or_hSICtl, 'hSI');
    else
        error('moveZaxis_fast:InvalidSIHandle', ...
            'Input must be hSI, hSICtl (with hModel), or wrapper with .hSI that has .hMotors.');
    end

    hMotors = getMember(hSI, 'hMotors');
    if isempty(hMotors)
        error('moveZaxis_fast:InvalidSIHandle', 'Resolved hSI has empty hMotors.');
    end

    if ~hasMember(hMotors, 'hMotorXYZ') || ~hasMember(hMotors, 'motorAxisXYZ')
        error('moveZaxis_fast:MissingZMotorMapping', ...
            'hMotors must expose hMotorXYZ and motorAxisXYZ.');
    end

    hMotorXYZ = getMember(hMotors, 'hMotorXYZ');
    if ~iscell(hMotorXYZ) || numel(hMotorXYZ) < 3 || isempty(hMotorXYZ{3})
        error('moveZaxis_fast:MissingZMotorMapping', ...
            'hMotors.hMotorXYZ{3} is missing or invalid.');
    end
    hZMotor = hMotorXYZ{3};

    motorAxisXYZ = getMember(hMotors, 'motorAxisXYZ');
    if numel(motorAxisXYZ) < 3
        error('moveZaxis_fast:MissingZMotorMapping', ...
            'hMotors.motorAxisXYZ(3) is missing.');
    end
    zAxis = double(motorAxisXYZ(3));
    if ~isscalar(zAxis) || ~isfinite(zAxis) || zAxis < 1 || mod(zAxis, 1) ~= 0
        error('moveZaxis_fast:MissingZMotorMapping', ...
            'hMotors.motorAxisXYZ(3) must be a positive integer axis index.');
    end
end

function tf = hasMember(obj, name)
tf = false;
if isempty(obj)
    return;
end

if isstruct(obj)
    tf = isfield(obj, name);
    return;
end

try
    tf = isprop(obj, name);
catch
    tf = false;
end
end

function val = getMember(obj, name)
if isstruct(obj)
    val = obj.(name);
else
    val = obj.(name);
end
end
