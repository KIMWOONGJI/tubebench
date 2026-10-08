%DEMO_SIMULATION Complete workflow on the virtual rig; writes example plots.
%
%   Runs: connect (mock instruments) -> TEDS -> sensor-switching calibration
%   -> log-sweep measurement -> stepped-sine measurement -> analysis ->
%   figures + CSV in examples/output/. All data are SIMULATED.
%   The virtual sample is a 10 mm porous layer (Miki model, 20 kPa*s/m^2)
%   in front of a nearly anechoic termination (|R| = 0.05), with the
%   "true" geometry of cfg.simulation.Geometry. In simulation the analysis
%   is given the true geometry; in the lab you must MEASURE it.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
cfg = tim.app.defaultConfig();
cfg.mode = 'simulation';
cfg.geometry = cfg.simulation.Geometry;
out = fullfile(root, 'examples', 'output');
if ~exist(out, 'dir'), mkdir(out); end
cfg.output.dataDir = fullfile(out, 'data');
cfg.output.calibrationDir = fullfile(out, 'calibration');
cfg.excitation.sweep.duration = 3;
cfg.excitation.sweep.repetitions = 2;
cfg.excitation.stepped.nPoints = 15;

s = tim.app.MeasurementSession(cfg);
s.connect();
s.prepareAcquisition();
cal = tim.app.runCalibration(s);
fc = tim.app.plotCalibration(cal, struct('Visible', 'off'));
exportgraphics(fc, fullfile(out, 'example_calibration.png'), 'Resolution', 150);

meas = s.measure('sweep');
res = tim.app.processMeasurement(meas, cfg, cal);
figs = tim.app.plotResults(res, meas, struct('Visible', 'off'));
tim.app.exportFigures(figs, out, {'png'});
names = fieldnames(figs);
for i = 1:numel(names)
    movefile(fullfile(out, ['fig_' names{i} '.png']), fullfile(out, ['example_sweep_' names{i} '.png']));
end
folder = tim.app.saveMeasurement(meas, res, cfg, 'demo_porous_sweep', []);

measS = s.measure('stepped');
resS = tim.app.processMeasurement(measS, cfg, cal);

% ---- comparison with the simulation truth (possible only in simulation)
truth = s.Rig.trueResponse(res.analysis.f).model;
a = res.analysis; v = a.valid.valid;
f1 = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 600]);
tl = tiledlayout(f1, 2, 1);
ax = nexttile(tl);
semilogx(ax, a.f, abs(truth.R), 'k-', a.f(v), abs(a.R(v)), 'b.', resS.analysis.f, abs(resS.analysis.R), 'ro');
legend(ax, {'truth (analytic)', 'log sweep (valid bins)', 'stepped sine'}, 'Location', 'best');
ylabel(ax, '|R|'); grid(ax, 'on'); title(ax, 'SIMULATION: recovered vs true reflection coefficient');
ax = nexttile(tl);
semilogx(ax, a.f, abs(truth.tau), 'k-', a.f(v), abs(a.tau(v)), 'b.', resS.analysis.f, abs(resS.analysis.tau), 'ro');
ylabel(ax, '|\tau|'); xlabel(ax, 'Frequency [Hz]'); grid(ax, 'on');
exportgraphics(f1, fullfile(out, 'example_truth_comparison.png'), 'Resolution', 150);

err = struct('R_median', median(abs(a.R(v) - truth.R(v))), 'R_max', max(abs(a.R(v) - truth.R(v))), ...
    'tau_median', median(abs(a.tau(v) - truth.tau(v))), 'tau_max', max(abs(a.tau(v) - truth.tau(v))), ...
    'validBins', nnz(v), 'bins', numel(v), 'summary', res.summary, 'sweepLaw', res.diagnostics.sweepLaw);
fid = fopen(fullfile(out, 'example_results.json'), 'w');
fprintf(fid, '%s', jsonencode(err, 'PrettyPrint', true)); fclose(fid);
disp(err)
fprintf('Demo output in %s\n', out);
close all
s.close();
