module model_mod

! <next three lines automatically updated by CVS, do not edit>
!  $Source$
!  $Revision$
!  $Date$

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!                                                                       !!
!!                   GNU General Public License                          !!
!!                                                                       !!
!! This file is part of the Flexible Modeling System (FMS).              !!
!!                                                                       !!
!! FMS is free software; you can redistribute it and/or modify           !!
!! it and are expected to follow the terms of the GNU General Public     !!
!! License as published by the Free Software Foundation.                 !!
!!                                                                       !!
!! FMS is distributed in the hope that it will be useful,                !!
!! but WITHOUT ANY WARRANTY; without even the implied warranty of        !!
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         !!
!! GNU General Public License for more details.                          !!
!!                                                                       !!
!! You should have received a copy of the GNU General Public License     !!
!! along with FMS; if not, write to:                                     !!
!!          Free Software Foundation, Inc.                               !!
!!          59 Temple Place, Suite 330                                   !!
!!          Boston, MA  02111-1307  USA                                  !!
!! or see:                                                               !!
!!          http://www.gnu.org/licenses/gpl.txt                          !!
!!                                                                       !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! Assimilation interface for Held-Suarez Bgrid

!-----------------------------------------------------------------------
!
!     interface for B-grid dynamics using the Held-Suarez forcing
!
!-----------------------------------------------------------------------
!---------------- m o d u l e   i n f o r m a t i o n ------------------

use bgrid_core_driver_mod, only: bgrid_dynam_type,       &
                                 bgrid_core_driver_init, &
                                 bgrid_core_driver,      &
                                 bgrid_core_time_diff,   &
                                 bgrid_core_driver_end,  &
                                 get_bottom_data,        &
                                 put_bottom_data

use diag_manager_mod, only: diag_manager_init, diag_manager_end, get_base_date


use   bgrid_prog_var_mod, only: prog_var_type, var_init, prog_var_init, &
                                open_prog_var_file, read_prog_var

use      bgrid_horiz_mod, only: get_horiz_grid_size,        &
                                get_horiz_grid_bound, TGRID, VGRID

use time_manager_mod, only: time_type, set_time, get_time,  &
                            operator(+), operator (<), operator (>), &
                            operator (/=), operator (/), operator (*)

use              fms_mod, only: file_exist, open_namelist_file, &
                                error_mesg, FATAL,              &
                                check_nml_error, stdlog,        &
                                write_version_number,           &
                                mpp_pe, mpp_root_pe,            &
                                close_file, set_domain,         &
                                fms_init, mpp_clock_init,       &
                                MPP_CLOCK_SYNC,                 &
                                open_restart_file, mpp_clock_end, &
                                mpp_clock_begin

use       mpp_io_mod, only: mpp_open, mpp_close, MPP_ASCII, MPP_OVERWR, &
                            MPP_SEQUENTIAL, MPP_SINGLE, MPP_DELETE


! routines used by subroutine bgrid_physics
use bgrid_change_grid_mod, only: vel_to_mass, mass_to_vel
use       bgrid_horiz_mod, only: horiz_grid_type
use        bgrid_vert_mod, only: vert_grid_type, &
                                 compute_pres_full, compute_pres_half
use        bgrid_halo_mod, only: update_halo, UWND, VWND, TEMP, &
                                 NORTH, EAST, WEST, SOUTH
use        hs_forcing_mod, only: hs_forcing_init, hs_forcing

! DART routines 
use          location_mod, only: location_type, get_location, set_location, &
                                 get_dist, vert_is_level, query_location, &
                                 LocationDims, LocationName, LocationLName

use        random_seq_mod, only: random_seq_type, init_random_seq, random_gaussian
use             types_mod, only: r8, pi

!-----------------------------------------------------------------------

implicit none
private

public  get_model_size, adv_1step, get_state_meta_data, model_interpolate, &
        get_model_time_step, end_model, static_init_model, init_time, &
        init_conditions, TYPE_PS, TYPE_T, TYPE_U, TYPE_V, TYPE_TRACER, &
        model_get_close_states, nc_write_model_atts, nc_write_model_vars, &
        pert_model_state

!-----------------------------------------------------------------------
! CVS Generated file description for error handling, do not edit
character(len=128) :: version = "$Id$"
character(len=128) :: tag = "$Name$"
character(len=128) :: &
source   = "$Source$", &
revision = "$Revision$", &
revdate  = "$Date$"

!-----------------------------------------------------------------------
! bgrid_prog_var_mod:prog_var_type
! data structure that contains all prognostic fields and tracers
! type prog_var_type
!      integer       :: nlon, nlat, nlev, ntrace
!      integer       :: ilb, iub, jlb, jub, klb, kub
!      real, pointer :: ps(:,:), pssl(:,:)
!      real, pointer :: u(:,:,:), v(:,:,:), t(:,:,:), r(:,:,:,:)
! end type prog_var_type
! It would be great if the data structure could have character names and some metadata
! for each variable ... units, etc. 

! integer, parameter :: N_prog_Var = 6
! character(len=NF90_MAX_NAME), dimension(N_prog_Var) :: Prog_Var_Names = (/ "ps", "pssl", "u","v","t","r" /)
! character(len=NF90_MAX_NAME), dimension(N_prog_Var) :: Prog_Var_Units = (/ "hPa", "hPa", "m/s","m/s","degrees Kelvin","depends" /)


!-----------------------------------------------------------------------
!---- namelist (saved in file input.nml) ----
!
! physics_window  The number of "i" by "j" rows processed each time
!                 the modular physics is called. To process the entire
!                 domain use physics_window = (/0,0/).
!                   [integer, default: physics_window = 0,1]

   integer, dimension(2) :: physics_window = (/0,0/)

   namelist /atmosphere_nml/ physics_window

!-----------------------------------------------------------------------
! Additional stuff currently in main_nml moved down from atmos_solo_driver
! This time stuff may not really belong here???

   integer, dimension(4) :: current_time = (/ 0, 0, 0, 0 /)
   logical  :: override = .false.  ! override restart values for date
   integer  :: days=0, hours=0, minutes=0, seconds=0
   integer  :: dt_atmos = 0
   real(r8) :: noise_sd = 0.0_r8
   integer  :: dt_bias  = -1
   logical  :: output_state_vector = .false.  ! output prognostic variables

   namelist /main_nml/ current_time, override, dt_atmos, &
                       days, hours, minutes, seconds, noise_sd, &
                       dt_bias, output_state_vector 

!-----------------------------------------------------------------------
! More stuff from atmos_solo driver
! ----- model time -----

   type (time_type) :: Time, Time_init, Time_end, Time_step_atmos

! ----- coupled model initial date -----

   integer :: date_init(6)

!-----------------------------------------------------------------------
! Public definition of variable types
integer, parameter :: TYPE_PS = 0, TYPE_T = 1, TYPE_U = 2, TYPE_V = 3, TYPE_TRACER = 4

!-----------------------------------------------------------------------
!---- private data ----

type (bgrid_dynam_type) :: Dynam
type    (prog_var_type) :: Var_dt

integer                            :: model_size
!real                               :: dt_atmos
real(r8),    dimension(:,:,:), pointer :: omega
integer, dimension(4)              :: atmos_axes
integer                            :: num_levels
integer                            :: ntracers 
! Havana no longer distinguishes dynamic tracers
!!!integer                            :: nprognostic

real(r8), dimension(:), pointer        :: v_lons, v_lats, t_lons, t_lats

!------------------------------------------------------------
! ----- timing flags -----

integer :: id_init, id_loop, id_end
integer, parameter :: timing_level = 1


!-----------------------------------------------------------------------

! Stuff to allow addition of random 'sub-grid scale' noise
type(random_seq_type) :: random_seed
logical :: first_call = .true.


contains


!#######################################################################

 subroutine atmosphere (Var, Time)


 type (time_type), intent(in) :: Time
 type (prog_var_type), intent(inout) :: Var

  type(time_type) :: Time_prev, Time_next
!-----------------------------------------------------------------------

   Time_prev = Time                       ! two time-level scheme
   Time_next = Time + Time_step_atmos

!---- dynamics -----

   call bgrid_core_driver ( Time_next, Var, Var_dt, Dynam, omega )

!---- call physics -----

   call bgrid_physics ( physics_window, real(dt_atmos), Time_next,  &
                        Dynam%Hgrid,   Dynam%Vgrid,    Dynam,             &
                        Var,     Var_dt                       )

!---- time differencing and diagnostics -----

   call bgrid_core_time_diff ( omega, Time_next, Dynam, Var, Var_dt )

!-----------------------------------------------------------------------

 end subroutine atmosphere

!#######################################################################

subroutine adv_1step(x, Time)

! Does single time-step advance for B-grid model with vector state as
! input and output. This is a modified version of subroutine atmosphere
! in original bgrid_solo_atmosphere driver.


real(r8), intent(inout) :: x(:)
! Time is needed for more general models like this; need to add in to 
! low-order models
type(time_type), intent(in) :: Time
!!!type(prog_var_type), intent(inout) :: Var

type(prog_var_type) :: Var
type(time_type) :: Time_next

integer :: i, j, k
real(r8) :: temp_t

! Convert the vector to a B-grid native state representation
call vector_to_prog_var(x, get_model_size(), Var)

! Compute the end of the time interval
Time_next = Time + Time_step_atmos

! Do dynamics
! Dynam, Var_dt and omega currently in static storage, is that where they should stay?
call bgrid_core_driver(Time_next, Var, Var_dt, Dynam, omega)

! Call physics; physics_window is also in global static storage
! dt_atmos is seconds for time step from namelist for now
call bgrid_physics(physics_window, real(dt_atmos), Time_next, &
   Dynam%Hgrid, Dynam%Vgrid, Dynam, Var, Var_dt)

!!!write(*, *) 'max tendency ', maxval(abs(Var_dt%t))
!!!write(*, *) 'mean tendency ' , sum(abs(Var_dt%t)) / (size(Var_dt%t))

! First pass at creating some random 'sub-grid' noise 
! Need to initialize random sequence on first call
if(first_call) then
   write(*, *) 'NOISE_SD is ', noise_sd
   call init_random_seq(random_seed)
   first_call = .false.
endif

! Just modify T for now by multiplying by 1 + r(0.0, noise_sd) * dt
do i = 1, size(Var_dt%t, 1)
   do j = 1, size(Var_dt%t, 2)
      do k = 1, size(Var_dt%t, 3)
         temp_t = Var_dt%t(i, j, k)
         Var_dt%t(i, j, k) = &
            (1.0_r8 + random_gaussian(random_seed, 0.0_r8, dble(noise_sd))) * Var_dt%t(i, j, k)
      end do
   end do
