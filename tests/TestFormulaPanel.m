classdef TestFormulaPanel < matlab.unittest.TestCase
    %TESTFORMULAPANEL The "Formula" view (tim.gui.equationsPanel).
    %   The panel is built in an invisible uifigure (inside a uitab, as in
    %   Tubebench). Checked: no error or warning while building; the common view
    %   layout (tim.gui.ViewPage header 'Formula'); every LaTeX string renders
    %   with the R2022b LaTeX interpreter (each one is drawn once with text()
    %   in an invisible figure, an invalid string gives a warning); the
    %   thresholds and example numbers follow tim.app.defaultConfig and the
    %   code; the formulas use the glossary symbols (D diameter, d thickness,
    %   kappa for the ratio of specific heats, tau_a for the anechoic
    %   coefficient) and the code's choices (0.58 c/D, Zc in the velocity,
    %   Kirchhoff k, stepped SNR per block, the stepped-sine settled check,
    %   the Zt bias of 'iso10534'); the
    %   texts name the control-panel section and fields; plain text has no
    %   ASCII math; every section ends with its sources, and the numbered
    %   references are those of docs/theory.md, word for word.

    properties
        fig
        labels          % all uilabels of the panel
        latex           % cellstr: Text of every LaTeX label
        plain           % cellstr: Text of every plain-text label
    end

    methods (TestMethodSetup)
        function build(tc)
            tc.fig = uifigure('Visible', 'off', 'Position', [50 50 1300 800]);
            tc.addTeardown(@() delete(tc.fig));
            tg = uitabgroup(tc.fig);
            t = uitab(tg, 'Title', 'Formula');
            tc.verifyWarningFree(@() tim.gui.equationsPanel(t), 'building the Formula view');
            tc.labels = findall(tc.fig, 'Type', 'uilabel');
            isTex = strcmp({tc.labels.Interpreter}, 'latex');
            tc.latex = {tc.labels(isTex).Text};
            tc.plain = {tc.labels(~isTex).Text};
        end
    end

    methods (Test)
        function sameLayoutAsTheOtherViews(tc)
            % ViewPage header: title 'Formula' and a one-line description
            tc.verifyTrue(any(strcmp(tc.plain, 'Formula')), 'view title');
            tc.verifyNotEmpty(findall(tc.fig, 'Type', 'uilabel', 'Tag', 'formula:h'));
            hl = findall(tc.fig, 'Type', 'uilabel', 'Tag', 'formula:h');
            heads = {hl.Text};
            for h = {'Conventions', 'Transfer functions', 'Switching calibration', 'decomposition', ...
                    'specimen faces', 'Reflection, transmission', 'Transfer impedance', 'Transmission loss', ...
                    'Transfer matrix (two-load method', 'Air properties', 'Geometric validity range', ...
                    'Validity criteria', 'Units', 'References'}
                tc.verifyTrue(any(contains(heads, h{1})), ['section ' h{1}]);
            end
            sl = findall(tc.fig, 'Type', 'uilabel', 'Tag', 'formula:h2');
            sub = {sl.Text};
            tc.verifyTrue(any(contains(sub, 'Swept sine')) && any(contains(sub, 'Stepped sine')));
            % the content scrolls inside the body of the page
            g = findall(tc.fig, 'Type', 'uigridlayout', 'Scrollable', 'on');
            tc.verifyNumElements(g, 1);
        end

        function everyLatexStringRenders(tc)
            tc.verifyGreaterThan(numel(tc.latex), 60);
            f = figure('Visible', 'off'); c = onCleanup(@() delete(f));
            ax = axes(f);
            for i = 1:numel(tc.latex)
                s = tc.latex{i};
                tc.verifyTrue(startsWith(s, '$') && endsWith(s, '$') && count(s, '$') == 2, ['math mode: ' s]);
                tc.verifyWarningFree(@() TestFormulaPanel.render(ax, s), ['LaTeX does not render: ' s]);
            end
        end

        function thresholdsFollowDefaultConfig(tc)
            cfg = tim.app.defaultConfig(); a = cfg.analysis;
            n = @(x) sprintf('%.10g', x);
            cl = findall(tc.fig, 'Type', 'uilabel', 'Tag', 'formula:c');
            crit = {cl.Text};
            has = @(s) any(contains(crit, s));
            tc.verifyTrue(has(['\gamma_k^{2} \ge ' n(a.coherenceMin) '$']), 'coherence');
            tc.verifyTrue(has(['\mathrm{SNR}_k \ge ' n(a.snrMin_dB) '\ \mathrm{dB}']), 'SNR');
            tc.verifyTrue(has(['\Delta_k - 4\,\sigma_{\Delta,k} \le ' n(a.settleDriftMax) '$']), ...
                'settled check of the stepped sine (1.6.0)');
            tc.verifyTrue(has(['\mathrm{cond} \le ' n(a.condMax) '$']), 'condition number');
            tc.verifyTrue(has(['\le ' n(a.maxPhaseSensitivity) ', \quad \delta\varphi = ' n(a.phaseUncertainty_rad)]), ...
                'phase sensitivity');
            tc.verifyTrue(has(['|R| \le ' n(1 + a.passivityTol) ',']), 'passivity');
            tc.verifyTrue(has(['|R_{\mathrm{term}}| \le ' n(a.anechoicRmax) '$']), 'anechoic termination');
            tc.verifyTrue(has(sprintf('\\delta_u \\le %.2f$', a.velocityMismatchMax)), 'velocity mismatch');
            tc.verifyTrue(has(sprintf('%.2f\\,c/s \\le f \\le %.2f\\,c/s', a.lowerFraction, a.upperFraction)), ...
                'spacing fractions');
            % example limits and air properties computed by the code
            air = tim.acoustics.airProperties(cfg.environment);
            lim = tim.acoustics.frequencyLimits(cfg.geometry.diameter, ...
                [cfg.geometry.spacingUp cfg.geometry.spacingDown], air);
            txt = [tc.plain tc.latex];
            tc.verifyTrue(any(contains(txt, sprintf('%.0f–%.0f Hz', lim.fLower, lim.fUpper))), 'geometric range');
            tc.verifyTrue(any(contains(txt, sprintf('ISO diameter rule %.0f Hz', lim.isoDiameterLimit))));
            tc.verifyTrue(any(contains(txt, sprintf('\\rho = %.4f\\ \\mathrm{kg/m^{3}}', air.rho))), 'density');
            tc.verifyTrue(any(contains(txt, sprintf('\\rho c = %.1f\\ ', air.Z0))), 'rho c');
            tc.verifyTrue(any(contains(txt, ['default: ' a.lossModel])), 'default loss model');
        end

        function formulasAreThoseOfTheCode(tc)
            e = strjoin(tc.latex, newline);
            % upper limit: ISO 0.58 c/D (binding), (1,1) cut-on only as a value
            tc.verifyTrue(contains(e, 'f \;<\; 0.58\,\frac{c}{D}'));
            tc.verifyTrue(contains(e, 'f_{(1,1)} = \frac{1.8412\,c}{\pi D}'));
            % velocity and TL from Zt with the characteristic impedance Zc of the loss model
            tc.verifyTrue(contains(e, 'u_L = \frac{A_1 e^{-jkx_L} - B_1 e^{jkx_L}}{Z_c}'));
            tc.verifyTrue(contains(e, '\tau_a = \frac{2}{2 + Z_t/Z_c}'));
            tc.verifyTrue(contains(e, '20\log_{10}\left|1 + \frac{Z_t}{2 Z_c}\right|'));
            tc.verifyTrue(contains(e, '\mathrm{TL}_{\tau} = -20\log_{10}|\tau|'));
            % Kirchhoff wavenumber and density of the code
            tc.verifyTrue(contains(e, 'k = \frac{\omega}{c} + (1 - j)\,k^{\prime\prime}'));
            tc.verifyTrue(contains(e, '\frac{p_s}{287.05\ \mathrm{J/(kg\,K)}\cdot T}'));
            % stepped-sine SNR per block, swept-sine noise energy
            tc.verifyTrue(contains(e, '{G_{\mathrm{n},k}\,f_s/N}'));
            tc.verifyTrue(contains(e, 'E|N_k|^{2} = \frac{G_{\mathrm{n},k}}{2}\,f_s\sum_m w_m^{2}'));
            % settled check of the stepped sine (1.6.0): first vs last block, the
            % noise sigma from the per-block SNR with the noise of the pre-roll,
            % the excess over 4 sigma (tim.dsp.sineResponse, tim.app.processMeasurement)
            tc.verifyTrue(contains(e, '\Delta_k = \frac{|H_{k,n_b} - H_{k,1}|}{|H_k^{\mathrm{m}}|}'));
            tc.verifyTrue(contains(e, ['\sigma_{\Delta,k} = \sqrt{2\left(10^{-\mathrm{SNR}^{0}_k/10} + ' ...
                '10^{-\mathrm{SNR}^{0}_{\mathrm{ref}}/10}\right)}']));
            % the deviation of the equalizer has its own symbol (not the drift Delta_k)
            tc.verifyTrue(contains(e, '|\Delta L_k| \le '));
            tc.verifyFalse(contains(e, '|\Delta_k| \le '));
            tc.verifyTrue(contains(e, '\max_k\left(\Delta_k - 4\,\sigma_{\Delta,k}\right) > '));
            % calibration with the chain gain g (c is the speed of sound)
            tc.verifyTrue(contains(e, 'C_k = \frac{g_k}{g_{\mathrm{ref}}} = \sqrt{H^{\mathrm{I}}\,H^{\mathrm{II}}}'));
            % the numbers shown for the loss model are those of tim.acoustics.wavenumber
            cfg = tim.app.defaultConfig();
            air = tim.acoustics.airProperties(cfg.environment);
            k = tim.acoustics.wavenumber(1000, air, cfg.geometry.diameter);
            Cw = -imag(k) * air.c * cfg.geometry.diameter / sqrt(1000);
            tc.verifyTrue(contains(e, sprintf('C_w = %.3f\\cdot10^{-2}', 100 * Cw)));
            % Zt bias of the ISO 10534-2 loss model as documented in tim.acoustics.wavenumber
            % (review analysis-1; the old figure 3-17 % understated it)
            t = strjoin(tc.plain, newline);
            tc.verifyTrue(contains(t, '47 % at |Zt|/(ρc) = 0.05, 12 % at 0.2 and 2 % at 1'), 'iso10534 Zt bias');
            tc.verifyFalse(contains(t, '3–17 %'), 'old iso10534 Zt bias figure');
            % the swept-sine window is the sweep gate (processMeasurement, runCalibration);
            % the taper from the detected excitation is only its fallback (audit 2026-10-11)
            tc.verifyTrue(contains(t, 'the sweep gate: a matched filter finds the start and the duration of the sweep'));
            tc.verifyTrue(contains(t, 'If the sweep is not found: detected sweep start − 10 ms'));
            % the sweep-margin limits of the analysis: outer line edges (review 2026-10-11)
            tc.verifyTrue(contains(t, 'f_lo/1.3 (91.5 Hz for the default band)'), 'lower limit');
            tc.verifyTrue(contains(t, 'below 1.1 f_hi (4951.1 Hz)'), 'upper limit');
        end

        function glossarySymbols(tc)
            e = strjoin(tc.latex, newline);
            % d is the specimen thickness, never the diameter
            tc.verifyEmpty(regexp(e, '(c\\,d\}|\\pi d\}|c/d\b)', 'once'), 'd used for the diameter');
            % gamma is the coherence; the ratio of specific heats is kappa
            tc.verifyEmpty(regexp(e, '\\gamma\s*=|\\gamma\s*-\s*1', 'once'), 'gamma used for cp/cv');
            % the anechoic coefficient from T is tau_a, never a bare tau
            tc.verifyEmpty(strfind(e, '\tau = \frac{2}'), 'tau_a written as tau');
            % no static pressure p_a, no chain response c_k
            tc.verifyEmpty(regexp(e, 'p_a\}?\s*/\s*101325|c_k|c_\{\\mathrm\{ref\}\}', 'once'));
            % the texts name the control panel as it is: lengths are entered in the IMPEDANCE TUBE
            % section (Tube setup is a view), T and p_s in the fields 'T [°C]' and 'p [kPa]'
            t = strjoin(tc.plain, newline);
            tc.verifyTrue(contains(t, 'as entered in IMPEDANCE TUBE'), 'input section of the positions');
            tc.verifyFalse(contains(t, 'entered in Tube setup'), 'Tube setup is a view, not the input section');
            tc.verifyTrue(contains(t, 'field T [°C]') && contains(t, 'field p [kPa]'), 'field labels of T and p_s');
        end

        function everySectionNamesItsSources(tc)
            % owner request 2026-10-12: every section ends with its sources ([n] of
            % section 13 "References"); the list is that of docs/theory.md, word for word
            g = findall(tc.fig, 'Type', 'uigridlayout', 'Scrollable', 'on');
            kids = g.Children;
            [~, o] = sort(arrayfun(@(h) h.Layout.Row, kids));
            kids = kids(o);
            tags = arrayfun(@(h) h.Tag, kids, 'UniformOutput', false);
            hIdx = [find(strcmp(tags, 'formula:h')); numel(kids) + 1];
            heads = arrayfun(@(h) h.Text, kids(hIdx(1:end - 1)), 'UniformOutput', false);
            tc.verifyEqual(heads{end}, '13. References', 'last section');
            cited = [];
            for i = 1:numel(heads) - 1
                b = hIdx(i) + 1:hIdx(i + 1) - 1;
                src = kids(b(strcmp(tags(b), 'formula:src')));
                tc.verifyNotEmpty(src, ['no sources in section ' heads{i}]);
                tc.verifyEqual(tags{hIdx(i + 1) - 1}, 'formula:src', ['sources end section ' heads{i}]);
                for s = reshape(src, 1, [])
                    tc.verifyTrue(startsWith(s.Text, 'Sources: '), s.Text);
                    tok = regexp(s.Text, '\[(\d+)\]', 'tokens');
                    cited = [cited, cellfun(@(t) str2double(t{1}), tok)]; %#ok<AGROW>
                end
            end
            % the list: [1] .. [N], every entry cited, every citation listed
            rl = findall(tc.fig, 'Type', 'uilabel', 'Tag', 'formula:r');
            num = str2double(regexprep({rl.Text}, '[\[\]]', ''));
            txt = arrayfun(@(h) h.Parent.Children(strcmp({h.Parent.Children.Tag}, 'formula:rtext')).Text, ...
                rl, 'UniformOutput', false);
            [num, o] = sort(num); txt = txt(o);
            tc.verifyEqual(num, 1:numel(num), 'numbered 1..N');
            tc.verifyEmpty(setdiff(num, cited), 'every reference is cited');
            tc.verifyEmpty(setdiff(cited, num), 'every citation is in the list');
            % docs/theory.md: "* [n] text" under "## References", continuation lines indented
            doc = strrep(tim.app.readTextUtf8(fullfile(tim.app.projectRoot(), 'docs', 'theory.md')), char(13), '');
            doc = extractAfter(doc, sprintf('\n## References\n'));
            tc.assertNotEmpty(doc, 'docs/theory.md has a section "## References"');
            e = regexp(doc, '\n\* \[(\d+)\] ([^\n]*(?:\n {2,}[^\n]*)*)', 'tokens');
            dn = cellfun(@(x) str2double(x{1}), e);
            dt = cellfun(@(x) regexprep(x{2}, '\s*\n\s*', ' '), e, 'UniformOutput', false);
            tc.verifyEqual(dn, num, 'same numbers in docs/theory.md');
            if isequal(dn, num)
                for i = 1:numel(num)
                    tc.verifyEqual(txt{i}, dt{i}, sprintf('reference [%d]: Formula tab vs docs/theory.md', num(i)));
                end
            end
        end

        function plainTextHasNoAsciiMath(tc)
            t = strjoin(tc.plain, newline);
            tc.verifyEmpty(regexp(t, '\<(rho|tau|alpha|omega|pi|gamma|delta|kappa|sigma|phi|mu|deg|degC)\>', 'match'));
            tc.verifyEmpty(regexp(t, '[\\$]|_\{|\^\{|\<exp\(j|->', 'match'));
            tc.verifyEmpty(regexp(t, '\<rho c\>|\<sqrt\(', 'match'));
        end
    end

    methods (Static)
        function render(ax, s)
            h = text(ax, 0, 0.5, s, 'Interpreter', 'latex', 'FontSize', 14);
            drawnow;
            delete(h);
        end
    end
end
