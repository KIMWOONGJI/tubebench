function [fStartMax, fStopMin, band] = sweepGateLimits(fLines, df)
%SWEEPGATELIMITS Sweep range the sweep gate needs around the analysis band.
%   [fStartMax, fStopMin, band] = tim.dsp.sweepGateLimits(fLines, df)
%
%   fLines : the frequency lines of the analysis (or their first and last,
%            e.g. of the grid fMin:df:fMax of tim.app.processMeasurement)
%   df     : width of a line, Hz (each line covers [f - df/2, f + df/2],
%            tim.dsp.sweepResponse)
%   band   : outer edges of the lines, [min(fLines) - df/2, max(fLines) + df/2]
%            = [f_lo f_hi] of docs/theory.md section 4
%
%   The sweep gate of tim.dsp.sweepResponse has room for its ramps outside
%   the band when the sweep starts at or below fStartMax = f_lo/1.3 and
%   stops at or above fStopMin = 1.1 f_hi; an end beyond these gets another
%   window edge (owner decision 2026-10-11). One definition for the analysis
%   (tim.dsp.sweepResponse), the configuration check (tim.app.validateConfig)
%   and their messages, which print floor(fStartMax) and ceil(fStopMin):
%   for 120-4500 Hz at df = 2 Hz, 91 Hz and 4952 Hz.

band = [min(fLines) - df / 2, max(fLines) + df / 2];
fStartMax = band(1) / 1.3;
fStopMin = 1.1 * band(2);
end
