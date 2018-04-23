function varargout = coriolis_gui(varargin) %#ok<*NASGU>
% CORIOLIS_GUI MATLAB code for coriolis_gui.fig
%      CORIOLIS_GUI, by itself, creates a new CORIOLIS_GUI or raises the existing
%      singleton*.
%
%      H = CORIOLIS_GUI returns the handle to a new CORIOLIS_GUI or the handle to
%      the existing singleton*.
%
%      CORIOLIS_GUI('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in CORIOLIS_GUI.M with the given input arguments.
%
%      CORIOLIS_GUI('Property','Value',...) creates a new CORIOLIS_GUI or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before coriolis_gui_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to coriolis_gui_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help coriolis_gui

% Last Modified by GUIDE v2.5 23-Apr-2018 13:30:33

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @coriolis_gui_OpeningFcn, ...
                   'gui_OutputFcn',  @coriolis_gui_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

function coriolis_gui_OpeningFcn(hObject, ~, handles, varargin)
handles.output = hObject;

% Deal with files and stuff
handles.here = cd;
handles.record_fname = 'record.mat';
handles = load_all(handles);

guidata(hObject, handles);


function varargout = coriolis_gui_OutputFcn(hObject, ~, handles)
varargout{1} = handles.output;

%% My functions
function set_fname_fields(handles)
record = handles.record;

set(handles.fname_text, 'String', handles.record_fname);

% set edit fields to show real filenames
set(handles.fits_fname_edit, 'String', record.fits_fname);
set(handles.transformed_fname_edit, 'String', record.transformed_fname);
set(handles.dilated_fname_edit, 'String', record.dilated_fname);
set(handles.culled_fname_edit, 'String', record.culled_fname);
set(handles.final_fname_edit, 'String', record.final_fname);

function handles = load_all(handles)
% record
record = load_record(handles.record_fname);
handles.record = record;

set_fname_fields(handles);

cd(handles.here);

% datasets
fnames = {record.fits_fname, record.transformed_fname, ...
    record.dilated_fname, record.culled_fname, record.final_fname};
snames = {'fits', 'transformed', 'dilated', 'culled', 'final'};

ask_if_older = true;

% for each dataset
for i = 1:numel(fnames)
    if isfield(handles, snames{i})
        s = handles.(snames{i});
    else
        s = [];
    end
    
    % decide whether to load, depending on dates and user input
    if exist(fnames{i}, 'file')
        ss = load(fnames{i}, 'date');
        
        if ~isfield(handles, snames{i}) || isempty(handles.(snames{i}))
            timediff = Inf;
        else
            timediff = ss.date - handles.(snames{i}).date;
        end
        
        if timediff == 0
            % loaded file and saved file are the same
            loadthis = false;
        elseif timediff < 0 && ask_if_older
            % file is older, ask what to do
            msg = {sprintf(...
                'File for %s is older than the struct in memory',...
                snames{i}), 'What should I do?'};
            answer = questdlg(msg, 'Overwrite struct?', ...
                'Load', 'Skip', 'Load all',...
                'Load');
            switch answer
                case 'Skip'
                    loadthis = false;
                case 'Load all'
                    loadthis = true;
                    ask_if_older = false;
                case 'Load'
                    loadthis = true;
            end
        else
            loadthis = true;
        end
    else
        loadthis = false;
    end
    
    stat_field = [snames{i} '_stat'];        
    if loadthis
        s.date = ss.date;
        s.data = [];
        s.fname = fnames{i};
        status_str = {'loaded from file', char(s.date)};
        if isfield(handles, stat_field)
            set(handles.(stat_field), 'String', status_str);
        end
    end

    handles.(snames{i}) = s;
        
end
guidata(handles.figure1, handles);

%TODO: skip if data are the same age as the file
%TODO: generalize, via a savedataset function (culled is done right, the
%others aren't quite)
function save_all(handles)
record = handles.record;

cd(handles.here);

% save record
save(handles.record_fname, '-struct', 'record');

% save fits
if isfield(handles, 'fits') && ~isempty(handles.fits)
    fits = getdataset(handles, 'fits');
    save(record.fits_fname, '-struct', 'fits')
else
    warning('no fits to save');
end

% save transformed
if ~isempty(record.transformed_fname)
    if isfield(handles, 'transformed') && ~isempty(handles.transformed)
        transformed = getdataset(handles, 'transformed');
        save(record.transformed_fname, '-struct', 'transformed')
    else
        warning('no transformed data to save');
    end
end

% save dilated
if isfield(handles, 'dilated') && ~isempty(handles.dilated)
    dilated = getdataset(handles, 'dilated');
    save(record.dilated_fname, '-struct', 'dilated')
else
    warning('no dilated data to save');
end

% save culled
if ~isempty(record.culled_fname)
    if isfield(handles, 'culled') && ~isempty(handles.culled)
        culled = getdataset(handles, 'culled');
        save(record.culled_fname, '-struct', 'culled')
    else
        warning('no culled data to save');
    end
end

% save final data
if isfield(handles, 'final') && ~isempty(handles.final)
    final = getdataset(handles, 'final');
    save(record.final_fname, '-struct', 'final')
else
    warning('no drift-corrected data to save');
end

function record = load_record(fname)
if exist(fname, 'file')
    record = load(fname);
else
    record = SP_record_default();
end

function specs = getspecs(handles)
r = handles.record;
if isfield(r, 'SPspecs') && check_STORMprocess_specs(r.SPspecs)
    specs = r.SPspecs;
else
    error('record didn''t have a valid specs yet');
end

function d = getdataset(handles, name)
if isempty(handles.(name))
    d = [];
    return;
end

if ~isempty(handles.(name).data) % data is in memory
    d = handles.(name);
else
    now_here = cd;
    cd(handles.here);
    handles.(name) = load(handles.(name).fname);
    d = handles.(name);
    guidata(handles.figure1, handles);
    cd(now_here);
end


%% Callbacks
function choose_button_Callback(hObject, ~, handles) %#ok<*DEFNU>
[fname, fpath] = uigetfile('.mat','Choose a processing record...');
if fname == 0 % This means user pressed cancel
    return; % do nothing
end

handles.here = fpath;
cd(fpath);

handles.record_fname = fname;

handles = load_all(handles);

guidata(hObject, handles);

function runall_button_Callback(hObject, ~, handles)
dofits_button_Callback(hObject, [], handles);
geo_button_Callback(hObject, [], handles);
cull_button_Callback(hObject, [], handles);
compute_drift_button_Callback(hObject, [], handles);

function edit_fitspecs_button_Callback(hObject, ~, handles)
error('not implemented');

function dofits_button_Callback(hObject, ~, handles)
% Handle prereqs
specs = getspecs(handles);

% Do fitting
set(handles.fits_stat, 'String', 'Fitting ...');
drawnow;

[data, ~] = STORMprocess(specs);

fits.data = data;
fits.date = datetime;
fits.produced_by = 'STORMprocess';
fits.units = 'px';

handles.fits = fits;
guidata(hObject, handles);
set(handles.fits_stat, 'String', {'done', char(fits.date)});

function choose_transform_button_Callback(hObject, ~, handles)
[fname, fpath] = uigetfile('.mat','Choose a transform...');
if fname == 0 % This means user pressed cancel
    return; % do nothing
end

fname = [fpath, fname];

handles.record.dv_transform_fname = fname;

guidata(hObject, handles);

function geo_button_Callback(hObject, ~, handles)
% Prereqs
SPspecs = getspecs(handles);
cspecs = SPspecs.camera_specs;

fits = getdataset(handles, 'fits');
%fits = handles.fits;
if isempty(fits)
    error('geometry: No fits yet, aborting');
end

transf_fname = handles.record.dv_transform_fname;
if exist(transf_fname, 'file')
    % the transform structures only have reverse transforms,
    % so we need T_1_2 to transform 2->1
    tf = load(transf_fname, 'T_1_2');
    tf = tf.T_1_2;
else
    error('dualview transform file not specified or does not exist');
end

% transform
set(handles.dilated_stat, 'String', 'Applying Transform ...');
drawnow;

[tfdata] = apply_transform(fits.data{2}, tf);

transformed.data = {fits.data{1}, tfdata};
transformed.date = datetime;
transformed.produced_by = 'apply_transform';
transformed.units = 'px';

handles.transformed = transformed;

% pixel size
set(handles.dilated_stat, 'String', 'Converting to nm ...');
drawnow;

dilatefac = cspecs.pixel_size / cspecs.magnification * 1e3; %to nm

% apply the dilation to each channel
dilateddata = cellfun(@(d) dilatepts(d, dilatefac), transformed.data,...
                'UniformOutput', false);

dilated.data = dilateddata;
dilated.date = datetime;
dilated.units = 'nm';
dilated.produced_by = 'dilatepts';

handles.dilated = dilated;

guidata(hObject, handles);
set(handles.dilated_stat, 'String', {'done', char(dilated.date)});

function cullspec1_button_Callback(hObject, ~, handles)
cs1 = handles.record.cullspecs{1};
cs1 = cullspec_gui(cs1, handles.dilated.data{1});
handles.record.cullspecs{1} = cs1;
guidata(hObject, handles);

function cullspec2_button_Callback(hObject, ~, handles)
handles.record.cullspecs{2} = cullspec_gui(handles.record.cullspecs{2}, ...
    handles.dilated.data{2});
guidata(hObject, handles);

function cull_button_Callback(hObject, ~, handles)
% Prerequisites
if ~isfield(handles.record, 'cullspecs')
    nocs = 1;
else
    nocs = 0;
    cs = handles.record.cullspecs;
end

if nocs || isempty(cs) || isempty(cs{1}) || isempty(cs{2})
    error('cull: no cull specs, aborting');
end

if isempty(handles.dilated)
    error('cull: no data from geometry step, aborting');
end

% do culling
set(handles.culled_stat, 'String', 'Culling ...');
drawnow;

dilated = getdataset(handles, 'dilated');

culled.data = cell(1,2);
culled.data{1} = cullSTORM(dilated.data{1}, cs{1});
culled.data{2} = cullSTORM(dilated.data{2}, cs{2});

culled.date = datetime;
culled.produced_by = 'cullSTORM';
culled.units = 'nm';

handles.culled = culled;
guidata(hObject, handles);
set(handles.culled_stat, 'String', {'done ' char(culled.date)});

function driftspec_button_Callback(hObject, ~, handles)
error('not implemented');

function compute_drift_button_Callback(hObject, ~, handles)
% check prereqs
if ~isfield(handles.record, 'driftspecs')
    nods = 1;
else
    nods = 0;
    driftspecs = handles.record.driftspecs;
end

if nods || isempty(driftspecs)
    error('drift correction: no drift specs, aborting');
end

if isempty(handles.culled)
    error('drift correction: no culled data, aborting');
end

% do drift correction
set(handles.final_stat, 'String', 'Correcting Drift ...');
drawnow;

culled = getdataset(handles, 'culled');

final.data = cell(1,2);
%TODO: correct timing data!
[final.data{1}, drift_info] = compute_drift(culled.data{1}, [], driftspecs);
[final.data{2}] = apply_shifts(culled.data{2}, drift_info);

final.date = datetime;
final.produced_by = 'compute_drift';
final.units = 'nm';
final.drift_info = drift_info;

handles.final = final;

guidata(hObject, handles);
set(handles.final_stat, 'String', {'done', char(final.date)});

function save_button_Callback(~, ~, handles)
save_all(handles);

function fname_edit_Callback(hObject, ~, handles)
fname_name = hObject.Tag(1:end-5);
fname = get(hObject, 'String');
if iscell(fname) % This happened once, never figured out why
    fname = fname{1};
end

% add .mat if appropriate
if length(fname) < 4 || ~strcmp(fname((end-3):end), '.mat')
    fname = [fname '.mat'];
end
set(hObject, 'String', fname);

handles.record.(fname_name) = fname;

guidata(hObject, handles);

function fork_record_button_Callback(hObject, ~, handles)
% Get filename for new record
titlestr = 'Fork record...';
answer = inputdlg('Input name for new record file:', titlestr);

if isempty(answer) % user pressed cancel
    return;
end

record_fname = answer{1};
record = handles.record;

if length(answer) < 4 || ~strcmp(answer((end-3):end), '.mat')
    record_fname = [record_fname, '.mat'];
end

% Ask user where fork should happen
liststr = {'fits', 'transform', 'dilation', 'culling', 'drift correction'};
prompt = 'What processing step do you want to fork before?';

[selection, ok] = listdlg('PromptString', prompt, 'ListString', liststr,...
    'SelectionMode', 'single', 'Name', titlestr, 'ListSize', [250, 100]);

if ok == 0 % user pressed cancel
    return;
end

% Prefix to prepend to new filenames
answer = inputdlg('Choose a prefix for the new data file names:', titlestr);
if isempty(answer) % user pressed cancel
    return;
end

prefix = answer{1};

% put prefix on the filenames that will be different after the fork
if selection < 2 && ~isempty(record.fits_fname) % fits gets renamed
    record.fits_fname = [prefix, record.fits_fname];
end
if selection < 3 && ~isempty(record.transformed_fname) % tf gets renamed
    record.transformed_fname = [prefix, record.transformed_fname];
end
if selection < 4 && ~isempty(record.dilated_fname) % dilated gets renamed
    record.dilated_fname = [prefix, record.dilated_fname];
end
if selection < 5 && ~isempty(record.culled_fname) % dilated gets renamed
    record.culled_fname = [prefix, record.culled_fname];
end
if selection < 6 && ~isempty(record.final_fname) % final gets renamed
    record.final_fname = [prefix, record.final_fname];
end

handles.record = record;
handles.record_fname = record_fname;

set_fname_fields(handles);
guidata(hObject, handles);
