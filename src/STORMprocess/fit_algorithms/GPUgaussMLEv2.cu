/*!
 * \file GPUgaussMLEv2.cu
 * \author Keith Lidke, Thomas Shaw
 * \date January 10, 2010
 * \brief This file contains all of the Cuda kernels.  The helper functions
 * are defined in GPUgaussLib.cuh

 * Copyright (C) 2023 Keith Lidke and Thomas Shaw
 * This file is part of SMLM PROCESSING 
 * SMLM PROCESSING is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * SMLM PROCESSING is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with SMLM PROCESSING.  If not, see <https://www.gnu.org/licenses/>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cuda_runtime.h"
#include "definitions.h"
#include "MatInvLib.h"
#include "GPUgaussLib.cuh"
#include "GPUgaussMLEv2.h"

//*******************************************************************************************
//theta is: {x,y,N,bg}
__global__ void kernel_MLEFit(const float *d_data, float PSFSigma, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood,int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 * \param d_data array of subregions to fit copied to GPU
	 * \param PSFSigma sigma of the point spread function
	 * \param sz nxn size of the subregion to fit
	 * \param iterations number of iterations for solution to converge
	 * \param d_Parameters array of fitting parameters to return for each subregion
	 * \param d_CRLBs array of Cramer-Rao lower bound estimates to return for each subregion
	 * \param d_LogLikelihood array of loglikelihood estimates to return for each subregion
	 * \param Nfits number of subregions to fit
	 */
    __shared__ float s_data[MEM];
    float M[NV_P*NV_P], Diag[NV_P], Minv[NV_P*NV_P];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=NV_P;
    float dudt[NV_P], d2udt2[NV_P];
    float NR_Numerator[NV_P], NR_Denominator[NV_P];
    float theta[NV_P];
    float maxjump[NV_P]={1e0f, 1e0f, 1e2f, 2e0f};
    float gamma[NV_P]={1.0f, 1.0f, 0.5f, 1.0f};
    float Nmax;

    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<NV*NV;ii++) M[ii] = 0;
    for (ii=0;ii<NV*NV;ii++) Minv[ii] = 0;

    //load data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++)
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
    
    //initial values
    kernel_CenterofMass2D(sz, &s_data[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_data[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma*PSFSigma);
    
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], PSFSigma);
            PSFy=kernel_IntGauss1D(jj, theta[1], PSFSigma);
            
            model=theta[3]+theta[2]*PSFx*PSFy;
            data=s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], PSFSigma, theta[2], PSFy, &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], PSFSigma, theta[2], PSFx, &dudt[1], &d2udt2[1]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 1.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
        if (kk<2)
            for (ll=0;ll<NV;ll++)
                theta[ll]-=gamma[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        else
            for (ll=0;ll<NV;ll++)
                theta[ll]-=min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        theta[3]=max(theta[3], 0.01f);
        
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        PSFx=kernel_IntGauss1D(ii, theta[0], PSFSigma);
        PSFy=kernel_IntGauss1D(jj, theta[1], PSFSigma);
        
        model=theta[3]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], PSFSigma, theta[2], PSFy, &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], PSFSigma, theta[2], PSFx, &dudt[1], NULL);
        dudt[2] = PSFx*PSFy;
        dudt[3] = 1.0f;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV);
    
    //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    
    return;
}

