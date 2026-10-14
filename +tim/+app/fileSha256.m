function h = fileSha256(file)
%FILESHA256 SHA-256 of a file as 64 lower-case hex digits (Java MessageDigest).
%
%   h = tim.app.fileSha256(file)
%   The two-load pair folder records the SHA-256 of the raw.mat of every load
%   (tim.app.saveTwoLoad), so that opening it can tell a changed load folder.

md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(file, 'r');
if fid < 0, error('tim:file:open', 'Cannot read %s.', file); end
c = onCleanup(@() fclose(fid));
while true
    b = fread(fid, 2^22, '*uint8');
    if isempty(b), break; end
    md.update(typecast(b, 'int8'));
end
d = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(d, 2).', 1, []));
end
