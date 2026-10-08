function p = palette()
%PALETTE Common colours of all plots (Okabe-Ito, colour-blind safe).
%   p.ch(c,:)    colour of DAQ channel / position c (1..4)
%   p.a, p.b, p.c  first / second / third quantity in a plot
%   p.invalid    values outside the valid mask
%   p.grid       light grid / annotation grey
p.ch = [0.000 0.447 0.698      % blue
        0.835 0.369 0.000      % vermillion
        0.000 0.620 0.451      % bluish green
        0.800 0.475 0.655];    % reddish purple
p.a = p.ch(1, :);
p.b = p.ch(2, :);
p.c = p.ch(3, :);
p.d = [0.902 0.624 0.000];     % orange
p.invalid = [0.80 0.80 0.80];
p.grid = [0.55 0.55 0.55];
p.lineWidth = 1.2;
end
