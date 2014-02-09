//
//  GLInternalModes.m
//  InternalWaves
//
//  Created by Jeffrey J. Early on 1/14/14.
//  Copyright (c) 2014 Jeffrey J. Early. All rights reserved.
//

#import "GLInternalModes.h"

#define g 9.81

@interface GLInternalModes ()
- (void) createStratificationProfileFromDensity: (GLFunction *) rho atLatitude: (GLFloat) latitude;
- (void) normalizeEigenvalues: (GLFunction *) lambda eigenvectors: (GLLinearTransform *) S withNorm: (GLFunction *) norm;
@property(strong) GLEquation *equation;
@property(strong) GLDimension *zDim;
@property(strong) GLLinearTransform *diffZ;
@end

@implementation GLInternalModes

- (void) createStratificationProfileFromDensity: (GLFunction *) rho atLatitude: (GLFloat) latitude
{
    if (rho.dimensions.count != 1) {
        [NSException raise:@"InvalidDimensions" format:@"Only one dimension allowed, at this point"];
    }
    
    GLScalar *rho0 = [rho mean];
    self.f0 = 2*(7.2921e-5)*sin(latitude*M_PI/180);
    
    self.equation = rho.equation;
    self.zDim = rho.dimensions[0];
    
	// First construct N^2
    self.diffZ = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 1 leftBC: kGLNeumannBoundaryCondition rightBC:kGLNeumannBoundaryCondition bandwidth:1 fromDimension:self.zDim forEquation: self.equation];
    self.N2 = [self.diffZ transform: [[rho dividedBy: rho0] times: @(-g)]];
}

- (void) normalizeEigenvalues: (GLFunction *) lambda eigenvectors: (GLLinearTransform *) S withNorm: (GLFunction *) norm
{
    lambda = [lambda makeRealIfPossible];
    S = [S makeRealIfPossible];
	
	if (self.maximumModes) {
        NSArray *dimensions = S.toDimensions;
        NSMutableString *fromIndexString = [NSMutableString stringWithFormat: @""];
        NSMutableString *toIndexString = [NSMutableString stringWithFormat: @""];
        for (GLDimension *dim in dimensions) {
            dim==self.zDim ? [fromIndexString appendFormat: @"0:%lu", self.maximumModes-1] : [fromIndexString appendFormat: @":"];
            [toIndexString appendFormat: @":"];
            if ([dimensions indexOfObject: dim] < dimensions.count-1) {
                [fromIndexString appendFormat: @","];
                [toIndexString appendFormat: @","];
            }
        }
        S = [S reducedFromDimensions: fromIndexString toDimension: toIndexString];
		lambda = [lambda variableFromIndexRangeString:fromIndexString];
	}
    
    self.eigendepths = [lambda scalarDivide: 1.0];
    self.S = [S normalizeWithFunction: norm];
    
    GLLinearTransform *diffZ;
    if (S.toDimensions.count == diffZ.fromDimensions.count) {
        diffZ = self.diffZ;
    } else {
        diffZ = [self.diffZ expandedWithFromDimensions: S.toDimensions toDimensions:S.toDimensions];
    }
    
    self.Sprime = [diffZ multiply: S];
    self.rossbyRadius = [[self.eigendepths times: @(g/(self.f0*self.f0))] sqrt];
}


- (NSArray *) internalGeostrophicModesFromDensityProfile: (GLFunction *) rho forLatitude: (GLFloat) latitude
{
    [self createStratificationProfileFromDensity: rho atLatitude: latitude];
    
    GLFunction *invN2 = [self.N2 scalarDivide: -g];
	
    GLLinearTransform *diffZZ = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 2 leftBC: kGLDirichletBoundaryCondition rightBC:kGLDirichletBoundaryCondition bandwidth:1 fromDimension: self.zDim forEquation: self.equation];
    GLLinearTransform *invN2_trans = [GLLinearTransform linearTransformFromFunction: invN2];
    GLLinearTransform *diffOp = [invN2_trans multiply: diffZZ];
	
    NSArray *system = [diffOp eigensystemWithOrder: NSOrderedAscending];
	
    [self normalizeEigenvalues: system[0] eigenvectors: system[1] withNorm: [self.N2 times: @(1/g)]];
	
    self.eigenfrequencies = [self.eigendepths times: @(0)];
    return @[self.eigendepths, self.S, self.Sprime];
}

