function tf = zaxis_fast_queryMoving(hZMotor)
%ZAXIS_FAST_QUERYMOVING True when mapped Z motor reports motion.

    state = hZMotor.queryMoving();
    tf = any(logical(state(:)));
end
