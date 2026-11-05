function L = faceLevels(an, pRefPk)
%FACELEVELS Absolute incident pressure and particle velocity at the specimen front face.
%
%   L = tim.acoustics.faceLevels(an, pRefPk)
%
%   an      result of tim.acoustics.analyzeFourMic for pressures RELATIVE to
%           the reference microphone (H = p / p_ref)
%   pRefPk  (Nf x 1) pressure amplitude at the reference microphone [Pa peak]
%
%   The decomposition scales with p_ref, so (docs/theory.md, section 3C)
%       |p_inc| = |A1 e^{-jk xFront}| * pRefPk / sqrt(2)          [Pa rms]
%       L_inc   = 20 log10(|p_inc| / 20 uPa)                       [dB SPL]
%       |u_L|   = 1e3 * |u_L| * pRefPk / sqrt(2)                   [mm/s rms]
%   with u_L of an.boundary (Zc of the loss model). A1 and u_L come from the
%   upstream pair M1/M2 alone. All NaN when the face positions are unknown
%   (an.boundary.available false).
%
%   L fields (Nf x 1): incident_Pa, incident_dB_SPL, faceVelocity_mm_s.

n = numel(an.f);
L = struct('incident_Pa', nan(n, 1), 'incident_dB_SPL', nan(n, 1), 'faceVelocity_mm_s', nan(n, 1));
if ~(isfield(an, 'boundary') && an.boundary.available), return; end
p = abs(pRefPk(:));
inc = abs(an.waves.A1 .* exp(-1j * an.k * an.boundary.xFront)) .* p / sqrt(2);
L.incident_Pa = inc;
L.incident_dB_SPL = 20 * log10(inc / 2e-5);
L.incident_dB_SPL(~(inc > 0)) = NaN;              % no -Inf dB
L.faceVelocity_mm_s = 1e3 * abs(an.boundary.uL) .* p / sqrt(2);
end
