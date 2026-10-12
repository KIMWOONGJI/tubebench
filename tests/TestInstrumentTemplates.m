classdef TestInstrumentTemplates < matlab.unittest.TestCase
    %TESTINSTRUMENTTEMPLATES The driver templates work as they are, on their mocks.
    %
    %   templates/instrument holds the starting files of a new driver
    %   (docs/adding_an_instrument.md). That folder is not on the path and not
    %   a package folder, so nothing in it registers or runs by accident. Here
    %   the files are copied into a temporary +tim/+instr folder (MATLAB merges
    %   it with the package) and the three driver templates are registered for
    %   this test class only: they pass tests/TestInstrumentContract (run with
    %   the templates as its parameters) and their own driver tests, and the
    %   configuration snippet selects them. A template that stops working is
    %   found here, not by the next person who copies it.

    properties (Constant)
        Classes = struct('templatesource', 'TemplateSource', 'templateacquisition', 'TemplateAcquisition', ...
            'templatecombined', 'TemplateCombined')
    end
    properties
        Folder char = ''        % temporary folder on the path: +tim/+instr and the driver tests
    end

    methods (TestClassSetup)
        function copyAndRegister(tc)
            src = templateFolder();
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Folder = f.Folder;
            pkg = fullfile(f.Folder, '+tim', '+instr');
            mkdir(pkg);
            for d = [dir(fullfile(src, 'Template*.m')); dir(fullfile(src, 'MockTemplate*.m'))].'
                copyfile(fullfile(src, d.name), pkg);
            end
            for d = dir(fullfile(src, 'TestTemplate*.m')).'
                copyfile(fullfile(src, d.name), f.Folder);
            end
            % the combined template with another device block (4096 samples), made
            % with the replacements of the guide's step 3: the contract cases must
            % not assume the template's 2048
            for t = {'TemplateCombined', 'MockTemplateCombined'}
                txt = tim.app.readTextUtf8(fullfile(src, [t{1} '.m']));
                txt = strrep(strrep(txt, 'TemplateCombined', 'TemplateBigBlock'), 'TEMPLATECOMBINED', 'TEMPLATEBIGBLOCK');
                txt = strrep(txt, 'templatecombined', 'templatebigblock');
                txt = strrep(txt, '''blockSamples'', 2048)', '''blockSamples'', 4096)');
                fid = fopen(fullfile(pkg, [strrep(t{1}, 'TemplateCombined', 'TemplateBigBlock') '.m']), 'w', 'n', 'UTF-8');
                fwrite(fid, unicode2native(txt, 'UTF-8')); fclose(fid);
            end
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(f.Folder));
            names = [fieldnames(tc.Classes).', {'templatebigblock'}];
            classes = [struct2cell(tc.Classes).', {'TemplateBigBlock'}];
            for i = 1:numel(names)
                tim.instr.drivers('add', struct('name', names{i}, 'class', ['tim.instr.' classes{i}]));
                tc.addTeardown(@() tim.instr.drivers('remove', names{i}));
            end
        end
    end

    methods (Test)
        function templateFolderIsInert(tc)
            % not on the path, no package folder, not in the registry file, and
            % every template marks the places of the instrument facts
            src = templateFolder();
            tc.verifyFalse(any(strcmpi(strsplit(path, pathsep), src)), 'templates/instrument is not on the path');
            tc.verifyFalse(contains(src, [filesep '+']), 'not inside a package folder');
            tc.verifyEmpty(which('TemplateSource'), 'the bare template class is not found');
            tc.verifyEmpty(regexpi(fileread(which('tim.instr.drivers')), 'template', 'once'), ...
                'no template in the registry file');
            files = [{dir(fullfile(src, '*.m')).name}, {'ref_template.md', 'config_snippet.json', 'config_snippet_combined.json'}];
            tc.verifyNumElements(files, 12);
            for f = files
                tc.verifySubstring(fileread(fullfile(src, f{1})), 'TODO', [f{1} ' marks the instrument facts']);
            end
        end

        function templatesMeetTheContract(tc)
            % tests/TestInstrumentContract with the three templates as its drivers
            p = matlab.unittest.parameters.Parameter.fromData( ...
                'driver', {'templatesource', 'templateacquisition', 'templatecombined'}, ...
                'source', {'templatesource', 'templatecombined'}, ...
                'acquisition', {'templateacquisition', 'templatecombined'}, ...
                'instrumentSource', {'templatesource'}, ...
                'separateAcquisition', {'templateacquisition'}, ...
                'blockDevice', {'templatecombined'});
            suite = matlab.unittest.TestSuite.fromClass(?TestInstrumentContract, 'ExternalParameters', p);
            keep = ~arrayfun(@(s) isempty(s.Parameterization), suite) | endsWith({suite.Name}, 'stepKeysUnique');
            tc.verifyGreaterThan(nnz(keep), 30, 'every parameterised contract case');
            tc.verifyEmpty(runQuietly(suite(keep)), 'contract cases that failed for a template');
        end

        function anotherBlockSizeMeetsTheContract(tc)
            % the combined template with a device block of 4096 samples (a
            % newcomer's device buffer): the same contract cases pass
            tc.assertEqual(tim.instr.driverInfo('templatebigblock').defaults.settings.blockSamples, 4096);
            p = matlab.unittest.parameters.Parameter.fromData( ...
                'driver', {'templatebigblock'}, 'source', {'templatebigblock'}, 'acquisition', {'templatebigblock'}, ...
                'instrumentSource', {'templatesource'}, 'separateAcquisition', {'templateacquisition'}, ...
                'blockDevice', {'templatebigblock'});
            suite = matlab.unittest.TestSuite.fromClass(?TestInstrumentContract, 'ExternalParameters', p);
            keep = arrayfun(@(s) ~isempty(s.Parameterization) && ...
                any(strcmp({s.Parameterization.Value}, 'templatebigblock')), suite);
            tc.verifyGreaterThan(nnz(keep), 20, 'every case of a combined block device');
            tc.verifyEmpty(runQuietly(suite(keep)), 'contract cases that failed with a block of 4096 samples');
        end

        function driverTestTemplatesPass(tc)
            suite = matlab.unittest.Test.empty;
            for n = {'TestTemplateSource', 'TestTemplateAcquisition', 'TestTemplateCombined'}
                suite = [suite, matlab.unittest.TestSuite.fromFile(fullfile(tc.Folder, [n{1} '.m']))]; %#ok<AGROW>
            end
            tc.verifyGreaterThanOrEqual(numel(suite), 10);
            tc.verifyEmpty(runQuietly(suite), 'driver-test templates that failed');
        end

        function configSnippetSelectsTheTemplates(tc)
            % the snippets load without a warning and select the template drivers
            % (a source and a separate DAQ; a device in both roles); the inputs
            % take the acquisition driver's defaults
            file = fullfile(templateFolder(), 'config_snippet.json');
            cfg = tc.verifyWarningFree(@() tim.app.loadConfig(file));
            tc.verifyEqual(cfg.generator.driver, 'templatesource');
            tc.verifyEqual(cfg.daq.driver, 'templateacquisition');
            def = tim.instr.driverInfo('templateacquisition').defaults.acquisition;
            tc.verifyEqual({cfg.acquisition.sampleRate, cfg.acquisition.range, cfg.acquisition.filter}, ...
                {def.sampleRate, def.range, def.filter});
            tc.verifyWarningFree(@() tim.app.validateConfig(cfg, 'instruments'));
            % a device in both roles: named in both sections, its settings in daq.<reg>
            file = fullfile(templateFolder(), 'config_snippet_combined.json');
            cfg = tc.verifyWarningFree(@() tim.app.loadConfig(file));
            tc.verifyEqual({cfg.generator.driver, cfg.daq.driver}, {'templatecombined', 'templatecombined'});
            tc.verifyEqual(cfg.daq.templatecombined.blockSamples, 2048);
            tc.verifyWarningFree(@() tim.app.validateConfig(cfg, 'instruments'));
            % the same settings in the generator section are not read: a warning
            u = jsondecode(tim.app.readTextUtf8(file));
            u.generator.templatecombined = u.daq.templatecombined;
            u.daq = rmfield(u.daq, 'templatecombined');
            f2 = fullfile(tc.Folder, 'misplaced.json');
            fid = fopen(f2, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(jsonencode(u), 'UTF-8')); fclose(fid);
            tc.verifyWarning(@() tim.app.loadConfig(f2), 'tim:config:misplacedSettings');
        end
    end
end

function f = templateFolder()
% templates/instrument of this project
f = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'templates', 'instrument');
end

function failed = runQuietly(suite)
% run a suite without console output; the failures as text (name: diagnostics)
runner = matlab.unittest.TestRunner.withNoPlugins();
runner.addPlugin(matlab.unittest.plugins.DiagnosticsRecordingPlugin());
r = runner.run(suite);
failed = {};
for i = find(~[r.Passed])
    txt = r(i).Name;
    rec = r(i).Details.DiagnosticRecord;
    for k = 1:numel(rec), txt = sprintf('%s\n%s', txt, rec(k).Report); end
    failed{end+1} = txt; %#ok<AGROW>
end
end