end do

!!!write(*, *) 'max tendency with noise ', maxval(abs(Var_dt%t))
!!!write(*, *) 'mean tendency with noise ' , sum(abs(Var_dt%t)) / (size(Var_dt%t))

! Time differencing and diagnostics
call bgrid_core_time_diff(omega, Time_next, Dynam, Var, Var_dt)

! Convert back to vector form
call prog_var_to_vector(Var, x, get_model_size())

end subroutine adv_1step

!#######################################################################

subroutine static_init_model()

! INitializes class data for a B-grid model (all the stuff that needs to
! be done once.


call fms_init()
call atmos_model_init()

end subroutine static_init_model

!#######################################################################

subroutine init_model_instance(Var)

! Initializes an instance (Var) of a B-grid model state variable


type(prog_var_type), intent(out) :: Var

call prog_var_init(Dynam%Hgrid, num_levels, ntracers, Var)
! Havana no longer distinguishes prognostic tracers
!!!call prog_var_init(Dynam%Hgrid, num_levels, ntracers, nprognostic, Var)

end subroutine init_model_instance

!#######################################################################

subroutine init_conditions(x)


! Reads in restart initial conditions from B-grid and converts to vector

! Following changed to intent(inout) for ifc compiler;should be like this
real(r8), intent(inout) :: x(:)

type(prog_var_type) :: Var
real(r8), dimension(Dynam%Hgrid%ilb:Dynam%Hgrid%iub, Dynam%Hgrid%jlb:Dynam%Hgrid%jub) :: fis, res
real(r8), allocatable, dimension(:) :: eta, peta
integer :: ix, jx, kx, nt
! Havana no longer distinguishes prognostic tracers
!!!integer :: ix, jx, kx, nt, ntp

! Need to initialize var???
call init_model_instance(Var)

! FOR NOW, TRY TO READ IN CURRENT ICS via read_prog_var
call open_prog_var_file(ix, jx, kx)
! Havana no longer distinguishes prognostic tracers
! Havana no longer returns the number of tracers on this call
!!!call open_prog_var_file(ix, jx, kx, nt, ntp)

allocate(eta(kx + 1), peta(kx + 1))

!!! WARNING; MAY BE DANGEROUS TO USE Dynam%Hgrid here, it could get changed
!!! inappropriately???
call read_prog_var(Dynam%Hgrid, Var, eta, peta, fis, res)

deallocate(eta, peta)

call prog_var_to_vector(Var, x, get_model_size())

! Probably need to release allocated storage from Var, too???

end subroutine init_conditions

!#######################################################################

! THIS SUBROUTINE WAS ORIGINALLY IN ATMOS_SOLO DRIVER

   subroutine atmos_model_init()

!-----------------------------------------------------------------------
    integer :: total_days, total_seconds, iunit, ierr, io, id, jd, kd
    integer :: date(6)
    type (time_type) :: Run_length
    logical :: use_namelist

    integer :: num_atmos_calls
!-----------------------------------------------------------------------
!----- initialization timing identifiers ----

 id_init = mpp_clock_init ('MAIN: initialization', timing_level, flags=MPP_CLOCK_SYNC)
 id_loop = mpp_clock_init ('MAIN: time loop'     , timing_level, flags=MPP_CLOCK_SYNC)
 id_end  = mpp_clock_init ('MAIN: termination'   , timing_level, flags=MPP_CLOCK_SYNC)

 call mpp_clock_begin (id_init)

!----- read namelist -------

   iunit = open_namelist_file ( )
   ierr=1; do while (ierr /= 0)
          read  (iunit, nml=main_nml, iostat=io, end=10)
          ierr = check_nml_error (io, 'main_nml')
   enddo
10 call mpp_close (iunit)

!----- write namelist to logfile -----

   call write_version_number (version,tag)
   if ( mpp_pe() == mpp_root_pe() ) write (stdlog(), nml=main_nml)

   if(dt_atmos == 0) then
     call error_mesg ('program atmos_model', 'dt_atmos has not been specified', FATAL)
   endif

!----- read restart file -----

   if (file_exist('INPUT/atmos_model.res')) then
       iunit = open_restart_file ('INPUT/atmos_model.res', 'read')
       read  (iunit) date
       call mpp_close (iunit)
       use_namelist = .false.
   else
       use_namelist = .true.
   endif

!----- override date with namelist values ------
!----- (either no restart or override flag on) ---

 if ( use_namelist .or. override ) then
      date(1:2) = 0
      date(3:6) = current_time
 endif

!----- write current/initial date actually used to logfile file -----

    if ( mpp_pe() == mpp_root_pe() ) then
      write (stdlog(),16) date(3:6)
    endif

 16 format ('  current time used = day',i5,' hour',i3,2(':',i2.2))

!-----------------------------------------------------------------------
!------ initialize diagnostics manager ------

    call diag_manager_init

!----- always override initial/base date with diag_manager value -----

    call get_base_date ( date_init(1), date_init(2), date_init(3), &
                         date_init(4), date_init(5), date_init(6)  )

    if ( date_init(1)+date_init(2) /= 0 ) then
         call error_mesg ('program atmos_model', 'invalid base base - &
                          &must have year = month = 0', FATAL)
    endif

!----- set initial and current time types ------
!----- set run length and compute ending time -----

    Time_init  = set_time_increment (date_init(3), date_init(4), date_init(5), date_init(6))
    Time       = set_time_increment (date     (3), date     (4), date     (5), date     (6))
    Run_length = set_time_increment (days        , hours       , minutes     , seconds     )
    Time_end   = Time + Run_length

!-----------------------------------------------------------------------
!----- write time stamps (for start time and end time) ------

      call mpp_open (iunit, 'time_stamp.out', form=MPP_ASCII, action=MPP_OVERWR, &
                     access=MPP_SEQUENTIAL, threading=MPP_SINGLE, nohdrs=.true. )

      if ( mpp_pe() == mpp_root_pe() ) write (iunit,20) date

!     compute ending time in days,hours,minutes,seconds
      call get_time_increment (Time_end, date(3), date(4), date(5), date(6))

      if ( mpp_pe() == mpp_root_pe() ) write (iunit,20) date

      call mpp_close (iunit)

  20  format (6i7,2x,'day')   ! can handle day <= 999999

!-----------------------------------------------------------------------
!----- compute the time steps ------
!----- determine maximum number of iterations per loop ------

      Time_step_atmos = set_time (dt_atmos,0)

!-----------------------------------------------------------------------
!----- initial (base) time must not be greater than current time -----

   if ( Time_init > Time ) call error_mesg ('program atmos_model',  &
                   'initial time is greater than current time', FATAL)

!-----------------------------------------------------------------------
!------ initialize atmospheric model ------

      call atmosphere_init (Time_init, Time, Time_step_atmos)

!-----------------------------------------------------------------------
!---- open and close output restart to make sure directory is there ----

      iunit = open_restart_file ('RESTART/atmos_model.res', 'write')
      call mpp_close (iunit, action=MPP_DELETE)


!  ---- terminate timing ----
   call mpp_clock_end (id_init)

!-----------------------------------------------------------------------

   end subroutine atmos_model_init



!#######################################################################

 subroutine atmosphere_init (Time_init, Time, Time_step )

 type (time_type),     intent(in)    :: Time_init, Time, Time_step


!!! WARNING: This PROG_VAR_TYPE MAY HOG STORAGE FOREVER, NEED TO DEALLOCATE
type(prog_var_type) :: Var

  integer :: iunit, sec, ierr, io
  integer :: tnlon, tnlat, vnlon, vnlat
  integer :: t_horiz_size, v_horiz_size

real(r8), allocatable :: t_lat_bnds(:), t_lon_bnds(:), v_lat_bnds(:), v_lon_bnds(:)

integer :: i


!-----------------------------------------------------------------------
!----- read namelist -----

    if (file_exist('input.nml')) then
        iunit = open_namelist_file ( )
        ierr=1; do while (ierr /= 0)
           read (iunit, nml=atmosphere_nml, iostat=io, end=10)
           ierr = check_nml_error (io, 'atmosphere_nml')
        enddo
 10     call close_file (iunit)
    endif

!----- write version and namelist to log file -----

    call write_version_number ( version, tag )
    if ( mpp_pe() == mpp_root_pe() ) write (stdlog(), nml=atmosphere_nml)

!---- compute physics/atmos time step in seconds ----

   Time_step_atmos = Time_step
   call get_time (Time_step_atmos, sec)
!   dt_atmos = real(sec) LEFT OVER FROM COMBINE OF ATMOS_SOLO DRIVER

!----- initialize dynamical core -----

   call bgrid_core_driver_init ( Time_init, Time, Time_step,    &
                                 Var, Var_dt, Dynam, atmos_axes )

!----- initialize storage needed for vert motion ----

    omega => var_init (Dynam%Hgrid, Dynam%Vgrid%nlev)

!----- initialize physics interface -----

    call hs_forcing_init ( atmos_axes, Time )

!   ----- use entire grid as window ? -----

    if (physics_window(1) <= 0) physics_window(1) = Dynam%Hgrid%Tmp%ie-Dynam%Hgrid%Tmp%is+1
    if (physics_window(2) <= 0) physics_window(2) = Dynam%Hgrid%Tmp%je-Dynam%Hgrid%Tmp%js+1

!-----------------------------------------------------------------------

! Initialize model_size variables

! Fixed to use only global grid for now (need to modify for mpp)
call get_horiz_grid_size (Dynam % Hgrid, TGRID, tnlon, tnlat, .true.)
call get_horiz_grid_size (Dynam % Hgrid, VGRID, vnlon, vnlat, .true.)
t_horiz_size = tnlon * tnlat
v_horiz_size = vnlon * vnlat
! Num_levels is in global storage
num_levels = Dynam%Vgrid%nlev

! U and V for size
model_size = 2 * num_levels * v_horiz_size
! T and PS for size
model_size = model_size + (1 + num_levels) * t_horiz_size
! Tracers for size
model_size = model_size + Var%ntrace * num_levels * t_horiz_size
write(*, *) 'model_size ', model_size

! Also static store the number of levels, ntracers, and prognostic tracers
ntracers = Var%ntrace
! Havana no longer distinguishes prognostic tracers
!!!nprognostic = Var%ntprog

! Get the lats and lons of the actual grid points; keep in static store
allocate(t_lons(tnlon), t_lats(tnlat), v_lons(vnlon), v_lats(vnlat))
allocate(t_lon_bnds(tnlon + 1), t_lat_bnds(tnlat + 1), &
         v_lon_bnds(vnlon + 1), v_lat_bnds(vnlat + 1))
call get_horiz_grid_bound(Dynam%Hgrid, TGRID, t_lon_bnds, t_lat_bnds)
call get_horiz_grid_bound(Dynam%Hgrid, VGRID, v_lon_bnds, v_lat_bnds)

! Grid points are at the mid points of the bounds
do i = 1, tnlon
   t_lons(i) = (t_lon_bnds(i) + t_lon_bnds(i + 1)) / 2.0 * (180.0 / 3.14159265)
end do
do i = 1, tnlat
   t_lats(i) = (t_lat_bnds(i) + t_lat_bnds(i + 1)) / 2.0 * (180.0 / 3.14159265)
end do
do i = 1, vnlon
   v_lons(i) = (v_lon_bnds(i) + v_lon_bnds(i + 1)) / 2.0  * (180.0 / 3.14159265)
end do
do i = 1, vnlat
   v_lats(i) = (v_lat_bnds(i) + v_lat_bnds(i + 1)) / 2.0  * (180.0 / 3.14159265)
end do

deallocate(t_lon_bnds, t_lat_bnds, v_lon_bnds, v_lat_bnds)

 end subroutine atmosphere_init

!#######################################################################

 subroutine atmosphere_end(Var)

 type(prog_var_type), intent(in) :: Var

 integer :: iunit

    call bgrid_core_driver_end ( Var, Dynam )

 end subroutine atmosphere_end

!#######################################################################
!    returns the number of longitude and latitude grid points
!    for either the local PEs grid (default) or the global grid

 subroutine atmosphere_resolution (nlon, nlat, global)

  integer, intent(out)          :: nlon, nlat
  logical, intent(in), optional :: global

!---- return the size of the grid used for physics computations ----

    call get_horiz_grid_size (Dynam % Hgrid, TGRID, nlon, nlat, global)

 end subroutine atmosphere_resolution

!#######################################################################
!    returns the longitude and latitude grid box edges
!    for either the local PEs grid (default) or the global grid

 subroutine atmosphere_boundary (blon, blat, global)

    real(r8),    intent(out)          :: blon(:), blat(:)
    logical, intent(in), optional :: global

!----- return the longitudinal and latitudinal grid box edges ----------

    call get_horiz_grid_bound (Dynam % Hgrid, TGRID, blon, blat, global)

 end subroutine atmosphere_boundary

!#######################################################################
!    returns the axis indices associated with the coupling grid

 subroutine get_atmosphere_axes ( axes )

   integer, intent(out) :: axes (:)

!----- returns the axis indices for the atmospheric (mass) grid -----

     if ( size(axes) < 0 .or. size(axes) > 4 ) call error_mesg (    &
                    'get_atmosphere_axes in atmosphere_mod', &
                           'size of argument is incorrect', FATAL   )

     axes (1:size(axes)) = atmos_axes (1:size(axes))

 end subroutine get_atmosphere_axes

!#######################################################################

subroutine bgrid_physics ( window, dt_phys, Time, Hgrid, Vgrid, &
                           Dynam, Var, Var_dt )

!-----------------------------------------------------------------------
!
!   Time      =  current time (time_type, see time manager)
!
!-----------------------------------------------------------------------
  integer, intent(in)                :: window(2)
  real(r8),    intent(in)                :: dt_phys
       type(time_type),intent(in)    :: Time
type (horiz_grid_type),intent(inout) :: Hgrid
type  (vert_grid_type),intent(in)    :: Vgrid
type(bgrid_dynam_type),intent(in)    :: Dynam
type   (prog_var_type),intent(in)    :: Var
type   (prog_var_type),intent(inout) :: Var_dt

!-----------------------------------------------------------------------
  integer :: j, k, n, is, ie, js, je, i1, i2, j1, j2, nt
  integer :: ix, jx, idim, jdim
!-----------------------------------------------------------------------

   real(r8), dimension(window(1),window(2),Vgrid%nlev) :: p_full, u_dt, v_dt

   real(r8), dimension(window(1),window(2),Vgrid%nlev+1) :: p_half

   real(r8), dimension(Hgrid%ilb:Hgrid%iub, &
                   Hgrid%jlb:Hgrid%jub, &
                   Vgrid%nlev) :: uh, vh, uh_dt, vh_dt

   real(r8), dimension(window(1),window(2)) :: pssl_new
!-----------------------------------------------------------------------
!---------------------------- do physics -------------------------------

    idim = window(1)
    jdim = window(2)

!   --- momentum and momentum tendency on mass grid ---

    call update_halo (Hgrid, UWND, Var_dt%u, flags=SOUTH+WEST)
    call update_halo (Hgrid, VWND, Var_dt%v, flags=SOUTH+WEST)

    call vel_to_mass (Hgrid, Var%u, Var%v,   &
                      uh, vh, Dynam%Masks%Vel%mask)
    call vel_to_mass (Hgrid, Var_dt %u, Var_dt %v, &
                      uh_dt, vh_dt, Dynam%Masks%Vel%mask)

!   --- loop through physics windows ---

    nt = Var%ntrace
    js = Hgrid%Tmp%js

    do while ( js <= Hgrid%Tmp%je )

       je = min ( js+jdim-1, Hgrid%Tmp%je )
       jx = je-js+1
       is = Hgrid%Tmp%is

    do while ( is <= Hgrid%Tmp%ie )

       ie = min ( is+idim-1, Hgrid%Tmp%ie )
       ix = ie-is+1

!      ---- pass updated surface pressure ----
       pssl_new(1:ix,1:jx) = Var%pssl(is:ie,js:je) + &
                             Var_dt%pssl(is:ie,js:je) * dt_phys

       call compute_pres_full (Vgrid, pssl_new(1:ix,1:jx), &
                                        p_full(1:ix,1:jx,:))
       call compute_pres_half (Vgrid, pssl_new(1:ix,1:jx), &
                                        p_half(1:ix,1:jx,:))


       u_dt(1:ix,1:jx,:) = uh_dt(is:ie,js:je,:)
       v_dt(1:ix,1:jx,:) = vh_dt(is:ie,js:je,:)


!      ---- j-axis indices in the global physics grid ----

       j1 = js-Hgrid%Tmp%js+1; j2 = j1+(je-js)
       i1 = is-Hgrid%Tmp%is+1; i2 = i1+(ie-is)

!-----------------------------------------------------------------------
!-------------------------- call physics -------------------------------
!------------ (need to add leap-frog option for uh,vh) -----------------
!-----------------------------------------------------------------------
  if (.not.Dynam%Masks%sigma) then
!------------ eta coordinate -------------------------------------------

      call hs_forcing ( i1, i2, j1, j2, dt_phys, Time ,&
                            Hgrid%Tmp%aph(is:ie,js:je)    ,&
                            p_half   ( 1:ix, 1:jx,:)      ,&
                            p_full   ( 1:ix, 1:jx,:)      ,&
                            uh       (is:ie,js:je,:)      ,&
                            vh       (is:ie,js:je,:)      ,&
                            Var%t    (is:ie,js:je,:)      ,&
                            Var%r    (is:ie,js:je,:,:)    ,&
                            uh       (is:ie,js:je,:)      ,&
                            vh       (is:ie,js:je,:)      ,&
                            Var%t    (is:ie,js:je,:)      ,&
                            Var%r    (is:ie,js:je,:,:)    ,&
                            u_dt     ( 1:ix, 1:jx,:)      ,&
                            v_dt     ( 1:ix, 1:jx,:)      ,&
                            Var_dt%t (is:ie,js:je,:)      ,&
                            Var_dt%r (is:ie,js:je,:,:)    ,&
                            mask=Dynam%Masks%Tmp%mask(is:ie,js:je,:) ,&
                            kbot=Dynam%Masks%Tmp%kbot(is:ie,js:je)    )

  else
!------------- sigma coordinate ----------------------------------------

      call hs_forcing ( i1, i2, j1, j2, dt_phys, Time ,&
                            Hgrid%Tmp%aph(is:ie,js:je)    ,&
                            p_half   ( 1:ix, 1:jx,:)      ,&
                            p_full   ( 1:ix, 1:jx,:)      ,&
                            uh       (is:ie,js:je,:)      ,&
                            vh       (is:ie,js:je,:)      ,&
                            Var%t    (is:ie,js:je,:)      ,&
                            Var%r    (is:ie,js:je,:,:)    ,&
                            uh       (is:ie,js:je,:)      ,&
                            vh       (is:ie,js:je,:)      ,&
                            Var%t    (is:ie,js:je,:)      ,&
                            Var%r    (is:ie,js:je,:,:)    ,&
                            u_dt     ( 1:ix, 1:jx,:)      ,&
                            v_dt     ( 1:ix, 1:jx,:)      ,&
                            Var_dt%t (is:ie,js:je,:)      ,&
                            Var_dt%r (is:ie,js:je,:,:)     )

  endif

!       ---- physics tendency on mass grid ----
        uh(is:ie,js:je,:) = u_dt(1:ix,1:jx,:) - uh_dt(is:ie,js:je,:)
        vh(is:ie,js:je,:) = v_dt(1:ix,1:jx,:) - vh_dt(is:ie,js:je,:)

        is = is + idim

     enddo

        js = js + jdim

     enddo

!-----------------------------------------------------------------------
!---- move momentum tendencies from mass to momentum points ----
!---- zero out unused polar row, no harm if not polar row ----

     call update_halo (Hgrid, TEMP, uh, flags=NORTH+EAST)
     call update_halo (Hgrid, TEMP, vh, flags=NORTH+EAST)

     call mass_to_vel (Hgrid, uh, uh)
     call mass_to_vel (Hgrid, vh, vh)

     uh(:,Hgrid%jub,:) = 0.0_r8
     vh(:,Hgrid%jub,:) = 0.0_r8

!---- update momentum tendencies ----

     Var_dt%u = Var_dt%u + uh * Dynam%Masks%Vel%mask
     Var_dt%v = Var_dt%v + vh * Dynam%Masks%Vel%mask

!---- update halo rows ----

     call update_halo (Hgrid, TEMP, Var_dt%t)
     call update_halo (Hgrid, TEMP, Var_dt%r)
     call update_halo (Hgrid, UWND, Var_dt%u)
     call update_halo (Hgrid, VWND, Var_dt%v)

!-----------------------------------------------------------------------

end subroutine bgrid_physics

!#######################################################################

function get_model_size()


integer :: get_model_size

get_model_size = model_size

end function get_model_size

!#######################################################################

subroutine prog_var_to_vector(vars, x, isize)


integer, intent(in) :: isize
type(prog_var_type), intent(in) :: vars
real(r8), intent(out) :: x(isize)

integer :: i, j, k, nt, indx
integer :: num_levs
integer :: tis, tie, tjs, tje, vis, vie, vjs, vje

! Get the bounds for storage on Temp and Velocity grids
tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je
num_levs = vars%kub - vars%klb + 1

! Start copying fields to straight vector
! Do everything on the T grid first
indx = 0
do i = tis, tie
   do j = tjs, tje
! Surface pressure is first
      indx = indx + 1
      x(indx) = vars%ps(i, j)
! Now do t and tracers at successive levels
      do k = vars%klb, vars%kub
         indx = indx + 1
         x(indx) = vars%t(i, j, k)
         do nt = 1, vars%ntrace
            indx = indx + 1
            x(indx) = vars%r(i, j, k, nt)
         end do
      end do
   end do
end do

! Now do the velocity grid, u and v
do i = vis, vie
   do j = vjs, vje
      do k = vars%klb, vars%kub
         indx = indx + 1
         x(indx) = vars%u(i, j, k)
         indx = indx + 1
         x(indx) = vars%v(i, j, k)
      end do
   end do
end do
   



! Temporary check
if(indx /= isize) then
   write(*, *) 'prog_var_to_vector bad index sum '
   write(*, *) 'indx, isize ', indx, isize
   stop
endif

end subroutine prog_var_to_vector

!#######################################################################

subroutine vector_to_prog_var(x, isize, vars)


integer, intent(in) :: isize
real(r8), intent(in) :: x(isize)
type(prog_var_type), intent(inout) :: vars

integer :: i, j, k, nt, indx
integer :: num_levs
integer :: tis, tie, tjs, tje, vis, vie, vjs, vje

! Initialize the static parts of the prog var type
! Don't want to initialize prog_var_type vars if already done (memory)
! Modified on 11 Dec. 2002 to slow B-grid memory leak
if(.not. associated(vars%ps)) &
   call prog_var_init(Dynam%Hgrid, num_levels, ntracers, vars)



! Havana no longer distinguishes prognostic tracers
!!!call prog_var_init(Dynam%Hgrid, num_levels, ntracers, nprognostic, vars)

! Get the bounds for storage on Temp and Velocity grids
tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je
num_levs = vars%kub - vars%klb + 1

! Start copying fields from straight vector
! Everything on T grid first
indx = 0
do i = tis, tie
   do j = tjs, tje
! Surface pressure is first
      indx = indx + 1
      vars%ps(i, j) = x(indx)
! For non-eta models, pssl is same as ps??? Need to change?
      vars%pssl(i, j) = vars%ps(i, j)
! Now do t and tracers at successive levels
      do k = vars%klb, vars%kub
         indx = indx + 1
         vars%t(i, j, k) = x(indx)
         do nt = 1, vars%ntrace
            indx = indx + 1
            vars%r(i, j, k, nt) = x(indx)
         end do
      end do
   end do
end do

! Now do the velocity grid, u and v
do i = vis, vie
   do j = vjs, vje
      do k = vars%klb, vars%kub
         indx = indx + 1
         vars%u(i, j, k) = x(indx)
         indx = indx + 1
         vars%v(i, j, k) = x(indx)
      end do
   end do
end do

! Need to do halo updates to fill in the rest
!!!call halo_update()
call update_halo (Dynam%Hgrid, UWND, vars%u)
call update_halo (Dynam%Hgrid, VWND, vars%v)
call update_halo (Dynam%Hgrid, TEMP, vars%t)
call update_halo (Dynam%Hgrid, TEMP, vars%r)
call update_halo (Dynam%Hgrid, TEMP, vars%ps)
call update_halo (Dynam%Hgrid, TEMP, vars%pssl)



! Temporary check
if(indx /= isize) then
   write(*, *) 'vector_to_prog_var bad index sum '
   write(*, *) 'indx, isize ', indx, isize
   stop
endif



end subroutine vector_to_prog_var

!#######################################################################

function get_model_time_step()
!------------------------------------------------------------------------
! function get_model_time_step()
!
! Returns the the time step of the model. In the long run should be repalced
! by a more general routine that returns details of a general time-stepping
! capability.

type(time_type) :: get_model_time_step

! Time_step_atmos is global static storage
get_model_time_step =  Time_step_atmos


! CODE ADDED TO SIMULATE MODEL ERROR BY MAKING MODEL THINK IT IS
! ADVANCING AT A DIFFERENT RATE THAN IT IS
! THIS auxiliary timestep is only used if namelist parameter
! dt_bias is set to a non-zero value 

if(dt_bias > 0) get_model_time_step = set_time(dt_bias, 0)

end function get_model_time_step



  subroutine get_state_meta_data(index_in, location, var_type)
!---------------------------------------------------------------------
! subroutine get_state_meta_data(index_in, location, var_type)
!
! Given an integer index into the state vector structure, returns the
! associated location. This is not a function because the more general
! form of the call has a second intent(out) optional argument kind.
! Maybe a functional form should be added?
! Types for this bgrid model are, TYPE_PS, TYPE_T, TYPE_U, TYPE_V, TYPE_TRACER

integer,             intent(in)  :: index_in
type(location_type), intent(out) :: location
integer, optional,   intent(out) :: var_type

integer :: i, j, k, nt, indx, local_var_type, var_type_temp
integer :: tis, tie, tjs, tje, vis, vie, vjs, vje
integer :: t_size, v_size, t_grid_size, v_grid_size, t_per_col, v_per_col
integer :: num_t_lons, num_t_lats, num_v_lons, num_v_lats
integer :: col_num, col_elem, v_index
integer :: lat_index, lon_index
real(r8) :: lon, lat, lev

! Get the bounds for storage on Temp and Velocity grids
tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
num_t_lons = tie - tis + 1
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
num_t_lats = tje - tjs + 1
t_size = num_t_lons *num_t_lats
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
num_v_lons = vie - vis + 1
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je
num_v_lats = vje - vjs + 1
v_size = num_v_lons * num_v_lats


! Compute size of t_grid storage
t_per_col = 1 + (1 + ntracers) * num_levels
t_grid_size = t_per_col * t_size
v_per_col = 2 * num_levels
v_grid_size = v_per_col * v_size

! Easier to compute with a 0 to size - 1 index
indx = index_in - 1

! Is this point in the t_grid
if(indx < t_grid_size) then
   col_num = indx / t_per_col
   col_elem = indx - col_num * t_per_col
   !   write(*, *) 't_grid col and element ', col_num, col_elem
   lon_index = col_num / num_t_lats
   lat_index = col_num - lon_index * num_t_lats
   !   write(*, *) 'lon and lat index ', lon_index, lat_index

   ! Note, array runs from 1, index runs from 0
   lon = t_lons(lon_index + 1)
   lat = t_lats(lat_index + 1)

   if(col_elem == 0) then ! First variable on mass grid is PS
      lev = -1
      local_var_type = TYPE_PS 
   else ! Rest of variables are temperature and tracers

      lev = int((col_elem  + 1)/ (1 + ntracers))
      var_type_temp = mod(col_elem - 1, 1 + ntracers)

      ! First element on each level is T, 
      ! remainder are tracers from 1 to ntracers
      if(var_type_temp == 0) then
         local_var_type = TYPE_T
      else
         local_var_type = TYPE_TRACER + var_type_temp - 1
      endif
   endif

else

   ! It's in the v_grid
   v_index = indx - t_grid_size
   col_num = v_index / v_per_col
   col_elem = v_index - col_num * v_per_col

   !   write(*, *) 'v_grid col and element ', col_num, col_elem
   lon_index = col_num / num_v_lats
   lat_index = col_num - lon_index * num_v_lats

   !   write(*, *) 'lon and lat index ', lon_index, lat_index

   ! Note, array runs from 1, index runs from 0
   lon = v_lons(lon_index + 1)

   ! Problems with round-off over 360.0
   if(abs(lon - 360.0_r8) < 0.00001_r8) lon = 360.0_r8

   lat = v_lats(lat_index + 1)
   lev = int((col_elem + 2) / 2)

   ! Compute u or v, u is even, v is odd
   if(col_elem / 2 * 2 == col_elem) then
      local_var_type = TYPE_U
   else
      local_var_type = TYPE_V
   endif
endif

!write(*, *) 'lon, lat, and lev ', lon, lat, lev

location = set_location(lon, lat, lev, 1) ! 1 == level (indexical)

! If the type is wanted, return it
if(present(var_type)) var_type = local_var_type


end subroutine get_state_meta_data



RECURSIVE function model_interpolate(x, location, itype)

real(r8) :: model_interpolate
real(r8),            intent(in) :: x(:)
type(location_type), intent(in) :: location
integer,             intent(in) :: itype

integer :: num_lons, num_lats, lon_below, lon_above, lat_below, lat_above, i
real(r8) :: bot_lon, top_lon, delta_lon, bot_lat, top_lat, delta_lat
real(r8) :: lon_fract, lat_fract, val(2, 2), temp_lon, a(2)
real(r8) :: lon, lat, level, lon_lat_lev(3), pressure

! Would it be better to pass state as prog_var_type (model state type) to here?
! As opposed to the stripped state vector. YES. This would give time interp.
! capability here; do we really want this or should it be pushed up?

! Get the position, determine if it is model level or pressure in vertical
lon_lat_lev = get_location(location)
lon = lon_lat_lev(1); lat = lon_lat_lev(2); 
if(vert_is_level(location)) then 
   level = lon_lat_lev(3)
else
   pressure = lon_lat_lev(3)
endif

! Depending on itype, get appropriate lon and lat grid specs
! Types temporarily defined as 1=u, 2=v, 3=ps, 4=t, n=tracer number n-4
if(itype == 1 .or. itype == 2) then
   num_lons = size(v_lons)
   num_lats = size(v_lats)
   bot_lon = v_lons(1)
   top_lon = v_lons(num_lons)
   delta_lon = v_lons(2) - v_lons(1)
   bot_lat = v_lats(1)
   top_lat = v_lats(num_lats)
   delta_lat = v_lats(2) - v_lats(1)
else
   num_lons = size(t_lons)
   num_lats = size(t_lats)
   bot_lon = t_lons(1)
   top_lon = t_lons(num_lons)
   delta_lon = t_lons(2) - t_lons(1)
   bot_lat = t_lats(1)
   top_lat = t_lats(num_lats)
   delta_lat = t_lats(2) - t_lats(1)
endif

! Compute bracketing lon indices
if(lon >= bot_lon .and. lon <= top_lon) then
   lon_below = int((lon - bot_lon) / delta_lon) + 1
   lon_above = lon_below + 1
!   write(*, *) 'lon, delta_lon, bot_lon', lon, delta_lon, bot_lon
!   write(*, *) 'prod ', ((lon_below - 1) * delta_lon + bot_lon)
   lon_fract = (lon - ((lon_below - 1) * delta_lon + bot_lon)) / delta_lon
else
! At wraparound point
   lon_below = num_lons
   lon_above = 1
   if(lon < bot_lon) then 
      temp_lon = lon + 360.0_r8
   else
      temp_lon = lon
   endif
   lon_fract = (temp_lon - top_lon) / delta_lon
endif
   

! Next, compute neighboring lat rows
! NEED TO BE VERY CAREFUL ABOUT POLES; WHAT'S BEING DONE MAY BE WRONG
if(lat >= bot_lat .and. lat <= top_lat) then
   lat_below = int((lat - bot_lat) / delta_lat) + 1
   lat_above = lat_below + 1
   lat_fract = (lat - ((lat_below - 1) * delta_lat + bot_lat)) / delta_lat
else if(lat <= bot_lat) then
! South of bottom lat NEED TO DO BETTER: NOT REALLY REGULAR
   lat_below = 1
   lat_above = 2
   lat_fract = 0.0_r8
else
! North of top lat NEED TO DO BETTER: NOT REALLY REGULAR
   lat_below = num_lats - 1
   lat_above = num_lats
   lat_fract = 1.0_r8
endif

! Case 1: model level specified in vertical
if(vert_is_level(location)) then
! Now, need to find the values for the four corners
   val(1, 1) =  get_val(x, lon_below, lat_below, nint(level), itype)
   val(1, 2) =  get_val(x, lon_below, lat_above, nint(level), itype)
   val(2, 1) =  get_val(x, lon_above, lat_below, nint(level), itype)
   val(2, 2) =  get_val(x, lon_above, lat_above, nint(level), itype)

else
! Case of pressure specified in vertical
   val(1, 1) =  get_val_pressure(x, lon_below, lat_below, pressure, itype)
   val(1, 2) =  get_val_pressure(x, lon_below, lat_above, pressure, itype)
   val(2, 1) =  get_val_pressure(x, lon_above, lat_below, pressure, itype)
   val(2, 2) =  get_val_pressure(x, lon_above, lat_above, pressure, itype)
endif

! Do the weighted average for interpolation
!write(*, *) 'fracts ', lon_fract, lat_fract
do i = 1, 2
   a(i) = lon_fract * val(2, i) + (1.0 - lon_fract) * val(1, i)
end do

model_interpolate = lat_fract * a(2) + (1.0 - lat_fract) * a(1)


end function model_interpolate

!#######################################################################

function get_val(x, lon_index, lat_index, level, itype)


real(r8) :: get_val
real(r8), intent(in) :: x(:)
integer, intent(in) :: lon_index, lat_index, level, itype

! Find the index into state array and return this value
get_val = x(get_state_index(lon_index, lat_index, level, itype))

end function get_val



  function get_val_pressure(x, lon_index, lat_index, pressure, itype)
!================================================================================
! function get_val_pressure(x, lon_index, lat_index, pressure, itype)
!
! Gets the vertically interpolated value on pressure for variable type
! at lon_index, lat_index horizontal grid point

real(r8) :: get_val_pressure
real(r8), intent(in) :: x(:), pressure
integer,  intent(in) :: lon_index, lat_index, itype

type(location_type) :: ps_location
real(r8) :: ps(1, 1), pfull(1, 1, Dynam%Vgrid%nlev), fraction
integer  :: top_lev, bot_lev, i
real(r8) :: bot_val, top_val, ps_lon

! Need to get the surface pressure at this point.
! For t or tracers (on mass grid with ps) this is trivial
! For u or v (on velocity grid)

if(itype >= 3) then

   ps = get_val(x, lon_index, lat_index, -1, 3)

else

   ! Bgrid model has nasty habit of having longitudes truncated to > 360.0
   ! Need to fix this here to avoid death in location module
   ps_lon = v_lons(lon_index)
   if(ps_lon > 360.00_r8 .and. ps_lon < 360.00001_r8) ps_lon = 360.0_r8

   ! The vertical is not important for this interpolation -- still --
   ! mark it as missing (-1.0) but give it some type information (2==pressure)
   ps_location = set_location(ps_lon, v_lats(lat_index), -1.0, 2 )
   ps          = model_interpolate(x, ps_location, 3)

endif

! Next, get the values on the levels for this ps
call compute_pres_full(Dynam%Vgrid, ps, pfull)

! Interpolate in vertical to get two bounding levels

!write(*, *) 'itype is ', itype
!write(*, *) 'pfull values for ps = ', ps(1, 1)
!write(*, *) pfull(1, 1, :)

! What to do about pressures above top??? Just use the top for now.
! Could extrapolate, but that would be very tricky. Might need to
! reject somehow.
!write(*, *) 'pressure , ps ', pressure, ps(1, 1)
if(pressure < pfull(1, 1, 1)) then
   top_lev = 1
   bot_lev = 2
   fraction = 1.0_r8
else if(pressure > pfull(1, 1, Dynam%Vgrid%nlev)) then
! Same for bottom
   bot_lev = Dynam%Vgrid%nlev
   top_lev = bot_lev - 1
   fraction = 0.0_r8

else

! Search down through pressures
   do i = 2, Dynam%Vgrid%nlev
      if(pressure < pfull(1, 1, i)) then
         top_lev = i -1
         bot_lev = i
         fraction = (pfull(1, 1, i) - pressure) / &
            (pfull(1, 1, i) - pfull(1, 1, i - 1))
         goto 21
      endif
   end do
end if

! Get the value at these two points
21 bot_val = get_val(x, lon_index, lat_index, bot_lev, itype)
top_val = get_val(x, lon_index, lat_index, top_lev, itype)
!write(*, *) 'bot_lev, top_lev, fraction', bot_lev, top_lev, fraction
   
get_val_pressure = (1.0_r8 - fraction) * bot_val + fraction * top_val
!write(*, *) 'bot_val, top_val, val', bot_val, top_val, get_val_pressure

end function get_val_pressure

!#######################################################################

function get_state_index(lon_index, lat_index, level, itype)


integer :: get_state_index
integer, intent(in) :: lon_index, lat_index, level, itype

! Returns the index in the state vector for variable of itype at
! the lon_index, lat_index, level position on the grid
! Types are currently hard-coded as u=1, v=2, ps=3, t=4, tracers = n-4
integer :: tis, tie, num_t_lons, tjs, tje, num_t_lats, t_size
integer :: vis, vie, num_v_lons, vjs, vje, num_v_lats, v_size
integer :: t_per_col, t_grid_size, v_per_col, v_grid_size

! Get the bounds for storage on Temp and Velocity grids
tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
num_t_lons = tie - tis + 1
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
num_t_lats = tje - tjs + 1
t_size = num_t_lons *num_t_lats
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
num_v_lons = vie - vis + 1
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je
num_v_lats = vje - vjs + 1
v_size = num_v_lons * num_v_lats


! Compute size of t_grid storage
t_per_col = 1 + (1 + ntracers) * num_levels
t_grid_size = t_per_col * t_size
v_per_col = 2 * num_levels
v_grid_size = v_per_col * v_size

! Is this point in the t_grid; ps, t or tracer
if(itype > 2) then
   get_state_index = t_per_col * (lat_index - 1 + (lon_index - 1) * num_t_lats)
   if(itype == 3) then
      get_state_index = get_state_index + 1
   else 
      get_state_index = get_state_index + &
         1 + (level - 1) * (1 + ntracers) + (itype - 3)
   endif

! Type 1 or 2 is u or v
else
! It's in the v_grid
   get_state_index = t_grid_size + &
      v_per_col * (lat_index - 1 + (lon_index - 1) * num_v_lats)
   get_state_index = get_state_index + (level - 1) * 2 + itype
endif

end function get_state_index

!#######################################################################

subroutine end_model()


! At some point, this stub should coordinate with atmosphere_end but
! that requires an instance variable.

end subroutine end_model

!#######################################################################
! routines to set/get date when no calendar is set (i.e., yr=0 and mo=0)
!#######################################################################
! return the time increment for the given
! number of days, hours, minutes, and seconds

 function Set_time_increment ( d, h, m, s )
 integer, intent(in) :: d, h, m, s
 type(time_type) :: Set_time_increment

   Set_time_increment = set_time ( h*3600+m*60+s, d )

 end function Set_time_increment

!#######################################################################
! compute time in days, hours, minutes, seconds ----

 subroutine get_time_increment ( T, d, h, m, s )
 type(time_type), intent(in)  :: T
 integer,         intent(out) :: d, h, m, s

   call get_time ( T, s, d )

 ! compute hours and minutes
   h = h/3600 ;   s = s - h*3600
   m = s/60   ;   s = s - m*60

 end subroutine get_time_increment

!#######################################################################

subroutine init_time(i_time)


! For now returns value of Time_init which is set in initialization routines.

type(time_type), intent(out) :: i_time

i_time = Time

end subroutine init_time



!--------------------------------------------------------------------

subroutine model_get_close_states(o_loc, radius, nfound, indices, dist)


type(location_type), intent(in) :: o_loc
real(r8), intent(in) :: radius
integer, intent(out) :: nfound, indices(:)
real(r8), intent(out) :: dist(:)

real(r8) :: loc_array(3), o_lon, o_lat
integer :: tnlon, tnlat, vnlon, vnlat, num, max_size, i, j, num1
integer :: t_size, v_size, t_per_col, t_grid_size, v_per_col, col_base_index
integer, allocatable :: lon_ind(:), lat_ind(:)
real(r8), allocatable :: close_dist(:)

integer :: lji

! Number found starts at 0
nfound = 0

! Fixed to use only global grid for now (need to modify for mpp)
call get_horiz_grid_size (Dynam % Hgrid, TGRID, tnlon, tnlat, .true.)
call get_horiz_grid_size (Dynam % Hgrid, VGRID, vnlon, vnlat, .true.)

! Do the t_grid and then the v_grid

! Num of close horizontal grid points starts at 0, too
num = 0
! For now, just allocate enough space for all grid points, may want
! to make this smaller at some point for big models.
max_size = tnlon*tnlat + vnlon*vnlat
allocate(lon_ind(max_size), lat_ind(max_size), close_dist(max_size))

! Look for close grid points on the t grid
call grid_close_states2(o_loc, t_lons, t_lats, tnlon, tnlat, radius, &
   num, lon_ind, lat_ind, close_dist)

! Compute size of grid storage for full levels
t_size = tnlon * tnlat
v_size = vnlon * vnlat
t_per_col = 1 + (1 + ntracers) * num_levels
t_grid_size = t_per_col * t_size
v_per_col = 2 * num_levels

! Add all t-grid variables in this column to the close list with this distance
do i = 1, num
   col_base_index = ((lon_ind(i) - 1) * tnlat + lat_ind(i) - 1) * t_per_col
   do j = 1, t_per_col
      nfound = nfound + 1
      if(nfound <= size(indices)) indices(nfound) = col_base_index + j
      if(nfound <= size(dist)) dist(nfound) = close_dist(i)
   end do
end do
   
num1 = num + 1

call grid_close_states2(o_loc, v_lons, v_lats, vnlon, vnlat, radius, &
   num, lon_ind, lat_ind, close_dist)

! Add all v-grid variables in this column to close list with this distance
do i = num1, num
   col_base_index = t_grid_size + ((lon_ind(i) - 1) * vnlat + lat_ind(i) - 1) * v_per_col
   do j = 1, v_per_col
      nfound = nfound + 1
      if(nfound <= size(indices)) indices(nfound) = col_base_index + j
      if(nfound <= size(dist)) dist(nfound) = close_dist(i)
   end do
end do

deallocate(lon_ind, lat_ind, close_dist)

end subroutine model_get_close_states


!-----------------------------------------------------------------

subroutine grid_close_states2(o_loc, lons, lats, nlon, nlat, radius, &
   num, close_lon_ind, close_lat_ind, close_dist)

! Finds close state points from a particular grid;


type(location_type), intent(in) :: o_loc
integer, intent(in) :: nlon, nlat
real(r8), intent(in) :: lons(nlon), lats(nlat), radius
integer, intent(inout) :: num
integer, intent(inout) :: close_lon_ind(:), close_lat_ind(:)
real(r8), intent(out) :: close_dist(:)

real(r8) :: glat, glon, loc_array(3), o_lon, o_lat, o_lev
real(r8) :: gdist, diff, row_dist(nlon)
integer :: blat_ind, blon_ind, i, j, lat_ind, lon_ind
integer :: row_lon_ind(nlon), row_num
real(r8), parameter :: glev = 1.0_r8
type(location_type) :: loc

! Get the lat and lon from the loc
loc_array = get_location(o_loc)
o_lon = loc_array(1)
o_lat = loc_array(2)

! Get index to closest lat and lon for this observation
blat_ind = get_closest_lat_index(o_lat, lats, nlat)
!write(*, *) 'closest latitude in grid is ', blat_ind, lats(blat_ind)
blon_ind = get_closest_lon_index(o_lon, lons, nlon)
!write(*, *) 'closest longitude in grid is ', blon_ind, lons(blon_ind)

! Begin a search along the latitude axis in the positive direction
do lat_ind = blat_ind, nlat
   glat = lats(lat_ind)
! Take care of storage round-off
   if(glat < -90.0_r8) glat =  0.0_r8
   if(glat >  90.0_r8) glat = 90.0_r8

! Search all the contiguous close longitudes around the base longitude
   call lon_search(glat, glev, blon_ind, o_loc, radius, lons, &
      row_lon_ind, row_dist, row_num)
! If none are found, it's time to search in the negative latitude direction
   if(row_num == 0) goto 11
! Copy the points found in the row into summary storage
   close_lon_ind(num+1 : num+row_num) = row_lon_ind(1:row_num)
   close_lat_ind(num+1 : num+row_num) = lat_ind
   close_dist(num+1 : num+row_num) = row_dist(1:row_num)
   num = num + row_num
end do

! Search in the negative lat direction
11 continue
do lat_ind = blat_ind - 1, 1, -1
   glat = lats(lat_ind)
! Take care of storage round-off
   if(glat < -90.0_r8) glat =  0.0_r8
   if(glat >  90.0_r8) glat = 90.0_r8

! Search all the contiguous close longitudes around the base longitude
   call lon_search(glat, glev, blon_ind, o_loc, radius, lons, &
      row_lon_ind, row_dist, row_num)
! If none are found, it's time to give up
   if(row_num == 0) return
! Copy the points found in the row into summary storage
   close_lon_ind(num+1 : num+row_num) = row_lon_ind(1:row_num)
   close_lat_ind(num+1 : num+row_num) = lat_ind
   close_dist(num+1 : num+row_num) = row_dist(1:row_num)
   num = num + row_num
end do

end subroutine grid_close_states2



subroutine lon_search(glat, glev, blon_ind, o_loc, radius, lons, &
                      close_lon_ind, close_dist, num)
!------------------------------------------------------------------------
!
! Given an observation location and radius and a latitude row from a grid,
! searches to find all longitude points in this row that are within radius
! of the observation location and returns their latitude index, longitude
! index, and the distance between them and the observation.

real(r8),            intent(in)  :: glat, glev, radius, lons(:)
integer,             intent(in)  :: blon_ind
type(location_type), intent(in)  :: o_loc
integer,             intent(out) :: close_lon_ind(:), num
real(r8),            intent(out) :: close_dist(:)

type(location_type) :: loc
integer  :: nlon, j, max_pos, lon_ind, which_vert
real(r8) :: glon, gdist

! Total number found is 0 at start
num = 0
nlon = size(lons)

! Search as far as possible in the positive direction
do j = 0, nlon - 1
   max_pos = j
   lon_ind = blon_ind + j
   if(lon_ind > nlon) lon_ind = lon_ind - nlon
   glon = lons(lon_ind)

   ! Correct for longitude storage round-off
   if(glon > 360.0_r8) glon = 360.0_r8 
   if(glon <   0.0_r8) glon =   0.0_r8

   ! set vertical type to same as input 
   which_vert = nint(query_location(o_loc))
   loc        = set_location(glon, glat, glev, which_vert)
   gdist      = get_dist(loc, o_loc)

   if(gdist <= radius) then
      num = num + 1
      close_lon_ind(num) = lon_ind
      close_dist(num) = gdist
      ! If radius is too far for closest longitude, 
      ! no need to search further or to search other side
   else if (j == 0) then
      return
   else
      ! Look in negative longitude offset direction next
      goto 21
   endif
end do
! Falling off end means the whole longitude circle has been searched; move along
return

! Search around the other way
21 continue
do j = 1, nlon - 1 - max_pos
   lon_ind = blon_ind - j
   if(lon_ind < 1) lon_ind = nlon + lon_ind
   glon = lons(lon_ind)

   ! Correct for longitude storage round-off
   if(glon > 360.0_r8) glon = 360.0_r8
   if(glon <   0.0_r8) glon =   0.0_r8

   ! set vertical type to same as input 
   which_vert = nint(query_location(o_loc))
   loc        = set_location(glon, glat, glev, which_vert)
   gdist      = get_dist(loc, o_loc)

   if(gdist <= radius) then
      num = num + 1
      close_lon_ind(num) = lon_ind
      close_dist(num) = gdist
   else
      ! No more longitudes in negative direction
      return
   endif
end do

end subroutine lon_search

!--------------------------------------------------------------------------

function get_closest_lat_index(o_lat, lats, nlat)

integer, intent(in) :: nlat
real(r8), intent(in) :: o_lat, lats(nlat)
integer :: get_closest_lat_index

real(r8) :: lat_bot, lat_top, lat_int, diff
integer :: lower_ind

! Find closest lat
lat_bot = lats(1)
lat_top = lats(nlat)
lat_int = lats(2) - lats(1)
if(o_lat <= lat_bot) then
   get_closest_lat_index = 1
else if(o_lat >= lat_top) then
   get_closest_lat_index = nlat
else
   diff = (o_lat - lat_bot) / lat_int
   lower_ind = int(diff) + 1
   if(diff - int(diff) < 0.5_r8) then
      get_closest_lat_index = lower_ind
   else
      get_closest_lat_index = lower_ind + 1
   endif
endif

end function get_closest_lat_index


!--------------------------------------------------------------

function get_closest_lon_index(o_lon, lons, nlon)

integer, intent(in) :: nlon
real(r8), intent(in) :: o_lon, lons(nlon)
integer :: get_closest_lon_index

real(r8) :: diff, lon_bot, lon_top, lon_int
integer :: lower_ind, blon_ind 

! Find closest longitude on grid to given longitude
lon_bot = lons(1)
lon_top = lons(nlon)
lon_int = lons(2) - lons(1)
if(o_lon <= lon_bot) then
   diff = (lon_bot - o_lon) / lon_int
   if(diff > 0.5_r8) then
      get_closest_lon_index = nlon
   else
      get_closest_lon_index = 1
   end if
else if(o_lon >= lon_top) then
   diff = (o_lon - lon_top) / lon_int
   if(diff > 0.5_r8) then
      get_closest_lon_index = 1
   else
      get_closest_lon_index = nlon
   end if
else
   diff = (o_lon - lon_bot) / lon_int
   lower_ind = int(diff) + 1
   if(diff - int(diff) < 0.5_r8) then
      get_closest_lon_index = lower_ind
   else
      get_closest_lon_index = lower_ind + 1
   end if
end if

end function get_closest_lon_index



function nc_write_model_atts( ncFileID ) result (ierr)
!-----------------------------------------------------------------------------------------
! Writes the model-specific attributes to a netCDF file
! TJH Dec 5 2002
!
! TJH 29 July 2003 -- for the moment, all errors are fatal, so the
! return code is always '0 == normal', since the fatal errors stop execution.
!                                                                                
! There are two different (staggered) 3D grids being used simultaneously here. 
! The routine "prog_var_to_vector" packs the prognostic variables into
! the requisite array for the data assimilation routines. That routine
! is the basis for the information stored in the netCDF files.
!
! TemperatureGrid : surface pressure  vars%ps(tis:tie, tjs:tje) 
!                 : temperature       vars%t (tis:tie, tjs:tje, klb:kup)
!                 : tracers           vars%r (tis:tie, tjs:tje, klb:kub, 1:vars%ntrace)
! VelocityGrid    : u                 vars%u (vis:vie, vjs:vje, klb:kub) 
!                 : v                 vars%v (vis:vie, vjs:tje, klb:kup)
!
! So there are six different dimensions and five different variables as long as
! simply lump "tracers" into one. 
!
! TJH 22 May 2003 -- It is now possible to output the prognostic variables 
! _or_ the state vector. If a "state" variable exists, we do nothing. 
! If it does not exist, we can assume we need to define the prognostic variables.

use typeSizes
use netcdf

integer, intent(in)  :: ncFileID        ! netCDF file identifier
integer              :: ierr            ! return value of function

!-----------------------------------------------------------------------------------------

integer :: nDimensions, nVariables, nAttributes, unlimitedDimID
integer :: TmpIDimID, TmpJDimID, levDimID, tracerDimID, VelIDimID, VelJDimID, MemberDimID
integer :: TmpIVarID, TmpJVarID, levVarID, tracerVarID, VelIVarID, VelJVarID, StateVarID
integer :: StateVarDimID, StateVarVarID, TimeDimID
integer :: psVarID, tVarID, rVarID, uVarID, vVarID
integer :: tis, tie, tjs, tje       ! temperature grid start/stop
integer :: vis, vie, vjs, vje       ! velocity    grid start/stop
integer :: klb, kub
integer :: nTmpI, nTmpJ, nVelI, nVelJ, nlev, ntracer, i

!-----------------------------------------------------------------------------------------

ierr = 0     ! assume normal termination

!-------------------------------------------------------------------------------
! Get the bounds for storage on Temp and Velocity grids
! I hate using these in this manner.
!-------------------------------------------------------------------------------

tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je

write(*,*)'klb = ',klb,'  kub = ',kub

nTmpI   = tie - tis + 1
nTmpJ   = tje - tjs + 1
nlev    = Var_dt%kub - Var_dt%klb + 1
ntracer = Var_dt%ntrace 
nVelI   = vie - vis + 1
nVelJ   = vje - vjs + 1

!-------------------------------------------------------------------------------
! make sure ncFileID refers to an open netCDF file, 
! and then put into define mode.
!-------------------------------------------------------------------------------

call check(nf90_Inquire(ncFileID, nDimensions, nVariables, nAttributes, unlimitedDimID))
call check(nf90_Redef(ncFileID))

!-------------------------------------------------------------------------------
! We need the dimension ID for the number of copies 
!-------------------------------------------------------------------------------

call check(nf90_inq_dimid(ncid=ncFileID, name="copy", dimid=MemberDimID))
call check(nf90_inq_dimid(ncid=ncFileID, name="time", dimid=  TimeDimID))

if ( TimeDimID /= unlimitedDimId ) then
  write(*,*)'ERROR: nc_write_model_atts: Time      dimension is ',TimeDimID
  write(*,*)'ERROR: nc_write_model_atts: unlimited dimension is ',unlimitedDimId
  write(*,*)'ERROR: they must be the same.'
  stop
endif

!-------------------------------------------------------------------------------
! Define the model size, state variable dimension ... whatever ...
!-------------------------------------------------------------------------------
call check(nf90_def_dim(ncid=ncFileID, name="StateVariable", &
                        len=model_size, dimid = StateVarDimID))

!-------------------------------------------------------------------------------
! Write Global Attributes 
!-------------------------------------------------------------------------------

call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_source",source))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_revision",revision))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model_revdate",revdate))
call check(nf90_put_att(ncFileID, NF90_GLOBAL, "model","FMS_Bgrid"))

