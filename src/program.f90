!> \file program.f90
!! Main program

!>
!! \mainpage
!! Dutch Atmospheric Large Eddy Simulation
!! \section DALES Dutch Atmospheric Large Eddy Simulation
!!
!! @version 4.0.1alpha
!!
!! @author
!! Steef Boing
!! (TU Delft)
!! \author
!! Chiel van Heerwaarden
!! (Wageningen University)
!! \author
!! Thijs Heus
!! (Max Planck Institute Hamburg)
!! \author
!! Steef B\"oing
!! (TU Delft)
!>
!! \section Log Change log
!! \par New Features
!! \par Changes
!! - Changed Modfields+modglobal+modmicrodata switches
!! - Startup with new variables
!! \todo

!! This subversion
!! - Anelastic advection
!! - Anelastic resolved buoyancy (based on theta_l,q_l -> theta_v)
!! - Anelastic poisson solver
!! - Simple ice microphysics scheme (Grabowski)
!! - Icemicrostat (including precipitation)
!! - Reviewed saturation pressure with table lookup fiormula (Murphy and Koop)
!! - Gravity wave damping towards mean state
!! - Analytical function for surface forcing (may be removed later)
!! \todo
!! - Test scheme on a number of cases (e.g. TRMM LBA, Kuang and Bretherton, ARM case of K&R)
!! Todo
!! 4.0.1 improved thermodynamics
!! - Review Thermodynamic variables and pressure gradient expansion (fromztop, rhof, thetav, etc)
!! - Remove allocation from loops
!! - Review Thermodynamic variables and pressure gradient expansion (fromztop, rhof, thetav, etc), maybe let fromztop integrate from top of domain
!! - Thermodynamic variables!
!! - Make SFS-TKE itself a thermodynamic variable
!! - Look at Lipps-Hemler scheme and possible TKE term in momentum equation (consistent Lipps-Hemler implementation)
!! - Revised TKE subgrid scheme (consider diffusion) and diffusion
!! - Namoptions switch for autoconversion
!! - Integrate ice micophysics with bulk microphysics?
!! - Make ql first scalar? 
!! - Fix basic warm start
!! - Check surface boundary condition!
!! - Reimplement time-step from Thijs
!! Further
!! - Fix fielddump routine
!! - Look into evaporation
!! - Netcdf for small variables (e.g. evaporation tendencies)
!! - Look into influence of advection scheme for deep convection (Walcek scheme??)
!! - Seifert Beheng Ice microphysics (with prognostic precipitate number concentrations)
!! - 2D option
!! - Parallelization (merge with dales 3.3)
!! - Review diagnostics (in particular budgets)
!! - Review particle routine
!! - I/O: Check for necessity of netcdf/warm start including base state variables
!!
!! \section License License
!!  This file is part of DALES.
!!
!!  DALES is free software; you can redistribute it and/or modify it under the
!! terms of the GNU General Public License as published by the Free Software
!! Foundation; either version 3 of the License, or (at your option) any later
!! version.
!!
!!  DALES is distributed in the hope that it will be useful, but WITHOUT ANY
!! WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
!! PARTICULAR PURPOSE.  See the GNU General Public License for more details.
!!
!!  You should have received a copy of the GNU General Public License along with
!! this program.  If not, see <http://www.gnu.org/licenses/>.
!!
!!  Copyright 1993-2009 Delft University of Technology, Wageningen University,
!! Utrecht University, KNMI
!!
program DALES      !Version 4.0.0alpha

!!----------------------------------------------------------------
!!     0.0    USE STATEMENTS FOR CORE MODULES
!!----------------------------------------------------------------
  use modmpi,            only : myid, initmpi
  use modglobal,         only : rk3step,timee,btime,runtime,timeleft
  use modfields,         only : thl0
  use modstartup,        only : startup, writerestartfiles,exitmodules
  use modtimedep,        only : timedep
  use modboundary,       only : boundary, grwdamp,tqaver
  use modthermodynamics, only : thermodynamics
  use modmicrophysics,   only : microsources
  use modsurface,        only : surface
  use modsubgrid,        only : subgrid
  use modforces,         only : forces, coriolis, lstend
  use modradiation,      only : radiation
  use modpois,           only : poisson


!----------------------------------------------------------------
!     0.1     USE STATEMENTS FOR ADDONS STATISTICAL ROUTINES
!----------------------------------------------------------------
  use modchecksim,     only : initchecksim, checksim
  use modstat_nc,      only : initstat_nc
  use modtimestat,     only : inittimestat, timestat
  use modgenstat,      only : initgenstat, genstat, exitgenstat
  use modradstat,      only : initradstat ,radstat, exitradstat
  use modlsmstat,      only : initlsmstat ,lsmstat, exitlsmstat
  use modsampling,     only : initsampling, sampling,exitsampling
  use modcrosssection, only : initcrosssection, crosssection,exitcrosssection  
  use modlsmcrosssection, only : initlsmcrosssection, lsmcrosssection,exitlsmcrosssection
  use modcloudfield,   only : initcloudfield, cloudfield
  use modfielddump,    only : initfielddump, fielddump,exitfielddump
  use modstattend,     only : initstattend, stattend,exitstattend, tend_start,tend_adv,tend_subg,tend_force,&
                              tend_rad,tend_ls,tend_micro, tend_topbound,tend_pois,tend_addon, tend_coriolis

  use modbulkmicrostat,only : initbulkmicrostat, bulkmicrostat,exitbulkmicrostat
  use modsimpleicestat,only : initsimpleicestat, simpleicestat,exitsimpleicestat
  use modbudget,       only : initbudget, budgetstat, exitbudget
  use modheterostats,  only : initheterostats, heterostats, exitheterostats

  ! modules below are disabled by default to improve compilation time
  !use modstress,       only : initstressbudget, stressbudgetstat, exitstressbudget

  !use modtilt,         only : inittilt, tiltedgravity, tiltedboundary, exittilt
  !use modparticles,    only : initparticles, particles, exitparticles
  !use modnudge,        only : initnudge, nudge, exitnudge
  !use modprojection,   only : initprojection, projection
  !use modchem,         only : initchem,inputchem,twostep


  implicit none

