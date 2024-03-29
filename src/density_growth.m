function [density_cum, density_inc] = density_growth(is, fac)
% [DENSITY_CUM, DENSITY_INC] = DENSITY_GROWTH(IS, FAC)

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

% Set up fitting options
ff = fittype(@(peak,sd, x) exp(-(x.^2/(2*sd.^2)))*peak/(2*pi*sd.^2) + 1);
fo = fitoptions(ff);
fo.StartPoint = [1e7, 30];
fo.Lower = [0 0];

% load data 
if isempty(is.data)
    if isempty(is.data_fname)
        error('no data in imagestruct');
    else
        is.data = load(is.data_fname);
    end
end

data = is.data.data;
is_short = is;

% this is for setting density units at the end
if nargin < 2
    switch is.data.units
        case 'nm'
            fac = 1e3;
        case 'um'
            fac = 1;
        case 'px'
            fac = 1/.160;
    end
end

nchan = is.channels;

r_auto = (10:10:300)*1e3/fac;
for j = 1:size(is.data.data{1},1)
    is.data.data = cellfun(@(d) d(1:j,:), data, 'UniformOutput', false);
    is_short.data.data = cellfun(@(d) d(j,:), data, 'UniformOutput', false);
    
    nm = numel(is.maskx);
    
    g = acors_from_imagestructs(is, r_auto);
    if nargout > 1
        g_short = acors_from_imagestructs(is_short, r_auto);
    end
    
    for i = 1:nm
%         A(i) = polyarea(is.maskx{i}, is.masky{i});
%         data = apply_mask(is.data.data{nc}, is.maskx{i}, is.masky{i});
%         n_loc(i) = sum(arrayfun(@(s) numel(s.x), is.data.data(:)));
%         n_loc_short(i) = sum(arrayfun(@(s) numel(s.x), data(:)));
        
        for ichan = 1:nchan
            gf = fit(r_auto' - 5*1e3/fac, g{ichan}(i,:)', ff, fo);
            density_cum{ichan}(i,j) = fac^2/gf.peak;
            if nargout > 1
                gf_short = fit(r_auto' - 5*1e3/fac, g_short{ichan}(i,:)', ff, fo);
                density_inc{ichan}(i,j) = fac^2/gf_short.peak;
            end
        end
    end
end
% 
% loc_dens = n_loc ./ A * fac^2;
% overcounting = loc_dens./channel_density;

figure;
for i = 1:numel(density_cum)
    plot(density_cum{i}');
    hold on;
    
    if nargout > 1
        plot(density_inc{i}');
    end
end
hold off
