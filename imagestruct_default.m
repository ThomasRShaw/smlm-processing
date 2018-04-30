function is = imagestruct_default(fname)

if ischar(fname)
    ds = load(fname);
    is.data_fname = fname;
    is.data = [];
else
    ds = fname;
    is.data = ds;
    is.data_fname = [];
end

nchan = numel(ds.data);
is.channels = nchan;
is.units = ds.units;
switch is.units
    case 'nm'
        fac = 1;
    case 'um'
        fac = 1e-3;
    case 'px'
        fac = 1/160;
end
is.psize = 16*fac;
is.imageref = default_iref(ds.data{1}, is.psize);
is.sigmablur = repmat(20, 1, nchan)*fac;
is.cmin = zeros(1, nchan);
is.cmax = is.cmin + 5;
if nchan == 1
    is.color = {'white'};
else
    is.color = {'green', 'magenta'};
end