! how about namelist input? might be nice to save ...

!-------------------------------------------------------------------------------
! Define the new dimensions IDs
!-------------------------------------------------------------------------------

call check(nf90_def_dim(ncid=ncFileID, name="TmpI",   len = nTmpI,   dimid =   TmpIDimID)) 
call check(nf90_def_dim(ncid=ncFileID, name="TmpJ",   len = nTmpJ,   dimid =   TmpJDimID)) 
call check(nf90_def_dim(ncid=ncFileID, name="lev",    len = nlev,    dimid =    levDimID)) 
call check(nf90_def_dim(ncid=ncFileID, name="VelI",   len = nVelI,   dimid =   VelIDimID)) 
call check(nf90_def_dim(ncid=ncFileID, name="VelJ",   len = nVelJ,   dimid =   VelJDimID)) 
if ( ntracer > 0 ) then
   call check(nf90_def_dim(ncid=ncFileID, name="tracers",len = ntracer, dimid = tracerDimID)) 
endif

! should implement "trajectory-like" coordinate defn ... a'la section 5.4, 5.5 of CF standard
! call check(nf90_def_dim(ncid=ncFileID, name="locationrank", &
!   len = LocationDims, dimid = LocationDimID))

!-------------------------------------------------------------------------------
! Create the (empty) Variables and the Attributes
!-------------------------------------------------------------------------------

