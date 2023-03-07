function [ data ] = fitpsf_gpuspline(psfstack, bgstack, fittype, specs, coeff)
    psf = specs.PSFwidth;
    dL = round(specs.r_centroid);
    iters = specs.mle_iters;
    
    n = size(psfstack,3);
    if ~(size(psfstack) == size(bgstack))
        error('fitpsf_gpumle: size of psfstack and bgstack must be equal!');
    end

    bgmeans = repmat(mean(mean(bgstack,1),2),2*dL + 1,2*dL + 1);

    % Do fitting
    tic
    n = size(psfstack,3);
    switch specs.bg_method
        case {'standard','unif'}
            stk = single(psfstack);
            %if strcmp(specs.bg_method, 'standard')
            stk = stk-single(bgstack)+single(bgmeans);
            %end
            fittype=5;
            fitpar=single(coeff);
            varstack=0;
            [P, CRLB, LL] = mleFit_LM(stk,fittype,iters,fitpar,varstack,1);
        otherwise
            error(['no such bg_method: ', specs.bg_method]);
    end
    t = toc;
    fprintf('GPUgaussMLEv2 completed %d fits in %f s\n', n, t);

    % Extract data ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    data.xroi = P(:,2)' - dL; data.yroi = P(:,1)' - dL; % positions wrt center of fitting region
    data.z = P(:,5)';
    data.I = P(:,3)'; % Fitted intensity
    data.bg = P(:,4)';
    data.errorx = sqrt(CRLB(:,2)');
    data.errory = sqrt(CRLB(:,1)');
    data.errorz = sqrt(CRLB(:,5)');
    data.errorI = sqrt(CRLB(:,3)');
    data.errorbg = sqrt(CRLB(:,4)');
    data.LL = LL';
    
    
end
