classdef ScanTiles
    properties
        Index           % Index of the ScanTile in the stage grid
        StagePosition   % [x, y, z] position in the stage coordinate system
        Nodes           % Array of Nodes belonging to this ScanTile
        UniqueZs        % Unique Z positions for scanning, sorted in decreasing depth
        BeamWaypoints   % Set of 2D nodes sorted
        OptimizedPath   % Stores the precomputed optimized scan path
        BeamPower       % Nominal percentage of power from pockel cell
        ScanInstructions
    end

    methods
        function [obj] = ScanTiles(Index, StagePosition, Nodes, UniqueZs, BeamWaypoints, OptimizedPath, BeamPower)
            if nargin < 7; BeamPower = [];      end
            if nargin < 6; OptimizedPath = [];  end
            if nargin < 5; BeamWaypoints = [];  end
            if nargin < 4; UniqueZs = [];       end
            if nargin < 3; Nodes = [];          end
            if nargin < 2; StagePosition = [];  end
            if nargin < 1; Index = [];          end

            obj.BeamPower = BeamPower;
            obj.OptimizedPath = OptimizedPath;
            obj.BeamWaypoints = BeamWaypoints;
            obj.UniqueZs = UniqueZs;
            obj.Nodes = Nodes;
            obj.StagePosition = StagePosition;
            obj.Index = Index;

        end
    end
end