- (NSArray *) internalWaveModesFromDensityProfile: (GLFunction *) rho wavenumber: (GLFloat) k forLatitude: (GLFloat) latitude
{
    [self createStratificationProfileFromDensity: rho atLatitude: latitude];
    	
    GLFunction *invN2 = [[self.N2 minus: @(self.f0*self.f0)] scalarDivide: -g];
	
    GLLinearTransform *diffZZ = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 2 leftBC: kGLDirichletBoundaryCondition rightBC:kGLDirichletBoundaryCondition bandwidth:1 fromDimension:self.zDim forEquation:self.equation];
    GLLinearTransform *invN2_trans = [GLLinearTransform linearTransformFromFunction: invN2];
    GLLinearTransform *k2 = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[self.zDim] toDimensions: @[self.zDim] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation:self.equation matrix:^( NSUInteger *row, NSUInteger *col ) {
		return (GLFloatComplex) (row[0]==col[0] ? k*k : 0);
	}];
    GLLinearTransform *diffOp = [invN2_trans multiply: [diffZZ minus: k2]];
	
    NSArray *system = [diffOp eigensystemWithOrder: NSOrderedAscending];
	
    [self normalizeEigenvalues: system[0] eigenvectors: system[1] withNorm: [[self.N2 minus: @(self.f0*self.f0)] times: @(1/g)]];
	   
    self.eigenfrequencies = [[[[self.eigendepths abs] times: @(g*k*k)] plus: @(self.f0*self.f0)] sqrt];
    return @[self.eigendepths, self.S, self.Sprime];
}

- (NSArray *) internalWaveModesFromDensityProfile: (GLFunction *) rho withFullDimensions: (NSArray *) dimensions forLatitude: (GLFloat) latitude
{
	// create an array with the intended transformation (this is agnostic to dimension ordering).
	NSMutableArray *basis = [NSMutableArray array];
	GLDimension *zDim;
	for (GLDimension *dim in dimensions) {
		if ( [dim.name isEqualToString: @"x"] || [dim.name isEqualToString: @"y"]) {
			[basis addObject: @(kGLExponentialBasis)];
		} else {
			zDim = dim;
			[basis addObject: @(dim.basisFunction)];
		}
	}
	
	NSArray *transformedDimensions = [GLDimension dimensionsForRealFunctionWithDimensions: dimensions transformedToBasis: basis];
	GLDimension *kDim, *lDim;
	for (GLDimension *dim in transformedDimensions) {
		if ( [dim.name isEqualToString: @"k"]) {
			kDim = dim;
		} else if ( [dim.name isEqualToString: @"l"]) {
			lDim = dim;
		}
	}
	
	GLEquation *equation = rho.equation;
	self.k = [GLFunction functionOfRealTypeFromDimension: kDim withDimensions: transformedDimensions forEquation: equation];
	self.l = [GLFunction functionOfRealTypeFromDimension: lDim withDimensions: transformedDimensions forEquation: equation];
	GLFunction *K2 = [[self.k multiply: self.k] plus: [self.l multiply: self.l]];
		
    [self createStratificationProfileFromDensity: rho atLatitude: latitude];
	
    GLFunction *invN2 = [[self.N2 minus: @(self.f0*self.f0)] scalarDivide: -g];
    
	// Now construct A = k*k*eye(N) - Diff2;
    GLLinearTransform *diffZZ1D = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 2 leftBC: kGLDirichletBoundaryCondition rightBC:kGLDirichletBoundaryCondition bandwidth:1 fromDimension:zDim forEquation:equation];
	GLLinearTransform *diffZZ = [diffZZ1D expandedWithFromDimensions: transformedDimensions toDimensions: transformedDimensions];

    GLLinearTransform *invN2_trans = [[GLLinearTransform linearTransformFromFunction: invN2] expandedWithFromDimensions: transformedDimensions toDimensions: transformedDimensions];
    GLLinearTransform *diffOp = [invN2_trans multiply: [diffZZ minus: [GLLinearTransform linearTransformFromFunction:K2]]];
	
    NSArray *system = [diffOp eigensystemWithOrder: NSOrderedAscending];
    
	[self normalizeEigenvalues: system[0] eigenvectors: system[1] withNorm: [[self.N2 minus: @(self.f0*self.f0)] times: @(1/g)]];
    
    NSArray *spectralDimensions = self.eigendepths.dimensions;
    GLFunction *k = [GLFunction functionOfRealTypeFromDimension: kDim withDimensions: spectralDimensions forEquation: equation];
	GLFunction *l = [GLFunction functionOfRealTypeFromDimension: lDim withDimensions: spectralDimensions forEquation: equation];
	GLFunction *K2_spectral = [[k multiply: k] plus: [l multiply: l]];
    self.eigenfrequencies = [[[[self.eigendepths abs] multiply: [K2_spectral times: @(g)]] plus: @(self.f0*self.f0)] sqrt];
	    
    return @[self.eigendepths, self.S, self.Sprime];
}













