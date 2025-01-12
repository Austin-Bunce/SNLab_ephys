function split_dat(data_path,save_path, subject_order,varargin)
% split_dat for recordings of multiple animals from Intan RHX USB
% acquisition system. Assumes intan one data per data type format. Will
% split amplifer and aux by available ports by default.


% input:
%   data_path: path to file location with intan data to be split
%   save_path: cell array of paths to general directory where subject data folders are
%              located (one path per port)
%   subject_order: cell array with subject name (i.e. {'HPC01','HPC02'...}
%            will give data_path\HPC01, data_path\HPC02, ...). Order must
%            match order: Port A, Port B, Port C, Port D i.e. HPC01 was recording on 
%            Port A, HPC02 on Port B etc.
%
% variable arguments:
%   digitalin_order: numeric vector that signifies the digitalin channel
%           that corresponds to the port_order. Default is [2,3,4,5] so
%           events for port A would be on channel 1, port B channel 2, etc.
%

% TO-DO:
%  - Make dynamic input so multiple ports can be assiged to the same animal
%    for drives over 64 channels.
% - Add availablity to scan data_path\split_folder and automatically process folders that
%    have not yet been processed



% output:
%   saves the aux and amplifier dat file split by occupied ports into
%   folders determined by subject order.

% L Berkowitz 03/2022

p = inputParser;
addParameter(p,'digitalin_order',[2,3,4,5],@isnumeric) %snlab rig wiring for events
addParameter(p,'input_name',{'video','A','B','C','D'},@isnumeric) %snlab rig wiring 
addParameter(p,'trim_dat',false,@islogical) %snlab rig wiring 

parse(p,varargin{:});

digitalin_order = p.Results.digitalin_order;
input_name = p.Results.input_name;
trim_dat = p.Results.trim_dat; 


% identify inputs that require processing -- order of inputs is associated
% with port, so [0 0 1 1] would correspond to ports C and D, [1 0 0 0] port
% A, etc.
subject_idx = ~cellfun(@isempty,subject_order);

% Load info.rhd for port information
[amplifier_channels, ~, aux_input_channels, ~,...
    ~, ~, frequency_parameters,~ ] = ...
    read_Intan_RHD2000_file_snlab(data_path);

% make the basepath if its not already made
for port = find(subject_idx)
    basepath{port} = fullfile(save_path{port},filesep,subject_order{port},[subject_order{port},'_',basenameFromBasepath(data_path)]);
    
    if ~isfolder(basepath{port})
        mkdir(basepath{port})
    end
end

%% load digitalin channels for session start end times (first and last event per channel)
digitalIn = process_digitalin(data_path,frequency_parameters.board_dig_in_sample_rate);
%%
% Pull start and end from digitalin channels that correspond to dat
port = 1;
for channel =  digitalin_order(subject_idx)
    %timestamp multiplied by sample rate
    trim_dat_epoch(port,1) = digitalIn.timestampsOn{1, channel}(1)*...
        (frequency_parameters.board_dig_in_sample_rate);
    
    trim_dat_epoch(port,2) = digitalIn.timestampsOff{1,channel}(end)*...
        (frequency_parameters.board_dig_in_sample_rate);
    
    session_duration = (digitalIn.timestampsOff{1,channel}(end)...
        - digitalIn.timestampsOn{1, channel}(1))/60;
    
    disp(['port ',input_name{port},' recording was ',...
        num2str(session_duration),' minutes'])
    port = port+1;
end

% splits dat according to subject_order and saves to data_path
if trim_dat
    process_aux(data_path,aux_input_channels,subject_order,basepath,...
        'trim_dat_epoch',trim_dat_epoch);
    process_amp(data_path,amplifier_channels,frequency_parameters,...
        subject_order,basepath,'trim_dat_epoch',trim_dat_epoch);
else
    process_aux(data_path,aux_input_channels,subject_order,basepath);
    process_amp(data_path,amplifier_channels,frequency_parameters,...
        subject_order,basepath);

end

% Loop through folders.
% Order of folders should match port_order and digitalin_order
for port = find(~cellfun(@isempty,subject_order))
    
    % if video file with subid is present, move that to basepath
    if isfile([data_path,filesep,'*_',subject_order{port},'.avi'])
        movefile([data_path,filesep,'*_',subject_order{port},'.avi'],basepath{port})
    end
    
    % make copy of rhd, and setting to basepath
    copyfile([data_path,filesep,'settings.xml'],basepath{port});
    copyfile([data_path,filesep,'info.rhd'],basepath{port});

if trim_dat
    % create digitalIn event structure and save to basepath, and reset
    % relative to recording start and end
    parse_digitalIn(digitalIn,digitalin_order(port),basepath{port},'trim_dat_epoch',...
        trim_dat_epoch{port,:}*frequency_parameters.board_dig_in_sample_rate)
