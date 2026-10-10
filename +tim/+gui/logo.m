function file = logo(variant, px)
%LOGO Path of the tubebench mark ("four ports").
%
%   file = tim.gui.logo()               % light version, SVG (white / light backgrounds)
%   file = tim.gui.logo('reverse')      % reverse version, SVG (dark header, P.ui.bar #334A63)
%   file = tim.gui.logo('light', 32)    % PNG, 32 x 32 px, transparent background
%   file = tim.gui.logo('reverse', 256) %   (any size; 16, 32, 48 and 256 px are in the repository)
%   file = tim.gui.logo('icon')         % window icon (uifigure 'Icon'): light PNG, 32 px
%
%   The mark: the tube (capsule outline) with the specimen block in the
%   middle and the four microphones above it in the channel colours
%   (ch1 blue, ch2 raspberry, ch3 bluish green, ch4 dark yellow, as
%   tim.gui.palette().ch). The SVG files in resources/logo/ are the master
%   (viewBox 0 0 64 64): uiimage shows them sharply at any size. The
%   uifigure 'Icon' takes only PNG, JPEG or GIF (R2022b), so PNG versions
%   are drawn from the same shapes (anti-aliased) and written next to the
%   SVG files the first time they are needed.

if nargin < 1 || isempty(variant), variant = 'light'; end
if nargin < 2, px = []; end
if strcmp(variant, 'icon'), variant = 'light'; px = 32; end
assert(any(strcmp(variant, {'light', 'reverse'})), 'tim:gui:logo', 'Unknown logo variant "%s".', variant);
folder = fullfile(tim.app.projectRoot(), 'resources', 'logo');
name = 'tubebench-mark';
if strcmp(variant, 'reverse'), name = [name '-reverse']; end
if isempty(px)
    file = fullfile(folder, [name '.svg']);
    return
end
file = fullfile(folder, sprintf('%s-%d.png', name, px));
if ~isfile(file)
    if ~isfolder(folder), mkdir(folder); end
    [img, alpha] = drawMark(variant, px);
    imwrite(img, file, 'Alpha', alpha);
end
end

function [img, alpha] = drawMark(variant, N)
% the shapes of the SVG (64 x 64 units, y down), painted in SVG order,
% 4096 samples per pixel side at most, averaged to N x N pixels
hex = @(h) double(sscanf(h(2:end), '%2x')).' / 255;
if strcmp(variant, 'reverse')
    tube = hex('#FFFFFF');
    mics = {hex('#5AB0F0'), hex('#F06A9F'), hex('#33C99A'), hex('#E8C547')};
else
    tube = hex('#334A63');
    mics = {hex('#0072B2'), hex('#C2185B'), hex('#009E73'), hex('#BF9900')};
end
S = max(4, min(16, floor(2048 / N)));            % supersampling
M = N * S;
u = ((1:M) - 0.5) / M * 64;                        % sample centres in SVG units
[X, Y] = meshgrid(u, u);
masks = {}; colors = {};
% tube: rect x 4..60, y 34..48, rx 7 = a capsule (centre line 11..53 at y 41,
% radius 7), stroke 3 centred on the outline
dTube = seg(X, Y, [11 41], [53 41]);
masks{end + 1} = abs(dTube - 7) <= 1.5; colors{end + 1} = tube;
% specimen block: x 26..38, y 34..48
masks{end + 1} = X >= 26 & X <= 38 & Y >= 34 & Y <= 48; colors{end + 1} = tube;
% microphones: line y 33..18 (width 4, round caps), circle r 3.5 at y 14
xm = [10 18 46 54];
for i = 1:4
    masks{end + 1} = seg(X, Y, [xm(i) 33], [xm(i) 18]) <= 2; colors{end + 1} = mics{i}; %#ok<AGROW>
end
for i = 1:4
    masks{end + 1} = hypot(X - xm(i), Y - 14) <= 3.5; colors{end + 1} = mics{i}; %#ok<AGROW>
end
% compose (painted in order) and average S x S blocks (premultiplied alpha)
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
    img(:, :, c) = down(rgb(:, :, c) .* a) ./ max(alpha, eps);
end
img = min(max(img, 0), 1);
end

function d = seg(X, Y, a, b)
% distance of every sample to the segment a-b
ab = b - a; t = ((X - a(1)) * ab(1) + (Y - a(2)) * ab(2)) / sum(ab.^2);
t = min(max(t, 0), 1);
d = hypot(X - (a(1) + t * ab(1)), Y - (a(2) + t * ab(2)));
end
