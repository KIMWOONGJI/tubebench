function [ttl, desc] = viewText(key)
%VIEWTEXT Title and one-line description of a measurement / result view.
%   [title, description] = tim.plots.viewText('reflection')
%   keys = tim.plots.viewText()                   all keys, in view order
%
%   One source for the header of a view in the GUI (tim.gui.ViewPage) and of
%   its saved figure (tim.app.plotResults), so that both say the same.
%   Keys = field names of tim.app.plotResults: waveforms, spectrum,
%   transfer, reflection, transmissionLoss, impedance, validity.
%   Plain text with Unicode symbols, as a uilabel shows it; the saved
%   figures convert it to TeX (X_word -> subscript).
T = {
    'waveforms', 'Time signals', ['Sound pressure of the four channels (voltage / sensitivity), live during an ' ...
        'acquisition. Display high-pass 20 Hz; the raw data are stored in volts.']
    'spectrum', 'Spectrum', ['Power spectral density of the sound pressure (swept sine, noise, background noise) ' ...
        'or the level of every step (stepped sine). Dashed: analysis band.']
    'transfer', 'Transfer functions', ['Calibrated transfer functions H = p(port) / p(reference) of the four ' ...
        'ports, their phase and the coherence of every channel.']
    'reflection', 'Reflection and transmission', ['Reflection coefficient R at the specimen front face, ' ...
        'transmission coefficient τ to the rear face and dissipation coefficient α_d = 1 − |R|² − |τ|². ' ...
        'Grey: outside the valid range.']
    'transmissionLoss', 'Transmission loss', ['Normal-incidence transmission loss TL from τ = −20 log10 |τ| ' ...
        '(anechoic termination); thin specimens also TL from Z_t. Grey: outside the valid range.']
    'impedance', 'Transfer impedance', ['Thin-element transfer impedance Z_t = (p_front − p_rear) / u, ' ...
        'normalised by ρc (thin specimens only: k·d ≪ 1). Grey: outside the valid range.']
    'validity', 'Validity', ['Which frequency lines meet each criterion (geometry, coherence and SNR, ' ...
        'passivity, anechoic termination, thin-element velocity match).']
    };
if nargin < 1
    ttl = T(:, 1).';
    return
end
i = find(strcmp(T(:, 1), key), 1);
if isempty(i)
    error('tim:plots:viewText', 'Unknown view "%s" (known: %s).', char(key), strjoin(T(:, 1).', ', '));
end
ttl = T{i, 2}; desc = T{i, 3};
end
