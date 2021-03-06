*************************************************************************
* calculate C term of the diffusion equation (EFFECTIVE THERMAL CAPACITY)
*************************************************************************
        real*8 function Cterm(T,time,ix,fo)
        implicit none
	include 'parEBM.h'
        real*8 T
        integer ix
        real*8 CL, CO, CIL, CIO, CATM 
	real*8 fi,fil,fio
	real*8 time
        real *8 f_ice, fo(N)
	real*8 pressPtot,cp_Ptot,molwtPtot
	
	common /gasplusvapor_pars/ pressPtot,cp_Ptot,molwtPtot 

*       we scale the thermal inertia of the atmosphere according to planet parameters 
*       cp: specific heat capacity; gP: planet gravitational acceleration   Pierrehumbert (2010, pp. 445,446)] 
      CATM=CATM_E*(cp_Ptot/cp_E)*(pressPtot/pressE)/(gP/gE)
      
      CL =CSOLID+CATM     ! effective thermal capacity over lands
      CIL=CSOLID+CATM     ! ... and over continental ices
      
      CO =CATM+COCEAN      ! effective thermal capacity over oceans  
      CIO=CSOLID+CATM     ! ... and over ocean ices 
     
*       thermal inertia associated with the latent heat of water-ice phase change
      if(T.gt.263.0.and.T.lt.273.0) then
      CIL=CIL+CML50/5.  ! additional contribution of 42.d9
      CIO=CIO+CML50/5.  ! additional contribution of 42.d9
      end if
	
        fio = f_ice(T,time,ix)
	fil = fio  
	
        Cterm = (1-fo(ix))*((1.-fil)*CL+fil*CIL) ! CONTINENTI
     >         + fo(ix)*( (1-fio)*CO + fio*CIO) ! OCEANI

        return
        end



**************************************************************************
*       calculate D term of the diffusion equation (diffusion coefficient)
**************************************************************************
        real*8 function Dterm(time,x,T,Ddry)
        implicit none
        real*8 T 
        real*8 time,x
	real*8 nu,xx,phi,delta
	real*8 xl,Ls,cosH,HH,sind
	real*8 modulation,mu_med 
	real*8 pressPtot,cp_Ptot,molwtPtot
        real*8 halfday
        real*8 DTbc,T1bc,Sbc,vTgrad 
        real*8 SL1, SL2 ! scaling laws of dry and moist transport
        real*8 Ddry
	
        include 'parEBM.h'  
	
	common /gasplusvapor_pars/ pressPtot,cp_Ptot,molwtPtot
        common /transportpar/ DTbc,T1bc,Sbc,vTgrad
	
	Ls=nu(time)+LSP 
	
        if(xmin<-1.5) then
           phi = x
           xx = dsin(x)
        else
           xx = x               !integration in sin(lat)
           phi =  dasin(xx)
        endif

        if(xx.lt.-1.0) xx=-1.0
        if(xx.gt. 1.0) xx= 1.0
        xl   =  dmod(Ls+Ls0,pi2) 
	
        sind= -dsin(OBLIQUITY)*dcos(xl)
        delta=dasin(sind) 
	HH=halfday(phi,delta)

*          mean diurnal value of cos(zenith distance) Eq. (A23)	
	if(dabs(HH).gt.0.) then
	mu_med=dsin(phi)*dsin(delta)
     >        +dcos(phi)*dcos(delta)*dsin(HH)/HH
	else
	mu_med=0.
	end if   

*          SCALING LAW OF DRY ATMOSPHERIC FLUX
        SL1=(Rplanet/Rearth)**(-6./5)
     >     *((pressPtot/pressE)/(gP/gE))**(2./5)
     >     *(cp_Ptot/cp_E) ! *(molwtE/molwtPtot)**2  ! atmospheric data
     >     *(omegaP/omegaE)**(-4./5)              ! rot. angular velocity 
     >     *(DTbc/DTbcE)**(3./5)  !  mean temperature difference between mid latitude limits
     >     *(Sbc/SbcE)**(3./5)       !  diabatic forcing over mid-latitude region 
     >     *(T1bc/T1bcE)**(-3./5)     !  representative temperature baroclinic zone

