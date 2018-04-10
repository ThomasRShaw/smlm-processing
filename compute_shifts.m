function [shifteddata, diag] = compute_shifts(data, timings, specs)

olddata = data;
% Put the data in the right shape
if size(data,2) ~= numel(data)
    data = reshape(data', 1, numel(data));
end

% Get parameters
nTimeBin = round(specs.npoints_for_alignment);
binwidth = round(specs.nframes_per_alignment);
nframes = numel(data);

psize = specs.psize_for_alignment;
rmax1 = specs.rmax_shift;
rmax = specs.rmax;
update = specs.update_reference_flag;
interp_method = specs.interp_method;
include_diagnostics = specs.include_diagnostics;

% Compute which frames belong to which time bins
binspacing = (nframes - binwidth)/(nTimeBin-1);
firstframe = round(1 + (0:nTimeBin-1)*binspacing);
lastframe = min(nframes, firstframe + binwidth);

% Initialize some stuff
xshift = zeros(nTimeBin,1);
yshift = zeros(nTimeBin,1);

dxshift = zeros(nTimeBin,1);
dyshift = zeros(nTimeBin,1);

amp = zeros(1, nTimeBin);
width = zeros(1, nTimeBin);

goodinitial = true(1,nTimeBin);
npoints = zeros(1,nTimeBin);

if include_diagnostics
    finalfits = cell(1,nTimeBin);
    Csms = cell(1,nTimeBin);
end

% helper function for getting data
getnthdata = @(n) data(firstframe(n):lastframe(n));

% useful numbers for initial fit
rmaxpx1 = ceil(rmax1/psize);
npx1 = 2*rmaxpx1 + 1;
pxrange1 = (-rmaxpx1):rmaxpx1;
[x1,y1] = meshgrid(1:npx1, 1:npx1);

% useful numbers for second fit
rmaxpx= ceil(rmax/psize);
npx = 2*rmaxpx + 1;
pxrange = (-rmaxpx):rmaxpx;
[x,y] = meshgrid(1:npx, 1:npx);

% make a fittype for the gaussian
fitgauss = fittype(...
    @(A,s,x0,y0,c,x,y) A*exp(-((x0-x).^2 + (y0-y).^2)/(2*s.^2)) + c,...
        'coefficients', {'A', 's', 'x0', 'y0','c'},...
        'indep', {'x', 'y'}, 'dep', 'z');
    
% Fit options for first fit, using L-M
fgo1 = fitoptions(fitgauss);
fgo1.Algorithm = 'Levenberg-Marquardt';

% Fit options for more refined fit, using Trust-Region algorithm
fgo = fitoptions(fitgauss);
fgo.Lower = [1,0,1,1,0];
fgo.Upper = [Inf,Inf,npx,npx,Inf];

% Compute xcors, and resulting offsets
refdata = getnthdata(1);
npoints(1) = numel([refdata.x]);
refbin = 1;
while npoints(refbin) == 0;
    refbin = refbin + 1;
    if refbin > nTimeBin
        error('None of the timebins contain points!')
    end
    refdata = getnthdata(refbin);
    npoints(refbin) = numel([refdata.x]);
end

for i = (refbin + 1):nTimeBin
    thisdata  = getnthdata(i);

    npoints(i) = numel([thisdata.x]);
    if npoints(i) == 0
        continue;
    end
        
    C = xcor_dirty(refdata, thisdata, psize, rmax);
    
    % First fit, large box centered on no shift
    smallinds1 = round(size(C,1)/2) + pxrange1;
    smallinds2 = round(size(C,2)/2) + pxrange1;

    Csm = C(smallinds1, smallinds2);

    cx = mean((1:npx1).* mean(Csm, 1))/ mean(Csm(:));
    cy = mean((1:npx1).* (mean(Csm, 2)'))/mean(Csm(:));

    fgo1.StartPoint = [Csm(round(cy),round(cx)), 2/psize, cx, cy, 0];
    F1 = fit([x1(:), y1(:)], Csm(:), fitgauss,fgo1);
    
    if F1.s < 2/psize % First fit is good enough
        xshift(i) = (F1.x0 - rmaxpx1 - 1)*psize;
        yshift(i) = (F1.y0 - rmaxpx1 - 1)*psize;

        finalfit = F1; %for extracting parameters for diag
    else
        outofframe = F1.x0 < rmaxpx || F1.x0 > npx1 - rmaxpx ||...
                        F1.y0 < rmaxpx || F1.y0 > npx1 - rmaxpx;
        % Fail if the first fit was off the large fitting frame
        % Not sure if this is the best way to go yet, we'll see how
        % often this happens
        if outofframe
            error(['First fit gave a result bigger than rmax_shift.\n'...
                'Try changing the value?']);
        end
        goodinitial(i) = false;
        smallinds1 = round(F1.y0) + pxrange;
        smallinds2 = round(F1.x0) + pxrange;
        
        fgo.StartPoint = [Csm(round(F1.y0), round(F1.x0)), 2/psize, ...
            rmaxpx+1, rmaxpx+1, 0];

        Csm = Csm(smallinds1, smallinds2);
        F = fit([x(:), y(:)], Csm(:), fitgauss, fgo);
        
        xshift(i) = (F.x0 - rmaxpx - 1 + round(F1.x0) - rmaxpx1 - 1)*psize;
        yshift(i) = (F.y0 - rmaxpx - 1 + round(F1.y0) - rmaxpx1 - 1)*psize;

        finalfit = F; %for extracting parameters for diag
    end
    
    % extract parameters
    CI = confint(finalfit, .34);
    d = .5*(diff(CI, 1)); % standard errors
    dxshift(i) = d(3);
    dyshift(i) = d(4);
    
    amp(i) = finalfit.A;
    width(i) = finalfit.s*psize;

    if include_diagnostics
        finalfits{i} = finalfit;
        Csms{i} = Csm;
    end
    
    % Use this to debug large shifts
%     if max(xshift(i), yshift(i)) > 2
%         keyboard;
%     end
    
    % Also TODO: handle update_reference_image flag
end

% interpolate
if isempty(timings)
    timings = 1:nframes;
end

midtiming = zeros(1,nTimeBin);
for i  = 1:nTimeBin
    midtiming(i) = mean(timings(firstframe(i):lastframe(i)));
end

xfit = interp1(midtiming, xshift, timings, interp_method, 'extrap');
yfit = interp1(midtiming, yshift, timings, interp_method, 'extrap');

% Diagnostics?
diag.xshift = xshift;
diag.yshift = yshift;
diag.dxshift = dxshift;
diag.dyshift = dyshift;
diag.amplitude = amp;
diag.fitwidth = width;
diag.xfit = xfit;
diag.yfit = yfit;
diag.timings = timings;
diag.midtiming = midtiming;
if include_diagnostics
    diag.finalfits = finalfits;
    diag.Csms = Csms;
end

shifteddata = apply_shifts(olddata, diag);
