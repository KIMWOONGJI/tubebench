function txt = readTextUtf8(file)
%READTEXTUTF8 Read a UTF-8 text file (BOM tolerated) independent of the
%   system code page (fileread uses the OS default, e.g. CP949 on Korean Windows).
fid = fopen(file, 'r', 'n', 'UTF-8');
if fid < 0
    error('tim:io:open', 'Cannot open "%s".', file);
end
c = onCleanup(@() fclose(fid));
txt = fread(fid, [1 inf], '*char');
if ~isempty(txt) && double(txt(1)) == 65279
    txt = txt(2:end);
end
end
