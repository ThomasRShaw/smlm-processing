function [c, err] = xcor_crosspairs_bandwidth(pts1, pts2, r, bandwidth, maskx, masky)
% [C, ERR] = XCOR_CROSSPAIRS_BANDWIDTH(PTS1, PTS2, R, BANDWIDTH, MASKX, MASKY)

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
    X1 = PTS1(:,1);
    y1 = pts1(:,2);
    x2 = pts2(:,1);
    y2 = pts2(:,2);
    
    rs_for_bins = sort(unique([r + bandwidth/2, r - bandwidth/2]));
    iminus = r;
    iplus = r;
    
    rs_for_bins = unique(max(rs_for_bins,0));
    
    for i = 1:numel(r)
        if (r(i) - bandwidth/2 < 0)
            iminus(i) = 1;
        else
            iminus(i) = find(rs_for_bins == r(i) - bandwidth/2);
        end
        iplus(i) = find(rs_for_bins == r(i) + bandwidth/2)-1;
    end

    t1 = zeros(size(x1)); % collapse in tau
    t2 = zeros(size(x2));
    taumin = 0; taumax = 0; noutmax = 5e8;
    [dx, dy] = crosspairs(x1, y1, t1, x2, y2, t2, max(rs_for_bins), taumin, taumax, noutmax);
    dr = sqrt(dx.^2 + dy.^2);
    if numel(dx) == noutmax
        warning('Too many pairs! Consider taking a smaller number of data frames or lowering rmax.')
    end
    % get rid of localizations paired with themselves
    bad_inds = (dr == 0);
    dx = dx(~bad_inds); dy = dy(~bad_inds); dr = dr(~bad_inds); 
    
    pc_bins = histcounts(dr, rs_for_bins);
    
    pc = zeros(size(r));
    for i = 1:numel(r)
        pc(i) = sum(pc_bins(iminus(i):iplus(i)));
    end

    n1 = numel(x1); n2 = numel(x2);
    lambda_fac = polyarea(maskx, masky)^2/(n1*n2);
    
    edge_cor = edge_correction(maskx, masky, r);
    
    % the pair correlation
    c = pc ... % counts per distance bin
        .* lambda_fac ... % (lambda1*lambda2)^(-1)
        ./ (r .* bandwidth * 2 * pi) ... % area of bin: 2 pi r delta_r
        ./ edge_cor; % average Ripley edge correction factor wij
    
    err = zeros(size(c));
end
