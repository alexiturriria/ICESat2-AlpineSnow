function [E,Rnmad] = reference_elevations(icesat2_elevations, norths, easts, elevations, Ref, A)
% Function COREGISTER_ICESAT2 coregisters icesat-2 data with a corresponding digital
% terrain model 
% INPUTS:   icesat2_elevations = array of ICESat-2 elevations
%           norths = array of ICESat-2 Northing coordinates
%           easts = array of ICESat-2 Easting coordinates 
%           elevations = the reference elevation matrix 
%           Ref = the cell map reference for the reference DTM
%           A = a [2 1] vector that serves as the spatial offsets in
%                       the x and y directions (meters)
% OUTPUTS:  E = 

% last modified Feb 2024 Karina Zikan (karinazikan@u.boisestate.edu)

% Set ICESat-2 footwidth
footwidth = 11; % approx. width of icesat2 shot footprint in meters

%identify the ends of each transect and flag them so that neighboring
%transects aren't used when constructing footprints (use beam variable & date)
dates = T.date;
[~,unique_refs] = unique([num2str(dates)],'rows');
end_flag = zeros(size(norths,1),1);
end_flag(unique_refs) = 1; end_flag(unique_refs(unique_refs~=1)-1) = 1; end_flag(end) = 1;


%% Calculating footprints for each data point
%define the Reference elevation data
if isfield(Ref,'LatitudeLimits')
    [latgrid,longrid] = meshgrid(Ref.LongitudeLimits(1)+0.5*Ref.CellExtentInLongitude:Ref.CellExtentInLongitude:Ref.LongitudeLimits(2)-0.5*Ref.CellExtentInLongitude,...
        Ref.LatitudeLimits(2)-0.5*Ref.CellExtentInLatitude:-Ref.CellExtentInLatitude:Ref.LatitudeLimits(1)+0.5*Ref.CellExtentInLatitude);
    [xgrid, ygrid,~] = wgs2utm(latgrid,longrid);
else
    x = Ref.XWorldLimits(1)+0.5*Ref.CellExtentInWorldX:Ref.CellExtentInWorldX:Ref.XWorldLimits(2)-0.5*Ref.CellExtentInWorldX;
    if strcmp(Ref.ColumnsStartFrom,'north')
        y = Ref.YWorldLimits(2)-0.5*Ref.CellExtentInWorldY:-Ref.CellExtentInWorldY:Ref.YWorldLimits(1)+0.5*Ref.CellExtentInWorldY;
    else
        y = Ref.YWorldLimits(1)+0.5*Ref.CellExtentInWorldY:Ref.CellExtentInWorldY:Ref.YWorldLimits(2)-0.5*Ref.CellExtentInWorldY;
    end
    [xgrid, ygrid] = meshgrid(x, y); % create grids of each of the x and y coords
end

% calculates footprint corners
[xc,yc,theta] = ICESat2_FootprintCorners([A(2)+norths],[A(1)+easts],default_length,end_flag);

%% Calculate Reference Elevations, Slope, & Aspect
for r=1:length(icesat2_elevations)

    %identify the R2erence elevation points in each ICESat2 footprint
    xv = xc(r,[3:6 3]); % bounding box x vector
    yv = yc(r,[3:6 3]); % bounding box y vector

    % subset giant grid
    ix = find(x <= (xc(r,1)+60) & x >= (xc(r,1)-60)); % x index for subgrid
    iy = find(y <= (yc(r,1)+60) & y >= (xc(r,1)-60)); % y index for subgrid
    xsubgrid = xgrid(iy,ix);
    ysubgrid = ygrid(iy,ix);
    subelevations = elevations(iy,ix);
    subslope = slope(iy,ix);
    subaspect = aspect(iy,ix);

   %data in the footprint
    in = inpolygon(xsubgrid, ysubgrid, xv, yv); % get logical array of in values
    pointsinx = xsubgrid(in); % save x locations
    pointsiny = ysubgrid(in); % save y locations
    elevationsin = subelevations(in); % save elevations
    slopesin = subslope(in); % save slopes
    aspectsin = subaspect(in); % save slopes

    %wieghted average
    dist = nan([1,length(pointsinx)])'; %initialize dist
    for a = 1:length(pointsinx)
        phi = atan2d((pointsiny(a)-norths(r)),(pointsinx(a)-easts(r)));
        dist(a)=abs(sqrt((pointsiny(a)-norths(r))^2+(pointsinx(a)-easts(r))^2)*sind(phi-theta(r))); %distance from the line in the center of the window
    end
    maxdist = footwidth/2; % defining the maximum distance a point can be from the center icesat2 point
    w = 15/16*(1-(dist/maxdist).^2).^2; %bisqared kernel
    elevation_report_mean(r,:) = sum(w.*elevationsin)./sum(w); %weighted elevation estimate
    elevation_report_std(r,:) = std(elevationsin); %std of the elevations within the footprint

    %non wieghted average
    elevation_report_nw_mean(r,:) = nanmean(elevationsin); % non-wieghted elevations
    slope_mean(r,:) = nanmean(slopesin);
    slope_std(r,:) = std(slopesin);
    aspect_mean(r,:) = nanmean(aspectsin);
    aspect_std(r,:) = std(aspectsin);
end
%interpolated elevation
elevation_report_interp = interp2(x,y,elevations,easts,norths);

Residuals = icesat2_elevations - elevation_report_nw_mean; % difference ICESat-2 and ref elevations
Rmean = nanmean(Residuals); % calculate mean of Residuals
Rnmad = 1.4826*median(abs(Residuals-Rmean,'omitnan'); % normalized meadian absolute difference

E = table(elevation_report_nw_mean,elevation_report_mean,elevation_report_interp,elevation_report_std,slope_mean,slope_std,aspect_mean,aspect_std);