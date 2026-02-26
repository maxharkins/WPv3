function [hImg2D] = plotImageTiles(imageDir, plotOnNewFig, plotOnWP, hWP)
% Dynamically determine image naming format

if nargin < 3
    plotOnWP = 0;
end
if nargin < 2
    plotOnNewFig = 1;
end

imageFiles = dir(fullfile(imageDir, '*.tif'));
imageNameFunc = [];
if ~isempty(imageFiles)
    % Extract the first matching filename
    exampleName = imageFiles(1).name;
    match = regexp(exampleName, '^(.*?)(\d{5})\.tif$', 'tokens');
    if ~isempty(match)
        baseName = match{1}{1};
        imageNameFunc = @(x) sprintf('%s%05d.tif', baseName, x);
    end
end

if isempty(imageNameFunc)
    error('No valid image files found with expected format.');
end

imagePositions = importdata(fullfile(imageDir,'StagePath.txt'))*1;
arbitraryZs = 0;

numStacks = size(imagePositions, 1);
imagesPerVolume = numel(arbitraryZs);
numFrames = numStacks * imagesPerVolume;
imageSize = (650)*[1, 1]*1;

hTiles = cell(1, numStacks);
positionsList = zeros(numStacks, 3);

%colormap(gray);

for stackIdx = 1:numStacks
    % Get the X, Y position for this volume
    positionXY = imagePositions(stackIdx, :);

    for imgIdx = 1:imagesPerVolume
        % Compute absolute frame index
        absIdx = (stackIdx - 1) * imagesPerVolume + imgIdx;
        
        % Assign Z position
        position3D = [positionXY, arbitraryZs(imgIdx)];
        
        % Read and process image
        imgName = imageNameFunc(absIdx);
        imgFilePath = fullfile(imageDir, imgName);

        if exist(imgFilePath, 'file')  % Check if file exists
            img = imread(imgFilePath);
        else
            warning('Image %s not found.', imgFilePath);
            continue;
        end
        
        img = uint8(img);
        img = imresize(img, imageSize);
        img = flipud(img);  % Flip for proper orientation
        
        % Store in 2D figure
        hTiles{absIdx} = TileImages('Image', img, 'Size', imageSize, 'Position', position3D);
        positionsList(absIdx, :) = position3D(1:3);
    end
end

% Sort images by Y (descending) then X (ascending) for top-left to bottom-right order
[~, sortIdx] = sortrows(positionsList, [-2, 1]);
if plotOnNewFig == 1
    hFig2D = figure; hold on;
end
%colormap(gray);

for idx = 1:length(sortIdx)
    absIdx = idx; %sortIdx(idx);
    if isempty(hTiles{absIdx})
        continue;
    end
    if plotOnNewFig
        figure(hFig2D); hold on;
        hImg2D = imshow(hTiles{absIdx}.Image, 'XData', hTiles{absIdx}.Range(1, :), 'YData', hTiles{absIdx}.Range(2, :));
        set(hImg2D, 'AlphaData', 1);
    end
%%
    if plotOnWP == 1
        % Extract 3D corners (ensuring correct Z-level)
        X = [hTiles{absIdx}.Corners(1,1), hTiles{absIdx}.Corners(2,1);
             hTiles{absIdx}.Corners(4,1), hTiles{absIdx}.Corners(3,1)];
    
        Y = [hTiles{absIdx}.Corners(1,2), hTiles{absIdx}.Corners(2,2);
             hTiles{absIdx}.Corners(4,2), hTiles{absIdx}.Corners(3,2)];
    
        Z = [hTiles{absIdx}.Corners(1,3), hTiles{absIdx}.Corners(2,3);
             hTiles{absIdx}.Corners(4,3), hTiles{absIdx}.Corners(3,3)];
    
        % Plot in 3D (ensuring each layer is added)
        surf(hWP.Axes_XYZ, X, Y, Z, 'CData', hTiles{absIdx}.Image, 'FaceColor', 'texturemap', 'EdgeColor', 'none');
    end

end

axis on
if plotOnNewFig == 1
    hTool2D = imcontrast(hFig2D);
end
if plotOnWP == 1
    hWP.frames.hTiles = hTiles;
end