else
    % create digitalIn event structure and save to basepath
    parse_digitalIn(digitalIn,digitalin_order(port),basepath{port})
end
end


end


% Local functions
function process_aux(dat_path,aux_input_channels,folders,basepath,varargin)
% processes intan auxillary file and splits into separate files indicated
% by ports.
% input:
% - dat_path: path where auxiliary.dat is found
% - aux_input_channels: table containing metadata from intan RHD file
%   (output of read_Intan_RHD2000_file_snlab)
% - frequency_parameters: table containing metadata from intan RHD file
%   (output of read_Intan_RHD2000_file_snlab)
% - ports: cell array containing
% output:
% - saves port_aux.dat to dat_path
% LB 03/22

p = inputParser;
addParameter(p,'trim_dat_epoch',[],@isnumeric) %snlab rig wiring for events

parse(p,varargin{:});

trim_dat_epoch = p.Results.trim_dat_epoch;


% Check to see if files have been created 
% find ports to write
write_port = unique({aux_input_channels.port_name});
basepath = basepath(~cellfun(@isempty,folders));
write_port = write_port(~cellfun(@isempty,folders)); % write ports based on inputs

% if all files have been written, exit the function
if isempty(write_port)
    return
end

% Load the file
n_channels = size(aux_input_channels,2);
contFile = fullfile(dat_path,'auxiliary.dat');
file = dir(contFile);
samples = file.bytes/(n_channels * 2); %int16 = 2 bytes
aux = memmapfile(contFile,'Format',{'uint16' [n_channels samples] 'mapped'});

% loop through ports
if ~isempty(trim_dat_epoch) % trims dat based on digitalin events
    for port = 1:length(write_port)
        write_aux(aux,write_port{port},aux_input_channels,basepath{port},...
            'trim_dat_epoch',trim_dat_epoch(port,:))
    end
else
    for port = 1:length(write_port) % keeps entire dat
        write_aux(aux,write_port{port},aux_input_channels,basepath{port})
    end
end

clear aux 
end

function process_amp(dat_path,amplifier_channels,frequency_parameters,subject_order,basepath,varargin)
% processes intan amplifier file and splits into separate files indicated
% by ports.
% input:
% - dat_path: path where amplifier.dat is found
% - amplifier_channels: table containing metadata from intan RHD file
%   (output of read_Intan_RHD2000_file_snlab)
% - frequency_parameters: table containing metadata from intan RHD file
%   (output of read_Intan_RHD2000_file_snlab)
% - subject order: cell array containing subject names 'hpc01'
% - basepath: cell array of each basepath per subject
%
%optional: 
% trim_dat_epoch: matrix of start and end time in samples to cut dat file.
% output:
% - saves port_amplifier.dat to dat_path
% LB 03/22
% Check to see if files have been created 

p = inputParser;
addParameter(p,'trim_dat_epoch',[],@isnumeric) %snlab rig wiring for events

parse(p,varargin{:});

trim_dat_epoch = p.Results.trim_dat_epoch;

% loop through ports
write_port = unique({amplifier_channels.port_name});
basepath = basepath(~cellfun(@isempty,subject_order));
write_port = write_port(~cellfun(@isempty,subject_order)); % write ports based on inputs

% loop through ports
remove_port_idx = [];
for port = 1:length(write_port)
    if isfile([basepath{port},filesep,'amplifier.dat'])
        disp([basepath{port},' amplifier.dat ','already created'])
        % remove from list
        remove_port_idx = [remove_port_idx;find(ismember(write_port,write_port{port}))];
    end
end

if ~isempty(remove_port_idx)
    basepath(remove_port_idx) = [];
    write_port(remove_port_idx) = [];
end

% if all files have been written, exit the function
if isempty(write_port)
    return
end

n_channels = size(amplifier_channels,2);
contFile = fullfile(dat_path,'amplifier.dat');
file = dir(contFile);
samples = file.bytes/(n_channels * 2); %int16 = 2 bytes
amp = memmapfile(contFile,'Format',{'int16' [n_channels, samples] 'mapped'});

% create batches
if isempty(trim_dat_epoch)
    batch = ceil(linspace(0,samples,ceil(samples/frequency_parameters.amplifier_sample_rate/4)));
end
% initialize new dat, channel index, and batch
for port = 1:length(write_port)
    if ~isempty(trim_dat_epoch)
        temp_samples = trim_dat_epoch(port,2) - trim_dat_epoch(port,1);
        batch{port} = ceil(linspace(trim_dat_epoch(port,1),temp_samples,...
            ceil(trim_dat_epoch(port,2)/frequency_parameters.amplifier_sample_rate/4)));
    end
    idx{port} = contains({amplifier_channels.port_name},write_port{port});
