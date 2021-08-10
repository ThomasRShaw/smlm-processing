function [iout, jout, status] = crosspairs_indices(x1, y1, t1, x2, y2, t2, rmax, mintau, maxtau, noutmax)
% the only advantage of using this over crosspairs_alloutputs is memory
% usage, since you only need to generate iout and jout

% Sort based on x. This is necessary for the crosspairs function
[x1_s, s1] = sort(x1(:));
x1_s = x1_s';
[x2_s, s2] = sort(x2(:));
x2_s = x2_s';

y1_s = y1(s1);
t1_s = t1(s1);
y2_s = y2(s2);
t2_s = t2(s2);

[iout_after, jout_after, status] = Fcrosspairs_indices(x1_s, y1_s, t1_s, x2_s, y2_s, t2_s, rmax, mintau, maxtau, int64(noutmax));
% status of 0 means okay, 1 means too many pairs

iout = s1(iout_after);
jout = s2(jout_after);
end