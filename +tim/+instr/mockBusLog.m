function out = mockBusLog(action, bus, text)
%MOCKBUSLOG Process-wide recorder of the traffic the protocol mocks receive.
%
%   tim.instr.mockBusLog('start')                  % clear and start recording
%   tim.instr.mockBusLog('add', 'SCPI', '> *IDN?') % called by the mocks
%   lines = tim.instr.mockBusLog('lines')          % recorded so far (keeps recording)
%   lines = tim.instr.mockBusLog('stop')           % stop recording, return the lines
%
%   Every protocol mock (MockScpiTransport, MockLanXiHttp, MockLanXiStream)
%   adds one line per command it receives, so the traffic of all instruments
%   of a simulated session forms ONE log in the order it was sent, e.g.
%   'SCPI > OUTP OFF', 'REST PUT /rest/rec/open {...}', 'STREAM open port 1536'.
%   tests/TestBusTraffic compares this log with a stored fixture (WO-001:
%   the bus behaviour must not change when the drivers are refactored).
%   Recording is off by default: 'add' then does nothing (no memory growth
%   in normal simulation use).

persistent on lines
if isempty(on), on = false; lines = {}; end
out = [];
switch action
    case 'start'
        on = true; lines = {};
    case 'add'
        if on, lines{end+1, 1} = sprintf('%s %s', bus, text); end
    case 'lines'
        out = lines;
    case 'stop'
        on = false; out = lines; lines = {};
    otherwise
        error('tim:instr:busLog', 'Unknown action "%s" (start, add, lines or stop).', action);
end
end
