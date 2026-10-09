function p = palette()
%PALETTE Common colours of the GUI and of all plots.
%   p.ch(c,:)    colour of DAQ channel c (1..4) - used ONLY for channels
%                (waveforms, spectra, transfer functions, cards, 3D model)
%   p.q.*        colours of physical quantities that are not channels
%                (R, tau, alpha, R_term, TL, Zt ...), never a channel colour
%   p.invalid    values outside the valid mask (whole curve drawn underneath)
%   p.ok/warn/fail/run/idle   status colours (lamps, checklists); always
%                shown together with an icon or a text, never alone
%   p.ui.*       colours of the window (section bars, panels, texts)
% Channels 1-3 and the quantities use the Okabe-Ito palette (colour-blind safe);
% ch4 is a darkened yellow (contrast about 2.7:1 on white).
p.ch = [0.000 0.447 0.698      % ch1 blue
        0.835 0.369 0.000      % ch2 vermillion
        0.000 0.620 0.451      % ch3 bluish green
        0.750 0.600 0.000];    % ch4 dark yellow (#BF9900; pure yellow is too light on white)
% quantities (Okabe-Ito black, orange, sky blue, yellow-dark, grey)
p.q.first = [0.10 0.10 0.10];   % |R|, Re{Zt}/rho c, TL from tau
p.q.second = [0.902 0.624 0.000]; % |tau|, Im{Zt}/rho c, TL from Zt
p.q.third = [0.337 0.706 0.914];  % alpha (dissipation)
p.q.ref = [0.45 0.45 0.45];     % reference curves (|R_term|, limits, model)
p.a = p.q.first;               % legacy names (first / second / third quantity)
p.b = p.q.second;
p.c = p.q.third;
p.d = [0.902 0.624 0.000];     % orange
p.invalid = [0.72 0.72 0.72];  % outside the valid mask (visible on white)
p.invalidMarker = [0.55 0.55 0.55];
% status colours (lamps, checklists): distinct from the channel colours
p.ok = [0.18 0.60 0.24];
p.warn = [0.93 0.58 0.00];
p.fail = [0.82 0.16 0.16];
p.run = [0.10 0.45 0.80];
p.idle = [0.75 0.75 0.75];
p.grid = [0.55 0.55 0.55];
p.lineWidth = 1.2;
% window
p.ui.bar = [0.20 0.29 0.39];       % section bars of the control panel (white text)
p.ui.barText = [1 1 1];
p.ui.panel = [0.97 0.97 0.98];     % control panel background
p.ui.header = [0.94 0.95 0.97];    % header strip of a view
p.ui.text = [0.13 0.13 0.15];
p.ui.muted = [0.40 0.42 0.45];     % secondary text (units, notes)
p.ui.accent = [0.10 0.45 0.80];    % links, selected items
p.ui.attention = [1.00 0.95 0.75]; % field background: a value must be entered
p.ui.start = [0.16 0.55 0.29];     % START button
p.ui.stop = [0.80 0.18 0.18];      % STOP / ABORT button
end