*           SCALING LAW OF MOIST ATMOSPHERIC FLUX COMPONENT
        SL2=(RH/RH_E)*(cp_Ptot/cp_E)**(-1) 
     >     *(molwtP/molwtE)**(-1)
     >     *(pressP/pressE)**(-1)
     >     *vTgrad/vTgradE  ! delta(vapor)/delta(T)  

c        SL2=1.d0 !   CASO DRY

        Dterm=(C0par+C1par*mu_med)*D0par*SL1
     >        *(1.+lambdaE*SL2)/(1.+lambdaE)

        Ddry=Dterm/(1.+lambdaE*SL2)

*************   FOR THE CALIBRATION OF THE EARTH MODEL
********        Dterm=D0par*(C0par+C1par*mu_med)

        return
        end



 
*************************************************************
*        CALCULATE the OLR INTERPOLATING THE TABLE OBTAINED
*        FROM THE CRM RADIATIVE CALCULATIONS
*************************************************************
      real*8 function Iterm(ilat,T)
      integer ilat
      real*8 T  
      real*8 olrTAB,cloudforcing
      real*8 lininterp 
      include 'parEBM.h'  
      real*8 zonalfc(N) 
      
      common /zonalcloudcover/ zonalfc
      
c     interpolate value of tabulated OLR at current temperature 
c     arrays TOLR and vOLR are read from file parEBM.h
      olrTAB = lininterp(TOLR,vOLR,NOLR,T)  
      
c     calculate cloud forcing   
c      fcGLOBAL_E: GLOBAL CLOUD COVER OF THE EARTH
c      cloudOLRforcingE: global OLR cloud forcing of the Earth
      cloudforcing=cloudOLRforcingE*zonalfc(ilat)/fcGLOBAL_E

c     subtract cloud forcing
      Iterm=olrTAB - cloudforcing 
   
      return
      end
	
***************************************************************
*       Home-made interpolation function used by "Iterm"
*       Input: arrays x & y, integer n, real x0
*       x must be increasing    
*       Output: real y0 interpolated at position x0
*       if x0 is outside range of x, the value of y0 is extrapolated
***************************************************************      
        real*8 function lininterp(x,y,n,x0)

        integer k,n
        real*8 x0,y0,x(n),y(n)
        
        do k=1,n-1
        if( x0.ge.x(k).and.x0.le.x(k+1) ) then
        y0=y(k)+(y(k+1)-y(k))*(x0-x(k))/(x(k+1)-x(k)) 
        end if 
        end do
        
        if(x0.lt.x(1)) then
        y0=y(1)
c        print *,'EXTRAPOLATION AT START OF RANGE',x0
        end if
        
        if(x0.gt.x(n)) then
        y0=y(n)
c        print *,'EXTRAPOLATION AT END OF RANGE',x0
        end if
        
        lininterp=y0
        return
        end



        
****************************************************************************
*       calculate the term A of the diffusion equation (mean diurnal albedo)
****************************************************************************
      real*8 function Aterm(time,x,T,i,fo)

      implicit none
      include 'parEBM.h'
      
      real*8 time,x,T
      real*8 xl,phi,delta,cosH,HH,sind
      real*8 nu, Ls  
      real*8 halfday
      real*8 alb_Z   
      external alb_Z
      
      real*8 fo(N),folat(N)
      integer i 
      
      real*8 Tlat,ctime
      integer ilat,j 

      real*8 meandiurnalclalb,pi
      
      common /albparam/ ctime,phi,delta,folat,Tlat,ilat

      if(albedoType.eq.'fix') then
      Aterm=fixAlbedo
      return 
      end if
      
      Tlat=T
      ilat=i 
      ctime=time
      
      do j=1,N
      folat(j)=fo(j)
      end do

      phi=dasin(x) 
 
      Ls=nu(time)+LSP                  !  Eq. (A26)
      xl  = dmod(Ls+Ls0,pi2)                              
      sind= -dsin(OBLIQUITY)*dcos(xl)  ! Eq. (A25)  
      delta=dasin(sind) 
 
      HH=halfday(phi,delta)
      
      if (dabs(HH).gt.0.0) then  
