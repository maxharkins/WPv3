function handleVolumeDone(src,event)
    hWP = src.hWP;
    globalDest = hWP.hStage.Position + [-50, 00, 00];
    movementRequest(hWP, 'stage', globalDest)
    disp('volume done')
end