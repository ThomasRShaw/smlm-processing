function varargout = res_specs_gui(varargin)
% RES_SPECS_GUI MATLAB code for res_specs_gui.fig
%      RES_SPECS_GUI, by itself, creates a new RES_SPECS_GUI or raises the existing
%      singleton*.
%
%      H = RES_SPECS_GUI returns the handle to a new RES_SPECS_GUI or the handle to
%      the existing singleton*.
%
%      RES_SPECS_GUI('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in RES_SPECS_GUI.M with the given input arguments.
%
%      RES_SPECS_GUI('Property','Value',...) creates a new RES_SPECS_GUI or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before res_specs_gui_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to res_specs_gui_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

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
% Edit the above text to modify the response to help res_specs_gui

% Last Modified by GUIDE v2.5 04-Mar-2023 04:19:23

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @res_specs_gui_OpeningFcn, ...
                   'gui_OutputFcn',  @res_specs_gui_OutputFcn, ...
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


% --- Executes just before res_specs_gui is made visible.
function res_specs_gui_OpeningFcn(hObject, eventdata, handles, varargin)
handles.to_return = nargout;

if numel(varargin) < 1
    error('Not enough arguments for res_specs_gui. 1 required')
end

handles.specs = varargin{1};

specs_version = 0.1;
% Fill in missing values from default
handles.specs = validate_res_specs(handles.specs, specs_version);

update_fields_from_specs(handles);
handles.output = handles.specs;

% Update handles structure
guidata(hObject, handles);

% --- Outputs from this function are returned to the command line.
function varargout = res_specs_gui_OutputFcn(hObject, eventdata, handles) 
handles.to_return = nargout;
guidata(hObject, handles);

if nargout > 0
    uiwait(handles.figure1);
    handles = guidata(hObject);
    
    varargout{1} = handles.output;
    delete(handles.figure1);
end

function update_fields_from_specs(handles)
s = handles.specs;

set(handles.Npts_edit, 'String', num2str(s.Npts));
set(handles.rmax_edit, 'String', num2str(s.rmax));
set(handles.binsize_edit, 'String', num2str(s.binsize));

set(handles.show_diagnostics_checkbox, 'value', s.show_diagnostics)

units_options = {'nm', 'px'};
set(handles.units_menu, 'String', units_options);
set(handles.units_menu, 'Value', find(strcmp(units_options, s.units)));

function specs = update_specs_from_fields(handles)
s = handles.specs;
s.Npts = round(str2double(get(handles.Npts_edit, 'String')));
s.rmax = round(str2double(get(handles.rmax_edit, 'String')));
s.binsize = round(str2double(get(handles.binsize_edit, 'String')));

s.show_diagnostics = get(handles.show_diagnostics_checkbox, 'value');

units_options = get(handles.units_menu, 'String');
s.units = units_options{get(handles.units_menu, 'value')};

specs = s;

% --- Executes on button press in return_button.
function return_button_Callback(hObject, eventdata, handles)
% hObject    handle to return_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.specs = update_specs_from_fields(handles);

handles.output = handles.specs;
guidata(hObject, handles);
uiresume(handles.figure1);

if ~handles.to_return
    delete(handles.figure1)
end
