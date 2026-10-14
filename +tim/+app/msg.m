function s = msg(lang, key, varargin)
%MSG Operator-facing prompt texts in English ('en', default) or Korean ('ko').
%
%   s = tim.app.msg(cfg.ui.language, 'calConfigI', k, ref, a, k, b)
%   cfg.ui.language selects the language of the operator texts of this
%   function: the calibration step prompts (dialog and command window; the
%   prompts are also written to the log in that language by
%   tim.app.runCalibration), the dialog buttons and titles, the excitation
%   confirmation with its drive line (also in the 'Excitation confirmed'
%   log line), the loudspeaker power and amplifier gain errors
%   (tim:session:speakerPower, tim:session:gainRequired), the channel
%   identification and the command-window prompts (Enter / y). All other
%   log lines, errors, window labels and the documentation stay in English.
%   Both languages take the same format arguments in the same order.

if isempty(lang), lang = 'en'; end
switch key
    case 'confirmExcitation'   % what, Vpp (programmed), maxVpp, amplifier line[, generator.load[, open-circuit Vpp]]
        % Amplitudes in Vpk, Vpp in brackets. generator.load 'INF' (default):
        % the programmed value is the open-circuit voltage. A resistance R
        % (the amplifier input, WO-004): it is the voltage across R; the
        % open-circuit voltage is higher (tim.app.driveEstimate: Voc_pp; '50'
        % with the 33220A: twice). The amplitude limit generator.maxVpp is an
        % open-circuit voltage.
        a = varargin;
        ld = 'INF'; if numel(a) >= 5 && ~isempty(a{5}), ld = char(a{5}); end
        if ~strcmp(ld, 'INF')
            voc = 2 * a{2}; if numel(a) >= 6 && ~isempty(a{6}), voc = a{6}; end   % (without it: the 33220A at 50 Ω)
            varargin = {a{1}, a{2} / 2, a{2}, ld, voc / 2, a{3} / 2, a{4}};
            t.ko = ['스피커를 구동합니다 (%s).\n  발생기: %.3g Vpk (%.3g Vpp, %s Ω 부하 기준 설정값 = 앰프 입력 전압; 개방전압 %.3g Vpk); ' ...
                '진폭 상한 개방전압 %.3g Vpk\n  %s\n앰프 게인을 포함한 모든 설정이 위와 같고, 가진을 시작해도 안전합니까?'];
            t.en = ['The loudspeaker will be driven (%s).\n  Generator: %.3g Vpk (%.3g Vpp, programmed into %s Ω = at the ' ...
                'amplifier input; open circuit %.3g Vpk); amplitude limit %.3g Vpk open circuit\n  %s\n' ...
                'Is everything set as shown, including the amplifier gain, and is it safe to start the excitation?'];
        else
            varargin = {a{1}, a{2} / 2, a{2}, a{3} / 2, a{4}};
            t.ko = ['스피커를 구동합니다 (%s).\n  발생기: %.3g Vpk (%.3g Vpp, 개방전압); 진폭 상한 %.3g Vpk\n  %s\n' ...
                '앰프 게인을 포함한 모든 설정이 위와 같고, 가진을 시작해도 안전합니까?'];
            t.en = ['The loudspeaker will be driven (%s).\n  Generator: %.3g Vpk (%.3g Vpp, open circuit); amplitude limit %.3g Vpk\n  %s\n' ...
                'Is everything set as shown, including the amplifier gain, and is it safe to start the excitation?'];
        end
    case 'ampDirect'           % source impedance Ω (driver), Z, Vpk and Vrms at loudspeaker, mA peak, mW, % of limit, limit mW, near text
        t.ko = ['직결 (앰프 없음), 발생기 %g Ω 출력 경유: 스피커 %g Ω (공칭), 약 %.3g Vpk (%.3g Vrms), %.3g mA peak, ' ...
            '%.3g mW = 시험 한계의 %.3g %% (스피커 전력 상한 %.4g mW)%s'];
        t.en = ['Direct drive (no amplifier) via the %g Ω generator output: loudspeaker %g Ω (nominal), approx. %.3g Vpk ' ...
            '(%.3g Vrms), %.3g mA peak, %.3g mW = %.3g %% of the test limit (loudspeaker power limit %.4g mW)%s'];
    case 'ampGain'             % model, gain factor, gain dB, Z, Vpk and Vrms at loudspeaker, mW, % of limit, limit mW, near text, setting note
        t.ko = ['앰프 %s, 게인 ×%.3g (%.1f dB) → 스피커 %g Ω (공칭), 약 %.3g Vpk (%.3g Vrms), %.3g mW = 시험 한계의 %.3g %% ' ...
            '(스피커 전력 상한 %.4g mW)%s%s'];
        t.en = ['Amplifier %s, gain ×%.3g (%.1f dB) → loudspeaker %g Ω (nominal), approx. %.3g Vpk (%.3g Vrms), %.3g mW = ' ...
            '%.3g %% of the test limit (loudspeaker power limit %.4g mW)%s%s'];
    case 'nearLimit'           % appended to the drive line from 80 % of the test limit
        t.ko = ' – 한계 근처: 실제 임피던스가 낮은 주파수에서는 한계에 닿을 수 있습니다';
        t.en = ' – near the limit: at frequencies where the real impedance is lower the limit may be reached';
    case 'speakerPower'        % P mW, limit mW
        t.ko = ['예상 스피커 전력 %.3g mW가 스피커 전력 상한 %.4g mW를 넘습니다 (loudspeaker.maxPower_W). ' ...
            '발생기 진폭 또는 앰프 게인을 낮추세요.'];
        t.en = ['Estimated loudspeaker power %.3g mW exceeds the loudspeaker power limit of %.4g mW ' ...
            '(loudspeaker.maxPower_W). Reduce the generator amplitude or the amplifier gain.'];
    case 'gainRequired'
        t.ko = ['앰프 게인이 입력되지 않았습니다. 파워 앰프의 전압 게인을 배수로 입력하세요 (×10 = 20 dB). ' ...
            '게인이 없으면 스피커 전압과 전력을 계산할 수 없습니다.'];
        t.en = ['Amplifier gain not entered. Enter the voltage gain of the power amplifier as a factor ' ...
            '(×10 = 20 dB); without it the loudspeaker voltage and power cannot be estimated.'];
    case 'ampUnknownGain'      % model, setting
        t.ko = '앰프 %s, 게인 미입력%s – 앰프 출력을 알 수 없습니다.';
        t.en = 'Amplifier %s, gain not entered%s – amplifier output unknown.';
    case 'typeY'
        t.ko = '계속하려면 y, 취소하려면 다른 키를 입력하세요: ';
        t.en = 'Type y to continue, anything else to cancel: ';
    case 'pressEnter'
        t.ko = '    완료되면 Enter를 누르세요 (취소: Ctrl+C)… ';
        t.en = '    Press Enter when done (Ctrl+C to cancel)… ';
    case 'calConfigI'          % k, ref, a, k, b
        t.ko = '[ch%d 교정] 구성 I: 기준 마이크(ch%d)를 포트 M%d (a)에, ch%d 마이크를 포트 M%d (b)에 장착하세요.';
        t.en = 'Configuration I for ch%d: insert the ch%d microphone (reference) in port M%d (a) and the ch%d microphone in port M%d (b).';
    case 'calConfigIrep'       % k
        t.ko = '[ch%d 교정] 구성 I 반복: 두 마이크를 뺐다가 같은 포트에 다시 장착하세요 (재장착 반복성 확인).';
        t.en = 'Configuration I, repeated, for ch%d: remove both microphones and reinsert them in the same ports (checks the remounting repeatability).';
    case 'calConfigII'         % k, ref, b, k, a
        t.ko = ['[ch%d 교정] 구성 II: 두 마이크를 서로 맞바꾸세요 – ch%d 마이크를 포트 M%d (b)에, ch%d 마이크를 포트 M%d (a)에. ' ...
            '케이블은 모두 원래 채널에 그대로 두세요.'];
        t.en = ['Configuration II for ch%d: interchange the two microphones – ch%d microphone in port M%d (b), ' ...
            'ch%d microphone in port M%d (a). Leave every cable on its channel.'];
    case 'calPrepare'          % section text (' (75 mm)' or ''), ports a, b
        t.ko = ['교정 준비: (1) 빈 시편 섹션%s을 장착하세요 (시편을 넣지 않은 시편 섹션). 섹션을 빼고 관을 바로 연결하지 마세요 – ' ...
            '관이 이어진 상태여야 모든 포트가 측정 때와 같은 위치에 있습니다. (2) 흡음 종단을 장착하여 정재파를 최소화하세요. ' ...
            '(3) 모든 포트를 마이크 또는 더미 플러그로 밀봉하세요. (4) 마이크만 옮기고 케이블과 DAQ 입력은 바꾸지 마세요. ' ...
            '(5) 온도를 일정하게 유지하세요. 교정 포트: M%d (a), M%d (b).'];
        t.en = ['Prepare the calibration: (1) Mount the empty specimen section%s, i.e. the specimen section without a specimen. ' ...
            'Do not remove the section and join the tubes: the tube must stay continuous so that every port keeps ' ...
            'its measurement position. (2) Mount the absorbing termination to minimise standing waves. (3) Seal every port with a ' ...
            'microphone or a dummy plug. (4) Move only the microphones – never the cables or DAQ inputs. ' ...
            '(5) Keep the temperature constant. Calibration ports: M%d (a) and M%d (b).'];
    case 'calDone'
        t.ko = ['교정 측정 완료. 모든 마이크를 측정 포트(설정된 채널-포트 배정)로 되돌리세요. ' ...
            '빈 시편 섹션은 그대로 두세요: 빈 관 검사(Test E)를 위한 스윕 1회가 이어집니다.'];
        t.en = ['Calibration measurements complete. Return all microphones to their measurement ports (channel-to-port assignment as configured). ' ...
            'Leave the empty specimen section mounted: one sweep for the empty-tube check (Test E) follows.'];
    case 'calDoneNoCheck'      % reason
        t.ko = '교정 측정 완료. 모든 마이크를 측정 포트(설정된 채널-포트 배정)로 되돌리세요. 빈 관 검사(Test E)는 하지 않습니다: %s.';
        t.en = ['Calibration measurements complete. Return all microphones to their measurement ports (channel-to-port assignment as configured). ' ...
            'The empty-tube check (Test E) is skipped: %s.'];
    case 'calMountSpecimen'
        t.ko = ['교정 완료. 빈 시편 섹션을 시편이 든 시편 섹션으로 교체하세요 (같은 방향, 플랜지 밀봉). ' ...
            '측정 전에 L1, d, L2가 장착한 시편과 맞는지 확인하세요.'];
        t.en = ['Calibration complete. Replace the empty specimen section with the specimen section holding the specimen ' ...
            '(same orientation, flanges sealed). Before measuring, check that L1, d and L2 describe the mounted specimen.'];
    case 'calAborted'          % the calibration ended before it was saved
        t.ko = ['교정이 중단되었습니다 (저장되지 않음). 측정 전에 모든 마이크를 측정 포트(설정된 채널-포트 배정)로 ' ...
            '되돌리고 시편이 든 시편 섹션을 장착하세요.'];
        t.en = ['Calibration ended before it was saved. Before measuring, return all microphones to their measurement ' ...
            'ports (channel-to-port assignment as configured) and mount the specimen section.'];
    case 'calDoneButton'
        t.ko = '측정'; t.en = 'Measure';
    case 'calContinueButton'   % operator steps without a measurement (prepare, mount the specimen)
        t.ko = '계속'; t.en = 'Continue';
    case 'abortButton'
        t.ko = '교정 취소'; t.en = 'Cancel calibration';
    case 'calStepTitle'
        t.ko = '교정 단계'; t.en = 'Calibration step';
    case 'calStepHeader'       % step n, number of steps N (first line of the calibration dialog)
        t.ko = '교정 단계 %d / %d'; t.en = 'Calibration step %d of %d';
    case 'calSeeDiagram'       % last line of the calibration dialog ("Calibration" = view name in the GUI)
        t.ko = '(Calibration 화면의 그림을 참고하세요)'; t.en = '(see the diagram in the Calibration view)';
    case 'confirmTitle'
        t.ko = '가진 확인'; t.en = 'Confirm excitation';
    case 'yesPlay'
        t.ko = '가진 시작'; t.en = 'Start excitation';
    case 'cancel'
        t.ko = '취소'; t.en = 'Cancel';
    case 'tapReady'            % seconds
        t.ko = '준비… %d'; t.en = 'Get ready… %d';
    case 'tapNow'              % channel, seconds
        t.ko = '지금 ch%d 마이크에\n가볍게 입김을 부세요\n(%d s)';
        t.en = 'Now blow gently\nonto the ch%d microphone\n(%d s)';
    case 'tapDone'             % found
        t.ko = '완료: 감지 순서 %s'; t.en = 'Done: detected order %s';
    case 'tapStart'
        t.ko = ['채널 확인: 그림 창의 안내에 따라 ch1 → ch4 순서로 표시된 마이크에만 가볍게 입김을 부세요 ' ...
            '(테이블을 치지 마세요). Enter를 누르면 시작합니다… '];
        t.en = ['Channel identification: follow the figure window and blow gently onto the indicated ' ...
            'microphone only, ch1 → ch4 (do not tap the table). Press Enter to start… '];
    case 'interchange12'
        t.ko = '묶음 안에서 ch1과 ch2 마이크를 서로 맞바꾼 뒤 Enter를 누르세요… ';
        t.en = 'Interchange the ch1 and ch2 microphones in the bundle, then press Enter… ';
    % ---- two-load measurement (WO-005, tim.app.runTwoLoad): the termination of
    % each load (distance of its face behind M4 as text, e.g. '291 mm')
    case 'tlMount_absorber_tubeEnd'
        t.ko = '연장관 안에 흡음재, end cap 닫음 (종단 면: M4에서 %s)';
        t.en = 'the extension tube with the absorber inside, the end cap on (face %s behind M4)';
    case 'tlMount_rigid_tubeEnd'
        t.ko = '흡음재를 뺀 빈 연장관, end cap을 닫고 밀폐 (종단 면: M4에서 %s)';
        t.en = 'the extension tube empty (absorber removed), the end cap on and sealed (face %s behind M4)';
    case 'tlMount_open_tubeEnd'
        t.ko = '흡음재를 뺀 빈 연장관, end cap 없음: 관이 M4에서 %s 지점에서 열림';
        t.en = 'the extension tube empty (absorber removed), the end cap off: the tube open %s behind M4';
    case 'tlMount_rigid_joint'
        t.ko = '연장관을 분리하고 joint 플랜지에 강체 마개를 밀폐해 장착 (종단 면: M4에서 %s)';
        t.en = 'the extension tube removed, a rigid cap sealed on the joint flange (face %s behind M4)';
    case 'tlMount_open_joint'
        t.ko = '연장관을 분리하고 joint를 열어 둠 (관 끝: M4에서 %s)';
        t.en = 'the extension tube removed, the joint left open (%s behind M4)';
    case 'tlFirst'             % load name (A), its label, its mount text
        t.ko = ['종단 %s: %s – %s. 이 상태로 장착되어 있는지 확인하세요. 모든 종단 측정 동안 시편 구간과 마이크는 ' ...
            '그대로 둡니다.'];
        t.en = ['Load %s: %s – %s. Check that the tube is terminated so. The specimen section and the microphones ' ...
            'stay untouched for all loads.'];
    case 'tlSwap'              % load name (B, A again), its label, its mount text
        t.ko = '종단 %s: %s – %s. 종단을 이렇게 바꾸세요. 시편 구간과 마이크는 건드리지 마세요.';
        t.en = 'Load %s: %s – %s. Change the termination to this; do not touch the specimen section or the microphones.';
    case 'tlRepeatName'
        t.ko = 'A (반복)'; t.en = 'A (repeat)';
    case 'tlStepHeader'        % step n, number of steps N
        t.ko = '두 종단 측정 단계 %d / %d'; t.en = 'Two-load step %d of %d';
    case 'tlDone'              % label of the load mounted at the end
        t.ko = '두 종단 측정 완료. 지금 장착된 종단: %s.'; t.en = 'Two-load measurement complete. Mounted now: %s.';
    case 'tlMeasureButton'
        t.ko = '측정'; t.en = 'Measure';
    case 'tlAbortButton'
        t.ko = '측정 중단'; t.en = 'Abort';
    otherwise
        error('tim:msg:key', 'Unknown message key "%s".', key);
end
if ~isfield(t, lang), lang = 'en'; end
s = sprintf(t.(lang), varargin{:});
end
