function adata = get_adata_from_imagedata(imdata_fname)
% ADATA = GET_ADATA_FROM_IMAGEDATA(IMDATA_FNAME)

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

if isnumeric(imdata_fname)
    switch imdata_fname
        case 1
            imdata_fname = 'imagedata1.mat';
        case 2
            imdata_fname = 'imagedata2.mat';
        otherwise
            error('invalid input');
    end
end

load(imdata_fname, 'alignment_data');

adata.x = [alignment_data.alldata.x];
adata.y = [alignment_data.alldata.y];
adata.I = [alignment_data.alldata.I];