__global__ void kernel_MLEFit_no_b(const float *d_data, float PSFSigma, float *d_bg, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood,int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 */
    __shared__ float s_data[MEM], s_bg[MEM], s_diff[MEM];
    float M[NV_PNB*NV_PNB], Diag[NV_PNB], Minv[NV_PNB*NV_PNB];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=NV_PNB;
    float dudt[NV_PNB];
    float d2udt2[NV_PNB];
    float NR_Numerator[NV_PNB], NR_Denominator[NV_PNB];
    float theta[NV_PNB];
    float maxjump[NV_PNB]={1e0f, 1e0f, 1e2f};
    float gamma[NV_PNB]={1.0f, 1.0f, 0.5f};
    float Nmax;
    float bg;

    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<NV*NV;ii++)M[ii]=0;
    for (ii=0;ii<NV*NV;ii++)Minv[ii]=0;
    //load data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
        s_bg[sz*sz*tx+sz*jj+ii]=d_bg[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
        s_diff[sz*sz*tx + sz*jj + ii] = s_data[sz*sz*tx + sz*jj + ii] - s_bg[sz*sz*tx + sz*jj + ii];
    }
    
    //initial values
    kernel_CenterofMass2D(sz, &s_diff[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_diff[sz*sz*tx], &Nmax, &bg);
    theta[2]=max(0.0f, (Nmax)*2*pi*PSFSigma*PSFSigma);
    
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], PSFSigma);
            PSFy=kernel_IntGauss1D(jj, theta[1], PSFSigma);
            
            model = s_bg[sz*sz*tx+sz*jj+ii] + theta[2]*PSFx*PSFy;
            data = s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], PSFSigma, theta[2], PSFy, &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], PSFSigma, theta[2], PSFx, &dudt[1], &d2udt2[1]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
        if (kk<2)
            for (ll=0;ll<NV;ll++)
                theta[ll]-=gamma[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        else
            for (ll=0;ll<NV;ll++)
                theta[ll]-=min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        PSFx=kernel_IntGauss1D(ii, theta[0], PSFSigma);
        PSFy=kernel_IntGauss1D(jj, theta[1], PSFSigma);
        
        model=s_bg[sz*sz*tx+sz*jj+ii]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], PSFSigma, theta[2], PSFy, &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], PSFSigma, theta[2], PSFx, &dudt[1], NULL);
        dudt[2] = PSFx*PSFy;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV);
    
    //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    
    return;
}
//*******************************************************************************************
__global__ void kernel_MLEFit_sigma(const float *d_data, float PSFSigma, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood,int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 */
    
    __shared__ float s_data[MEM];
    float M[NV_PS*NV_PS], Diag[NV_PS], Minv[NV_PS*NV_PS];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=NV_PS;
    float dudt[NV_PS];
    float d2udt2[NV_PS];
    float NR_Numerator[NV_PS], NR_Denominator[NV_PS];
    float theta[NV_PS];
    float maxjump[NV_PS]={1e0f, 1e0f, 1e2f, 2e0f, 5e-1f};
    float gamma[NV_PS]={1.0f, 1.0f, 0.5f, 1.0f, 1.0f};
    float Nmax;
    
    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<NV*NV;ii++)M[ii]=0;
    for (ii=0;ii<NV*NV;ii++)Minv[ii]=0;
      
    //copy in data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++)
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
    
    //initial values
    kernel_CenterofMass2D(sz, &s_data[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_data[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma*PSFSigma);
    theta[4]=PSFSigma;
    
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
            PSFy=kernel_IntGauss1D(jj, theta[1], theta[4]);
            
            model=theta[3]+theta[2]*PSFx*PSFy;
            data=s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx, &dudt[1], &d2udt2[1]);
            kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1], theta[4], theta[2], PSFx, PSFy, &dudt[4], &d2udt2[4]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 1.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
        if (kk<5)
            for (ll=0;ll<NV;ll++)
                theta[ll]-=gamma[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        else
            for (ll=0;ll<NV;ll++)
                theta[ll]-=min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        theta[3]=max(theta[3], 0.01f);
        theta[4]=max(theta[4], 0.5f);
        theta[4]=min(theta[4], (float)sz);
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0f;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
        PSFy=kernel_IntGauss1D(jj, theta[1], theta[4]);
        
        model=theta[3]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx, &dudt[1], NULL);
        kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1], theta[4], theta[2], PSFx, PSFy, &dudt[4], NULL);
        dudt[2] = PSFx*PSFy;
        dudt[3] = 1.0f;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV);
  
    
    //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    
    return;
}

