function data = parseGCodeFile(filePath, varargin)
% parseGCodeFile  Parse common G-code dialects into ordered XY moves.
% Returns both:
%   - extrusion-only segments
%   - full ordered XY moves with travel/extrusion labels
% Output units are microns.

    p = inputParser;
    p.addParameter('AssumeMMIsMicrons', true, @(x)islogical(x) || ismember(x,[0 1]));
    p.parse(varargin{:});
    assumeMMIsMicrons = logical(p.Results.AssumeMMIsMicrons);

    fid = fopen(filePath, 'r');
    if fid == -1
        error('Could not open G-code file: %s', filePath);
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    state.pos = [0 0 0];
    state.e = 0;
    state.absXYZ = true;
    state.absE = true;
    if assumeMMIsMicrons
        % Cura workaround: interpret "mm" numbers as already-micron-scaled.
        state.unitsToMicrons = 1;
    else
        state.unitsToMicrons = 1000;
    end
    state.extruderOn = false;    % M101/M103 legacy toggle

    segChunk = 50000;
    segs = zeros(segChunk, 6); % [x0 y0 z0 x1 y1 z1]
    nSeg = 0;
    moves = zeros(segChunk, 6); % [x0 y0 z0 x1 y1 z1]
    moveIsTravel = false(segChunk, 1);
    moveIsExtrusion = false(segChunk, 1);
    nMove = 0;

    line = fgetl(fid);
    while ischar(line)
        s = stripCommentsFast(line);
        if ~isempty(s)
            [cmdType, cmdNum] = parseCommandFast(s);
            words = parseWordsFast(s);

            switch cmdType
                case 'G'
                    switch cmdNum
                        case 20 % inches
                            state.unitsToMicrons = 25400;
                        case 21 % mm
                            if assumeMMIsMicrons
                                state.unitsToMicrons = 1;
                            else
                                state.unitsToMicrons = 1000;
                            end
                        case 90 % absolute XYZ
                            state.absXYZ = true;
                        case 91 % relative XYZ
                            state.absXYZ = false;
                        case 92 % set position
                            state = applyG92(state, words);
                        case {0, 1} % linear move
                            [state, move, isTravelMove, isExtrusionMove] = applyLinearMove(state, words, cmdNum);
                            if ~isempty(move)
                                nMove = nMove + 1;
                                if nMove > size(moves,1)
                                    moves(end+segChunk, :) = 0;
                                    moveIsTravel(end+segChunk, 1) = false;
                                    moveIsExtrusion(end+segChunk, 1) = false;
                                end
                                moves(nMove, :) = move;
                                moveIsTravel(nMove) = logical(isTravelMove);
                                moveIsExtrusion(nMove) = logical(isExtrusionMove);
                            end
                            if isExtrusionMove
                                nSeg = nSeg + 1;
                                if nSeg > size(segs,1)
                                    segs(end+segChunk, :) = 0;
                                end
                                segs(nSeg, :) = move;
                            end
                        otherwise
                            % Ignore unsupported G-codes for now (e.g., arcs).
                    end

                case 'M'
                    switch cmdNum
                        case 82 % absolute E
                            state.absE = true;
                        case 83 % relative E
                            state.absE = false;
                        case 101 % extruder on (legacy)
                            state.extruderOn = true;
                        case 103 % extruder off (legacy)
                            state.extruderOn = false;
                        otherwise
                            % Ignore.
                    end
                otherwise
                    % Ignore.
            end
        end

        line = fgetl(fid);
    end

    if nMove == 0
        data = struct( ...
            'segments', zeros(0,6), ...
            'moves', zeros(0,6), ...
            'moveIsTravel', false(0,1), ...
            'moveIsExtrusion', false(0,1), ...
            'xyz', zeros(0,3));
        return;
    end

    if nSeg == 0
        segs = zeros(0,6);
    else
        segs = segs(1:nSeg, :);
    end
    moves = moves(1:nMove, :);
    moveIsTravel = moveIsTravel(1:nMove);
    moveIsExtrusion = moveIsExtrusion(1:nMove);
    xyz = [moves(:,1:3); moves(:,4:6)];
    data = struct( ...
        'segments', segs, ...
        'moves', moves, ...
        'moveIsTravel', moveIsTravel, ...
        'moveIsExtrusion', moveIsExtrusion, ...
        'xyz', xyz);
end

