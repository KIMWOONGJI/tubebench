classdef TestInstrumentContract < matlab.unittest.TestCase
    %TESTINSTRUMENTCONTRACT Every registered driver meets the instrument contract.
    %
    %   docs/instrument_interface.md section 11 (WO-001 task 8). Each driver
    %   runs in simulation mode on its protocol mock, built through the
    %   registry (tim.instr.create) on one tim.sim.SimulatedRig; the duties
    %   are observed through the driver's static testHooks (the instrument
    %   as the mock sees it), so no duty is tested for one driver only.
    %   Parameters: driver = every registered driver; source / acquisition =
    %   the drivers with that role; instrumentSource, separateAcquisition and
    %   blockDevice the drivers of the cases that apply only to them (see
    %   registered). A combined driver is created for both roles. A source
    %   that plays a planned output (combined block device, section 8.3) is
    %   switched on inside the planning pass of an acquisition (whilePlaying);
    %   the block cases check what was really played with the rig's
    %   OutputLog and the driver's playedSignal hook.

    properties (TestParameter)
        driver = TestInstrumentContract.registered('')
        source = TestInstrumentContract.registered('source')
        acquisition = TestInstrumentContract.registered('acquisition')
        instrumentSource = TestInstrumentContract.registered('instrumentReadback')
        separateAcquisition = TestInstrumentContract.registered('separateAcquisition')
        blockDevice = TestInstrumentContract.registered('blockDevice')
    end

    methods (Static)
        function p = registered(kind)
            %REGISTERED Registered driver names of a kind, as a struct: '' all,
            %   'source' / 'acquisition' the drivers with that role,
            %   'instrumentReadback' sources whose output state is read back
            %   from the instrument, 'separateAcquisition' acquisitions that work
            %   with a separate source, 'blockDevice' combined drivers that play
            %   a planned output (section 8.3).
            list = tim.instr.drivers();
            p = struct();
            for i = 1:numel(list)
                c = feval([list(i).class '.capabilities']);
                isSource = any(strcmp('source', c.roles));
                isAcq = any(strcmp('acquisition', c.roles));
                switch kind
                    case '', take = true;
                    case {'source', 'acquisition'}, take = any(strcmp(kind, c.roles));
                    case 'instrumentReadback', take = isSource && strcmp(c.source.readback, 'instrument');
                    case 'separateAcquisition', take = isAcq && ~c.rolesTogether;
                    case 'blockDevice', take = isAcq && c.rolesTogether && strcmp(c.acquisition.mode, 'block');
                end
                if take, p.(list(i).name) = list(i).name; end
            end
        end
    end

    methods
        function cfg = config(~, role, name)
            % simulation configuration selecting driver name for role; the
            % other role keeps its default driver unless name must take both
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            cfg.generator.maxVpp = 0.5;
            cfg.daq = struct('driver', 'lanxi');
            cfg.generator.driver = 'keysight33220a';
            c = capabilitiesOf(name);
            if strcmp(role, 'source') || c.rolesTogether, cfg.generator.driver = name; end
            if strcmp(role, 'acquisition') || c.rolesTogether, cfg.daq.driver = name; end
        end

        function [obj, h, cfg, rig] = make(tc, role, name, cfg)
            % one driver in simulation through the registry (closed at teardown)
            if nargin < 4, cfg = tc.config(role, name); end
            rig = tim.sim.SimulatedRig(cfg);
            ctx = struct('mode', 'simulation', 'rig', rig, 'progress', []);
            obj = tim.instr.create(role, cfg, ctx);
            tc.addTeardown(@() obj.close());
            quiet(obj);
            h = feval([class(obj) '.testHooks'], obj);
        end

        function c = channelSetup(~, cfg)
            % prepare() input from the acquisition section of the configuration
            a = cfg.acquisition;
            c = struct('sampleRate', a.sampleRate, 'range', a.range, 'filter', a.filter, 'ccld', a.ccld, ...
                'channels', 1:4, 'detectTeds', a.detectTeds, 'names', {{'M1', 'M2', 'M3', 'M4'}});
        end

        function [acq, h, cfg, rig] = preparedAcquisition(tc, name)
            [acq, h, cfg, rig] = tc.make('acquisition', name);
            acq.prepare(tc.channelSetup(cfg));
        end

        function err = whilePlaying(tc, src, h, cfg, action)
            % switch the configured output on and run action while it plays:
            % an instrument at once; a planned (block) output inside the
            % execution pass of an acquisition (on from sample B, action at 3B).
            % Returns the error that ended the acquisition ([] = none).
            err = [];
            if ~isBlockSource(src)
                src.armOutput(true); src.outputOn();
                tc.verifyTrue(h.outputOn(), 'the output plays');
                action();
                return
            end
            src.prepare(tc.channelSetup(cfg));
            src.armOutput(true);
            B = 2048; done = false;
            function onBlock(n)
                if src.isPlanning()
                    if n == B, src.outputOn(); end
                elseif ~done && n >= 3 * B
                    done = true;
                    tc.verifyTrue(h.outputOn(), 'the output plays');
                    action();
                end
            end
            try
                src.acquire(8 * B, @onBlock);
            catch err
            end
            tc.verifyTrue(done, 'the action ran while the output played');
        end

        function [p, on] = playSweep(tc, src, h, cfg, s)
            % a configured sweep played by a block source with the session's
            % schedule: on and triggered at the pre-roll, off after waitComplete;
            % p = the played output samples, on = the planned trigger sample
            src.prepare(tc.channelSetup(cfg));
            fs = src.SampleRate; B = 2048;
            nPre = 4 * B; nSweep = round(s.duration * fs);
            on = NaN; off = NaN; early = false;
            function onBlock(n)
                if ~src.isPlanning(), return; end
                if isnan(on) && n >= nPre
                    src.outputOn(); src.triggerSweep(); on = n;
                elseif ~isnan(on) && isnan(off)
                    if n < on + nSweep
                        early = early || src.waitComplete(0);
                    else
                        tc.verifyTrue(src.waitComplete(5), 'the sweep has ended on the device timeline');
                        src.outputOff(); off = n;
                    end
                end
            end
            src.armOutput(true);
            src.acquire(nPre + nSweep + 4 * B, @onBlock);
            src.armOutput(false);
            tc.verifyFalse(early, 'waitComplete is never true before the sweep has ended');
            tc.verifyFalse(isnan(off), 'the sweep was switched off inside the record');
            tc.verifyFalse(h.outputOn());
            p = h.playedSignal();
        end
    end

    methods (Test)
        %% ---------------- every driver ----------------
        function describeAndCapabilitiesConsistent(tc, driver)
            d = tim.instr.driverInfo(driver);
            tc.verifyEqual(d.name, driver, 'describe().name is the registry name');
            tc.verifyNotEmpty(d.displayName);
            tc.verifyTrue(any(strcmp(d.simulation, {'protocol', 'only'})));
            tc.verifyTrue(isstruct(d.defaults.settings));
            tc.verifyTrue(ischar(d.texts.settle));
            c = d.capabilities;
            tc.verifyNotEmpty(c.roles);
            tc.verifyTrue(all(ismember(c.roles, {'source', 'acquisition'})));
            tc.verifyTrue(islogical(c.sharedClock) && islogical(c.rolesTogether));
            tc.verifyTrue(isstruct(c.products) && all(isfield(c.products, {'name', 'feature'})));
            tc.verifyFalse(c.rolesTogether && numel(c.roles) < 2, 'rolesTogether only for a combined driver');
            mc = meta.class.fromName(d.class);
            for r = c.roles
                base = struct('source', 'tim.instr.SignalSource', 'acquisition', 'tim.instr.Acquisition');
                tc.verifyTrue(any(strcmp(base.(r{1}), superclassNames(mc))), sprintf('%s derives from %s', d.class, base.(r{1})));
                tc.verifyNotEmpty(d.labels.(r{1}), 'lamp label per role');
            end
            if any(strcmp('source', c.roles))
                s = c.source;
                tc.verifyTrue(any(strcmp('sweep', s.waveforms)), 'a swept sine is required (calibration, Test E)');
                tc.verifyTrue(all(ismember(s.waveforms, {'sine', 'sweep', 'noise'})));
                tc.verifyTrue(all(ismember(s.sweepSpacing, {'LOG', 'LIN'})) && ~isempty(s.sweepSpacing));
                tc.verifyTrue(s.frequencyRange(1) > 0 && s.frequencyRange(2) > s.frequencyRange(1));
                tc.verifyTrue(s.frequencyRange(1) <= 80, 'excitation from 80 Hz');
                tc.verifyEqual(numel(s.maxVpp), numel(s.loads));
                tc.verifyEqual(numel(s.minVpp), numel(s.loads));
                tc.verifyTrue(all(s.minVpp >= 0 & s.minVpp < s.maxVpp));
                tc.verifyTrue(s.sweepTime(1) > 0 && s.sweepTime(2) > s.sweepTime(1));
                tc.verifyGreaterThanOrEqual(s.outputImpedance_ohm, 0);
                tc.verifyTrue(any(strcmp(s.trigger, {'bus', 'software', 'clock'})));
                tc.verifyTrue(any(strcmp(s.readback, {'instrument', 'device', 'none'})));
                tc.verifyFalse(strcmp(s.readback, 'device') && ~c.sharedClock, ...
                    'read-back of the device session only for a shared-clock combined device');
                tc.verifyTrue(islogical(s.levelKnown));
                tc.verifyGreaterThan(s.noiseCrest, 1);
            end
            if any(strcmp('acquisition', c.roles))
                q = c.acquisition;
                tc.verifyGreaterThanOrEqual(q.channels, 4);
                tc.verifyTrue(q.simultaneous, 'all inputs on one clock');
                tc.verifyTrue(~isempty(q.sampleRates) || numel(q.sampleRateRange) == 2);
                tc.verifyTrue(q.bandFraction > 0 && q.bandFraction <= 0.5);
                tc.verifyTrue(iscellstr(q.ranges) && iscellstr(q.filters));
                tc.verifyTrue(islogical(q.ccld) && islogical(q.teds) && islogical(q.needsOwnSource));
                tc.verifyTrue(any(strcmp(q.dataUnit, {'V', 'FS'})));
                tc.verifyTrue(any(strcmp(q.mode, {'streaming', 'block'})));
                tc.verifyFalse(q.needsOwnSource && ~(c.rolesTogether && c.sharedClock), ...
                    'a driver that cannot deliver data while recording must be its own source');
                def = d.defaults.acquisition;
                tc.verifyTrue(any(strcmp(def.range, q.ranges)) && any(strcmp(def.filter, q.filters)));
            end
            s = d.steps;
            tc.verifyTrue(all(isfield(s, {'key', 'label', 'role', 'phase'})));
            tc.verifyTrue(all(ismember({s.role}, [c.roles, {'both'}])));
            tc.verifyTrue(all(ismember({s.phase}, {'connect', 'prepare'})));
            % the driver accepts the default configuration that selects it
            report = feval([d.class '.checkConfig'], tc.config(c.roles{1}, driver));
            tc.verifyTrue(iscellstr(report) || isempty(report)); %#ok<ISCLSTR>
        end

        function stepKeysUnique(tc)
            % keys of every pair of drivers that can be combined are unique,
            % and never the session's own steps
            list = tim.instr.drivers();
            info = arrayfun(@(e) tim.instr.driverInfo(e.name), list, 'UniformOutput', false);
            src = info(cellfun(@(d) any(strcmp('source', d.capabilities.roles)), info));
            acq = info(cellfun(@(d) any(strcmp('acquisition', d.capabilities.roles)), info));
            for ia = 1:numel(src)
                for ib = 1:numel(acq)
                    a = src{ia}; b = acq{ib};
                    same = strcmp(a.name, b.name);
                    if ~same && (a.capabilities.rolesTogether || b.capabilities.rolesTogether), continue; end
                    if same, keys = {a.steps.key}; else, keys = [{a.steps.key}, {b.steps.key}]; end
                    tc.verifyEqual(numel(unique(keys)), numel(keys), sprintf('%s + %s', a.name, b.name));
                    tc.verifyFalse(any(ismember(keys, {'sens', 'settle', 'signal'})), 'session step keys are reserved');
                end
            end
        end

        function identityAndMetadataComplete(tc, driver)
            c = capabilitiesOf(driver);
            obj = tc.make(c.roles{1}, driver);
            id = obj.identity();
            for f = {'vendor', 'model', 'serial', 'firmware', 'raw'}
                tc.verifyTrue(ischar(id.(f{1})), f{1});
            end
            tc.verifyNotEmpty(id.model, 'the instrument reported its model');
            tc.verifyNotEmpty(id.raw);
            md = obj.metadata();
            tc.verifyEqual(md.driver, driver);
            d = tim.instr.driverInfo(driver);
            tc.verifyEqual(md.displayName, d.displayName);
            tc.verifyEqual(md.identity, id);
            tc.verifyTrue(all(ismember(md.roles, c.roles)));
            tc.verifyEqual(md.sharedClock, c.sharedClock);
            tc.verifyTrue(isstruct(md.settings));
            txt = jsonencode(md);                                   % stored as metadata.json
            tc.verifyNotEmpty(txt);
        end

        function secondCloseSendsNothing(tc, driver)
            c = capabilitiesOf(driver);
            [obj, h] = tc.make(c.roles{1}, driver);
            obj.close();
            n = numel(h.traffic());
            obj.close();
            obj.setTimeout(1);
            tc.verifyEqual(numel(h.traffic()), n, 'a second close() sends nothing');
            if isa(obj, 'tim.instr.SignalSource')
                obj.outputOff();
                tc.verifyFalse(h.outputOn());
                tc.verifyError(@() obj.configureSine(1000, 0.2), ?MException);
                tc.verifyError(@() obj.outputOn(), ?MException);
            end
            if isa(obj, 'tim.instr.Acquisition')
                tc.verifyError(@() obj.prepare(tc.channelSetup(tc.config('acquisition', driver))), 'tim:instr:closed');
                tc.verifyError(@() obj.acquire(1024), 'tim:instr:closed');
            end
            tc.verifyEqual(numel(h.traffic()), n, 'nothing is sent after close()');
        end

        function lostLinkNeverThrows(tc, driver)
            % instrument switched off / cable pulled: outputOff and close return
            % at once without an error (a warning is allowed)
            c = capabilitiesOf(driver);
            [obj, h] = tc.make(c.roles{1}, driver);
            if isa(obj, 'tim.instr.Acquisition'), obj.prepare(tc.channelSetup(tc.config('acquisition', driver))); end
            h.breakLink();
            ws = warning('off', 'all'); restore = onCleanup(@() warning(ws));
            t0 = tic;
            if isa(obj, 'tim.instr.SignalSource'), obj.outputOff(); end
            obj.close();
            tc.verifyLessThan(toc(t0), 5, 'bounded in time');
            clear restore
        end

        %% ---------------- sources ----------------
        function outputOffAfterCreation(tc, source)
            [src, h] = tc.make('source', source);
            tc.verifyFalse(h.outputOn(), 'the instrument output is off after creation');
            tc.verifyFalse(src.OutputArmed);
            tc.verifyFalse(src.isOutputOn());
        end

        function outputOffAfterClose(tc, source)
            [src, h, cfg] = tc.make('source', source);
            src.configureSine(1000, 0.2);
            err = tc.whilePlaying(src, h, cfg, @() src.close());
            tc.verifyFalse(h.outputOn(), 'close switches the output off');
            tc.verifyFalse(src.OutputArmed, 'close disarms');
            if isBlockSource(src)
                tc.verifyEqual(err.identifier, 'tim:instr:closed', 'close ends the running acquisition');
                log = h.outputLog();
                tc.verifyEqual(log(end, 4), 0, 'the last output value is 0 V');
            end
        end

        function outputOffAfterDriverError(tc, source)
            [src, h, cfg] = tc.make('source', source);
            src.configureSine(1000, 0.2);
            if isBlockSource(src)
                % the device reports an error while it plays: the acquisition ends with it
                err = tc.whilePlaying(src, h, cfg, @() h.injectError());
                tc.verifyNotEmpty(err, 'the device error ends the acquisition');
            else
                tc.whilePlaying(src, h, cfg, @() h.injectError());
                tc.verifyError(@() src.setFrequency(500), ?MException);
            end
            tc.verifyFalse(h.outputOn(), 'an instrument error leaves the output off');
        end

        function levelLimitEnforced(tc, source)
            [src, h, cfg] = tc.make('source', source);
            c = capabilitiesOf(src); c = c.source;
            lim = cfg.generator.maxVpp;
            sw = struct('fStart', 80, 'fStop', 5500, 'duration', 1, 'spacing', c.sweepSpacing{1}, 'amplitudeVpp', 1.5 * lim);
            tc.verifyError(@() src.configureSine(1000, 1.5 * lim), 'tim:gen:amplitude');
            tc.verifyError(@() src.configureSweep(sw), 'tim:gen:amplitude');
            if any(strcmp('noise', c.waveforms))
                tc.verifyError(@() src.configureNoise(1.5 * lim), 'tim:gen:amplitude');
            end
            tc.verifyError(@() src.configureSine(1000, 0), 'tim:gen:amplitude');
            tc.verifyError(@() src.configureSine(1000, -0.1), 'tim:gen:amplitude');
            k = find(strcmp(cfg.generator.load, c.loads), 1);
            if c.minVpp(k) > 0
                tc.verifyError(@() src.configureSine(1000, 0.5 * c.minVpp(k)), 'tim:gen:amplitude');
            end
            tc.verifyTrue(all(h.levelHistory() <= lim), 'no level above the limit reached the instrument');
            src.configureSine(1000, 0.4 * lim);
            tc.verifyEqual(h.levelHistory(), 0.4 * lim, 'RelTol', 1e-3, 'only the allowed level was programmed');
            tc.verifyFalse(h.outputOn());
            if isfield(h, 'forceLevel')
                % level changed at the instrument behind the driver: outputOn re-checks it
                src.armOutput(true);
                h.forceLevel(1.5 * lim);
                tc.verifyError(@() src.outputOn(), 'tim:gen:amplitude');
                tc.verifyFalse(h.outputOn());
                src.armOutput(false);
            end
        end

        function outputOnOnlyArmedAndConfigured(tc, source)
            [src, h, cfg] = tc.make('source', source);
            tc.verifyError(@() src.outputOn(), 'tim:gen:notArmed');
            src.armOutput(true);
            tc.verifyError(@() src.outputOn(), 'tim:gen:mode', 'not configured');
            src.armOutput(false);
            src.configureSine(1000, 0.2);
            tc.verifyError(@() src.outputOn(), 'tim:gen:notArmed');
            tc.verifyFalse(h.outputOn());
            if isBlockSource(src)
                % a planned output is switched on only inside an acquisition (section 3.5)
                src.armOutput(true);
                tc.verifyError(@() src.outputOn(), 'tim:gen:schedule');
                tc.verifyFalse(src.isOutputOn(), 'false outside acquire');
                tc.verifyFalse(h.outputOn());
                err = tc.whilePlaying(src, h, cfg, @() src.configureSine(500, 0.2));
                tc.verifyEqual(err.identifier, 'tim:gen:schedule', 'no level change while the plan plays');
                tc.verifyFalse(h.outputOn(), 'the output stops with the acquisition');
                src.armOutput(false);
                return
            end
            src.armOutput(true); src.outputOn();
            tc.verifyTrue(h.outputOn());
            src.configureSine(500, 0.2);
            tc.verifyFalse(h.outputOn(), 'configure* leaves the output off');
            src.outputOn();
            src.armOutput(false);
            tc.verifyFalse(h.outputOn(), 'armOutput(false) switches the output off');
            src.outputOff(); src.outputOff();                    % idempotent
            tc.verifyFalse(h.outputOn());
        end

        function sweepConfigurationRoundTrip(tc, source)
            [src, h, cfg] = tc.make('source', source);
            c = capabilitiesOf(src); c = c.source;
            for sp = c.sweepSpacing
                s = struct('fStart', 80, 'fStop', 5500, 'duration', 1, 'spacing', sp{1}, 'amplitudeVpp', 0.2);
                src.configureSweep(s);                           % read back by the driver
                tc.verifyFalse(h.outputOn(), 'configureSweep leaves the output off');
                tc.verifyError(@() src.setFrequency(500), 'tim:gen:mode');
                if isBlockSource(src)
                    tc.verifyError(@() src.triggerSweep(), 'tim:gen:schedule', 'the sweep starts on the device clock');
                    tc.playSweep(src, h, cfg, s);
                    continue
                end
                src.armOutput(true); src.outputOn();
                src.triggerSweep();
                tc.verifyTrue(src.waitComplete(5), 'the sweep completes');
                src.outputOff();
                tc.verifyFalse(h.outputOn());
                src.armOutput(false);
            end
            bad = struct('fStart', 80, 'fStop', 5500, 'duration', 2 * c.sweepTime(2), 'spacing', c.sweepSpacing{1}, 'amplitudeVpp', 0.2);
            tc.verifyError(@() src.configureSweep(bad), 'tim:gen:sweep');
            bad.duration = 1; bad.fStart = 0;
            tc.verifyError(@() src.configureSweep(bad), 'tim:gen:sweep');
            bad.fStart = 80; bad.spacing = 'CUBIC';
            tc.verifyError(@() src.configureSweep(bad), 'tim:gen:sweep');
            src.configureSine(1000, 0.2);
            tc.verifyError(@() src.triggerSweep(), 'tim:gen:mode');
            tc.verifyFalse(h.outputOn());
        end

        function readBackFromTheInstrument(tc, instrumentSource)
            % read-back kind 'instrument' (the other kinds cannot be proved this way)
            [src, h] = tc.make('source', instrumentSource);
            h.forceOutputOn();                                   % front panel / another program
            tc.verifyTrue(src.isOutputOn(), 'isOutputOn asks the instrument, not a cached flag');
            tc.verifyTrue(src.isOutputOn(1), 'with a time-out');
            src.outputOff();
            tc.verifyFalse(src.isOutputOn(1));
            tc.verifyFalse(h.outputOn());
        end

        %% ---------------- acquisitions ----------------
        function acquireShapeRateUnitIntegrity(tc, acquisition)
            [acq, ~, cfg] = tc.preparedAcquisition(acquisition);
            c = capabilitiesOf(acq); c = c.acquisition;
            tc.verifyEqual(acq.SampleRate, cfg.acquisition.sampleRate, 'exactly the configured rate');
            tc.verifyFalse(acq.isAcquiring());
            tc.verifyFalse(acq.isPlanning(), 'no planning without a combined source');
            n = 8192;
            [x, info] = acq.acquire(n);
            tc.verifyEqual(size(x), [n 4]);
            tc.verifyClass(x, 'double');
            tc.verifyEqual(info.fs, repmat(acq.SampleRate, size(info.fs)), 'RelTol', 1e-9);
            tc.verifyEqual(info.dataUnit, c.dataUnit);
            g = info.integrity;
            tc.verifyTrue(g.ok, strjoin(g.fatal, ' | '));
            tc.verifyTrue(iscell(g.fatal) && iscell(g.warnings));
            tc.verifySize(g.peakFractionOfRange, [1 4]);
            tc.verifyTrue(all(g.peakFractionOfRange >= 0 & g.peakFractionOfRange < 1));
            tc.verifySize(g.channelFaults, [1 4]);
            tc.verifyTrue(all(cellfun(@isempty, g.channelFaults)));
            tc.verifyFalse(acq.isAcquiring(), 'stopped after acquire');
            [y, info2] = acq.collect(n);
            tc.verifyEqual(y, x);
            tc.verifyEqual(info2.integrity.ok, g.ok);
            [r, nTotal] = acq.recent(1000);
            tc.verifyEqual(size(r), [1000 4]);
            tc.verifyGreaterThanOrEqual(nTotal, n);
            tc.verifyEqual(r(end, :), x(end, :), 'AbsTol', 1e-12, 'recent ends with the newest sample');
            b = acq.rawBytes();
            tc.verifyClass(b, 'uint8');
            [x2, info3] = acq.acquire(n);                        % the next acquire works
            tc.verifyEqual(size(x2), [n 4]);
            tc.verifyTrue(info3.integrity.ok);
        end

        function channelFaultInIntegrity(tc, acquisition)
            [acq, h] = tc.preparedAcquisition(acquisition);
            h.injectChannelFault(2);
            [~, info] = acq.acquire(4096);
            g = info.integrity;
            tc.verifyFalse(g.ok, 'a device-reported channel fault is fatal');
            tc.verifyNotEmpty(g.channelFaults{2}, 'reported on input 2, in words');
            tc.verifyTrue(iscellstr(g.channelFaults{2}));
            tc.verifyTrue(all(cellfun(@isempty, g.channelFaults([1 3 4]))));
        end

        function stopDuringAcquire(tc, acquisition)
            % Stop while recording (a block device: in its execution pass)
            [acq, h] = tc.preparedAcquisition(acquisition);
            function onBlock(n)
                if acq.isPlanning(), return; end
                if n >= 4096, error('tim:session:stopped', 'Measurement stopped by user.'); end
            end
            tc.verifyError(@() acq.acquire(32768, @onBlock), 'tim:session:stopped', 'the error passes unchanged');
            tc.verifyFalse(h.isRecording(), 'the device stopped recording');
            tc.verifyFalse(acq.isAcquiring());
            x = acq.collect();
            tc.verifyGreaterThanOrEqual(size(x, 1), 4096, 'partial data kept');
            tc.verifyEqual(size(x, 2), 4);
            y = acq.acquire(4096);                               % the next acquire works
            tc.verifyEqual(size(y), [4096 4]);
        end

        function abortFcnFirstOnEveryAbnormalEnd(tc, acquisition)
            [acq, h] = tc.preparedAcquisition(acquisition);
            aborts = []; atBlock = NaN;
            acq.AbortFcn = @() recordAbort();
            function recordAbort()
                aborts(end + 1) = numel(h.traffic());
            end
            % normal end: no abort
            acq.acquire(4096, @(n) []);
            tc.verifyEmpty(aborts, 'AbortFcn is not called on a normal end');
            % error thrown by onBlock: abort before any further request
            function failingBlock(n)
                atBlock = numel(h.traffic());
                if n >= 4096, error('test:onBlock', 'failure in onBlock'); end
            end
            tc.verifyError(@() acq.acquire(32768, @failingBlock), 'test:onBlock');
            tc.verifyNumElements(aborts, 1, 'once');
            tc.verifyEqual(aborts(1), atBlock, 'AbortFcn before any stop request');
            tc.verifyFalse(h.isRecording());
            % error raised by the driver itself (data stop arriving)
            aborts = [];
            h.stallAfter(4096);
            function countingBlock(~)
                atBlock = numel(h.traffic());
            end
            tc.verifyError(@() acq.acquire(32768, @countingBlock, 60), ?MException);
            tc.verifyNumElements(aborts, 1, 'once');
            tc.verifyEqual(aborts(1), atBlock, 'AbortFcn before any stop request');
            tc.verifyFalse(h.isRecording());
            % a failing AbortFcn does not hide the error
            h.stallAfter(Inf);
            acq.AbortFcn = @() error('test:abort', 'abort failed');
            ws = warning('off', 'tim:instr:abortFcn'); restore = onCleanup(@() warning(ws));
            tc.verifyError(@() acq.acquire(32768, @failingBlock), 'test:onBlock');
            clear restore
        end

        function closeInsideAcquire(tc, acquisition)
            % close() while recording (a block device: in its execution pass)
            [acq, h] = tc.preparedAcquisition(acquisition);
            function onBlock(n)
                if acq.isPlanning(), return; end
                if n >= 4096, acq.close(); end
            end
            tc.verifyError(@() acq.acquire(32768, @onBlock), 'tim:instr:closed');
            tc.verifyFalse(h.isRecording(), 'close() stopped the device');
            tc.verifyFalse(acq.isAcquiring());
            x = acq.collect();
            tc.verifyGreaterThanOrEqual(size(x, 1), 4096, 'the data received stay available');
            n = numel(h.traffic());
            tc.verifyError(@() acq.acquire(4096), 'tim:instr:closed');
            acq.close();
            tc.verifyEqual(numel(h.traffic()), n, 'nothing is sent after close()');
        end

        function excitationRecordedWithSeparateSource(tc, separateAcquisition)
            % data-driven timing (section 8.2): a separate source switched on
            % and off from onBlock lies inside the record
            cfg = tc.config('acquisition', separateAcquisition);
            list = tim.instr.drivers();
            srcName = '';
            for i = 1:numel(list)
                c = capabilitiesOf(list(i).name);
                if any(strcmp('source', c.roles)) && ~c.rolesTogether, srcName = list(i).name; break; end
            end
            tc.assumeNotEmpty(srcName, 'no separate source driver registered');
            cfg.generator.driver = srcName;
            rig = tim.sim.SimulatedRig(cfg);
            ctx = struct('mode', 'simulation', 'rig', rig, 'progress', []);
            src = tim.instr.create('source', cfg, ctx);
            tc.addTeardown(@() src.close());
            acq = tim.instr.create('acquisition', cfg, ctx, src);
            tc.addTeardown(@() acq.close());
            quiet(acq);
            hs = feval([class(src) '.testHooks'], src);
            acq.prepare(tc.channelSetup(cfg));
            fs = acq.SampleRate;
            s = struct('fStart', 200, 'fStop', 2000, 'duration', 0.5, 'spacing', 'LOG', 'amplitudeVpp', 0.2);
            src.configureSweep(s);
            nPre = round(0.5 * fs); nSweep = round(s.duration * fs); nTotal = nPre + nSweep + round(0.5 * fs);
            on = NaN; off = NaN;
            function onBlock(n)
                if isnan(on) && n >= nPre
                    src.outputOn(); src.triggerSweep(); on = n;
                elseif ~isnan(on) && isnan(off) && n >= on + nSweep
                    src.waitComplete(5); src.outputOff(); off = n;
                end
            end
            src.armOutput(true);
            x = acq.acquire(nTotal, @onBlock);
            src.armOutput(false);
            tc.verifyFalse(hs.outputOn());
            tc.assertFalse(isnan(off), 'the schedule ran inside the acquisition');
            ex = tim.dsp.detectExcitation(x(:, 1), fs, [s.fStart s.fStop], 12, 0.5);
            tc.verifyTrue(ex.detected, 'the excitation was recorded');
            tc.verifyGreaterThan(ex.start_s, 0.4, 'after the pre-roll');
            tc.verifyLessThan(ex.end_s, nTotal / fs, 'inside the record');
            tc.verifyGreaterThan(ex.duration_s, 0.8 * s.duration);
        end

        %% ---------------- combined block device (planned output, section 8.3) ----------------
        function plannedActionsPlayedSampleExactly(tc, blockDevice)
            % every source call of the planning pass takes effect at its sample
            [dev, h, cfg] = tc.make('acquisition', blockDevice);
            dev.configureSine(1000, 0.2);
            dev.prepare(tc.channelSetup(cfg));
            fs = dev.SampleRate; B = 2048; fadeN = round(5e-3 * fs);
            function onBlock(n)
                if ~dev.isPlanning(), return; end
                switch n
                    case B, dev.outputOn();
                    case 3 * B, dev.configureSine(500, 0.2);          % output off at 3B, new frequency
                    case 4 * B, dev.outputOn();
                    case 6 * B, dev.armOutput(false);                 % off at 6B
                end
            end
            dev.armOutput(true);
            x = dev.acquire(8 * B, @onBlock);
            tc.verifySize(x, [8 * B 4]);
            p = h.playedSignal();
            tc.verifyEqual(p(1:B), zeros(B, 1), 'nothing before outputOn');
            tc.verifyGreaterThan(max(abs(p(B + 1:B + 20))), 0.05, 'on from sample B');
            tc.verifyLessThan(max(abs(p(3 * B + 1:3 * B + fadeN))), 0.1 + 1e-12, 'fade at 3B');
            tc.verifyEqual(p(3 * B + fadeN + 1:4 * B), zeros(B - fadeN, 1), 'off (0 V) from 3B + 5 ms');
            seg = p(4 * B + 1:6 * B);
            f = nnz(diff(sign(seg)) ~= 0) / 2 / (numel(seg) / fs);
            tc.verifyEqual(f, 500, 'RelTol', 0.02, 'the frequency planned at 3B');
            tc.verifyEqual(p(6 * B + fadeN + 1:end), zeros(2 * B - fadeN, 1), 'off at 6B (5 ms fade)');
            log = h.outputLog();
            tc.verifyEqual(log(end, 4), 0, 'the last output value is 0 V');
            tc.verifyFalse(h.outputOn());
        end

        function stopDuringPlanningPlaysNothing(tc, blockDevice)
            [dev, h, cfg, rig] = tc.make('acquisition', blockDevice);
            dev.configureSine(1000, 0.2);
            dev.prepare(tc.channelSetup(cfg));
            rows = size(rig.OutputLog, 1);
            function onBlock(n)
                if ~dev.isPlanning(), return; end
                if n == 2048, dev.outputOn(); end
                if n >= 4 * 2048
                    dev.outputOff();                                  % the window's Stop ...
                    error('tim:session:stopped', 'Measurement stopped by user.');   % ... and the session's check
                end
            end
            dev.armOutput(true);
            tc.verifyError(@() dev.acquire(8 * 2048, @onBlock), 'tim:session:stopped');
            log = rig.OutputLog(rows + 1:end, :);
            tc.verifyTrue(all(log(:, 3) == 0), 'nothing was played');
            tc.verifyEqual(log(end, 4), 0);
            tc.verifyFalse(h.outputOn());
            tc.verifyFalse(h.isRecording());
            tc.verifyEmpty(dev.collect(), 'nothing recorded');
            dev.armOutput(false);
            tc.verifySize(dev.acquire(4096), [4096 4], 'the next acquisition works');
        end

        function stopDuringExecutionEndsOutputWithinOneBlock(tc, blockDevice)
            [dev, h, cfg, rig] = tc.make('acquisition', blockDevice);
            dev.configureSine(1000, 0.2);
            dev.prepare(tc.channelSetup(cfg));
            B = dev.metadata().settings.blockSamples;
            s0 = rig.SampleCounter; stopAt = NaN;
            function onBlock(n)
                if dev.isPlanning()
                    if n == B, dev.outputOn(); end
                elseif n >= 4 * B
                    stopAt = n;
                    dev.outputOff();                                  % the window's Stop ...
                    error('tim:session:stopped', 'Measurement stopped by user.');   % ... and the session's check
                end
            end
            dev.armOutput(true);
            tc.verifyError(@() dev.acquire(16 * B, @onBlock), 'tim:session:stopped');
            dev.armOutput(false);
            log = rig.OutputLog;
            k = find(log(:, 3) > 0, 1, 'last');
            tc.verifyLessThanOrEqual(log(k, 1) + log(k, 2), s0 + stopAt + B, 'output ended within one block');
            tc.verifyEqual(log(end, 4), 0, 'the last output value is 0 V');
            tc.verifyFalse(h.outputOn());
            tc.verifyGreaterThanOrEqual(size(dev.collect(), 1), stopAt, 'partial data kept');
        end

        function onBlockErrorLeavesOutputAtZero(tc, blockDevice)
            [dev, h, cfg, rig] = tc.make('acquisition', blockDevice);
            dev.configureNoise(0.2);
            dev.prepare(tc.channelSetup(cfg));
            function onBlock(n)
                if dev.isPlanning()
                    if n == 2048, dev.outputOn(); end
                elseif n >= 5 * 2048
                    error('test:onBlock', 'failure in onBlock');
                end
            end
            dev.armOutput(true);
            tc.verifyError(@() dev.acquire(12 * 2048, @onBlock), 'test:onBlock', 'the error passes unchanged');
            dev.armOutput(false);
            tc.verifyFalse(h.outputOn());
            tc.verifyEqual(rig.OutputLog(end, 4), 0, 'the last output value is 0 V');
        end

        function plannedSweepFollowsItsLaw(tc, blockDevice)
            % the played sweep: exponential law, duration within 0.5 % (section 3.3),
            % started at the planned sample; waitComplete never true before its end
            [dev, h, cfg] = tc.make('acquisition', blockDevice);
            s = struct('fStart', 80, 'fStop', 5500, 'duration', 2, 'spacing', 'LOG', 'amplitudeVpp', 0.2);
            dev.configureSweep(s);
            [p, on] = tc.playSweep(dev, h, cfg, s);
            fs = dev.SampleRate;
            law = tim.dsp.estimateSweepLaw(p, fs, s.fStart, s.fStop, 'LOG', s.duration);
            tc.verifyEqual(law.duration_s, s.duration, 'RelTol', 0.005);
            tc.verifyEqual(law.startTime_s, on / fs, 'AbsTol', 2 * 256 / fs);
            log = h.outputLog();
            tc.verifyEqual(log(end, 4), 0, 'the last output value is 0 V');
        end

        %% ---------------- one object in both roles ----------------
        function combinedRoleClassMechanics(tc)
            % the contract classes accept one object in both roles (unregistered
            % stub in tests/support; the registered case: 'simcombined')
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), 'support')));
            obj = CombinedStub.fromConfig([], struct('roles', {{'source', 'acquisition'}}));
            tc.verifyTrue(isa(obj, 'tim.instr.SignalSource') && isa(obj, 'tim.instr.Acquisition'));
            tc.verifyEqual(obj.rolesInUse(), {'source', 'acquisition'});
            mc = ?CombinedStub;
            for p = {'ProgressFcn', 'Roles', 'OutputArmed', 'SampleRate', 'Teds', 'AbortFcn'}
                tc.verifyNumElements(findobj(mc.PropertyList, 'Name', p{1}), 1, sprintf('%s defined once', p{1}));
            end
            steps = {};
            obj.ProgressFcn = @(key, state, detail) recordStep(key);
            function recordStep(key), steps{end + 1} = key; end
            obj.ProgressFcn('device', 'run', '');
            tc.verifyEqual(steps, {'device'});
            obj.AbortFcn = @() obj.outputOff();
            tc.verifyError(@() setArmed(obj), 'MATLAB:class:SetProhibited', 'role state is set by the driver only');
            tc.verifyFalse(obj.isPlanning());
            obj.prepare(struct('sampleRate', 16384));
            tc.verifyEqual(obj.SampleRate, 16384);
            obj.armOutput(true); obj.outputOn();
            tc.verifyTrue(obj.isOutputOn());
            obj.close();
            tc.verifyFalse(obj.isOutputOn());
            tc.verifyFalse(obj.OutputArmed);
            md = obj.metadata();
            tc.verifyEqual(md.roles, {'source', 'acquisition'});
        end

        %% ---------------- registry ----------------
        function registryChecksTheSelection(tc)
            cfg = tc.config('source', 'keysight33220a');
            ctx = struct('mode', 'simulation', 'rig', [], 'progress', []);
            bad = cfg; bad.generator.driver = 'nosuchdriver';
            tc.verifyError(@() tim.instr.create('source', bad, ctx), 'tim:instr:unknownDriver');
            bad = cfg; bad.daq.driver = 'nosuchdriver';
            tc.verifyError(@() tim.instr.create('source', bad, ctx), 'tim:instr:unknownDriver', ...
                'the whole selection is checked before the first instrument is opened');
            bad = cfg; bad.generator.driver = 'lanxi';
            tc.verifyError(@() tim.instr.create('source', bad, ctx), 'tim:instr:role');
            bad = cfg; bad.daq.driver = 'keysight33220a';
            tc.verifyError(@() tim.instr.create('acquisition', bad, ctx), 'tim:instr:role');
            bad = cfg; bad.generator.load = 'HIGHZ';
            tc.verifyError(@() tim.instr.create('source', bad, ctx), 'tim:config:load', 'checkConfig before any I/O');
            tc.verifyError(@() tim.instr.create('output', cfg, ctx), 'tim:instr:role');
            tc.verifyError(@() tim.instr.driverInfo('nosuchdriver'), 'tim:instr:unknownDriver');
            % pairings (section 9.1): a driver that works only for both roles, or
            % delivers its data only in blocks, is not combined with another one;
            % a simulation-only driver is refused in hardware mode - all before any I/O
            hardware = struct('mode', 'hardware', 'rig', [], 'progress', []);
            list = tim.instr.drivers();
            for i = 1:numel(list)
                d = tim.instr.driverInfo(list(i).name);
                c = d.capabilities;
                if c.rolesTogether || (isfield(c, 'acquisition') && c.acquisition.needsOwnSource)
                    bad = cfg; bad.daq.driver = d.name;
                    tc.verifyError(@() tim.instr.create('acquisition', bad, ctx), 'tim:instr:role', [d.name ' with a separate source']);
                end
                if c.rolesTogether
                    bad = cfg; bad.generator.driver = d.name;
                    tc.verifyError(@() tim.instr.create('source', bad, ctx), 'tim:instr:role', [d.name ' with a separate DAQ']);
                end
                if strcmp(d.simulation, 'only')
                    sel = cfg;
                    if any(strcmp('source', c.roles)), sel.generator.driver = d.name; end
                    if any(strcmp('acquisition', c.roles)), sel.daq.driver = d.name; end
                    tc.verifyError(@() tim.instr.create(c.roles{1}, sel, hardware), 'tim:instr:simulationOnly', d.name);
                end
            end
        end

        function missingProductOfSelectedDriver(tc)
            % a selected driver that needs a MATLAB product which is not
            % installed: in hardware mode the registry names the product and the
            % driver before any I/O; in simulation the driver runs on its mock
            % without the product (test driver tests/support/FakeProductDaq)
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), 'support')));
            tim.instr.drivers('add', struct('name', 'fakeproductdaq', 'class', 'FakeProductDaq'));
            tc.addTeardown(@() tim.instr.drivers('remove', 'fakeproductdaq'));
            d = tim.instr.driverInfo('fakeproductdaq');
            cfg = tim.app.defaultConfig();
            cfg.daq.driver = 'fakeproductdaq';
            cfg.generator.keysight33220a.host = '127.0.0.1';     % never an instrument address
            cfg.daq.fakeproductdaq = struct('host', '127.0.0.1');
            hardware = struct('mode', 'hardware', 'rig', [], 'progress', []);
            try
                tim.instr.create('acquisition', cfg, hardware);
                tc.verifyFail('the missing product must be reported');
            catch err
                tc.verifyEqual(err.identifier, 'tim:instr:missingProduct');
                tc.verifySubstring(err.message, 'Fake Acquisition Toolbox');
                tc.verifySubstring(err.message, d.displayName);
            end
            sim = struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(cfg), 'progress', []);
            acq = tim.instr.create('acquisition', cfg, sim);
            tc.addTeardown(@() acq.close());
            quiet(acq);
            tc.verifyNotEmpty(acq.identity().model, 'runs on its mock without the product');
        end

        function productCheck(tc)
            tim.instr.checkProducts(struct('name', 'MATLAB', 'feature', 'MATLAB'), 'test device');
            tim.instr.checkProducts(struct('name', {}, 'feature', {}), 'test device');
            try
                tim.instr.checkProducts(struct('name', 'No Such Toolbox', 'feature', 'No_Such_Toolbox'), 'test device');
                tc.verifyFail('a missing product must raise an error');
            catch err
                tc.verifyEqual(err.identifier, 'tim:instr:missingProduct');
                tc.verifySubstring(err.message, 'No Such Toolbox');
                tc.verifySubstring(err.message, 'test device');
            end
        end

        function legacyConfigurationKeysUsed(tc)
            % a script that sets the old keys (generator.host / port, the lanxi
            % section) on the default configuration: the registry reads them
            % through tim.app.migrateConfig (docs/instrument_interface.md 9.3)
            cfg = tim.app.defaultConfig();
            cfg.generator.host = '10.0.0.7'; cfg.generator.port = 5026; cfg.lanxi.connector = 'LEMO';
            ctx = struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(cfg), 'progress', []);
            src = tim.instr.create('source', cfg, ctx);
            tc.addTeardown(@() src.close());
            acq = tim.instr.create('acquisition', cfg, ctx, src);
            tc.addTeardown(@() acq.close());
            ms = src.metadata(); ma = acq.metadata();
            tc.verifyEqual(ms.host, '10.0.0.7');
            tc.verifyEqual(ms.port, 5026);
            tc.verifyEqual(ma.connector, 'LEMO');
            tc.verifyEqual(ms.settings.timeout, cfg.generator.keysight33220a.timeout, 'not set: the driver default');
        end
    end
end

function c = capabilitiesOf(x)
% capabilities() of a driver given by registry name or by object
if ischar(x), x = tim.instr.driverInfo(x); c = x.capabilities; return; end
c = feval([class(x) '.capabilities']);
end

function n = superclassNames(mc)
% names of all superclasses of a meta.class (recursive)
n = {};
for s = mc.SuperclassList(:).'
    n = [n, {s.Name}, superclassNames(s)]; %#ok<AGROW>
end
end

function setArmed(obj)
% a write of a protected role property from outside the driver (must fail)
obj.OutputArmed = true;
end

function tf = isBlockSource(obj)
% a source that plays a planned output inside acquire (combined block device)
c = capabilitiesOf(obj);
tf = any(strcmp('source', c.roles)) && isfield(c, 'acquisition') && strcmp(c.acquisition.mode, 'block');
end

function quiet(obj)
% no console lines from a driver that has them (LAN-XI Verbose)
if isprop(obj, 'Verbose'), obj.Verbose = false; end
end
