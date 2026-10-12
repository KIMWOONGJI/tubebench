function checkProducts(products, driverName)
%CHECKPRODUCTS Raise tim:instr:missingProduct when a driver's MATLAB product is missing.
%
%   tim.instr.checkProducts(capabilities().products, describe().displayName)
%   products: struct array name (as listed by ver) and feature (license key,
%   e.g. 'Data_Acq_Toolbox'). Used by tim.instr.create in hardware mode only:
%   in simulation a driver runs on its protocol mock and needs no product.
%   Support packages and vendor runtimes are not MATLAB products; a driver
%   checks them in its optional static checkInstalled().

if isempty(products), return; end
v = ver;
installed = {v.Name};
for p = products(:).'
    if ~any(strcmp(p.name, installed))
        error('tim:instr:missingProduct', 'The driver of the %s needs %s, which is not installed.', driverName, p.name);
    end
    if ~license('test', p.feature)
        error('tim:instr:missingProduct', 'The driver of the %s needs %s, which is not licensed (license feature %s).', ...
            driverName, p.name, p.feature);
    end
end
end
