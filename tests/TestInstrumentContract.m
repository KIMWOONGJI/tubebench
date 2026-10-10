classdef TestInstrumentContract < matlab.unittest.TestCase
    %TESTINSTRUMENTCONTRACT Every registered driver meets the instrument contract.
    %
    %   docs/instrument_interface.md section 11 (WO-001 task 8). Each driver
    %   runs in simulation mode on its protocol mock, built through the
    %   registry (tim.instr.create) on one tim.sim.SimulatedRig; the duties
    %   are observed through the driver's static testHooks (the instrument
    %   as the mock sees it), so no duty is tested for one driver only.
    %   Parameters: driver = every registered driver; source / acquisition =
    %   the drivers with that role. A combined driver is created for both
    %   roles. The planning-pass cases of a combined block device and the
    %   checks on the rig's OutputLog come with the simulated combined
    %   driver (stage B).

    properties (TestParameter)
        driver = TestInstrumentContract.registered('')
        source = TestInstrumentContract.registered('source')
        acquisition = TestInstrumentContract.registered('acquisition')
    end

    methods (Static)
        function p = registered(role)
            %REGISTERED Registered driver names with the role ('' = all), as a struct.
            list = tim.instr.drivers();
            p = struct();
            for i = 1:numel(list)
                c = feval([list(i).class '.capabilities']);
                if isempty(role) || any(strcmp(role, c.roles))
                    p.(list(i).name) = list(i).name;
                end
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
            [src, h] = tc.make('source', source);
            src.configureSine(1000, 0.2);
            src.armOutput(true); src.outputOn();
            tc.assertTrue(h.outputOn());
            src.close();
            tc.verifyFalse(h.outputOn(), 'close switches the output off');
            tc.verifyFalse(src.OutputArmed, 'close disarms');
        end

        function outputOffAfterDriverError(tc, source)
            [src, h] = tc.make('source', source);
            src.configureSine(1000, 0.2);
            src.armOutput(true); src.outputOn();
            tc.assertTrue(h.outputOn());
            h.injectError();
            tc.verifyError(@() src.setFrequency(500), ?MException);
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
            [src, h] = tc.make('source', source);
            tc.verifyError(@() src.outputOn(), 'tim:gen:notArmed');
            src.armOutput(true);
            tc.verifyError(@() src.outputOn(), 'tim:gen:mode', 'not configured');
            src.armOutput(false);
            src.configureSine(1000, 0.2);
            tc.verifyError(@() src.outputOn(), 'tim:gen:notArmed');
            tc.verifyFalse(h.outputOn());
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
            [src, h] = tc.make('source', source);
            c = capabilitiesOf(src); c = c.source;
            for sp = c.sweepSpacing
                s = struct('fStart', 80, 'fStop', 5500, 'duration', 1, 'spacing', sp{1}, 'amplitudeVpp', 0.2);
                src.configureSweep(s);                           % read back by the driver
                tc.verifyFalse(h.outputOn(), 'configureSweep leaves the output off');
                tc.verifyError(@() src.setFrequency(500), 'tim:gen:mode');
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

        function readBackFromTheInstrument(tc, source)
            [src, h] = tc.make('source', source);
            c = capabilitiesOf(src); c = c.source;
            tc.assumeEqual(c.readback, 'instrument', 'only an instrument read-back can be proved this way');
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
            [acq, h] = tc.preparedAcquisition(acquisition);
            function onBlock(n)
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
            [acq, h] = tc.preparedAcquisition(acquisition);
            function onBlock(n)
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

        function excitationRecordedWithSeparateSource(tc, acquisition)
            % data-driven timing (section 8.2): a separate source switched on
            % and off from onBlock lies inside the record
            cfg = tc.config('acquisition', acquisition);
            caps = capabilitiesOf(acquisition);
            tc.assumeFalse(caps.rolesTogether, 'a combined driver is its own source (planned timing)');
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

        %% ---------------- one object in both roles ----------------
        function combinedRoleClassMechanics(tc)
            % the contract classes accept one object in both roles (unregistered
            % stub in tests/support; the registered case is 'simcombined', stage B)
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
            % until formatVersion 2 the registry reads generator.host/port/timeout
            % and the lanxi section (docs/instrument_interface.md D38)
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
            tc.verifyEqual(ms.settings.timeout, cfg.generator.timeout);
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

function quiet(obj)
% no console lines from a driver that has them (LAN-XI Verbose)
if isprop(obj, 'Verbose'), obj.Verbose = false; end
end
