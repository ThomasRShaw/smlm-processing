function [Imerge, If, ir] = imerge_from_imagestruct(istruct)

if isfield(istruct, 'data') && ~isempty(istruct.data)
    ds = istruct.data;
elseif isfield(istruct, 'data_fname') && ~isempty(istruct.data_fname)
    ds = load(istruct.data_fname);
else
    error('imerge_from_imagestruct: no data or data_fname');
end

if numel(ds.data) ~= istruct.channels
    error('imerge_from_imagestruct: data has different number of channels from imagestruct');
end

if ~strcmp(ds.units, istruct.units)
    error('imerge_from_imagestruct: data has different units from imagestruct');
end

if isfield(istruct, 'imageref')
    ir = istruct.imageref;
else
    ir = default_iref(ds.data{1}, istruct.psize);
end

cm_size = 64;
cm = gray(cm_size);
Imerge = zeros(ir.ImageSize);
% Make images for each channel
for i = 1:istruct.channels
    d = ds.data{i};

    I = reconstruct(d, ir);

    % sigmas need to be in units of reconstruction pixels
    sigma = istruct.sigmablur(i)/istruct.psize; 

    PSF = 2*pi*sigma^2*fspecial('gaussian', ceil(4*sigma), sigma);

    Iblur = imfilter(I, PSF, 'replicate');

    cmin = istruct.cmin(i);
    cmax = istruct.cmax(i);

    % scale to a color
    col = col2rgb(istruct.color{i});

    If{i} = ind2rgb( 1 + uint8((cm_size - 1)*(Iblur - cmin)/(cmax - cmin)), ...
                        cm*diag(col));

    Imerge = Imerge + If{i};
end


function rgb = col2rgb(col)
if isnumeric(col) && size(col) == [1 3]
    rgb=col;
else
    if ~ischar(col)
        error('col2rgb: col must be a string or a 1x3 matrix');
    end
    switch col
        case {'y', 'yellow'}
            rgb = [1 1 0];
        case {'m', 'magenta'}
            rgb = [1 0 1];
        case {'c', 'cyan'}
            rgb = [0 1 1];
        case {'r', 'red'}
            rgb = [1 0 0];
        case {'g', 'green'}
            rgb = [0 1 0];
        case {'b', 'blue'}
            rgb = [0 0 1];
        case {'w', 'white'}
            rgb = [1 1 1];
        case {'k', 'black'}
            rgb = [0 0 0];
    end
end