end


% loop though ports and write dats
if ~isempty(trim_dat_epoch)
    for port = 1:length(write_port)
        write_amp(amp,basepath{port},batch{port},idx{port})
    end
else
    for port = 1:length(write_port)
        write_amp(amp,basepath{port},batch,idx{port})
    end
end

% close amp_files
fclose('all');
clear amp 
end

function write_amp(amp,basepath,batch,idx)
amp_file = fopen(fullfile(basepath,'amplifier.dat'),'w');
% loop though batches
for ii = 1:length(batch)-1
    disp(['batch ',num2str(batch(ii)+1),' to ',num2str(batch(ii+1)),...
        '   ',num2str(ii),' of ',num2str(length(batch)-1)])
    % write to disk
    fwrite(amp_file,amp.Data.mapped(idx,batch(ii)+1:batch(ii+1)), 'int16');
end


end

function write_aux(aux,port,aux_input_channels,basepath,varargin)
% LB 03/22

p = inputParser;
addParameter(p,'trim_dat_epoch',[],@isnumeric) %snlab rig wiring for events

parse(p,varargin{:});

trim_dat_epoch = p.Results.trim_dat_epoch;

    % skip if file is already created
    if isfile([basepath,filesep,'auxiliary.dat'])
        disp([basepath,filesep,'auxiliary.dat ','already created'])
        return
    end
    
    % initiate file
    aux_file = fopen([basepath,filesep,'auxiliary.dat'],'w');
    idx = contains({aux_input_channels.port_name},port);
   
    if ~isempty(trim_dat_epoch)
        % write to disk
        fwrite(aux_file, aux.Data.mapped(idx,trim_dat_epoch(1):trim_dat_epoch(2)), 'uint16');
        fclose(aux_file);
    else
        % write to disk
        fwrite(aux_file, aux.Data.mapped(idx,:), 'uint16');
        fclose(aux_file);
    end
end

function digitalIn = parse_digitalIn(old_digitalIn,channel_index,basepath,varargin)
% saves events from digitalIn structure. By default, the video timestamp
% data is obtained from intan digitalin channel 0 on the RHD USB interface
% board
% input:
%  - digitalIn: structure produced by process_digitalIn containing events
%     from intan digitalIn.dat file
%  - channel_index: channels to be saved. 
%  - basepath: location to save digitalin.events.mat
% optional: 
%  - video_idx: digitalin channel that contains timestamps from video
%  source. Default is 1 (intan channel 0);
%  - trim_dat_epoch: start and end of recording in seconds 
%
% LB 03/22
p = inputParser;
addParameter(p,'video_idx',1,@isnumeric)
addParameter(p,'trim_dat_epoch',[],@isnumeric)
parse(p,varargin{:});

video_idx = p.Results.video_idx;
trim_dat_epoch = p.Results.trim_dat_epoch;

if ~isempty(trim_dat_epoch)
    
    digitalIn.timestampsOn{1,video_idx} = old_digitalIn.timestampsOn{1, video_idx} - trim_dat_epoch(1,1);
    digitalIn.timestampsOff{1,video_idx} = old_digitalIn.timestampsOff{1, video_idx} - trim_dat_epoch(1,1);
    digitalIn.timestampsOn{1,2} = old_digitalIn.timestampsOn{1, channel_index} - trim_dat_epoch(1,1);
    digitalIn.timestampsOff{1,2} = old_digitalIn.timestampsOff{1, channel_index} - trim_dat_epoch(1,1);
    digitalIn.ints{1,2} = old_digitalIn.ints{1, channel_index} - trim_dat_epoch(1,1);
    digitalIn.dur{1,2} = old_digitalIn.dur{1, channel_index};
    digitalIn.intsPeriods{1,2} = old_digitalIn.intsPeriods{1, channel_index} - trim_dat_epoch(1,1);
else

    digitalIn.timestampsOn{1,video_idx} = old_digitalIn.timestampsOn{1, video_idx};
    digitalIn.timestampsOff{1,video_idx} = old_digitalIn.timestampsOff{1, video_idx};
    digitalIn.timestampsOn{1,2} = old_digitalIn.timestampsOn{1, channel_index};
    digitalIn.timestampsOff{1,2} = old_digitalIn.timestampsOff{1, channel_index};
    digitalIn.ints{1,2} = old_digitalIn.ints{1, channel_index};
    digitalIn.dur{1,2} = old_digitalIn.dur{1, channel_index};
    digitalIn.intsPeriods{1,2} = old_digitalIn.intsPeriods{1, channel_index};

end
save([basepath,filesep,'digitalIn.events.mat'],'digitalIn');

end


