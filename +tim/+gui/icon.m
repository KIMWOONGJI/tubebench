function file = icon(name)
%ICON Path of a status icon for the GUI checklists (created on first use).
%
%   file = tim.gui.icon('ok')      % 'pending' | 'run' | 'ok' | 'warn' | 'fail' | 'skip' | 'start' | 'stop'
%
%   'run' is an animated GIF (rotating arc). It is animated by the figure
%   window itself, so it keeps turning while MATLAB is busy (e.g. during the
%   slow LAN-XI channel setup). The others are PNG with transparency.
%   The files are written to resources/icons/ the first time they are needed.

persistent folder
if isempty(folder)
    folder = fullfile(tim.app.projectRoot(), 'resources', 'icons');
end
if strcmp(name, 'run'), ext = '.gif'; else, ext = '.png'; end
file = fullfile(folder, [name ext]);
if ~exist(file, 'file')
    makeIcons(folder);
end
end

function makeIcons(folder)
if ~exist(folder, 'dir'), mkdir(folder); end
P = tim.gui.palette();
N = 40; S = 4; M = N * S;                         % 40 px icons, 4x supersampling
[X, Y] = meshgrid(((1:M) - 0.5) / M * 2 - 1);     % [-1, 1], y down
R = hypot(X, Y);
white = [1 1 1];
grey = [0.62 0.62 0.62];
circle = R < 0.92;
% pending: grey ring
writePng(folder, 'pending', {abs(R - 0.78) < 0.11}, {grey}, S);
% ok: green disc + white check mark
chk = seg(X, Y, [-0.45 0.02], [-0.12 0.36], 0.13) | seg(X, Y, [-0.12 0.36], [0.48 -0.34], 0.13);
writePng(folder, 'ok', {circle, chk}, {P.ok, white}, S);
% warn: amber disc + "!"
ex = seg(X, Y, [0 -0.52], [0 0.12], 0.13) | hypot(X, Y - 0.43) < 0.13;
writePng(folder, 'warn', {circle, ex}, {P.warn, white}, S);
% fail: red disc (P.fail) + "x"
cr = seg(X, Y, [-0.36 -0.36], [0.36 0.36], 0.13) | seg(X, Y, [-0.36 0.36], [0.36 -0.36], 0.13);
writePng(folder, 'fail', {circle, cr}, {P.fail, white}, S);
% skip: light grey disc + dash
writePng(folder, 'skip', {circle, seg(X, Y, [-0.4 0], [0.4 0], 0.12)}, {[0.8 0.8 0.8], white}, S);
% start / stop: white symbols for the coloured Start measurement / Stop buttons
tri = X >= -0.42 & abs(Y) <= 0.62 * (0.62 - X) / 1.04;
writePng(folder, 'start', {tri}, {white}, S);
writePng(folder, 'stop', {abs(X) < 0.5 & abs(Y) < 0.5}, {white}, S);
% run: animated arc on a light track; transparent background (edges blended
% with the default figure colour), so it also fits the lighter panels
bg = [0.94 0.94 0.94];
nF = 12; th = atan2(Y, X);
track = abs(R - 0.72) < 0.15;
file = fullfile(folder, 'run.gif');
for k = 1:nF
    a0 = 2 * pi * (k - 1) / nF;
    d = mod(th - a0, 2 * pi);
    arc = track & d < 0.6 * pi;
    img = compose({track, arc}, {[0.84 0.87 0.92], P.run}, bg, S);
    [ind, map] = rgb2ind(img, 32, 'nodither');
    t = double(ind(1, 1));                        % corner = background (0-based index)
    if k == 1
        imwrite(ind, map, file, 'gif', 'LoopCount', Inf, 'DelayTime', 0.07, ...
            'TransparentColor', t, 'DisposalMethod', 'restoreBG');
    else
        imwrite(ind, map, file, 'gif', 'WriteMode', 'append', 'DelayTime', 0.07, ...
            'TransparentColor', t, 'DisposalMethod', 'restoreBG');
    end
end
end

function m = seg(X, Y, a, b, w)
% pixels within distance w of the segment a-b
ab = b - a; t = ((X - a(1)) * ab(1) + (Y - a(2)) * ab(2)) / sum(ab.^2);
t = min(max(t, 0), 1);
m = hypot(X - (a(1) + t * ab(1)), Y - (a(2) + t * ab(2))) < w;
end

function writePng(folder, name, masks, colors, S)
[img, alpha] = compose(masks, colors, [], S);
imwrite(img, fullfile(folder, [name '.png']), 'Alpha', alpha);
end

function [img, alpha] = compose(masks, colors, bg, S)
% layers painted in order; anti-aliased by averaging SxS blocks
M = size(masks{1}, 1); N = M / S;
rgb = zeros(M, M, 3); a = zeros(M, M);
for i = 1:numel(masks)
    for c = 1:3
        ch = rgb(:, :, c); ch(masks{i}) = colors{i}(c); rgb(:, :, c) = ch;
    end
    a(masks{i}) = 1;
end
down = @(z) squeeze(mean(mean(reshape(z, S, N, S, N), 1), 3));
alpha = down(a);
img = zeros(N, N, 3);
for c = 1:3
    pre = down(rgb(:, :, c) .* a);                       % premultiplied
    if isempty(bg)
        img(:, :, c) = pre ./ max(alpha, eps);
    else
        img(:, :, c) = pre + (1 - alpha) * bg(c);
    end
end
img = min(max(img, 0), 1);
end
