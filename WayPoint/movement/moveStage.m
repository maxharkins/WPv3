function moveStage(hWP, globalDest, relativeDest)
    % globalDest is [x y z].
    numSteps = round(relativeDest(1:2)/2.5);
    
    X = numSteps(1);
    Y = numSteps(2);
    Z = globalDest(3);

    message = sprintf('x%.1f, y%.1f\n', -X,Y);

    writeline(hWP.serialPort.COM, message);
    
    % realZposition = hWP.hSI.hMotors.samplePosition(:,3);
    % if abs(realZposition - Z) >= 500
    %     warning('MAKE SURE THE OBJECTIVE IS AT CORRECT Z LOCATION')
    %     return;
    % elseif abs(realZposition - Z) < 500
    %     %hWP.hSI.hMotors.moveSample([0 0 Z])
    % end

end