function figs = plotResults(res, meas, opts)
%PLOTRESULTS Standard figures of a processed measurement.
%
%   figs = tim.app.plotResults(res, meas)                 % visible figures
%   figs = tim.app.plotResults(res, meas, struct('Visible', 'off'))
%
%   Values outside the valid mask are drawn thin and grey; valid values in
%   colour. Nothing is drawn as "valid" just because it is finite.
%   Stepped sine: results exist only at the step frequencies and are drawn
%   with markers; the spectrum figure shows the level of every step (the
%   PSD of a stepped record is a line spectrum). Thick specimen (k d > 1):
%   the thin-element curves (Zt, TL from Zt) are not drawn.

if nargin < 3, opts = struct(); end
vis = 'on'; if isfield(opts, 'Visible'), vis = opts.Visible; end
a = res.analysis; f = a.f; v = a.valid;
tag = ''; if isfield(meas, 'metadata') && isfield(meas.metadata, 'WARNING'), tag = ' [SIMULATION]'; end
P = tim.gui.palette(); col = P.ch;
figs = struct();
stepped = isfield(res, 'kind') && strcmp(res.kind, 'stepped');
if stepped, mkf = @(c) {'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', c}; else, mkf = @(c) {}; end
[thick, thickTxt] = thickSpecimen(a);

% ---- waveforms (Pa = volts / sensitivity; mV without a sensitivity)
figs.waveforms = figure('Visible', vis, 'Name', 'Waveforms', 'Color', 'w');
x = meas.records{1}; t = (0:size(x, 1) - 1) / meas.fs;
[bh, ah] = butter(2, 20 / (meas.fs / 2), 'high');         % display only (removes CCLD/DC settling drift)
x = filtfilt(bh, ah, x - mean(x, 1));
sens = [meas.mics.sensitivity_VperPa];
if numel(sens) == size(x, 2) && all(isfinite(sens) & sens > 0)
    x = x ./ sens; unit = 'Pa'; what = 'Sound pressure';
else
    x = 1e3 * x; unit = 'mV'; what = 'Channel voltages';
end
tl = tiledlayout(figs.waveforms, 4, 1, 'TileSpacing', 'compact');
for c = 1:4
    ax = nexttile(tl);
    plot(ax, t, x(:, c), 'Color', col(c, :));
    ylabel(ax, sprintf('ch%d [%s]', c, unit)); grid(ax, 'on');
    if c == 1, title(ax, [what ' > 20 Hz (repetition 1; display filter only)' tag]); end
end
xlabel(ax, 'Time [s]');

% ---- pressure spectra / step levels
if stepped && isfield(res, 'toneLevels')
    figs.spectrum = figure('Visible', vis, 'Name', 'Step levels', 'Color', 'w');
    ax = axes(figs.spectrum); hold(ax, 'on');
    tlv = res.toneLevels; hc = gobjects(1, size(tlv.spl_dB, 2));
    for c = 1:size(tlv.spl_dB, 2)
        hc(c) = plot(ax, tlv.f, tlv.spl_dB(:, c), '-o', 'Color', col(c, :), 'MarkerFaceColor', col(c, :), ...
            'MarkerSize', 4, 'LineWidth', 0.8);
        plot(ax, tlv.f, tlv.noise_dB(:, c), ':', 'Color', col(c, :));
    end
    hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on');
    xlim(ax, [min(tlv.f) / 1.2, max(tlv.f) * 1.2]);
    xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'Tone level [dB SPL]  (dotted: noise in fit bandwidth)');
    legend(ax, hc, arrayfun(@(c) sprintf('ch%d', c), tlv.channelOrder, 'UniformOutput', false), 'Location', 'best');
    title(ax, ['Stepped sine: level of every step (sine fit of the settled part)' tag]);