c          call qgaus(alb_Z,-HH,+HH,Aterm)
c          Aterm=Aterm/(2.*HH) ! normalization
	  call qgaus(alb_Z,0.d0,+HH,Aterm)     ! SFRUTTATA PROPRIETA' DI SIMMETRIA
          Aterm=Aterm/HH ! normalization  ! int(-H,+H)=2*int(0,+H)
      else
          Aterm=-1.
      end if   
******************* TEST CLOUD ALBEDO ***********************************
c      if (dabs(HH).gt.0.0) then   
c	  call qgaus(clalb,0.d0,+HH,meandiurnalclalb)  
c          meandiurnalclalb=meandiurnalclalb/HH
c      else
c          meandiurnalclalb=-1.
c      end if   
c      pi=3.1415926535
c      
c      if(time/Porb.ge.30..and.time/Porb.lt.31.) then
c      write(75,75) phi*180./pi,time/Porb,meandiurnalclalb
c      end if
c75    format(f6.2,2x,f6.3,2x,f6.3)
******************* END TEST *********************************************

      return
      end
      
********** TEST CLOUD ALBEDO
c      real*8 function clalb(hour)
c      include 'parEBM.h' ! read albedo parameters asl,asio,asil
c      integer ilat
c      real*8 hour 
c      real*8 phi,delta,T,time,fo(N)
c      real*8 mu, ZZ,pi, Zdeg,mzd(N)

c      common /albparam/ time,phi,delta,fo,T,ilat 
c      common /meanZenDist/ mzd 

*       calculate instantaneous ZENITH DISTANCE   Eq. (A20) 
c      mu= dsin(phi)*dsin(delta) + dcos(phi)*dcos(delta)*dcos(hour)  
      
c      if (abs(mu) .lt. 1d-10) mu=0.
      
c      ZZ=dacos(mu)   
c      pi=3.1415926535
c      Zdeg=ZZ*180./pi ! convert to degrees 

c      if(zendistType.eq.'instant') clalb=dmax1(0.,calpha+cbeta*Zdeg) 
c      if(zendistType.eq.'orbital') clalb=calpha+cbeta*mzd(ilat)  
c      return
c      end 
****************** END TEST CLOUD ALBEDO
                                      
*******************************************************************
*       CALCULATE instantaneous SURFACE ALBEDO AT HOUR ANGLE "hour"  
*******************************************************************       
      real*8 function alb_Z(hour) 

      include 'parEBM.h' ! read albedo parameters asl,asio,asil
      real*8 hour
      real*8 phi,delta,T,time
      real*8 mu, ZZ
      real*8 f_ice, fi, as, aso, asi, asc 
      integer ilat
      real*8 fo(N) 
      real*8 inc,nfr,rfr  ! Fresnel parameters 
      real*8 alfa, beta  
      real*8 TOA_albedo,TOA_diff,CloudAlbCess  
      real*8 fio,fil
      real*8 ToaQuadLinInterp,pi,Zdeg 
      real*8 mzd(N)  ! MEAN ORBITAL ZENITH DISTANCE
      
      common /albparam/ time,phi,delta,fo,T,ilat 
      common /interp_TOA/ Matrix_TOA,T_TOA,p_TOA,z_TOA,as_TOA 
      common /meanZenDist/ mzd 

      include 'module_vegalbedo_local.f'

*       calculate instantaneous ZENITH DISTANCE   Eq. (A20) 
      mu= dsin(phi)*dsin(delta) + dcos(phi)*dcos(delta)*dcos(hour)  
      
      if (abs(mu) .lt. 1d-10) mu=0.
      
      ZZ=dacos(mu)  

      pi=3.1415926535
      Zdeg=ZZ*180./pi ! convert to degrees 

