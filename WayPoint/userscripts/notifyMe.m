function notifyMe(msg)

    % --- Pushover credentials ---
    user  = 'up3fearijpvbxmrm5uts1wgthv2rkg';
    token = 'arwukfgn998bqmceczbs6sjwghgiai';

    % --- Build JSON payload ---
    data = struct( ...
        'token', token, ...
        'user', user, ...
        'message', msg, ...
        'title', 'MATLAB Alert' ...
    );

    % --- Send request ---
    try
        options = weboptions('MediaType','application/json', ...
                             'Timeout',10);

        response = webwrite('https://api.pushover.net/1/messages.json', data, options);

        % disp("Pushover sent:");
        % disp(response);

    catch ME
        warning("Failed to send Pushover notification:");
        disp(ME.message);
    end

end