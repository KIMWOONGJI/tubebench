function list = drivers(action, entry)
%DRIVERS The registry of instrument drivers: one line per driver.
%
%   list = tim.instr.drivers()      struct array name, class
%
%   The configuration selects a driver by its name (generator.driver,
%   daq.driver); tim.instr.create checks the selection and builds it. A
%   driver class implements tim.instr.SignalSource and / or
%   tim.instr.Acquisition, and describe().name equals its name here
%   (checked by tests/TestInstrumentContract). Adding a driver means one
%   line here; see docs/instrument_interface.md.
%
%   tim.instr.drivers('add', struct('name', 'mydriver', 'class', 'MyDriver'))
%   tim.instr.drivers('remove', 'mydriver')
%   An entry added this way exists only in this MATLAB session (tests, or
%   trying a driver before its line is added here); 'remove' takes it out.

persistent extra
if isempty(extra), extra = struct('name', {}, 'class', {}); end
if nargin >= 1
    switch action
        case 'add'
            extra = [extra(~strcmp({extra.name}, entry.name)), struct('name', entry.name, 'class', entry.class)];
        case 'remove'
            extra = extra(~strcmp({extra.name}, entry));
        otherwise
            error('tim:instr:registry', 'Unknown registry action "%s" (add or remove).', char(string(action)));
    end
end

list = struct( ...
    'name',  {'keysight33220a',           'lanxi',           'simcombined'}, ...
    'class', {'tim.instr.Keysight33220A', 'tim.instr.LanXi', 'tim.sim.SimulatedCombined'});
list = [list, extra(~ismember({extra.name}, {list.name}))];
end
