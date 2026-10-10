function d = driverInfo(name)
%DRIVERINFO Class-level description of a registered instrument driver.
%
%   d = tim.instr.driverInfo('lanxi')
%   d: the driver's describe() (name, displayName, labels, defaults, texts,
%   simulation) plus class, capabilities (capabilities()) and steps
%   (connectionSteps()). No I/O. An unknown name raises
%   tim:instr:unknownDriver, naming the registered drivers.

list = tim.instr.drivers();
if isstring(name) && isscalar(name), name = char(name); end
k = [];
if ischar(name), k = find(strcmp(name, {list.name}), 1); end
if isempty(k)
    got = name; if ~ischar(got), got = class(got); end
    error('tim:instr:unknownDriver', 'Unknown instrument driver "%s" (registered: %s).', got, strjoin({list.name}, ', '));
end
cls = list(k).class;
d = feval([cls '.describe']);
d.class = cls;
d.capabilities = feval([cls '.capabilities']);
d.steps = feval([cls '.connectionSteps']);
end
