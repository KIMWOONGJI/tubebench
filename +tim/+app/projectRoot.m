function r = projectRoot()
%PROJECTROOT Absolute path of the project folder (parent of +tim).
r = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