*       calculate OCEAN albedo at current zenith distance  Eq. (A14)
*       Briegleb et al,J. Clim. Appl. Meteorol. 25, 214–224 (1986) 
       aso = 0.026/(1.1*mu**1.7 + 0.065) 
     >      + 0.15*(mu-0.1)*(mu-0.5)*(mu-1.0)  ! OK CONTROLLATA  

*        ice cover
      fio=f_ice(T,time,ilat) ! ocean ice cover
      fil=fio                ! land ice cover

*        cloud albedo at mean zonal annual zenith distance 
*        based on Cess 1976 trend 
      if(zendistType.eq.'instant') asc=dmax1(0.,calpha+cbeta*Zdeg) 
      if(zendistType.eq.'orbital') asc=calpha+cbeta*mzd(ilat)  
      
*       calculate mean zonal surface albedo Eq. (A13)
*       values of land and ice albedos are read from parEBM.h
*       cloud albedo is treated as part of the surface albedo
      call albsup(fo(ilat),fio,fil,aso,asc,as) 

*       calculate Top-of-Atmosphere albedo as a function of:
*       T, p(DRY), zenith distance and surface albedo  
      alb_Z=ToaQuadLinInterp(T,pressP/1.d5,Zdeg,as)
      return
      end
      
*******************************************************************
*       calculate cloud albedo at zenith distance Z
*******************************************************************
c       real*8 function CloudAlbCess(Z)
c       include 'parEBM.h'  ! read fcw, fcl, fci from parameters file 
c       real*8 Z,pi  
cc        Eq. (A15), obtained from fit to Fig. 2 in Cess 1976 
c       pi=3.1415926535
c       Z=Z*180./pi  ! convert zenith distance to degrees 
c       CloudAlbCess=dmax1(0.,calpha+cbeta*Z)  
c       return
c       end   

*******************************************************************
*       calculate mean zonal surface albedo
*******************************************************************
        include "module_albedo_surf.f"

***********************  END OF ALBEDO ROUTINES  *************************

       


**********************************************************************
*  calculate S term in diffusion equation (mean diurnal stellar flux)
**********************************************************************
        real*8 function Sterm(time,x)
        implicit none
        include 'parEBM.h'
        real*8 time,x,xx
        real*8 sind0,xl,phi,delta,cosH,HH,sind
        real*8 Sterm0, Sterm1
	real*8 year, halfday
	
	real*8 keplerE
	real*8 ratio,q0HEL
	real*8 Ls,M,nu  
	
        ratio=1.-eccP*dcos(keplerE(time))  ! r/a in Eq. (A24)
	   
	q0HEL=q0/(ratio**2) ! instantaneous stellar flux at distance r 
        
	Ls=nu(time)+LSP   ! planetocentric longitude of the star, Eq. (A26)

        if(xmin<-1.5) then      !integration in latitude
           phi = x
           xx = dsin(x)
        else
           xx = x             !integration in sin(latitude)
           phi =  dasin(xx)
        endif

        if(xx.lt.-1.0) xx=-1.0
        if(xx.gt. 1.0) xx= 1.0 

        xl   =  dmod(Ls+Ls0,pi2) ! Ls0 is read from parEBM.h
