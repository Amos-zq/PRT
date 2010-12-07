classdef prtRvKde < prtRv
    % prtRvKde - Gaussian Kernel Density Estimation Random Variable 
    %   Assumes independence between each of the dimensions.
    %
    %   RV = prtRvKde creates a prtRvKde object with empty trainingData and
    %   bandwidths parameters. The trainingData must be set either directly
    %   or by calling the MLE method.
    %
    %   RV = prtRvKde('bandwidthMode', VALUE) enforces the bandwidths to be 
    %   determined either using 'manual' or 'diffusion'. Setting this
    %   property to 'manual' requires that the bandwidths also be
    %   sepecified. The default, 'diffusion', uses the automatic bandwidth
    %   selection method discussed in
    %
    %   Botev et al., Kernel density estimation via diffusion,
    %   Ann. Statist. Volume 38, Number 5 (2010), 2916-2957. 
    %   http://projecteuclid.org/DPubS?service=UI&version=1.0&verb=Display&handle=euclid.aos/1281964340
    %
    %   RV = prtRvKde(PROPERTY1, VALUE1,...) creates a prtRvKde object RV
    %   with properties as specified by PROPERTY/VALUE pairs.
    %
    %   A prtRvKde object inherits all properties from the prtRv class. In
    %   addition, it has the following properties:
    %
    %   bandwidthMode    - A string specifying the method by which the
    %                      bandwidths are determined. Possibilities
    %                      {'diffusion'}, 'manual'
    %   bandwidths       - The bandwidths of the kernels used in each
    %                      dimension of the kernel density estimate. These
    %                      are the diagonal values of the covariance matrix
    %                      for the RBF kernels.
    %   trainingData     - The training data used to determined the kernel
    %                      density estimate
    %   minimumBandwidth - Minium bandwidth that is aloud to be estimated.
    %                      Diffusion based estimation can correctly 
    %                      identify a discrete density and infer a very
    %                      small bandwidth. This is sometimes undesirable
    %                      and causes stability issues. The default value
    %                      is eps.
    %   
    %  A prtRvKde object inherits all methods from the prtRv class. The MLE
    %  method can be used to estimate the distribution parameters from
    %  data.
    %
    %  Examples:
    %
    %   % Plot a 2D density 
    %   ds = prtDataGenOldFaithful;
    %   plotPdf(mle(prtRvKde,ds))
    %   % or using the static method
    %   prtRvKde.ezPlotPdf(ds)
    %
    %   % Diffusion bandwidth estimation can identify discrete densities
    %   plotPdf(mle(prtRvKde,[0; 0; 0; 1; 1; 1; 2; 2;]))
    %
    %   % Comparison to ksdensity (Statistics toolbox required)
    %   % ksdensity() is only for 1D data
    %   ds = prtDataGenUnimodal;
    %   subplot(2,1,1)
    %   plotPdf(mle(prtRvKde,ds.getObservations(:,1)))
    %   xlim([-5 5]), ylim([0 0.2])
    %   subplot(2,1,2)
    %   ksdensity(ds.getObservations(:,1))
    %   xlim([-5 5]), ylim([0 0.2])
    % 
    %   % Classification comparison on multi-modal data
    %   % We use a MAP classifier with three different RVs
    %   ds = prtDataGenBimodal;
    %
    %   outputKde = kfolds(prtClassMap('rvs',prtRvKde),ds,5);
    %   outputMvn = kfolds(prtClassMap('rvs',prtRvMvn),ds,5);
    %   outputGmm = kfolds(prtClassMap('rvs',prtRvGmm('nComponents',2)),ds,5);
    %
    %   [pfKde,pdKde] = prtScoreRoc(outputKde);
    %   [pfMvn,pdMvn] = prtScoreRoc(outputMvn);
    %   [pfGmm,pdGmm] = prtScoreRoc(outputGmm);
    %
    %   plot(pfMvn,pdMvn,pfGmm,pdGmm,pfKde,pdKde)
    %   grid on
    %   xlabel('PF')
    %   ylabel('PD')
    %   title('Comparison of MAP Classification With Different RVs')
    %   legend({'MAP - MVN','MAP - GMM(2)','MAP - KDE'},'Location','SouthEast')
    %
    %   See also: prtRv, prtRvMvn, prtRvGmm, prtRvMultinomial,
    %   prtRvUniform, prtRvUniformImproper, prtRvVq
    
    properties
        bandwidthMode = 'diffusion';
        bandwidths = []; % Will be estimated
        trainingData = []% Locations of kernels
        minimumBandwidth = eps;
    end
    
    properties (Dependent = true, Hidden=true)
        nDimensions
    end
    
    methods
        % The Constructor
        function R = prtRvKde(varargin)
            R.name = 'Kernel Density Estimation RV';
            R = constructorInputParse(R,varargin{:});
        end

        function val = get.nDimensions(R)
            if R.isValid
                val = size(R.trainingData,2);
            else
                val = [];
            end
        end
        
        function R = set.bandwidthMode(R,val)
            assert(ischar(val),'bandwidthMode must be a string that is either, manual, or diffusion.');
            
            val = lower(val);
            
            % Limit the options for the covariance structure
            if ~(strcmpi(val,'manual') || strcmpi(val,'diffusion'))
                error('prt:prtRvKde:invalidBandwidthMode','%s is not a valid bandwidthMode. Possiblities are, manual, and diffusion',val);
            end
            
            R.bandwidthMode = val;
        end
        
        function R = set.minimumBandwidth(R,val)
            assert(isnumeric(val) && numel(val)==1 && val>=0,'minimumBandwidth must be a scalar, numeric, non-negative value');
            R.minimumBandwidth = val;
        end
        
        function R = mle(R,X)
            X = R.dataInputParse(X); % Basic error checking etc
            
            if isempty(X)
                error('prt:prtRvKde','prtRvKde.mle() requires non-empty X');
            end
            
            R.trainingData = X;
            
            switch R.bandwidthMode
                case 'manual'
                    % Nothing to do assume set and do error check to make
                    % sure
                    assert(~isempty(R.bandwidths),'When bandwidthMode is ''manual'', bandwidths must be set before calling mle().');
                    assert(numel(R.bandwidths)==size(X,2),'The number of specified bandwidths for this RV does not match the dimensionality of the training data.');
                case 'diffusion'
                    nDims = size(X,2);
                    if nDims == 1
                        % 1D solution from Botev et al. 2010
                        R.bandwidths = prtExternal.kde.kde(X);
                    elseif nDims == 2
                        % 2D solution from Botev et al. 2010
                        R.bandwidths = prtExternal.kde2d.kde2d(X);
                    else
                        % In higher than 2 dimensions we assume independence in selecting
                        % bandwidths and use the 1D solution from Botev et al. 2010
                        % This is not entirely "best"
                        R.bandwidths = zeros(1,nDims);
                        for iDim = 1:nDims;
                            R.bandwidths(iDim) = prtExternal.kde.kde(X(:,iDim));
                        end
                    end
                otherwise
                    error('prt:prtRvKde:unknownBandwidthMode','Unknown bandwidth mode %s.',R.bandwidthMode);
            end
            
            R.bandwidths = max(R.bandwidths,R.minimumBandwidth);
        end
        
        function vals = pdf(R,X)
            [isValid, reasonStr] = R.isValid;
            assert(isValid,'PDF cannot yet be evaluated. This RV is not yet valid %s.',reasonStr);
            
            vals = exp(logPdf(R,X));
        end
        
        function vals = logPdf(R,X)
            [isValid, reasonStr] = R.isValid;
            assert(isValid,'LOGPDF cannot yet be evaluated. This RV is not yet valid %s.',reasonStr);
            
            assert(size(X,2) == R.nDimensions,'Data, RV dimensionality missmatch. Input data, X, has dimensionality %d and this RV has dimensionality %d.', size(X,2), R.nDimensions)
            assert(isnumeric(X) && ndims(X)==2,'X must be a 2D numeric array.');
    
            
            nDims = size(X,2);
            nTrainingPoints = size(R.trainingData,1); 
            
            largestMatrixSize = prtOptionsGet('prtOptionsComputation','largestMatrixSize');
            memChunkSize = max(floor(largestMatrixSize/nTrainingPoints),1);
            
            vals = zeros(size(X,1),1);
            for iBlockStart = 1:memChunkSize:size(X,1);
                cInds = iBlockStart:min(iBlockStart+memChunkSize,size(X,1));
                
                cNSamples = length(cInds);
                
                cDist = zeros(cNSamples,size(R.trainingData,1));
                for iDim = 1:nDims
                    cDist = cDist + (bsxfun(@minus,X(cInds,iDim),R.trainingData(:,iDim)').^2) / R.bandwidths(iDim);
                end
                
                vals(cInds) = prtUtilSumExp(((-cDist.^2)/2 - 0.5*log(2*pi) - 0.5*sum(log(R.bandwidths)))')' - log(nTrainingPoints);
            end
        end
        
        function vals = draw(R,N)
            if nargin < 2 || isempty(N)
                N = 1;
            end
            
            assert(numel(N)==1 && N==floor(N) && N > 0,'N must be a positive integer scalar.')
                
            % Uniformly bootstrap the data and add mvn noise with variances
            % equal to the bandwidths
            vals = prtRvUtilRandomSample(size(R.trainingData,1),N,R.trainingData) + prtRvUtilMvnDraw(zeros(1,size(R.trainingData,2)),R.bandwidths,N);
        end
    end
    
    methods (Hidden = true)
        function [val, reasonStr] = isValid(R)
            if numel(R) > 1
                val = false(size(R));
                for iR = 1:numel(R)
                    [val(iR), reasonStr] = isValid(R(iR));
                end
                return
            end
            
            val = ~isempty(R.trainingData) & ~isempty(R.bandwidths);
            
            if val
                reasonStr = '';
            else
                badTrainingData = isempty(R.trainingData);
                badBandwidths = isempty(R.bandwidths);
                
                if badTrainingData && ~badBandwidths
                    reasonStr = 'because trainingData has not been set';
                elseif ~badTrainingData && badBandwidths
                    reasonStr = 'because bandwidths has not been set';
                elseif badTrainingData && badBandwidths
                    reasonStr = 'because trainingData and bandwidths have not been set';
                else
                    reasonStr = 'because of an unknown reason';
                end
            end
            
        end
        function val = plotLimits(R)
            % We use the minimum and maximum of the training data with an
            % additional 10% on each side.
            
            minX = min(R.trainingData,[],1);
            maxX = max(R.trainingData,[],1);
            
            rangeX = maxX-minX;
            
            val = zeros(1,2*R.nDimensions);
            val(1:2:R.nDimensions*2-1) = minX - rangeX/10;
            val(2:2:R.nDimensions*2) = maxX + rangeX/10;
        end
    end
    
    methods (Static)
        function ezPlotPdf(X)
            plotPdf(mle(prtRvKde,X));
        end
    end
    
    methods
        function varargout = plotPdf(R,varargin)
            % Plot the pdf
            %
            % This is overloaded from prtRv because we want to enforce that
            % the training data is included in the evaluated points
            % This ensures that when very small bandwidths are present
            % the plot still looks as expected.
            
            varargout = {};
            if R.isPlottable
                
                if nargin > 1 % Calculate appropriate limits from covariance
                    plotLims = varargin{1};
                else
                    plotLims = plotLimits(R);
                end
                
                tooBigNObservations = [2000 500 100];
                if size(R.trainingData,1) > tooBigNObservations(size(R.trainingData,2))
                    [linGrid,gridSize] = prtPlotUtilGenerateGrid(plotLims(1:2:end), plotLims(2:2:end), R.PlotOptions.nSamplesPerDim);
                else
                    [linGrid,gridSize] = prtPlotUtilGenerateGrid(plotLims(1:2:end), plotLims(2:2:end), R.PlotOptions.nSamplesPerDim, R.trainingData);
                end
                
                imageHandle = prtPlotUtilPlotGriddedEvaledFunction(R.pdf(linGrid), linGrid, gridSize, R.PlotOptions.colorMapFunction(R.PlotOptions.nColorMapSamples));
                
                if nargout
                    varargout = {imageHandle};
                end
            else
                [isValid, reasonStr] = R.isValid;
                if isValid
                    error('prt:prtRv:plot','This RV object cannont be plotted because it has too many dimensions.')
                else
                    error('prt:prtRv:plot','This RV object cannot be plotted. It is not yet valid %s.',reasonStr);
                end
            end
        end
    end
    
end