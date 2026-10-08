function fig = plotCalibration(cal, opts)
%PLOTCALIBRATION Complex calibration curves C_k = c_k / c_ref.
if nargin < 2, opts = struct(); end
vis = 'on'; if isfield(opts, 'Visible'), vis = opts.Visible; end
fig = figure('Visible', vis, 'Name', 'Calibration', 'Color', 'w');
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact');
ax1 = nexttile(tl); ax2 = nexttile(tl); hold(ax1, 'on'); hold(ax2, 'on');
P = tim.gui.palette(); col = P.ch; leg = {};
for k = 1:4
    if k == cal.refChannel, continue; end
    c = cal.C(:, k); ok = cal.valid(:, k);
    m = 20 * log10(abs(c)); p = rad2deg(unwrap(angle(c)));
    plot(ax1, cal.f, m, ':', 'Color', col(k, :)); mv = m; mv(~ok) = NaN;
    plot(ax1, cal.f, mv, '-', 'Color', col(k, :), 'LineWidth', 1.2);
    plot(ax2, cal.f, p, ':', 'Color', col(k, :)); pv = p; pv(~ok) = NaN;
    plot(ax2, cal.f, pv, '-', 'Color', col(k, :), 'LineWidth', 1.2);
    leg = [leg, {'', sprintf('ch%d / ch%d', k, cal.refChannel)}]; %#ok<AGROW>
end
set([ax1 ax2], 'XScale', 'log'); grid(ax1, 'on'); grid(ax2, 'on');
ylabel(ax1, '|C_k| [dB]'); ylabel(ax2, '\angle C_k [deg]'); xlabel(ax2, 'Frequency [Hz]');
legend(ax1, leg, 'Location', 'best');
title(tl, sprintf('Complex channel calibration %s (dotted = invalid bins)', cal.version));
end