- (NSArray *) internalModesGIPFromDensityProfile: (GLFunction *) rho wavenumber: (GLFloat) k latitude: (GLFloat) latitude
{
    if (rho.dimensions.count != 1) {
        [NSException raise:@"InvalidDimensions" format:@"Only one dimension allowed, at this point"];
    }
	
	GLFloat f0 = 2*(7.2921e-5)*sin(latitude*M_PI/180);
    GLScalar *rho0 = [rho mean];
	
    GLEquation *equation = rho.equation;
    GLDimension *zDim = rho.dimensions[0];
    
	// First construct N^2
    GLLinearTransform *diffZ = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 1 leftBC: kGLNeumannBoundaryCondition rightBC:kGLNeumannBoundaryCondition bandwidth:1 fromDimension:zDim forEquation:equation];
    self.N2 = [diffZ transform: [[rho dividedBy: rho0] times: @(-g)]];
	
	// Now construct A = k*k*eye(N) - Diff2;
	GLLinearTransform *k2 = [GLLinearTransform transformOfType: kGLRealDataFormat withFromDimensions: @[zDim] toDimensions: @[zDim] inFormat: @[@(kGLDiagonalMatrixFormat)] forEquation:equation matrix:^( NSUInteger *row, NSUInteger *col ) {
		return (GLFloatComplex) (row[0]==col[0] ? k*k : 0);
	}];
    GLLinearTransform *diffZZ = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 2 leftBC: kGLDirichletBoundaryCondition rightBC:kGLDirichletBoundaryCondition bandwidth:1 fromDimension:zDim forEquation:equation];
	GLLinearTransform *A = [k2 minus: diffZZ];
    
	// Now construct B = k*k*diag(N2) - f0*f0*Diff2;
	GLLinearTransform *B = [[[GLLinearTransform linearTransformFromFunction: self.N2] times: @(k*k)] minus: [diffZZ times: @(f0*f0)]];
	
    NSArray *system = [B generalizedEigensystemWith: A];
	
	GLFunction *lambda = [system[0] makeRealIfPossible];
    GLLinearTransform *S = [system[1] makeRealIfPossible];
	
	if (self.maximumModes) {
		S = [S reducedFromDimensions: [NSString stringWithFormat: @"0:%lu", self.maximumModes-1] toDimension: @":"];
		lambda = [lambda variableFromIndexRangeString:[NSString stringWithFormat: @"0:%lu", self.maximumModes-1]];
	}
	
    S = [S normalizeWithFunction: [[self.N2 minus: @(f0*f0)] times: rho0]];
	GLLinearTransform *Sprime = [diffZ multiply: S];
	
	GLFunction *omega = [[lambda abs] sqrt];
	
    return @[omega, S, Sprime];
}

