function [filePath, file, path] = browse()
% A very useful function so I dont have to keep copying file paths.
% Just type 'browse'. 

    [file, path] = uigetfile('*.*');
    if isequal(file, 0)
        filePath = [];
        disp('User selected Cancel.')
        return   
    else
        filePath = strcat(path,file);
    end
end