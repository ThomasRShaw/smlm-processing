function I = reconstruct(data, iref)
% I = RECONSTRUCT(DATA, IREF)

% Copyright (C) 2023 Thomas Shaw and Sarah Veatch
% This file is part of SMLM PROCESSING 
% SMLM PROCESSING is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% SMLM PROCESSING is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with SMLM PROCESSING.  If not, see <https://www.gnu.org/licenses/>
% USE IREF

left = iref.XWorldLimits(1);
right = iref.XWorldLimits(2);
top = iref.YWorldLimits(1);
bottom = iref.YWorldLimits(2);
pwidth = iref.PixelExtentInWorldX;
pheight = iref.PixelExtentInWorldY;

xedges = left:pwidth:right;
yedges = top:pheight:bottom;

xs = [data.x]; ys = [data.y];

I = histcounts2(ys, xs, yedges, xedges);
