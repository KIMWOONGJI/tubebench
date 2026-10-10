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
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(f.Folder));
            for n = fieldnames(tc.Classes).'
                tim.instr.drivers('add', struct('name', n{1}, 'class', ['tim.instr.' tc.Classes.(n{1})]));
                tc.addTeardown(@() tim.instr.drivers('remove', n{1}));
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
            files = [{dir(fullfile(src, '*.m')).name}, {'ref_template.md', 'config_snippet.json'}];
            tc.verifyNumElements(files, 11);
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

        function driverTestTemplatesPass(tc)
            suite = matlab.unittest.Test.empty;
            for n = {'TestTemplateSource', 'TestTemplateAcquisition', 'TestTemplateCombined'}
                suite = [suite, matlab.unittest.TestSuite.fromFile(fullfile(tc.Folder, [n{1} '.m']))]; %#ok<AGROW>
            end
            tc.verifyGreaterThanOrEqual(numel(suite), 10);
            tc.verifyEmpty(runQuietly(suite), 'driver-test templates that failed');
        end

        function configSnippetSelectsTheTemplates(tc)
            % the snippet loads without a warning, selects the template drivers,
            % and the inputs take the acquisition driver's defaults
            file = fullfile(templateFolder(), 'config_snippet.json');
            cfg = tc.verifyWarningFree(@() tim.app.loadConfig(file));
            tc.verifyEqual(cfg.generator.driver, 'templatesource');
            tc.verifyEqual(cfg.daq.driver, 'templateacquisition');
            def = tim.instr.driverInfo('templateacquisition').defaults.acquisition;
            tc.verifyEqual({cfg.acquisition.sampleRate, cfg.acquisition.range, cfg.acquisition.filter}, ...
                {def.sampleRate, def.range, def.filter});
            tc.verifyWarningFree(@() tim.app.validateConfig(cfg, 'instruments'));
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
