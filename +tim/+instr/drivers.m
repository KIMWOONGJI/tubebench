function list = drivers()
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

list = struct( ...
    'name',  {'keysight33220a',           'lanxi'}, ...
    'class', {'tim.instr.Keysight33220A', 'tim.instr.LanXi'});
end
