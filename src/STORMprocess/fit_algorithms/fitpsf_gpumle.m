function [ data ] = fitpsf_gpumle(psfstack, bgstack, fittype, specs)
% [ DATA ] = FITPSF_GPUMLE(PSFSTACK, BGSTACK, FITTYPE, SPECS)

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
    psf = specs.PSFwidth;
    dL = round(specs.r_centroid);
    iters = specs.mle_iters;
    
    n = size(psfstack,3);
    if ~(size(psfstack) == size(bgstack)),
        error('fitpsf_gpumle: size of psfstack and bgstack must be equal!');
    end

    bgmeans = repmat(mean(mean(bgstack,1),2),2*dL + 1,2*dL + 1);

    % Do fitting
    n = size(psfstack,3);
    switch specs.bg_method,
        case {'standard','unif'}
            stk = single(psfstack);
            if strcmp(specs.bg_method, 'standard')
                stk = stk-single(bgstack)+single(bgmeans);
            end

            if specs.fitsigma
                fittype=2;
            else
                fittype=1;
            end
            [P, CRLB, LL, t] = gaussmlev2(stk,psf,iters,fittype);
        case 'true'
            stk = single(psfstack);
            if specs.fitsigma
                fittype=5;
            else
                fittype=6;
            end
            [P, CRLB, LL, t] = gaussmlev2(stk,psf,iters,fittype,single(bgstack));
        otherwise
            error(['no such bg_method: ', specs.bg_method]);
    end

    fprintf('GPUgaussMLEv2 completed %d fits in %f s\n', n, t);

    % Extract data ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    data.xroi = P(:,2)' - dL; data.yroi = P(:,1)' - dL; % positions wrt center of fitting region
    data.I = P(:,3)'; % Fitted intensity
    if specs.fitsigma,
        data.widthxx = P(:,5)';
        data.widthyy = data.widthxx;
        data.d = data.widthxx;
        data.errorsigma = sqrt(CRLB(:,5)');
%    else
%        data.widthxx = psf*ones(1,n); %P(:,5);
%        data.widthyy = data.widthxx; % widths are same
%        data.d = data.widthxx;
    end
    data.errorx = sqrt(CRLB(:,2)'); data.errory = sqrt(CRLB(:,1)'); % estimated fit errors
    data.bg = P(:,4)';
    data.errorI = sqrt(CRLB(:,3)');
    data.errorbg = sqrt(CRLB(:,4)');
    data.LL = LL';
    
end