//*******************************************************************************************
__global__ void kernel_MLEFit_scmos_sigma(const float *d_data, float PSFSigma, float const *d_var, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood, float *d_lastjmp, int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 */
    
    __shared__ float s_data[MEM];
    __shared__ float s_var[MEM];
    float M[5*5], Diag[5], Minv[5*5];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=5;
    float dudt[5], d2udt2[5];
    float NR_Numerator[5], NR_Denominator[5];
    float theta[5];
    float maxjump[NV_PS]={1e0f, 1e0f, 1e2f, 2e0f, 5e-1f};
    float gamma[NV_PS]={1.0f, 1.0f, 0.5f, 1.0f, 1.0f};
    float lastjmp[5];
    float Nmax;
    
    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<5*5;ii++) M[ii] = 0;
    for (ii=0;ii<5*5;ii++) Minv[ii] = 0;
      
    //copy in data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++){
        s_data[sz*sz*tx+sz*jj+ii] = d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
        s_var[sz*sz*tx+sz*jj+ii] = d_var[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
    }
    
    //initial values
    kernel_CenterofMass2D(sz, &s_data[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_data[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma*PSFSigma);
    theta[3]=0.0f;
    theta[4]=PSFSigma;
    
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0; ll<5; ll++){
            NR_Numerator[ll] = 0;
            NR_Denominator[ll] = 0;
        }
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
            PSFy=kernel_IntGauss1D(jj, theta[1], theta[4]);
            
            model = theta[3] + theta[2]*PSFx*PSFy + s_var[sz*sz*tx+sz*jj+ii];
            data = s_data[sz*sz*tx+sz*jj+ii] + s_var[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy,
                    &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx,
                    &dudt[1], &d2udt2[1]);
            kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1],
                    theta[4], theta[2], PSFx, PSFy, &dudt[4], &d2udt2[4]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 1.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }

        if (kk == (iterations - 1)) { //last iter
            for (ll=0; ll<NV; ll++){
                lastjmp[ll] = -theta[ll];
            }
        }
        
        // The update
        if (kk<5)
            for (ll=0; ll<NV; ll++){
                theta[ll] -= gamma[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll],
                            -maxjump[ll]),
                        maxjump[ll]);
		}
        else
            for (ll=0;ll<NV;ll++){
                theta[ll] -= min(max(NR_Numerator[ll]/NR_Denominator[ll],
                            -maxjump[ll]),
                        maxjump[ll]);
		}
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        theta[3]=max(theta[3], 0.01f);
        theta[4]=max(theta[4], 0.5f);
        theta[4]=min(theta[4], sz/2.0f);
    }

    for (ll = 0; ll<NV; ll++) lastjmp[ll] += theta[ll];
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0f;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        PSFx = kernel_IntGauss1D(ii, theta[0], PSFSigma);
        PSFy = kernel_IntGauss1D(jj, theta[1], PSFSigma);
        
        model = theta[3] + theta[2]*PSFx*PSFy + s_var[sz*sz*tx+sz*jj+ii];
        data = s_data[sz*sz*tx+sz*jj+ii] + s_var[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy,
                &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx,
                &dudt[1], NULL);
        kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1], theta[4],
                theta[2], PSFx, PSFy, &dudt[4], NULL);
        dudt[2] = PSFx*PSFy;
        dudt[3] = 1.0f;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div += data*log(model) - model - data*log(data) + data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV_PS);
    
    //write to global arrays
    for (kk=0; kk<NV; kk++) d_Parameters[Nfits*kk + BlockSize*bx + tx] = theta[kk];
    for (kk=0; kk<NV; kk++) d_CRLBs[Nfits*kk + BlockSize*bx + tx] = Diag[kk];
    for (kk=0; kk<NV; kk++) d_lastjmp[Nfits*kk + BlockSize*bx + tx] = lastjmp[kk];
    d_LogLikelihood[BlockSize*bx + tx] = Div;
    
    return;
}