elseif isfield(res, 'pressureSpectrum') && isfield(res.pressureSpectrum, 'PSD_Pa2perHz')
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
    a1 = mkf(col(m, :));
    plot(ax1, f, 20 * log10(abs(res.Hposition(:, m))), 'Color', col(m, :), a1{:});
    if stepped   % coarse grid: unwrap would add spurious 2*pi jumps
        plot(ax2, f, rad2deg(angle(res.Hposition(:, m))), 'o', 'Color', col(m, :), 'MarkerFaceColor', col(m, :), 'MarkerSize', 4);
    else
        plot(ax2, f, rad2deg(unwrap(angle(res.Hposition(:, m)))), 'Color', col(m, :));
    end
end
sp = res.spectra;
for c = 1:4
    a1 = mkf(col(c, :));
    plot(ax3, sp.f, sp.coherence(:, c), 'Color', col(c, :), a1{:});
end
set([ax1 ax2 ax3], 'XScale', 'log'); grid(ax1, 'on'); grid(ax2, 'on'); grid(ax3, 'on');
ylabel(ax1, '|p_m/p_{ref}| [dB]'); ylabel(ax3, 'coherence');
if stepped
    ylabel(ax2, 'phase [deg] (wrapped)'); ylim(ax2, [-180 180]);
else
    ylabel(ax2, 'phase [deg]');
end
legend(ax1, {'M1', 'M2', 'M3', 'M4'}, 'Location', 'best');
title(ax1, sprintf('Calibrated relative pressures (%s)%s', res.calibration.version, tag));
xlabel(ax3, 'Frequency [Hz]');

% ---- reflection / transmission
figs.reflection = figure('Visible', vis, 'Name', 'Reflection/transmission', 'Color', 'w');
tl = tiledlayout(figs.reflection, 2, 2, 'TileSpacing', 'compact');
plotMasked(nexttile(tl), f, abs(a.R), v.validR, col(1, :), '|R| front face', stepped);
plotMasked(nexttile(tl), f, rad2deg(angle(a.R)), v.validR, col(1, :), '\angle R [deg]', stepped);
plotMasked(nexttile(tl), f, abs(a.tau), v.validTau, col(2, :), '|\tau| (anechoic assumption)', stepped);
ax = nexttile(tl);
plotMasked(ax, f, a.power.alpha, v.validTau, col(3, :), '\alpha = 1-|R|^2-|\tau|^2', stepped);
hold(ax, 'on'); plot(ax, f, abs(a.Rterm), ':', 'Color', [0.4 0.4 0.4]);
legend(ax, {'', '\alpha (valid)', '|R_{term}|'}, 'Location', 'best');
title(tl, ['Reflection and transmission' tag]);

% ---- transfer impedance
figs.impedance = figure('Visible', vis, 'Name', 'Transfer impedance', 'Color', 'w');
if thick
    ax = axes(figs.impedance); axis(ax, 'off');
    text(ax, 0.5, 0.5, {'Thin-element transfer impedance', thickTxt}, 'HorizontalAlignment', 'center', ...
        'Interpreter', 'none', 'FontSize', 11);
else
    tl = tiledlayout(figs.impedance, 2, 1, 'TileSpacing', 'compact');
    plotMasked(nexttile(tl), f, real(a.thin.Zt_norm), v.validThinZt, col(1, :), 'Re\{Z_t\}/\rho c', stepped);
    plotMasked(nexttile(tl), f, imag(a.thin.Zt_norm), v.validThinZt, col(2, :), 'Im\{Z_t\}/\rho c', stepped);
    title(tl, sprintf('Thin-element transfer impedance (u = %s)%s', a.thin.velocityRef, tag));
end