c          Ls0=pigreco/2->Spring equinox (vernal point); Ls0=0->Winter solstice
c          because we use here Eq. (A2) from WK97 instead of our equivalent Eq. (A25) 

        sind= -dsin(OBLIQUITY)*dcos(xl)  ! from WK97 Eq. (A2)
        delta=dasin(sind)  
        HH=halfday(phi,delta)

        Sterm=(q0HEL)*(HH*sind*dsin(phi) + 
     >        dsqrt(1-xx**2)*dcos(delta)*dsin(HH))
 
        Sterm=Sterm*2.0/pi2  
	
	year=   time/Porb 
	if(year.le.1.00d00) then  
	  if(xmin<-1.5) then ! phi
	   
	   if(dabs(x).lt.0.01) then  
	   write(55,38) year,Sterm 
	   endif 
	   if( x .gt. 1.5) then 
	   write(58,38) year,Sterm
	   endif 
	   if( x .lt.-1.5) then 
	   write(59,38) year,Sterm
	   endif 
	   if( x .gt. 0.764 .and. x .lt. 0.765) then 
	   write(56,38) year,Sterm
	   endif 
	   if( x .lt.-0.764 .and. x .gt. -0.765) then 
	   write(57,38) year,Sterm
	   endif
	   
	  else !  sin(phi)
	   
	   if(dabs(x).lt.0.01) then  
	   write(55,38) year,Sterm 
	   endif 
	   if( x .gt. 0.98) then 
	   write(58,38) year,Sterm
	   endif 
	   if( x .lt.-0.98) then 
	   write(59,38) year,Sterm
	   endif 
	   if( x .lt. 0.72 .and. x .gt. 0.70) then 
	   write(56,38) year,Sterm
	   endif 
	   if( x .lt.-0.70 .and. x .gt. -0.72) then 
	   write(57,38) year,Sterm
	   endif	   
	   
	  end if
	    
	endif
	
38         format(f12.8,2x,e14.8)  
        
        return
        end

*************************************************************
*     calculate half-day length, Eq. (A19)
*************************************************************
      real*8 function halfday(phi,delta)
      real*8 phi, delta, cosH

      cosH = -dtan(phi)*dtan(delta)  
      if(cosH.gt.1.0d0) cosH =  1.0d0;
      if(cosH.lt.-1.0d0) cosH = -1.0d0;
	
      halfday=dacos(cosH)
      return
      end

*******************************************************************
*   routines used to calculate the stellar flux in eccentric orbits
******************************************************************* 

	real*8 function M(time)  ! Mean anomaly, Eq. (A29)
	implicit none
	include 'parEBM.h'
	real*8 time
	M=omegaORB*time+Miniz
	return
	end

c  keplerian function from Eq. (A28)
	real*8 function kfun(E0,time)   
	implicit none
	real*8 E0,time,M  
	include 'parEBM.h'
	kfun=E0-eccP*dsin(E0)-M(time)
	return
	end
	
c  derivative of keplerian function from Eq. (A28)
	real*8 function derkfun(E0)     
	implicit none
	real*8 E0  
	include 'parEBM.h'
	derkfun=1.-eccP*dcos(E0)
	return
	end 
	
c Calculate Eccentric Anomaly Eq. (A28) with Newton's iteration method
	real*8 function keplerE(time) ! ECCENTRIC ANOMALY
	implicit none
	include 'parEBM.h'
	real*8 time,M
	real*8 kfun,derkfun
	real*8 epsk,pd
	real*8 E0,E1
	epsk=1.d-6
	E0=M(time)
	pd=1.0d0
	do while (pd .gt. epsk)
	E1=E0-kfun(E0,time)/derkfun(E0) ! Newthon's method
	pd=dabs(E1-E0)/E0
	E0=E1
	enddo
	keplerE=E1
	return
	end
	
c          true anomaly, Eq. (A27)
	real*8 function nu(time)
	implicit none
	include 'parEBM.h'
	real*8 time,keplerE
        nu=2.*datan(dsqrt((1.+eccP)/(1.-eccP))
     >     	*dtan(keplerE(time)/2.))
        return
	end
***** end of eccentric orbit routines **********************************

*****  COVERAGE OF ICE, CLOUDS AND OCEANS  *****************************

*********************************************************************** 
*     ICE COVER adopted by WK97
*     USED IN THE NEXT FUNCTION f_ice
*********************************************************************** 
      real*8 function iceWK97(T) 
      real*8 T 
      iceWK97=(1.00-dexp((T-273.15)/10.0)) 
      iceWK97=dmax1(0.00,iceWK97) 
      return
      end
      	  	 
