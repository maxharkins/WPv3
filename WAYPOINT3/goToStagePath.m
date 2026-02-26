function goToStagePath(hWP, stagePath, pathIdx)
    globalDest = stagePath(pathIdx, :);
    movementRequest(hWP, 'stage', globalDest);
end