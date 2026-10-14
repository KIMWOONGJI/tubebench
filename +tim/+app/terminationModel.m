function t = terminationModel(cfg, load)
%TERMINATIONMODEL Termination of the virtual rig for a load (simulation, WO-005).
%
%   t = tim.app.terminationModel(cfg, load)
%
%   The termination struct of tim.sim.tubeModel / tim.sim.SimulatedRig for a
%   termination load (tim.app.describeLoad):
%     absorber   simulation.Termination as configured (the virtual absorbing
%                termination of the configuration)
%     rigid      R = 1 at the place
%     open       model 'unflangedOpenEnd' at the place (|R| = exp(-(k a)^2/2),
%                end correction 0.6133 a; tim.sim.tubeModel)
%   The place lies tubeDrawing.downstreamLength (tube end) or
%   downstreamTubeEnd (joint) behind M4 of the simulated tube
%   (simulation.Geometry, else geometry), and never upstream of its rear face.

d = tim.app.describeLoad(load, cfg);
if strcmp(d.kind, 'absorber')
    t = cfg.simulation.Termination;
    return
end
g = cfg.geometry;
if isfield(cfg, 'simulation') && isfield(cfg.simulation, 'Geometry') && isstruct(cfg.simulation.Geometry)
    g = cfg.simulation.Geometry;
end
x = max(g.micPositions) + d.distance_m;
if ~isfinite(x)
    error('tim:sim:termination', 'The %s needs the microphone positions and tubeDrawing distances.', lower(d.label));
end
x = max(x, g.xRear);
switch d.kind
    case 'rigid'
        t = struct('R', 1, 'x', x);
    case 'open'
        t = struct('R', -1, 'x', x, 'model', 'unflangedOpenEnd');
end
end