//*******************************************************************************************
__global__ void kernel_MLEFit_sigma_no_b(const float *d_data, float PSFSigma, const float *d_bg, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood,int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 */
    
    __shared__ float s_data[MEM];
    __shared__ float s_bg[MEM];
    __shared__ float s_diff[MEM];
    float M[NV_PS*NV_PS], Diag[NV_PS], Minv[NV_PS*NV_PS];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=NV_PS;
    float dudt[NV_PS];
    float d2udt2[NV_PS];
    float NR_Numerator[NV_PS], NR_Denominator[NV_PS];
    float theta[NV_PS];
    float maxjump[NV_PS]={1e0f, 1e0f, 1e2f, 2e0f, 5e-1f};
    float gamma[NV_PS]={1.0f, 1.0f, 0.5f, 1.0f, 1.0f};
    float Nmax;
    
    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<NV*NV;ii++)M[ii]=0;
    for (ii=0;ii<NV*NV;ii++)Minv[ii]=0;
      
    //copy in data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++){
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
        s_bg[sz*sz*tx+sz*jj+ii]=d_bg[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
        s_diff[sz*sz*tx+sz*jj+ii]=s_data[sz*sz*tx + sz*jj + ii] - s_bg[sz*sz*tx + sz*jj + ii];
    }
    
    //initial values
    kernel_CenterofMass2D(sz, &s_diff[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_diff[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma*PSFSigma);
    theta[3]=0.0f;
    theta[4]=PSFSigma;
    
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
            PSFy=kernel_IntGauss1D(jj, theta[1], theta[4]);
            
            model=s_bg[sz*sz*tx+sz*jj+ii]+theta[2]*PSFx*PSFy;
            data=s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx, &dudt[1], &d2udt2[1]);
            kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1], theta[4], theta[2], PSFx, PSFy, &dudt[4], &d2udt2[4]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 0.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
        if (kk<5)
            for (ll=0;ll<NV;ll++){
		if (ll==3) continue;
                theta[ll]-=gamma[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
		}
        else
            for (ll=0;ll<NV;ll++){
		if (ll==3) continue;
                theta[ll]-=min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
		}
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        //theta[3]=max(theta[3], 0.01f);
        theta[4]=max(theta[4], 0.5f);
        theta[4]=min(theta[4], sz/2.0f);
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0f;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        PSFx=kernel_IntGauss1D(ii, theta[0], PSFSigma);
        PSFy=kernel_IntGauss1D(jj, theta[1], PSFSigma);
        
        model=s_bg[sz*sz*tx+sz*jj+ii]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], theta[4], theta[2], PSFx, &dudt[1], NULL);
        kernel_DerivativeIntGauss2DSigma(ii, jj, theta[0], theta[1], theta[4], theta[2], PSFx, PSFy, &dudt[4], NULL);
        dudt[2] = PSFx*PSFy;
        dudt[3] = 0.0f;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV);
  
    
    //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    
    return;
}
//*******************************************************************************************
__global__ void kernel_MLEFit_z(const float *d_data, float PSFSigma_x, float Ax, float Ay, float Bx, float By, float gamma, float d, float PSFSigma_y, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood,int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 * \param Ax ???
	 * \param Ay ???
	 * \param Bx ???
	 * \param By ???
	 * \param gamma ???
	 * \param d ???
	 * \param PSFSigma_y sigma of the point spread function on the y axis
	 */
    __shared__ float s_data[MEM];
    float M[5*5], Diag[5], Minv[5*5];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=5;
    float dudt[5];
    float d2udt2[5];
    float NR_Numerator[5], NR_Denominator[5];
    float theta[5];
    float maxjump[5]={1e0f, 1e0f, 1e2f, 2e0f, 1e-1f};
    float g[5]={1.0f, 1.0f, 0.5f, 1.0f, 1.0f};
    float Nmax;
    
    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;

    for (ii=0;ii<NV*NV;ii++)M[ii]=0;
    for (ii=0;ii<NV*NV;ii++)Minv[ii]=0;
    
    //copy in data
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++)
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
    
    //initial values
    kernel_CenterofMass2D(sz, &s_data[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma_x, &s_data[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma_x*PSFSigma_y*sqrt(2.0f));
    theta[4]=0;
   
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            kernel_DerivativeIntGauss2Dz(ii, jj, theta, PSFSigma_x,PSFSigma_y, Ax,Ay,Bx,By, gamma, d, &PSFx, &PSFy, dudt, d2udt2);
            
            model=theta[3]+theta[2]*PSFx*PSFy;
            data=s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating remaining derivatives
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 1.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
        if (kk<2)
            for (ll=0;ll<NV;ll++)
                theta[ll]-=g[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        else
            for (ll=0;ll<NV;ll++)
                theta[ll]-=min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);
        
        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        theta[3]=max(theta[3], 0.01f);
        
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0f;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        
        kernel_DerivativeIntGauss2Dz(ii, jj, theta, PSFSigma_x,PSFSigma_y, Ax,Ay, Bx,By, gamma, d, &PSFx, &PSFy, dudt, NULL);
        
        model=theta[3]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating remaining derivatives
        dudt[2] = PSFx*PSFy;
        dudt[3] = 1.0f;
       
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) 
    kernel_MatInvN(M, Minv, Diag, NV);
  
   //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    return;
}