! Temperature Grid Longitudes
call check(nf90_def_var(ncFileID, name="TmpI", xtype=nf90_double, &
                                               dimids=TmpIDimID, varid=TmpIVarID) )
call check(nf90_put_att(ncFileID, TmpIVarID, "long_name", "longitude"))
call check(nf90_put_att(ncFileID, TmpIVarID, "cartesian_axis", "X"))
call check(nf90_put_att(ncFileID, TmpIVarID, "units", "degrees_east"))
call check(nf90_put_att(ncFileID, TmpIVarID, "valid_range", (/ 0.0_r8, 360.0_r8 /)))

! Temperature Grid Latitudes
call check(nf90_def_var(ncFileID, name="TmpJ", xtype=nf90_double, &
                                               dimids=TmpJDimID, varid=TmpJVarID) )
call check(nf90_put_att(ncFileID, TmpJVarID, "long_name", "latitude"))
call check(nf90_put_att(ncFileID, TmpJVarID, "cartesian_axis", "Y"))
call check(nf90_put_att(ncFileID, TmpJVarID, "units", "degrees_north"))
call check(nf90_put_att(ncFileID, TmpJVarID, "valid_range", (/ -90.0_r8, 90.0_r8 /)))

! (Common) grid levels
call check(nf90_def_var(ncFileID, name="level", xtype=nf90_int, &
                                                dimids=levDimID, varid=levVarID) )
