% Helper to ramp to a target angle in a chosen time T
function rampToDeg(hX, thetaTarget_deg, T_sec)
    % Convert desired motion to volts
    k = hX.voltsPerDistance;                      % V/deg (yours is 0.5)
    thetaNow_deg = hX.readPositionOutput();       % current commanded pos (deg)
    dV = abs(thetaTarget_deg - thetaNow_deg) * k; % volts to travel

    % Choose slew so that time ≈ T_sec
    if T_sec <= 0 || dV == 0
        disp('here')
        hX.smoothTransitionPosition(thetaTarget_deg);
        hX.waitMoveComplete();
        return
    end
    slew_V_per_s_old = hX.slewRateLimit_V_per_s;  % remember current setting
    hX.slewRateLimit_V_per_s = dV / T_sec;        % V/s

    % Execute ramp and wait
    hX.smoothTransitionPosition(thetaTarget_deg);
    hX.waitMoveComplete();

    % Restore previous limit
    hX.slewRateLimit_V_per_s = slew_V_per_s_old;
end