- (NSArray *) internalWaveModesGIPFromDensityProfile: (GLFunction *) rho withFullDimensions: (NSArray *) dimensions forLatitude: (GLFloat) latitude
{
	// create an array with the intended transformation (this is agnostic to dimension ordering).
	NSMutableArray *basis = [NSMutableArray array];
	GLDimension *zDim;
	for (GLDimension *dim in dimensions) {
		if ( [dim.name isEqualToString: @"x"] || [dim.name isEqualToString: @"y"]) {
			[basis addObject: @(kGLExponentialBasis)];
		} else {
			zDim = dim;
			[basis addObject: @(dim.basisFunction)];
		}
	}
	
	NSArray *transformedDimensions = [GLDimension dimensionsForRealFunctionWithDimensions: dimensions transformedToBasis: basis];
	GLDimension *kDim, *lDim;
	for (GLDimension *dim in transformedDimensions) {
		if ( [dim.name isEqualToString: @"k"]) {
			kDim = dim;
		} else if ( [dim.name isEqualToString: @"l"]) {
			lDim = dim;
		}
	}
	
	GLEquation *equation = rho.equation;
	GLFunction *k = [GLFunction functionOfRealTypeFromDimension: kDim withDimensions: transformedDimensions forEquation: equation];
	GLFunction *l = [GLFunction functionOfRealTypeFromDimension: lDim withDimensions: transformedDimensions forEquation: equation];
	GLFunction *K2 = [[k multiply: k] plus: [l multiply: l]];
	self.k = k;
	self.l = l;
	
	GLFloat f0 = 2*(7.2921e-5)*sin(latitude*M_PI/180);
	GLScalar *rho0 = [rho mean];
	
	// First construct N^2
    GLLinearTransform *diffZ1D = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 1 leftBC: kGLNeumannBoundaryCondition rightBC:kGLNeumannBoundaryCondition bandwidth:1 fromDimension:zDim forEquation:equation];
    self.N2 = [diffZ1D transform: [[rho dividedBy: rho0] times: @(-g)]];
	
	// Now construct A = k*k*eye(N) - Diff2;
    GLLinearTransform *diffZZ1D = [GLLinearTransform finiteDifferenceOperatorWithDerivatives: 2 leftBC: kGLDirichletBoundaryCondition rightBC:kGLDirichletBoundaryCondition bandwidth:1 fromDimension:zDim forEquation:equation];
	GLLinearTransform *diffZZ = [diffZZ1D expandedWithFromDimensions: transformedDimensions toDimensions: transformedDimensions];
	GLLinearTransform *A = [[GLLinearTransform linearTransformFromFunction:K2] minus: diffZZ];
	
	// Now construct B = k*k*diag(N2) - f0*f0*Diff2;
	GLLinearTransform *B = [[GLLinearTransform linearTransformFromFunction: [K2 multiply: self.N2]] minus: [diffZZ times: @(f0*f0)]];
	
	NSArray *system = [B generalizedEigensystemWith: A];
	
	GLFunction *lambda = [system[0] makeRealIfPossible];
	GLLinearTransform *S = [system[1] makeRealIfPossible];
	
	if (self.maximumModes) {
		S = [S reducedFromDimensions: [NSString stringWithFormat: @"0:%lu,:,:", self.maximumModes-1] toDimension: @":,:,:"];
		lambda = [lambda variableFromIndexRangeString:[NSString stringWithFormat: @"0:%lu,:,:", self.maximumModes-1]];
//        S = [S reducedFromDimensions: [NSString stringWithFormat: @":,:,0:%lu", self.maximumModes-1] toDimension: @":,:,:"];
//		lambda = [lambda variableFromIndexRangeString:[NSString stringWithFormat: @":,:,0:%lu", self.maximumModes-1]];
	}
	
	lambda = [lambda setValue: 0.0 atIndices: @":,0,0"];
	//GLFloat deltaK = lDim.nPoints * kDim.nPoints;
    S = [S normalizeWithFunction: [[self.N2 minus: @(f0*f0)] times: rho0]];
	
	NSUInteger index = 0;
	//	NSUInteger totalVectors = S.matrixDescription.nPoints / S.matrixDescription.strides[index].nPoints;
	//	NSUInteger vectorStride = S.matrixDescription.strides[index].columnStride;
	NSUInteger vectorLength = S.matrixDescription.strides[index].nRows;
	NSUInteger vectorElementStride = S.matrixDescription.strides[index].rowStride;
	//	NSUInteger complexStride = S.matrixDescription.strides[index].complexStride;
	
	for (NSUInteger i=0; i<vectorLength; i++) {
		S.pointerValue[i*vectorElementStride] = 0;
	}
    
    GLLinearTransform *diffZ = [diffZ1D expandedWithFromDimensions: S.toDimensions toDimensions:S.toDimensions];
    GLLinearTransform *Sprime = [diffZ multiply: S];
	
	GLFunction *omega = [[lambda abs] sqrt];
	
    return @[omega, S, Sprime];
}

@end