call check(nf90_put_att(ncFileID, levVarID, "long_name", "level"))
call check(nf90_put_att(ncFileID, levVarID, "cartesian_axis", "Z"))
call check(nf90_put_att(ncFileID, levVarID, "units", "hPa"))
call check(nf90_put_att(ncFileID, levVarID, "positive", "down"))

! Velocity Grid Longitudes
call check(nf90_def_var(ncFileID, name="VelI", xtype=nf90_double, &
                                               dimids=VelIDimID, varid=VelIVarID) )
call check(nf90_put_att(ncFileID, VelIVarID, "long_name", "longitude"))
call check(nf90_put_att(ncFileID, VelIVarID, "cartesian_axis", "X"))
call check(nf90_put_att(ncFileID, VelIVarID, "units", "degrees_east"))
call check(nf90_put_att(ncFileID, VelIVarID, "valid_range", (/ 0.0_r8, 360.1_r8 /)))

! Velocity Grid Latitudes
call check(nf90_def_var(ncFileID, name="VelJ", xtype=nf90_double, &
                                               dimids=VelJDimID, varid=VelJVarID) )
call check(nf90_put_att(ncFileID, VelJVarID, "long_name", "latitude"))
call check(nf90_put_att(ncFileID, TmpIVarID, "cartesian_axis", "Y"))
call check(nf90_put_att(ncFileID, VelJVarID, "units", "degrees_north"))
call check(nf90_put_att(ncFileID, VelJVarID, "valid_range", (/ -90.0_r8, 90.0_r8 /)))