!----------------------------------------------------------------
!     1      READ NAMELISTS,INITIALISE GRID, CONSTANTS AND FIELDS
!----------------------------------------------------------------
  call initmpi

  call startup

!---------------------------------------------------------
!      2     INITIALIZE STATISTICAL ROUTINES AND ADD-ONS
!---------------------------------------------------------
  call initchecksim
  call initstat_nc   ! Should be called before stat-routines that might do netCDF
  call inittimestat  ! Timestat must preceed all other timeseries that could write in the same netCDF file (unless stated otherwise
  call initgenstat   ! Genstat must preceed all other statistics that could write in the same netCDF file (unless stated otherwise
  !call inittilt
  call initsampling
  call initcrosssection
  call initlsmcrosssection
  !call initprojection
  call initcloudfield
  call initfielddump
  call initstattend
  call initradstat
  call initlsmstat
  !call initparticles
  !call initnudge
  !call initparticles
  call initbulkmicrostat
  call initsimpleicestat
  call initbudget
  !call initstressbudget
  call initchem
  call initheterostats

!------------------------------------------------------
!   3.0   MAIN TIME LOOP
!------------------------------------------------------
  write(*,*)'START myid ', myid
  do while (timeleft>0 .or. rk3step < 3)
    call tstep_update
    call timedep
    call stattend(tend_start)

!-----------------------------------------------------
!   3.1   RADIATION         
!-----------------------------------------------------
    call radiation !radiation scheme
    call stattend(tend_rad)

!-----------------------------------------------------
!   3.2   THE SURFACE LAYER
!-----------------------------------------------------
    call surface

!-----------------------------------------------------
!   3.3   ADVECTION AND DIFFUSION
!-----------------------------------------------------
    call advection
    call stattend(tend_adv)
    call subgrid
    call stattend(tend_subg)

!-----------------------------------------------------
!   3.4   REMAINING TERMS
!-----------------------------------------------------
    call coriolis !remaining terms of ns equation
    call stattend(tend_coriolis)
    call forces !remaining terms of ns equation
    call stattend(tend_force)

    call lstend !large scale forcings
    call stattend(tend_ls)
    call microsources !Drizzle etc.
    call stattend(tend_micro)

!------------------------------------------------------
!   3.4   EXECUTE ADD ONS
!------------------------------------------------------
    !call nudge
    !call tiltedgravity
    call stattend(tend_addon)

!-----------------------------------------------------------------------
!   3.5  PRESSURE FLUCTUATIONS, TIME INTEGRATION AND BOUNDARY CONDITIONS
!-----------------------------------------------------------------------
    call grwdamp !damping at top of the model
    call tqaver !set thl, qt and sv(n) equal to slab average at level kmax
    call stattend(tend_topbound)
    call poisson
    call stattend(tend_pois,lastterm=.true.)

    call tstep_integrate
    call boundary
    !call tiltedboundary
!-----------------------------------------------------
!   3.6   LIQUID WATER CONTENT AND DIAGNOSTIC FIELDS
!-----------------------------------------------------
    call thermodynamics

!-----------------------------------------------------
!   3.7  WRITE RESTARTFILES AND DO STATISTICS
!------------------------------------------------------
    call twostep

    call checksim
    call timestat  !Timestat must preceed all other timeseries that could write in the same netCDF file (unless stated otherwise
    call genstat  !Genstat must preceed all other statistics that could write in the same netCDF file (unless stated otherwise
    call radstat
    call lsmstat
    call sampling
    call crosssection
    call lsmcrosssection
    call cloudfield
    call fielddump
    !call particles

    call bulkmicrostat
    call simpleicestat
    call budgetstat
    !call stressbudgetstat
    call heterostats

    call writerestartfiles
  end do

!-------------------------------------------------------
!             END OF TIME LOOP
!-------------------------------------------------------


!--------------------------------------------------------
!    4    FINALIZE ADD ONS AND THE MAIN PROGRAM
!-------------------------------------------------------
  call exitgenstat
  call exitradstat
  call exitlsmstat
  !call exitparticles
  !call exitnudge
  call exitsampling
  call exitstattend
  call exitbulkmicrostat
  call exitsimpleicestat
  call exitbudget
  !call exitstressbudget
  call exitcrosssection
  call exitlsmcrosssection
  call exitfielddump
  call exitheterostats
  call exitmodules

end program DALES
