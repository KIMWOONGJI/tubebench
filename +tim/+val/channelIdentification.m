function r = channelIdentification(session, opts)
%CHANNELIDENTIFICATION Verify the DAQ channel <-> microphone mapping (Test A).
%
%   r = tim.val.channelIdentification(session)
%   r = tim.val.channelIdentification(session, struct('waitForEnter', false))
%
%   One continuous recording (NO generator output). A figure window shows a
%   countdown: get ready (2 s), then for each channel ch1..ch4 (6 s each)
%   the operator blows gently onto ONLY that microphone (wind noise is very
%   local; tapping the table or a taped bundle excites all microphones and
%   cannot separate them - observed on the bench 2026-10-08).
%   For every segment the channel with the largest > 200 Hz energy
%   (in Pa, sensitivity layer) must be the instructed one, by > 6 dB.
%   Prompts follow cfg.ui.language ('ko' default).

if nargin < 2, opts = struct(); end
o = struct('waitForEnter', true, 'tReady', 2, 'tSeg', 6, 'hpFreq', 200, 'showFigure', true);
fn = fieldnames(opts); for i = 1:numel(fn), o.(fn{i}) = opts.(fn{i}); end
lang = session.lang();
daq = session.Daq;
fs = daq.SampleRate;
nCh = 4;
if o.waitForEnter
    input(tim.app.msg(lang, 'tapStart'), 's');
end
nTot = round((o.tReady + nCh * o.tSeg) * fs);
ht = [];
if o.showFigure
    hf = figure('Name', 'Channel identification', 'Color', 'w', 'Position', [200 200 900 420], ...
        'MenuBar', 'none', 'NumberTitle', 'off');
    ht = uicontrol(hf, 'Style', 'text', 'Units', 'normalized', 'Position', [0.02 0.1 0.96 0.8], ...
        'FontSize', 40, 'FontWeight', 'bold', 'BackgroundColor', 'w', 'String', '');
    figure(hf); drawnow;
end
    function update(n)
        if isempty(ht) || ~isvalid(ht), return; end
        t = n / fs;
        if t < o.tReady
            txt = tim.app.msg(lang, 'tapReady', ceil(o.tReady - t));
        else
            k = min(nCh, floor((t - o.tReady) / o.tSeg) + 1);
            txt = tim.app.msg(lang, 'tapNow', k, ceil(o.tSeg - mod(t - o.tReady, o.tSeg)));
        end
        set(ht, 'String', txt); drawnow('limitrate');
    end
[x, info] = daq.acquire(nTot, @update);
[b, a] = butter(4, o.hpFreq / (fs / 2), 'high');
y = filtfilt(b, a, x - mean(x, 1)) ./ [session.Mics.sensitivity_VperPa];
lev = zeros(nCh, nCh);
for k = 1:nCh
    i1 = round((o.tReady + (k - 1) * o.tSeg + 0.5) * fs) + 1;
    i2 = round((o.tReady + k * o.tSeg - 0.5) * fs);
    lev(k, :) = 10 * log10(mean(y(i1:i2, :).^2, 1) / 4e-10);
end
[srt, idx] = sort(lev, 2, 'descend');
found = idx(:, 1).';
dom = (srt(:, 1) - srt(:, 2)).';
r = struct('name', 'Test A - channel identification', 'levels_dB', lev, ...
    'expectedChannel', 1:nCh, 'foundChannel', found, 'dominance_dB', dom, ...
    'integrityOk', info.integrity.ok, 'passed', isequal(found, 1:nCh) && all(dom > 6));
r.criteria = 'in every segment the instructed channel is the loudest (> 200 Hz) by more than 6 dB';
if ~isempty(ht) && isvalid(ht)
    set(ht, 'String', tim.app.msg(lang, 'tapDone', mat2str(found))); drawnow;
end
end
