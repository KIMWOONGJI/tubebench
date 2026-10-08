function figs = plotResults(res, meas, opts)
%PLOTRESULTS Standard figures of a processed measurement.
%
%   figs = tim.app.plotResults(res, meas)                 % visible figures
%   figs = tim.app.plotResults(res, meas, struct('Visible', 'off'))
%
%   Values outside the valid mask are drawn thin and grey; valid values in
%   colour. Nothing is drawn as "valid" just because it is finite.

if nargin < 3, opts = struct(); end
vis = 'on'; if isfield(opts, 'Visible'), vis = opts.Visible; end
a = res.analysis; f = a.f; v = a.valid;
tag = ''; if isfield(meas, 'metadata') && isfield(meas.metadata, 'WARNING'), tag = ' [SIMULATION]'; end
P = tim.gui.palette(); col = P.ch;
figs = struct();

% ---- waveforms
figs.waveforms = figure('Visible', vis, 'Name', 'Waveforms', 'Color', 'w');
x = meas.records{1}; t = (0:size(x, 1) - 1) / meas.fs;
[bh, ah] = butter(2, 20 / (meas.fs / 2), 'high');         % display only (removes CCLD/DC settling drift)
x = filtfilt(bh, ah, x - mean(x, 1)) * 1e3;
tl = tiledlayout(figs.waveforms, 4, 1, 'TileSpacing', 'compact');
for c = 1:4
    ax = nexttile(tl);
    plot(ax, t, x(:, c), 'Color', col(c, :));
    ylabel(ax, sprintf('ch%d [mV]', c)); grid(ax, 'on');
    if c == 1, title(ax, ['Channel voltages > 20 Hz (repetition 1; display filter only)' tag]); end
end
xlabel(ax, 'Time [s]');

% ---- pressure spectra
if isfield(res, 'pressureSpectrum') && isfield(res.pressureSpectrum, 'PSD_Pa2perHz')
    figs.spectrum = figure('Visible', vis, 'Name', 'Spectrum', 'Color', 'w');
    ax = axes(figs.spectrum);
    ps = res.pressureSpectrum;
    hold(ax, 'on');
    for c = 1:size(ps.PSD_Pa2perHz, 2)
        plot(ax, ps.f, 10 * log10(ps.PSD_Pa2perHz(:, c) / (2e-5)^2), 'Color', col(c, :), 'LineWidth', P.lineWidth);
    end
    hold(ax, 'off'); set(ax, 'XScale', 'log');
    grid(ax, 'on'); xlim(ax, [20 meas.fs / 2]);
    xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]');
    legend(ax, arrayfun(@(c) sprintf('ch%d', c), ps.channelOrder, 'UniformOutput', false), 'Location', 'best');
    title(ax, ['Pressure spectra (sensitivity layer only)' tag]);
end

% ---- relative transfer functions + quality
figs.transfer = figure('Visible', vis, 'Name', 'Relative responses', 'Color', 'w');
tl = tiledlayout(figs.transfer, 3, 1, 'TileSpacing', 'compact');
ax1 = nexttile(tl); ax2 = nexttile(tl); ax3 = nexttile(tl);
hold(ax1, 'on'); hold(ax2, 'on'); hold(ax3, 'on');
for m = 1:4
    plot(ax1, f, 20 * log10(abs(res.Hposition(:, m))), 'Color', col(m, :));
    plot(ax2, f, rad2deg(unwrap(angle(res.Hposition(:, m)))), 'Color', col(m, :));
end
sp = res.spectra;
for c = 1:4
    plot(ax3, sp.f, sp.coherence(:, c), 'Color', col(c, :));
end
set([ax1 ax2 ax3], 'XScale', 'log'); grid(ax1, 'on'); grid(ax2, 'on'); grid(ax3, 'on');
ylabel(ax1, '|p_m/p_{ref}| [dB]'); ylabel(ax2, 'phase [deg]'); ylabel(ax3, 'coherence');
legend(ax1, {'M1', 'M2', 'M3', 'M4'}, 'Location', 'best');
title(ax1, sprintf('Calibrated relative pressures (%s)%s', res.calibration.version, tag));
xlabel(ax3, 'Frequency [Hz]');