function s = stripCommentsFast(line)
    if ~ischar(line) || isempty(line)
        s = '';
        return;
    end

    % Strip ';' trailing comments first.
    semi = find(line == ';', 1, 'first');
    if ~isempty(semi)
        line = line(1:semi-1);
        if isempty(line)
            s = '';
            return;
        end
    end

    % Strip parenthesized comments with a lightweight scanner.
    out = blanks(length(line));
    j = 0;
    depth = 0;
    for i = 1:length(line)
        ch = line(i);
        if ch == '('
            depth = depth + 1;
            continue;
        elseif ch == ')'
            if depth > 0
                depth = depth - 1;
            else
                j = j + 1;
                out(j) = ch;
            end
            continue;
        end

        if depth == 0
            j = j + 1;
            out(j) = ch;
        end
    end
    if j == 0
        s = '';
    else
        s = strtrim(out(1:j));
    end
end

function [cmdType, cmdNum] = parseCommandFast(s)
    cmdType = '';
    cmdNum = NaN;

    n = length(s);
    i = 1;
    while i <= n && isspace(s(i))
        i = i + 1;
    end
    if i > n
        return;
    end

    c = upper(s(i));
    if c ~= 'G' && c ~= 'M' && c ~= 'T'
        return;
    end
    cmdType = c;
    i = i + 1;

    while i <= n && isspace(s(i))
        i = i + 1;
    end
    if i > n
        cmdType = '';
        return;
    end

    signv = 1;
    if s(i) == '-'
        signv = -1;
        i = i + 1;
    elseif s(i) == '+'
        i = i + 1;
    end

    numStart = i;
    while i <= n && s(i) >= '0' && s(i) <= '9'
        i = i + 1;
    end

    if i == numStart
        cmdType = '';
        cmdNum = NaN;
        return;
    end

    cmdNum = signv * str2double(s(numStart:i-1));
end

function words = parseWordsFast(s)
    words = struct('X', NaN, 'Y', NaN, 'Z', NaN, 'E', NaN);

    n = length(s);
    i = 1;
    while i <= n
        ch = upper(s(i));
        if ch == 'X' || ch == 'Y' || ch == 'Z' || ch == 'E'
            i = i + 1;
            while i <= n && isspace(s(i))
                i = i + 1;
            end
            numStart = i;
            if i <= n && (s(i) == '+' || s(i) == '-')
                i = i + 1;
            end
            hasDigitOrDot = false;
            while i <= n
                c = s(i);
                if (c >= '0' && c <= '9') || c == '.'
                    hasDigitOrDot = true;
                    i = i + 1;
                    continue;
                end
                if (c == 'e' || c == 'E')
                    i = i + 1;
                    if i <= n && (s(i) == '+' || s(i) == '-')
                        i = i + 1;
                    end
                    continue;
                end
                break;
            end

            if hasDigitOrDot
                val = str2double(s(numStart:i-1));
                words.(ch) = val;
            end
        else
            i = i + 1;
        end
    end
end

function state = applyG92(state, words)
    if ~isnan(words.X), state.pos(1) = words.X * state.unitsToMicrons; end
    if ~isnan(words.Y), state.pos(2) = words.Y * state.unitsToMicrons; end
    if ~isnan(words.Z), state.pos(3) = words.Z * state.unitsToMicrons; end
    if ~isnan(words.E), state.e = words.E * state.unitsToMicrons; end
end

function [state, move, isTravelMove, isExtrusionMove] = applyLinearMove(state, words, gNum)
    startPos = state.pos;
    startE   = state.e;

    targetPos = startPos;
    hasE = ~isnan(words.E);
    if ~isnan(words.X)
        xv = words.X * state.unitsToMicrons;
        if state.absXYZ, targetPos(1) = xv; else, targetPos(1) = targetPos(1) + xv; end
    end
    if ~isnan(words.Y)
        yv = words.Y * state.unitsToMicrons;
        if state.absXYZ, targetPos(2) = yv; else, targetPos(2) = targetPos(2) + yv; end
    end
    if ~isnan(words.Z)
        zv = words.Z * state.unitsToMicrons;
        if state.absXYZ, targetPos(3) = zv; else, targetPos(3) = targetPos(3) + zv; end
    end

    if hasE
        ev = words.E * state.unitsToMicrons;
        if state.absE
            targetE = ev;
        else
            targetE = startE + ev;
        end
    else
        targetE = startE;
    end

    dE = targetE - startE;
    dXY = norm(targetPos(1:2) - startPos(1:2));
    isExtrusionMove = (dXY > 0) && ...
                      ((hasE && dE > 0 && gNum ~= 0) || ...
                       (state.extruderOn && gNum ~= 0));
    isTravelMove = (dXY > 0) && ~isExtrusionMove;

    if dXY > 0
        move = [startPos, targetPos];
    else
        move = [];
    end

    state.pos = targetPos;
    state.e   = targetE;
end