% ---- transmission loss
figs.transmissionLoss = figure('Visible', vis, 'Name', 'Transmission loss', 'Color', 'w');
ax = axes(figs.transmissionLoss);
yv = a.power.TL_tau_dB; yv(~v.validTau) = NaN;
a1 = mkf(col(2, :));
if thick
    plot(ax, f, yv, '--', 'Color', col(2, :), 'LineWidth', 1.1, a1{:});
    grid(ax, 'on'); set(ax, 'XScale', 'log'); xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'TL [dB]');
    legend(ax, {'TL = -20log_{10}|\tau| (anechoic, valid)'}, 'Location', 'best');
    title(ax, {['Transmission loss' tag], thickTxt}, 'Interpreter', 'none');
else
    plotMasked(ax, f, a.thin.TL_dB, v.validThinZt, col(1, :), 'TL [dB]', stepped);
    hold(ax, 'on');
    plot(ax, f, yv, '--', 'Color', col(2, :), 'LineWidth', 1.1, a1{:});
    legend(ax, {'', 'TL from Z_t: 20log_{10}|1+Z_t/(2\rhoc)| (valid)', 'TL = -20log_{10}|\tau| (anechoic, valid)'}, ...
        'Location', 'best');
    title(ax, ['Transmission loss' tag]);
end

% ---- validity overview
figs.validity = figure('Visible', vis, 'Name', 'Validity', 'Color', 'w');
ax = axes(figs.validity);
fl = v.flags; names = fieldnames(fl);
M = zeros(numel(names) + 3, numel(f));
for i = 1:numel(names), M(i, :) = fl.(names{i}); end
M(end-2, :) = v.valid; M(end-1, :) = v.validThinZt; M(end, :) = v.validated;
if stepped      % imagesc assumes evenly spaced x: markers on a log axis instead
    hold(ax, 'on'); onC = [0.2 0.4 0.8];
    for i = 1:size(M, 1)
        on = M(i, :) > 0;
        plot(ax, f(~on), i * ones(1, nnz(~on)), 's', 'Color', [0.8 0.8 0.8], 'MarkerSize', 6);
        plot(ax, f(on), i * ones(1, nnz(on)), 's', 'Color', onC, 'MarkerFaceColor', onC, 'MarkerSize', 6);
    end
    set(ax, 'XScale', 'log', 'YDir', 'reverse', 'YLim', [0.5, size(M, 1) + 0.5]); grid(ax, 'on');
else
    imagesc(ax, f, 1:size(M, 1), M); colormap(ax, [1 1 1; 0.2 0.4 0.8]);
end
set(ax, 'YTick', 1:size(M, 1), 'YTickLabel', [names; {'VALID'; 'VALID thin Zt'; 'VALIDATED (exp.)'}]);
xlabel(ax, 'Frequency [Hz]'); title(ax, ['Validity flags (blue = true)' tag]);
end

function plotMasked(ax, f, y, ok, c, lab, stepped)
if nargin < 7, stepped = false; end
P = tim.gui.palette();
mg = {}; mc = {};
if stepped
    mg = {'Marker', 'o', 'MarkerSize', 3, 'MarkerFaceColor', P.invalid};
    mc = {'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', c};
end
plot(ax, f, y, '-', 'Color', P.invalid, 'LineWidth', 0.7, mg{:});
hold(ax, 'on');
yv = y; yv(~ok) = NaN;
plot(ax, f, yv, '-', 'Color', c, 'LineWidth', 1.3, mc{:});
grid(ax, 'on'); set(ax, 'XScale', 'log');
ylabel(ax, lab); xlabel(ax, 'Frequency [Hz]');
end

function [thick, txt] = thickSpecimen(a)
% thin-element model meaningless for k d > 1 (lab specimen section d = 75 mm)
thick = false; txt = '';
if isfield(a, 'boundary') && isfield(a.boundary, 'thickness') && a.boundary.available
    kd = max(real(a.k)) * a.boundary.thickness;
    thick = kd > 1;
    txt = sprintf(['Thin-element model not applicable: d = %g mm (k d up to %.1f). ' ...
        'Use R / tau (anechoic termination) or the transfer matrix.'], round(1e3 * a.boundary.thickness, 3), kd);
end
end