% ---- reflection / transmission
figs.reflection = figure('Visible', vis, 'Name', 'Reflection/transmission', 'Color', 'w');
tl = tiledlayout(figs.reflection, 2, 2, 'TileSpacing', 'compact');
plotMasked(nexttile(tl), f, abs(a.R), v.validR, col(1, :), '|R| front face');
plotMasked(nexttile(tl), f, rad2deg(angle(a.R)), v.validR, col(1, :), '\angle R [deg]');
plotMasked(nexttile(tl), f, abs(a.tau), v.validTau, col(2, :), '|\tau| (anechoic assumption)');
ax = nexttile(tl);
plotMasked(ax, f, a.power.alpha, v.validTau, col(3, :), '\alpha = 1-|R|^2-|\tau|^2');
hold(ax, 'on'); plot(ax, f, abs(a.Rterm), ':', 'Color', [0.4 0.4 0.4]);
legend(ax, {'', '\alpha (valid)', '|R_{term}|'}, 'Location', 'best');
title(tl, ['Reflection and transmission' tag]);

% ---- transfer impedance
figs.impedance = figure('Visible', vis, 'Name', 'Transfer impedance', 'Color', 'w');
tl = tiledlayout(figs.impedance, 2, 1, 'TileSpacing', 'compact');
plotMasked(nexttile(tl), f, real(a.thin.Zt_norm), v.validThinZt, col(1, :), 'Re\{Z_t\}/\rho c');
plotMasked(nexttile(tl), f, imag(a.thin.Zt_norm), v.validThinZt, col(2, :), 'Im\{Z_t\}/\rho c');
title(tl, sprintf('Thin-element transfer impedance (u = %s)%s', a.thin.velocityRef, tag));

% ---- transmission loss
figs.transmissionLoss = figure('Visible', vis, 'Name', 'Transmission loss', 'Color', 'w');
ax = axes(figs.transmissionLoss);
plotMasked(ax, f, a.thin.TL_dB, v.validThinZt, col(1, :), 'TL [dB]');
hold(ax, 'on');
yv = a.power.TL_tau_dB; yv(~v.validTau) = NaN;
plot(ax, f, yv, '--', 'Color', col(2, :), 'LineWidth', 1.1);
legend(ax, {'', 'TL from Z_t: 20log_{10}|1+Z_t/(2\rhoc)| (valid)', 'TL = -20log_{10}|\tau| (anechoic, valid)'}, ...
    'Location', 'best');
title(ax, ['Transmission loss' tag]);

% ---- validity overview
figs.validity = figure('Visible', vis, 'Name', 'Validity', 'Color', 'w');
ax = axes(figs.validity);
fl = v.flags; names = fieldnames(fl);
M = zeros(numel(names) + 3, numel(f));
for i = 1:numel(names), M(i, :) = fl.(names{i}); end
M(end-2, :) = v.valid; M(end-1, :) = v.validThinZt; M(end, :) = v.validated;
imagesc(ax, f, 1:size(M, 1), M); colormap(ax, [1 1 1; 0.2 0.4 0.8]);
set(ax, 'YTick', 1:size(M, 1), 'YTickLabel', [names; {'VALID'; 'VALID thin Zt'; 'VALIDATED (exp.)'}]);
xlabel(ax, 'Frequency [Hz]'); title(ax, ['Validity flags (blue = true)' tag]);
end

function plotMasked(ax, f, y, ok, c, lab)
P = tim.gui.palette();
plot(ax, f, y, '-', 'Color', P.invalid, 'LineWidth', 0.7);
hold(ax, 'on');
yv = y; yv(~ok) = NaN;
plot(ax, f, yv, '-', 'Color', c, 'LineWidth', 1.3);
grid(ax, 'on'); set(ax, 'XScale', 'log');
ylabel(ax, lab); xlabel(ax, 'Frequency [Hz]');
end