! Number of Tracers
if ( ntracer > 0 ) then
   call check(nf90_def_var(ncFileID, name="tracers", xtype=nf90_int, &
                                                  dimids=tracerDimID, varid=tracerVarID) )
   call check(nf90_put_att(ncFileID, tracerVarID, "long_name", "tracer identifier"))
endif

if ( output_state_vector ) then

   !----------------------------------------------------------------------------
   ! Create attributes for the state vector 
   !----------------------------------------------------------------------------

  ! Define the state vector coordinate variable
   call check(nf90_def_var(ncid=ncFileID,name="StateVariable", xtype=nf90_int, &
              dimids=StateVarDimID, varid=StateVarVarID))
   call check(nf90_put_att(ncFileID, StateVarVarID, "long_name", "State Variable ID"))
   call check(nf90_put_att(ncFileID, StateVarVarID, "units",     "indexical") )
   call check(nf90_put_att(ncFileID, StateVarVarID, "valid_range", (/ 1, model_size /)))

   ! Define the actual state vector
   call check(nf90_def_var(ncid=ncFileID, name="state", xtype=nf90_real, &
              dimids = (/ StateVarDimID, MemberDimID, unlimitedDimID /), varid=StateVarID))
   call check(nf90_put_att(ncFileID, StateVarID, "long_name", "model state or fcopy"))
   call check(nf90_put_att(ncFileID, StateVarId, "vector_to_prog_var","FMS-Bgrid"))
   call check(nf90_put_att(ncFileID, StateVarId, "temperature_units","degrees Kelvin"))
   call check(nf90_put_att(ncFileID, StateVarId, "pressure_units","Pa"))
   call check(nf90_put_att(ncFileID, StateVarId, "U_units","m/s"))
   call check(nf90_put_att(ncFileID, StateVarId, "V_units","m/s"))

   ! Leave define mode so we can fill
   call check(nf90_enddef(ncfileID))

   ! Fill the state variable coordinate variable
   call check(nf90_put_var(ncFileID, StateVarVarID, (/ (i,i=1,model_size) /) ))

