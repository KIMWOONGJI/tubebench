function [file, folder] = fileDialog(kind, fig, filter, title, start)
%FILEDIALOG Standard Windows file dialog owned by the program's window.
%
%   [file, folder] = tim.gui.fileDialog('open', fig, filter, title, startFolder)
%   [file, folder] = tim.gui.fileDialog('save', fig, filter, title, startPathOrName)
%   ok = tim.gui.fileDialog('check')   compiles / loads the .NET helper (tests; Windows)
%
%   The arguments and results are those of uigetfile / uiputfile (filter: a
%   pattern such as '*.mat' or a cell {pattern, description; ...}; file = 0
%   when cancelled). 1.6.2 (owner report 2026-11-05): uigetfile / uiputfile
%   open their dialog as a window of the MATLAB process, not of the program's
%   window (R2022b has no option for that). When the dialog closed, Windows
%   activated another window - the MATLAB command window or another program -
%   in front of the program, which disappeared until it was raised again
%   (figure(fig)). Here the same standard Windows dialog
%   (System.Windows.Forms, through .NET) is opened with the program's window
%   as its owner, so Windows returns to the program when it closes. The
%   program's window is the foreground window of the MATLABWindow process when
%   the button was pressed. Anywhere else (not Windows, .NET not available, a
%   hidden window, no such foreground window) uigetfile / uiputfile is used, as
%   before, and the window is raised afterwards.

file = 0; folder = 0;
if strcmp(kind, 'check')                 % tim.gui.fileDialog('check'): the helper loads (tests)
    loadHelper();
    file = double(TubebenchWin.Dialogs.ForegroundOf('NoSuchProcess')) == 0;
    return
end
if nargin < 5, start = ''; end
owner = 0;
if ispc && ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible, 'on')
    try
        loadHelper();
        owner = double(TubebenchWin.Dialogs.ForegroundOf('MATLABWindow'));
    catch
        owner = 0;
    end
end
if owner ~= 0
    try
        [d, p] = splitStart(kind, start);
        r = char(TubebenchWin.Dialogs.Show(strcmp(kind, 'save'), int64(owner), netFilter(filter), title, p, d));
        if ~isempty(r)
            [folder, n, e] = fileparts(r);
            file = [n e]; folder = [folder filesep];
        end
        return
    catch
        % fall back to the dialog of MATLAB
    end
end
if strcmp(kind, 'save')
    [file, folder] = uiputfile(filter, title, start);
else
    [file, folder] = uigetfile(filter, title, start);
end
if ~isempty(fig) && isvalid(fig) && strcmp(fig.Visible, 'on'), figure(fig); end
end

function loadHelper()
% the .NET helper (private/TubebenchFileDialog.cs), compiled once per MATLAB
% session by the C# compiler of the .NET Framework (no C compiler needed)
persistent ok
if isempty(ok)
    NET.addAssembly('System');
    NET.addAssembly('System.Windows.Forms');
    dll = fullfile(tempdir, sprintf('tubebench_filedialog_%d.dll', feature('getpid')));
    if ~isfile(dll)
        src = fileread(fullfile(fileparts(mfilename('fullpath')), 'private', 'TubebenchFileDialog.cs'));
        prov = Microsoft.CSharp.CSharpCodeProvider();
        par = System.CodeDom.Compiler.CompilerParameters();
        par.OutputAssembly = dll; par.GenerateInMemory = false;
        par.ReferencedAssemblies.Add('System.dll');
        par.ReferencedAssemblies.Add('System.Windows.Forms.dll');
        srcs = NET.createArray('System.String', 1); srcs(1) = src;
        res = prov.CompileAssemblyFromSource(par, srcs);
        if res.Errors.HasErrors, error('tim:gui:fileDialog', 'File dialog helper: compilation failed.'); end
    end
    NET.addAssembly(dll);
    ok = true;
end
end

function [d, p] = splitStart(kind, start)
% folder and file name of the start argument
start = char(start); d = ''; p = '';
if isempty(start), return; end
if isfolder(start), p = start; return; end
[p0, n, e] = fileparts(start);
if strcmp(kind, 'save'), d = [n e]; end
if ~isempty(p0) && isfolder(p0), p = p0; end
end

function s = netFilter(filter)
% uigetfile filter -> "description|pattern;pattern|..." of .NET
if ischar(filter) || isstring(filter)
    f = char(filter);
    s = sprintf('%s|%s', f, f);
else
    rows = cell(size(filter, 1), 1);
    for i = 1:size(filter, 1)
        d = filter{i, 1};
        if size(filter, 2) > 1, d = filter{i, 2}; end
        rows{i} = sprintf('%s|%s', d, filter{i, 1});
    end
    s = strjoin(rows, '|');
end
s = [s '|All files (*.*)|*.*'];
end
