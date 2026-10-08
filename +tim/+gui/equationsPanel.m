function equationsPanel(parent)
%EQUATIONSPANEL Scrollable overview of all equations used by the software.
%   tim.gui.equationsPanel(uitabOrPanel)
%   Equations are rendered with the LaTeX interpreter of uilabel. The text
%   mirrors docs/theory.md (detailed derivations and references there).

items = {
 'h', '0. Conventions'
 't', 'Time dependence exp(+j omega t). Axis x from the loudspeaker towards the termination. Forward wave A, backward wave B. Velocity u positive towards +x.'
 'e', '$p(x) = A\,e^{-jkx} + B\,e^{+jkx}, \qquad u(x) = \frac{A\,e^{-jkx} - B\,e^{+jkx}}{\rho c}$'

 'h', '1. Microphone calibration by sensor switching (phase and amplitude)'
 't', 'Each complete chain (microphone + cable + CCLD + LAN-XI input) has a complex response c. Measured: Y = c p. Microphone k and the reference microphone are placed in ports a and b (configuration I), then the two microphone bodies are interchanged (configuration II); cables and inputs are NOT changed.'
 'e', '$H^{I} = \frac{Y_k}{Y_{ref}} = \frac{c_k\,p_b}{c_{ref}\,p_a}, \qquad H^{II} = \frac{Y_k}{Y_{ref}} = \frac{c_k\,p_a}{c_{ref}\,p_b}$'
 'e', '$C_k = \frac{c_k}{c_{ref}} = \sqrt{H^{I}\,H^{II}}, \qquad \frac{p_b}{p_a} = \sqrt{\frac{H^{I}}{H^{II}}}, \qquad \hat{H}_k = \frac{H_k}{C_k}$'
 't', 'Branch of the square root: the phase of H^I H^II is unwrapped over valid frequencies and halved; the multiple of pi is chosen so that the phase of C_k is near 0 at low frequency (matched microphones). Low-coherence / low-SNR bins are excluded and flagged. Interpolation uses log|C| and the unwrapped phase.'

 'h', '2. Relative responses from the swept sine (no generator/DAQ synchronisation needed)'
 'e', '$Y_c(f) = P(x_c,f)\,c_c(f)\,S(f) \;\Rightarrow\; H_c = \frac{\sum Y_c\,Y_{ref}^{*}}{\sum |Y_{ref}|^{2}}, \qquad \gamma_c^{2} = \frac{|\sum Y_c\,Y_{ref}^{*}|^{2}}{\sum |Y_{ref}|^{2}\,\sum |Y_c|^{2}}$'
 't', 'The unknown excitation spectrum S(f) cancels (sweep law, trigger time, generator clock, loudspeaker distortion). Sums over FFT bins within each band and over repetitions.'

 'h', '3. Plane-wave decomposition (pair M1/M2 upstream, M3/M4 downstream)'
 'e', '$A = \frac{p_1\,e^{jkx_2} - p_2\,e^{jkx_1}}{2j\,\sin k(x_2 - x_1)}, \qquad B = \frac{p_2\,e^{-jkx_1} - p_1\,e^{-jkx_2}}{2j\,\sin k(x_2 - x_1)}$'
 't', 'Singular when k s = n pi (s = microphone spacing). The condition number of this 2x2 system is reported per frequency.'

 'h', '4. Pressure and particle velocity at the sample faces (x_L front, x_R rear)'
 'e', '$p_L = A_1 e^{-jkx_L} + B_1 e^{jkx_L}, \quad u_L = \frac{A_1 e^{-jkx_L} - B_1 e^{jkx_L}}{\rho c}, \quad p_R = A_2 e^{-jkx_R} + B_2 e^{jkx_R}, \quad u_R = \frac{A_2 e^{-jkx_R} - B_2 e^{jkx_R}}{\rho c}$'

 'h', '5. Reflection and transmission coefficients'
 'e', '$R = \frac{B_1\,e^{jkx_L}}{A_1\,e^{-jkx_L}}, \qquad \tau = \frac{A_2\,e^{-jkx_R}}{A_1\,e^{-jkx_L}}, \qquad R_{term} = \frac{B_2\,e^{jkx_R}}{A_2\,e^{-jkx_R}}, \qquad \alpha = 1 - |R|^{2} - |\tau|^{2}$'
 't', 'tau and alpha are intrinsic sample properties only for an anechoic termination (|R_term| small).'

 'h', '6. Transfer impedance (thin element)'
 'e', '$Z_t = \frac{p_L - p_R}{u}, \qquad u = \frac{u_L + u_R}{2}, \qquad \delta_u = \frac{|u_L - u_R|}{\max(|u_L|,|u_R|)}$'
 't', 'Valid for an element of negligible thickness with (nearly) continuous velocity; frequencies with velocity mismatch above 10 % are flagged invalid. Normalised: Z_t / rho c.'

 'h', '7. Transmission loss'
 'e', '$\mathbf{T}_{thin}:\; T_{11}=1,\; T_{12}=Z_t,\; T_{21}=0,\; T_{22}=1 \;\Rightarrow\; \tau = \frac{2}{2 + Z_t/\rho c}, \qquad TL = 20\log_{10}\left|1 + \frac{Z_t}{2\rho c}\right|$'
 'e', '$TL_{\tau} = -20\log_{10}|\tau| \qquad (\mathrm{anechoic\ termination\ only})$'

 'h', '8. General two-port (thick samples): two-load method'
 'e', '$p_L = T_{11}\,p_R + T_{12}\,u_R, \qquad u_L = T_{21}\,p_R + T_{22}\,u_R$'
 'e', '$\mathbf{T} = \mathbf{P}\,\mathbf{Q}^{-1}, \qquad \mathbf{P} = [\,(p_L^{a}, u_L^{a})^{T} \;\; (p_L^{b}, u_L^{b})^{T}\,], \qquad \mathbf{Q} = [\,(p_R^{a}, u_R^{a})^{T} \;\; (p_R^{b}, u_R^{b})^{T}\,]$'
 'e', '$TL = 20\log_{10}\left|\frac{T_{11} + T_{12}/\rho c + \rho c\,T_{21} + T_{22}}{2}\right|$'
 't', 'Two measurements (a, b) with different terminations are required: one excitation state gives only 2 equations for the 4 unknowns.'

 'h', '9. Air and tube losses (ISO 10534-2)'
 'e', '$c = 343.2\sqrt{\frac{T}{293\,\mathrm{K}}}, \qquad \rho = 1.186\,\frac{p_a}{101325}\,\frac{293\,\mathrm{K}}{T}, \qquad k = \frac{\omega}{c} - j\,\frac{1.94\cdot10^{-2}\sqrt{f}}{c\,d}$'

 'h', '10. Frequency limits (d = 29 mm, s = 29 mm: 118 Hz ... 4.73 kHz)'
 'e', '$0.01\,\frac{c}{s} \;<\; f \;<\; \min\left(0.40\,\frac{c}{s},\; \frac{1.84\,c}{\pi d}\right), \qquad f_{singular} = \frac{c}{2s}$'
 't', 'Valid = measured AND geometry-permitted AND quality OK (coherence, SNR, complex calibration) AND passive. "Validated" only inside experimentally validated bands.'
};

g = uigridlayout(parent, [size(items, 1) 1], 'Scrollable', 'on', 'RowSpacing', 6, ...
    'Padding', [20 15 20 15], 'RowHeight', repmat({'fit'}, 1, size(items, 1)));
for i = 1:size(items, 1)
    switch items{i, 1}
        case 'h'
            l = uilabel(g, 'Text', items{i, 2}, 'FontWeight', 'bold', 'FontSize', 15, 'FontColor', [0 0.3 0.6]);
        case 't'
            l = uilabel(g, 'Text', items{i, 2}, 'WordWrap', 'on', 'FontSize', 12, 'FontColor', [0.25 0.25 0.25]);
        case 'e'
            l = uilabel(g, 'Text', items{i, 2}, 'Interpreter', 'latex', 'FontSize', 17);
    end
    l.Layout.Row = i;
end
end
