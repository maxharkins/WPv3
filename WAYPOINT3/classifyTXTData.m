function type = classifyTXTData(data)
% classifyTXTData  Identify semantic type of TXT data

    nCols = size(data.raw,2);

    if nCols == 2
        type = 'Mask2D';
    elseif nCols == 3
        type = 'Volume3D';
    else
        type = 'Unknown';
    end
end