else

   !----------------------------------------------------------------------------
   ! We need to process the prognostic variables.
   !----------------------------------------------------------------------------
   ! TemperatureGrid : surface pressure  vars%ps(tis:tie, tjs:tje) 
   !                 : temperature       vars%t (tis:tie, tjs:tje, klb:kub)
   !                 : tracers           vars%r (tis:tie, tjs:tje, klb:kub, 1:vars%ntrace)
   ! VelocityGrid    : u                 vars%u (vis:vie, vjs:vje, klb:kub) 
   !                 : v                 vars%v (vis:vie, vjs:tje, klb:kub)
   !----------------------------------------------------------------------------
   ! Create the (empty) Variables and the Attributes
   !----------------------------------------------------------------------------
 
   call check(nf90_def_var(ncid=ncFileID, name="ps", xtype=nf90_real, &
         dimids = (/ TmpIDimID, TmpJDimID, MemberDimID, unlimitedDimID /), &
         varid  = psVarID))
   call check(nf90_put_att(ncFileID, psVarID, "long_name", "surface pressure"))
   call check(nf90_put_att(ncFileID, psVarID, "units", "Pa"))
   call check(nf90_put_att(ncFileID, psVarID, "units_long_name", "pascals"))


   call check(nf90_def_var(ncid=ncFileID, name="t", xtype=nf90_real, &
         dimids = (/ TmpIDimID, TmpJDimID, levDimID, MemberDimID, unlimitedDimID /), &
         varid  = tVarID))
   call check(nf90_put_att(ncFileID, tVarID, "long_name", "temperature"))
   call check(nf90_put_att(ncFileID, tVarID, "units", "degrees Kelvin"))


   call check(nf90_def_var(ncid=ncFileID, name="u", xtype=nf90_real, &
         dimids = (/ VelIDimID, VelJDimID, levDimID, MemberDimID, unlimitedDimID /), &
         varid  = uVarID))
   call check(nf90_put_att(ncFileID, uVarID, "long_name", "zonal wind component"))
   call check(nf90_put_att(ncFileID, uVarID, "units", "m/s"))


   call check(nf90_def_var(ncid=ncFileID, name="v", xtype=nf90_real, &
         dimids = (/ VelIDimID, VelJDimID, levDimID, MemberDimID, unlimitedDimID /), &
         varid  = vVarID))
   call check(nf90_put_att(ncFileID, vVarID, "long_name", "meridional wind component"))
   call check(nf90_put_att(ncFileID, vVarID, "units", "m/s"))

   if ( ntracer > 0 ) then
      call check(nf90_def_var(ncid=ncFileID, name="r", xtype=nf90_real, &
      dimids = (/TmpIDimID, TmpJDimID, levDimID, tracerDimID, MemberDimID, unlimitedDimID/),&
         varid  = rVarID))
      call check(nf90_put_att(ncFileID, rVarID, "long_name", "various tracers"))
   endif

   call check(nf90_enddef(ncfileID))