***********************************************************************  
*     ICE COVER
*     Calculates the function "iceWK97(T)" either  
*     (1) at the mean diurnal zonal temperature (WK97 recipe)
*     or 
*     (2) at the mean annual zonal temperature.
*     During the first 20 orbits always use the option (1).
*     After the first 20 orbits use the option (2) in zones with T < 273 
*     for more than 50% of the orbit; otherwise keeps using option (1)
***********************************************************************

       real*8 function f_ice(temp,time,ilat)
       implicit none
       include 'parEBM.h' ! read Porb,Ns
       integer ilat,ks,js,kf
       real*8 temp,time 
       real*8 tempmat(Ns,N)
       real*8 freezefraction !,season,oldtemp
       real*8 Tmed
c       real*8 Tmedq
       real*8 iceWK97 
       real*8 arr(Ns) 
       
       common /tempmatrix/ tempmat 

       if(iceType.eq.'none') then
       f_ice=0.
       return
       end if
       
       if(time/Porb.lt.10.) then  
       f_ice=iceWK97(temp)
       return
       end if 

c      calculate the fraction of orbital period during which the latitude zone is frozen

       kf=0
       do js=1,Ns
          if(tempmat(js,ilat).lt.273.15) kf=kf+1
       end do
       freezefraction=dfloat(kf)/dfloat(Ns)  
        
c      calculate the ice fraction 

       if(freezefraction.gt.6./12.) then 
        
          Tmed=0. 
          do js=1,Ns  
	  Tmed=Tmed+tempmat(js,ilat) 
          end do  
	  Tmed=Tmed/dfloat(Ns)  

          f_ice=iceWK97(Tmed) 

c          Tmedq=0. !  QUADRATIC MEAN
c          do js=1,Ns  
c	  Tmedq=Tmedq+tempmat(js,ilat)**2 
c          end do  
c	  Tmedq=dsqrt( Tmedq/dfloat(Ns) ) 

c          f_ice=iceWK97(Tmedq)   

       else  
        
	  f_ice=iceWK97(temp) 
	  
       end if 
       
       return
       end 

**************************************************************************
c     calculate fraction of planet area covered by ice at a given time
c     used only in the main program
c     in forced exit criteria and as a print output of the simulation
**************************************************************************
      real*8 function icecover(T,time) 
      implicit none
      include 'parEBM.h'
      real*8 T(N),fi,f_ice,time
      real*8 fi1,fi2,dfi,dlat
      integer j
      
      icecover=0.
      
      do j=1,N  
      
      dfi=dlat(j)
      
      fi=f_ice(T(j),time,j)
      icecover = icecover + dfi*fi/2.0
      end do
      
      return
      end      


************************************************************
c     compute instantaneous zonal cloud coverage 
c     used in function Iterm to subtract the long wavelength cloud forcing
************************************************************
      subroutine subfc(T,time,ix,fo,fc) 
      include 'parEBM.h'  ! read fcw, fcl, fci from parameters file
      integer ix
      real*8 fo,T,fio,fil,time
      real*8 f_ice
      real*8 fc  ! output
      
      fio=f_ice(T,time,ix) 
      fil=fio
      
      fc=    fo*( (1.-fio)*fcw + fio*fci) +   ! OCEANS
     >  (1.-fo)*( (1.-fil)*fcl + fil*fci)       ! LANDS  
      
      return
      end 


****************   END OF CLIMATE ROUTINES  *****************

*******************************************************************************************
*      standard integrator from Numerical Recipes used to calculate the mean diurnal albedo 
*******************************************************************************************
      SUBROUTINE qgaus(func,a,b,ss)
      REAL*8 a,b,ss,func
      EXTERNAL func
      INTEGER j
      REAL*8 dx,xm,xr,w(5),x(5)
      SAVE w,x
      DATA w/.2955242247,.2692667193,.2190863625,.1494513491,
     *.0666713443/
      DATA x/.1488743389,.4333953941,.6794095682,.8650633666,
     *.9739065285/
      xm=0.5*(b+a)
      xr=0.5*(b-a)
      ss=0
      do 11 j=1,5
        dx=xr*x(j)
        ss=ss+w(j)*(func(xm+dx)+func(xm-dx))
11    continue
      ss=xr*ss
      return
      END
C  (C) Copr. 1986-92 Numerical Recipes Software 1@.




!***********************************************************

