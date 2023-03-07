function Iall = calibrate_emccd(Iall, specs, timestamp)

% In this case specs has fields:
% offset % counts
% gain % counts/photon

offset = specs.offset;
EM_gain = timestamp.EMCCD_gain;
if EM_gain == 0
    EM_gain = 1;
end

% sensitivity
if isfield(timestamp, 'sensitivity')
    sensitivity = timestamp.sensitivity;
    read_noise = 50.0;
else
    switch specs.name
        case 'iXon 888'
            if timestamp.Speed_value == 0
                if timestamp.preamp_gain == 2
                    sensitivity = 11.7;
                    read_noise = 50.0;
                elseif timestamp.preamp_gain == 1
                    sensitivity = 25.2;
                    read_noise = 58.4;
                elseif timestamp.preamp_gain == 0
                    sensitivity = 60.2;
                    read_noise = 90.3;
                end
            elseif timestamp.Speed_value == 1
                if timestamp.preamp_gain == 2
                    sensitivity = 9.8;
                    read_noise = 38.2;
                elseif timestamp.preamp_gain == 1
                    sensitivity = 22.0;
                    read_noise = 48.8;
                elseif timestamp.preamp_gain == 0
                    sensitivity = 53.2;
                    read_noise = 79.3;
                end
            elseif timestamp.Speed_value == 2
                if timestamp.preamp_gain == 2
                    sensitivity = 9.9;
                    read_noise = 29.5;
                elseif timestamp.preamp_gain == 1
                    sensitivity = 21.9;
                    read_noise = 36.4;
                elseif timestamp.preamp_gain == 0
                    sensitivity = 52.9;
                    read_noise = 59.3;
                end
            elseif timestamp.Speed_value == 3
                if timestamp.preamp_gain == 2
                    sensitivity = 3.9;
                    read_noise = 18.5;
                elseif timestamp.preamp_gain == 1
                    sensitivity = 8.4;
                    read_noise = 21.6;
                elseif timestamp.preamp_gain == 0
                    sensitivity = 21.0;
                    read_noise = 35.5;
                end
            end
        otherwise
            warning('I don''t know that camera, using default sensitivity');
            sensitivity = 11.7;
            read_noise = 50.5;
    end
end

% Do the calibration.
% offset is the baseline offset (typically 100 counts)
% sensitivity is the e-/count of the output amplifier (depends on gain
% and shift_speed
% read_noise is the output read noise standard deviation (in e- equivalent)
% it's added here to satisfy the var(signal) == mean(signal) requirement of
% poisson mle fitting
% EM_gain is the gain of the electron multiplication
% the factor of sqrt(2) accounts for the noise generated by electron multiplication
Iall = ((double(Iall) - offset) * sensitivity + read_noise)/ EM_gain / sqrt(2);
