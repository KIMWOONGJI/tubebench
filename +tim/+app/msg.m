function s = msg(lang, key, varargin)
%MSG Operator-facing prompt texts in English ('en', default) or Korean ('ko').
%
%   s = tim.app.msg(cfg.ui.language, 'calConfigI', k, ref, a, k, b)
%   Only texts shown to the operator (prompts, confirmations) are
%   localised; log lines, errors and documentation stay in English.

if isempty(lang), lang = 'en'; end
switch key
    case 'confirmExcitation'   % what, Vpp(open circuit), maxVpp, amplifier line
        % Amplitudes are shown in Vpk (generator open-circuit value,
        % OUTP:LOAD INF); Vpp in brackets.
        a = varargin;
        varargin = {a{1}, a{2} / 2, a{2}, a{3} / 2, a{4}};
        t.ko = ['스피커를 구동합니다 (%s):\n  발생기 %.3g Vpk (= %.3g Vpp, 개방전압; 상한 %.3g Vpk)\n  %s\n' ...
            '위와 같이 안전하게 설정되어 있습니까?'];
        t.en = ['About to drive the loudspeaker (%s):\n  generator %.3g Vpk (= %.3g Vpp, open circuit; limit %.3g Vpk)\n  %s\n' ...
            'Is everything set as stated and safe?'];
    case 'ampDirect'           % Z, Vpk at speaker, mA peak, mW, limit mW
        t.ko = '앰프 없음 (직결): 스피커(%g옴)에 약 %.3g Vpk, %.3g mA peak, %.3g mW (상한 %.4g mW) - 발생기 50옴 출력 경유';
        t.en = 'no amplifier (direct drive): loudspeaker (%g ohm) about %.3g Vpk, %.3g mA peak, %.3g mW (limit %.4g mW) via the 50-ohm generator output';
    case 'ampGain'             % model, gain factor, gain dB, Z, Vpk at speaker, mW, limit mW, setting note
        t.ko = '앰프 %s, 게인 x%.3g (%.1f dB) -> 스피커(%g옴) 약 %.3g Vpk, %.3g mW (상한 %.4g mW)%s';
        t.en = 'amplifier %s, gain x%.3g (%.1f dB) -> loudspeaker (%g ohm) about %.3g Vpk, %.3g mW (limit %.4g mW)%s';
    case 'speakerPower'        % P mW, limit mW
        t.ko = '예상 스피커 전력 %.3g mW가 상한 %.4g mW를 넘습니다 (설정 loudspeaker.maxPower_W). 진폭 또는 앰프 게인을 낮추세요.';
        t.en = 'Estimated loudspeaker power %.3g mW exceeds the limit %.4g mW (config loudspeaker.maxPower_W). Reduce the amplitude or the amplifier gain.';
    case 'gainRequired'
        t.ko = '앰프를 사용할 때는 게인(배수)을 입력해야 합니다. 스피커 전압/전력을 계산할 수 없습니다.';
        t.en = 'With an amplifier the gain (multiplier) must be entered; otherwise the loudspeaker voltage and power cannot be estimated.';
    case 'ampUnknownGain'      % model, setting
        t.ko = '앰프 %s, 게인 미입력%s  -- 앰프 출력을 알 수 없습니다!';
        t.en = 'amplifier %s, gain NOT RECORDED%s  -- amplifier output unknown!';
    case 'modelUnknown'
        t.ko = '(모델 미입력)'; t.en = '(model not specified)';
    case 'gainUnknown'
        t.ko = '기록 안 됨'; t.en = 'NOT RECORDED';
    case 'typeY'
        t.ko = '계속하려면 y, 취소하려면 다른 키를 입력하세요: ';
        t.en = 'Type y to continue, anything else to cancel: ';
    case 'pressEnter'
        t.ko = '    완료되면 ENTER (중단: Ctrl+C) ... ';
        t.en = '    Press ENTER when done (Ctrl+C to abort)... ';
    case 'calConfigI'          % k, ref, a, k, b
        t.ko = '[교정 채널 %d] 구성 I: 기준 마이크(ch%d)를 포트 %d에, ch%d 마이크를 포트 %d에 장착하세요.';
        t.en = 'CONFIG I for channel %d: put the microphone of channel %d (reference) in port %d and the microphone of channel %d in port %d.';
    case 'calConfigIrep'       % k
        t.ko = '[교정 채널 %d] 구성 I 반복: 두 마이크를 뺐다가 같은 포트에 다시 장착하세요 (장착 반복성 확인).';
        t.en = 'CONFIG I (repeat) for channel %d: REMOVE both microphones and re-insert them in the SAME ports (checks mounting repeatability).';
    case 'calConfigII'         % k, ref, b, k, a
        t.ko = '[교정 채널 %d] 구성 II: 두 마이크의 위치를 서로 바꾸세요 (ch%d → 포트 %d, ch%d → 포트 %d). 케이블/채널은 바꾸지 마세요.';
        t.en = 'CONFIG II for channel %d: INTERCHANGE the two microphones: channel %d in port %d, channel %d in port %d. Do not swap cables/channels.';
    case 'calPrepare'          % section text (' (75 mm)' or ''), ports a, b
        t.ko = ['교정 준비: (1) 시편 섹션 자리에 시편을 넣지 않은 빈 시편 섹션%s을 장착하세요. 섹션을 빼고 관을 바로 연결하지 마세요 - ' ...
            '관이 이어진 상태여야 모든 포트가 측정 때와 같은 위치에 있습니다. (2) 종단은 무반사(또는 흡음재)로 하여 정재파를 최소화하세요. ' ...
            '(3) 사용하지 않는 포트는 마이크 또는 더미 플러그로 밀봉하세요. (4) 교정 중 마이크 몸체만 옮기고 케이블/LAN-XI 입력은 바꾸지 마세요. ' ...
            '(5) 온도를 일정하게 유지하세요. 교정 포트: M%d, M%d.'];
        t.en = ['Prepare the calibration: (1) Mount the EMPTY specimen section%s - the middle part WITHOUT the specimen - in place of ' ...
            'the specimen section. Do not take the section out and join the tubes: the tube must stay continuous so that every port keeps ' ...
            'its measurement position. (2) Use an anechoic (or absorbing) termination to minimise standing waves. (3) Seal every port with a ' ...
            'microphone or a dummy plug. (4) During the calibration only the microphone bodies are moved - never the cables or LAN-XI inputs. ' ...
            '(5) Keep the temperature constant. Calibration ports: M%d and M%d.'];
    case 'calDone'
        t.ko = '교정 측정 완료: 모든 마이크를 측정 위치(설정된 채널→포트)로 되돌리세요. 빈 시편 섹션은 아직 그대로 두세요 (빈 관 검증 1회 측정).';
        t.en = ['Calibration measurements finished: return all microphones to their measurement ports (channel -> position as configured). ' ...
            'Keep the EMPTY section mounted for now (one empty-tube check sweep follows).'];
    case 'calMountSpecimen'
        t.ko = '교정 완료: 빈 시편 섹션을 시편이 든 시편 섹션으로 교체하세요 (같은 방향, 플랜지 밀봉). 형상(L1, d, L2)은 설정값 그대로입니다.';
        t.en = ['Calibration complete: replace the EMPTY section by the specimen section (same orientation, flanges sealed). ' ...
            'The geometry (L1, d, L2) stays as configured.'];
    case 'calDoneButton'
        t.ko = '완료 - 측정'; t.en = 'Done - measure';
    case 'abortButton'
        t.ko = '중단'; t.en = 'Abort';
    case 'calStepTitle'
        t.ko = '교정 단계'; t.en = 'Calibration step';
    case 'confirmTitle'
        t.ko = '가진 확인'; t.en = 'Confirm excitation';
    case 'yesPlay'
        t.ko = '예, 재생'; t.en = 'Yes, play';
    case 'cancel'
        t.ko = '취소'; t.en = 'Cancel';
    case 'tapReady'            % seconds
        t.ko = '준비... %d'; t.en = 'Get ready... %d';
    case 'tapNow'              % channel, seconds
        t.ko = '지금 ch%d 마이크에\n가볍게 입김을 부세요\n(%d s)';
        t.en = 'Now blow gently\nonto the ch%d microphone\n(%d s)';
    case 'tapDone'             % found
        t.ko = '완료: 감지 순서 %s'; t.en = 'Done: detected order %s';
    case 'tapStart'
        t.ko = ['채널 확인: 그림 창의 안내에 따라 ch1→ch4 순서로 해당 마이크에만 가볍게 입김을 부세요 ' ...
            '(테이블을 치지 마세요). ENTER를 누르면 시작합니다 ... '];
        t.en = ['Channel identification: follow the figure window and blow gently onto ONLY the indicated ' ...
            'microphone, ch1->ch4 (do not tap the table). Press ENTER to start ... '];
    case 'interchange12'
        t.ko = 'ch1과 ch2 마이크 헤드의 위치를 서로 바꾼 뒤 ENTER ... ';
        t.en = 'Interchange the positions of the ch1 and ch2 microphone heads in the bundle, then ENTER ... ';
    otherwise
        error('tim:msg:key', 'Unknown message key "%s".', key);
end
if ~isfield(t, lang), lang = 'en'; end
s = sprintf(t.(lang), varargin{:});
end