endif

!-------------------------------------------------------------------------------
! Fill the variables
!-------------------------------------------------------------------------------

call check(nf90_put_var(ncFileID,   TmpIVarID, t_lons(tis:tie) ))
call check(nf90_put_var(ncFileID,   TmpJVarID, t_lats(tjs:tje) ))
call check(nf90_put_var(ncFileID,   VelIVarID, v_lons(vis:vie) ))
call check(nf90_put_var(ncFileID,   VelJVarID, v_lats(vjs:vje) ))
call check(nf90_put_var(ncFileID,    levVarID, (/ (i,i=1,   nlev) /) ))
if ( ntracer > 0 ) then
   call check(nf90_put_var(ncFileID, tracerVarID, (/ (i,i=1,ntracer) /) ))
endif

!-------------------------------------------------------------------------------
! Flush the buffer and leave netCDF file open
!-------------------------------------------------------------------------------
call check(nf90_sync(ncFileID))

write (*,*)'nc_write_model_atts: netCDF file ',ncFileID,' is synched ...'

contains

  ! Internal subroutine - checks error status after each netcdf, prints 
  !                       text message each time an error code is returned. 
  subroutine check(istatus)
    integer, intent ( in) :: istatus

    if(istatus /= nf90_noerr) call error_mesg ('nc_write_model_atts', &
            trim(nf90_strerror(istatus)), FATAL)

  end subroutine check

end function nc_write_model_atts



function nc_write_model_vars( ncFileID, statevec, copyindex, timeindex ) result (ierr)
!-----------------------------------------------------------------------------------------
! Writes the model-specific variables to a netCDF file
! TJH 25 June 2003
!
! TJH 29 July 2003 -- for the moment, all errors are fatal, so the
! return code is always '0 == normal', since the fatal errors stop execution.
!                                                                                
! There are two different (staggered) 3D grids being used simultaneously here. 
! The routines "prog_var_to_vector" and "vector_to_prog_var", 
! packs the prognostic variables into
! the requisite array for the data assimilation routines. That routine
! is the basis for the information stored in the netCDF files.
!
! TemperatureGrid : surface pressure  vars%ps(tis:tie, tjs:tje) 
!                 : temperature       vars%t (tis:tie, tjs:tje, klb:kup)
!                 : tracers           vars%r (tis:tie, tjs:tje, klb:kub, 1:vars%ntrace)
! VelocityGrid    : u                 vars%u (vis:vie, vjs:vje, klb:kub) 
!                 : v                 vars%v (vis:vie, vjs:tje, klb:kup)
!
! So there are six different dimensions and five different variables as long as
! simply lump "tracers" into one. 

use typeSizes
use netcdf

integer,                intent(in) :: ncFileID      ! netCDF file identifier
real(r8), dimension(:), intent(in) :: statevec
integer,                intent(in) :: copyindex
integer,                intent(in) :: timeindex
integer                            :: ierr          ! return value of function

!-----------------------------------------------------------------------------------------
real(r8), dimension(SIZE(statevec)) :: x
type(prog_var_type) :: Var

integer :: nDimensions, nVariables, nAttributes, unlimitedDimID
integer :: StateVarID, psVarID, tVarID, rVarID, uVarID, vVarID
integer :: tis, tie, tjs, tje       ! temperature grid start/stop
integer :: vis, vie, vjs, vje       ! velocity    grid start/stop
integer :: kub, klb
integer :: nTmpI, nTmpJ, nVelI, nVelJ, nlev, ntracer, i

ierr = 0     ! assume normal termination

!-------------------------------------------------------------------------------
! Get the bounds for storage on Temp and Velocity grids
! ?JEFF why can't I use the components of the prog_var_type?  
! More precisely, why doesn't prog_var_type drag around the necessary
! indices instead of just the extents?
!-------------------------------------------------------------------------------

tis = Dynam%Hgrid%Tmp%is; tie = Dynam%Hgrid%Tmp%ie
tjs = Dynam%Hgrid%Tmp%js; tje = Dynam%Hgrid%Tmp%je
vis = Dynam%Hgrid%Vel%is; vie = Dynam%Hgrid%Vel%ie
vjs = Dynam%Hgrid%Vel%js; vje = Dynam%Hgrid%Vel%je
kub = Var_dt%kub
klb = Var_dt%klb

nTmpI   = tie - tis + 1
nTmpJ   = tje - tjs + 1
nlev    = Var_dt%kub - Var_dt%klb + 1
ntracer = Var_dt%ntrace 
nVelI   = vie - vis + 1
nVelJ   = vje - vjs + 1

!-------------------------------------------------------------------------------
! make sure ncFileID refers to an open netCDF file, 
! then get all the Variable ID's we need.
!-------------------------------------------------------------------------------

call check(nf90_Inquire(ncFileID, nDimensions, nVariables, nAttributes, unlimitedDimID))

if ( output_state_vector ) then

   call check(NF90_inq_varid(ncFileID, "state", StateVarID) )
   call check(NF90_put_var(ncFileID, StateVarID, statevec,  &
                start=(/ 1, copyindex, timeindex /)))                               

else
   
   !----------------------------------------------------------------------------
   ! Fill the variables
   ! TemperatureGrid : surface pressure  Var%ps(tis:tie, tjs:tje) 
   !                 : temperature       Var%t (tis:tie, tjs:tje, klb:kub)
   !                 : tracers           Var%r (tis:tie, tjs:tje, klb:kub, 1:vars%ntrace)
   ! VelocityGrid    : u                 Var%u (vis:vie, vjs:vje, klb:kub) 
   !                 : v                 Var%v (vis:vie, vjs:tje, klb:kub)
   !----------------------------------------------------------------------------

   x = statevec ! Unfortunately, have to explicity cast it ...
                ! the filter uses a type=double,
                ! the vector_to_prog_var function expects a single.
   call vector_to_prog_var(x, get_model_size(), Var)
   
   
   call check(NF90_inq_varid(ncFileID, "ps", psVarID))
   call check(nf90_put_var( ncFileID, psVarID, Var%ps(tis:tie, tjs:tje), &
                            start=(/ 1, 1, copyindex, timeindex /) ))

   call check(NF90_inq_varid(ncFileID,  "t",  tVarID))
   call check(nf90_put_var( ncFileID,  tVarID, Var%t( tis:tie, tjs:tje, klb:kub ), &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))

   call check(NF90_inq_varid(ncFileID,  "u",  uVarID))
   call check(nf90_put_var( ncFileID,  uVarId, Var%u( vis:vie, vjs:vje, klb:kub ), &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))

   call check(NF90_inq_varid(ncFileID,  "v",  vVarID))
   call check(nf90_put_var( ncFileID,  vVarId, Var%v( vis:vie, vjs:vje, klb:kub ), &
                            start=(/ 1, 1, 1, copyindex, timeindex /) ))

   if ( ntracer > 0 ) then
      call check(NF90_inq_varid(ncFileID,  "r",  rVarID))
      call check(nf90_put_var( ncFileID,  rVarID, &
                    Var%r( tis:tie, tjs:tje, klb:kub, 1:ntracer ), & 
                   start=(/   1,       1,       1,     1,    copyindex, timeindex /) ))
   endif
endif

!-------------------------------------------------------------------------------
! Flush the buffer and leave netCDF file open
!-------------------------------------------------------------------------------

write (*,*)'Finished filling variables ...'
call check(nf90_sync(ncFileID))
write (*,*)'netCDF file is synched ...'

contains

  ! Internal subroutine - checks error status after each netcdf, prints 
  !                       text message each time an error code is returned. 
  subroutine check(istatus)
    integer, intent ( in) :: istatus

    if(istatus /= nf90_noerr) call error_mesg ('nc_write_model_vars', &
            trim(nf90_strerror(istatus)), FATAL)

  end subroutine check

end function nc_write_model_vars




subroutine pert_model_state(state, pert_state, interf_provided)


! Perturbs a model state for generating initial ensembles
! Returning interf_provided means go ahead and do this with uniform
! small independent perturbations.

real(r8), intent(in)  :: state(:)
real(r8), intent(out) :: pert_state(:)
logical,  intent(out) :: interf_provided

interf_provided = .false.

end subroutine pert_model_state



!#######################################################################
end module model_mod