//*******************************************************************************************
__global__ void kernel_MLEFit_sigmaxy(const float *d_data, float PSFSigma, int sz, int iterations, 
        float *d_Parameters, float *d_CRLBs, float *d_LogLikelihood, int Nfits){
	/*! 
	 * \brief basic MLE fitting kernel.  No additional parameters are computed.
	 */
 
    __shared__ float s_data[MEM];
    float M[6*6], Diag[6], Minv[6*6];
    int tx = threadIdx.x;
    int bx = blockIdx.x;
    int BlockSize = blockDim.x;
    int ii, jj, kk, ll;
    float model, cf, df, data;
    float Div;
    float PSFy, PSFx;
    int NV=6;
    float dudt[6];
    float d2udt2[6];
    float NR_Numerator[6], NR_Denominator[6];
    float theta[6];
    float maxjump[6]={1e0f, 1e0f, 1e2f, 2e0f, 1e-1f,1e-1f};
    float g[6]={1.0f, 1.0f, 0.5f, 1.0f, 1.0f,1.0f};
    float Nmax;
    
    //Prevent read/write past end of array
    if ((bx*BlockSize+tx)>=Nfits) return;
    
    for (ii=0;ii<NV*NV;ii++)M[ii]=0;
    for (ii=0;ii<NV*NV;ii++)Minv[ii]=0;
    
    //copy in data
    
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++)
        s_data[sz*sz*tx+sz*jj+ii]=d_data[sz*sz*bx*BlockSize+sz*sz*tx+sz*jj+ii];
    
    //initial values
    kernel_CenterofMass2D(sz, &s_data[sz*sz*tx], &theta[0], &theta[1]);
    kernel_GaussFMaxMin2D(sz, PSFSigma, &s_data[sz*sz*tx], &Nmax, &theta[3]);
    theta[2]=max(0.0f, (Nmax-theta[3])*2*pi*PSFSigma*PSFSigma);
    theta[4]=PSFSigma;
    theta[5]=PSFSigma;
    for (kk=0;kk<iterations;kk++) {//main iterative loop
        
        //initialize
        for (ll=0;ll<NV;ll++){
            NR_Numerator[ll]=0;
            NR_Denominator[ll]=0;}
        
        for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
            PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
            PSFy=kernel_IntGauss1D(jj, theta[1], theta[5]);
            
            model=theta[3]+theta[2]*PSFx*PSFy;
            data=s_data[sz*sz*tx+sz*jj+ii];
            
            //calculating derivatives
            kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], &d2udt2[0]);
            kernel_DerivativeIntGauss1D(jj, theta[1], theta[5], theta[2], PSFx, &dudt[1], &d2udt2[1]);
            kernel_DerivativeIntGauss1DSigma(ii, theta[0], theta[4], theta[2], PSFy, &dudt[4], &d2udt2[4]);
            kernel_DerivativeIntGauss1DSigma(jj, theta[1], theta[5], theta[2], PSFx, &dudt[5], &d2udt2[5]);
            dudt[2] = PSFx*PSFy;
            d2udt2[2] = 0.0f;
            dudt[3] = 1.0f;
            d2udt2[3] = 0.0f;
            
            cf=0.0f;
            df=0.0f;
            if (model>10e-3f) cf=data/model-1;
            if (model>10e-3f) df=data/pow(model, 2);
            cf=min(cf, 10e4f);
            df=min(df, 10e4f);
            
            for (ll=0;ll<NV;ll++){
                NR_Numerator[ll]+=dudt[ll]*cf;
                NR_Denominator[ll]+=d2udt2[ll]*cf-pow(dudt[ll], 2)*df;
            }
        }
        
        // The update
            for (ll=0;ll<NV;ll++)
                theta[ll]-=g[ll]*min(max(NR_Numerator[ll]/NR_Denominator[ll], -maxjump[ll]), maxjump[ll]);

        // Any other constraints
        theta[2]=max(theta[2], 1.0f);
        theta[3]=max(theta[3], 0.01f);
        theta[4]=max(theta[4], PSFSigma/10.0f);
        theta[5]=max(theta[5], PSFSigma/10.0f);  
    }
    
    // Calculating the CRLB and LogLikelihood
    Div=0.0f;
    for (ii=0;ii<sz;ii++) for(jj=0;jj<sz;jj++) {
        
        PSFx=kernel_IntGauss1D(ii, theta[0], theta[4]);
        PSFy=kernel_IntGauss1D(jj, theta[1], theta[5]);
        
        model=theta[3]+theta[2]*PSFx*PSFy;
        data=s_data[sz*sz*tx+sz*jj+ii];
        
        //calculating derivatives
        kernel_DerivativeIntGauss1D(ii, theta[0], theta[4], theta[2], PSFy, &dudt[0], NULL);
        kernel_DerivativeIntGauss1D(jj, theta[1], theta[5], theta[2], PSFx, &dudt[1], NULL);
        kernel_DerivativeIntGauss1DSigma(ii, theta[0], theta[4], theta[2], PSFy, &dudt[4], NULL);
        kernel_DerivativeIntGauss1DSigma(jj, theta[1], theta[5], theta[2], PSFx, &dudt[5], NULL);
        dudt[2] = PSFx*PSFy;
        dudt[3] = 1.0f;
        
        //Building the Fisher Information Matrix
        for (kk=0;kk<NV;kk++)for (ll=kk;ll<NV;ll++){
            M[kk*NV+ll]+= dudt[ll]*dudt[kk]/model;
            M[ll*NV+kk]=M[kk*NV+ll];
        }
        
        //LogLikelyhood
        if (model>0)
            if (data>0)Div+=data*log(model)-model-data*log(data)+data;
            else
                Div+=-model;
    }
    
    // Matrix inverse (CRLB=F^-1) and output assigments
    kernel_MatInvN(M, Minv, Diag, NV);
   
    //write to global arrays
    for (kk=0;kk<NV;kk++) d_Parameters[Nfits*kk+BlockSize*bx+tx]=theta[kk];
    for (kk=0;kk<NV;kk++) d_CRLBs[Nfits*kk+BlockSize*bx+tx]=Diag[kk];
    d_LogLikelihood[BlockSize*bx+tx] = Div;
    return;
}
