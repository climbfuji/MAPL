!-------------------------------------------------------------------
! Note: use for OSSE project
!   File to be replaced by more systematic implementations.
!   It contains codes for time conversion and bisect.
!-------------------------------------------------------------------

#include "MAPL_Exceptions.h"
#include "MAPL_ErrLog.h"
#include "unused_dummy.H"

!
!>
!### MODULE: `Plain_netCDF_Time`
!
! Author: GMAO SI-Team
!
module Plain_netCDF_Time
  use MAPL_KeywordEnforcerMod
  use MAPL_ExceptionHandling
  use MAPL_ShmemMod
  use mapl_ErrorHandlingMod
  use MAPL_Constants
  use ESMF
  use pfio_NetCDF_Supplement
  !   use MAPL_CommsMod
  use, intrinsic :: iso_fortran_env, only: REAL32
  use, intrinsic :: iso_fortran_env, only: REAL64
  implicit none
  public

  integer, parameter :: NUM_DIM = 2

  interface convert_time_nc2esmf
     procedure :: time_nc_int_2_esmf
  end interface convert_time_nc2esmf

  interface convert_time_esmf2nc
     procedure :: time_esmf_2_nc_int
  end interface convert_time_esmf2nc

  interface get_v2d_netcdf
     procedure ::  get_v2d_netcdf_R4
     procedure ::  get_v2d_netcdf_R8
  end interface get_v2d_netcdf

  interface parse_timeunit
     procedure :: parse_timeunit_i4
     procedure :: parse_timeunit_i8
  end interface parse_timeunit

  interface hms_2_s
     procedure :: hms_2_s
  end interface hms_2_s

  interface bisect
     procedure :: bisect_find_LB_R8_I8
  end interface bisect
contains


  subroutine get_ncfile_dimension(filename, nlon, nlat, tdim, key_lon, key_lat, key_time, rc)
    use netcdf
    implicit none
    character(len=*), intent(in) :: filename
    integer, optional,intent(out) :: nlat, nlon, tdim
    character(len=*), optional, intent(in)  :: key_lon, key_lat, key_time
    integer, optional, intent(out) :: rc
    integer :: ncid , dimid
    integer :: status
    character(len=ESMF_MAXSTR) :: lon_name, lat_name, time_name

    call check_nc_status(nf90_open(trim(fileName), NF90_NOWRITE, ncid), _RC)
    if (present(key_lon)) then
       lon_name=trim(key_lon)
       !    call check_nc_status(nf90_inq_dimid(ncid, "lon", dimid), _RC)
       call check_nc_status(nf90_inq_dimid(ncid, trim(lon_name), dimid), _RC)
       call check_nc_status(nf90_inquire_dimension(ncid, dimid, len=nlon), _RC)
    endif

    if (present(key_lat)) then
       lat_name=trim(key_lat)
       !    call check_nc_status(nf90_inq_dimid(ncid, "lat", dimid), _RC)
       call check_nc_status(nf90_inq_dimid(ncid, trim(lat_name), dimid), _RC)
       call check_nc_status(nf90_inquire_dimension(ncid, dimid, len=nlat), _RC)
       call check_nc_status(nf90_close(ncid), _RC)
    endif

    if (present(key_time)) then
       time_name=trim(key_time)
       !    call check_nc_status(nf90_inq_dimid(ncid, 'time', dimid), _RC)
       call check_nc_status(nf90_inq_dimid(ncid, trim(time_name), dimid), _RC)
       call check_nc_status(nf90_inquire_dimension(ncid, dimid, len=tdim), _RC)
    endif
    call check_nc_status(nf90_close(ncid), _RC)

    ! debug summary
    !write(6,*) "get_ncfile_dimension:  nlat, nlon, tdim = ", nlat, nlon, tdim
  end subroutine get_ncfile_dimension


  subroutine get_attribute_from_group(filename, group_name, var_name, attr_name, attr)
    use netcdf
    use pfio_NetCDF_Supplement
    implicit none
    character(len=*), intent(in) :: filename, group_name, var_name, attr_name
    character(len=*), intent(INOUT) :: attr
    integer :: ncid, varid, ncid2
    integer :: rc, status, iret
    integer :: len, i, j, k
    integer :: xtype
    character(len=:), allocatable :: str
    integer(kind=C_INT) :: c_ncid, c_varid
    character(len=100) :: str2

    call check_nc_status ( nf90_open      (fileName, NF90_NOWRITE, ncid2), rc )
    call check_nc_status ( nf90_inq_ncid  (ncid2, group_name, ncid),  rc )
    call check_nc_status ( nf90_inq_varid (ncid,  var_name,  varid), rc )
    call check_nc_status ( nf90_inquire_attribute(ncid, varid, attr_name, xtype, len=len), rc )
    c_ncid= ncid
    c_varid= varid
    !! print*, 'f: xtype, len=', xtype, len
    select case (xtype)
    case(NF90_STRING)
       status = pfio_get_att_string(c_ncid, c_varid, attr_name, str)
       _VERIFY(status)
    case (NF90_CHAR)
       allocate(character(len=len) :: str)
       status = nf90_get_att(ncid, varid, trim(attr_name), str)
    case default
       _FAIL('code works only with string attribute')
    end select
    i=index(str, 'since')
    ! get rid of T in 1970-01-01T00:00:0
    str2=str(i+6:i+24)
    j=index(str2, 'T')
    if (j>1) then
       k=len_trim(str2)
       str2=str2(1:j-1)//' '//str2(j+1:k)
    endif
    attr = str(1:i+5)//trim(str2)
    deallocate(str)
    iret = nf90_close(ncid)

  end subroutine get_attribute_from_group



  subroutine get_v2d_netcdf_R4(filename, name, array, Xdim, Ydim)
    use netcdf
    implicit none
    character(len=*), intent(in) :: name, filename
    integer, intent(in) :: Xdim, Ydim
    real, dimension(Xdim,Ydim), intent(out) :: array
    integer :: ncid, varid
    real    :: scale_factor, add_offset
    integer :: rc, status, iret

    call check_nc_status (  nf90_open      (trim(fileName), NF90_NOWRITE, ncid), _RC )
    call check_nc_status (  nf90_inq_varid (ncid,  name,  varid), _RC )
    call check_nc_status (  nf90_get_var   (ncid, varid,  array), _RC )

    iret = nf90_get_att(ncid, varid, 'scale_factor', scale_factor)
    if(iret .eq. 0) array = array * scale_factor
    !
    iret = nf90_get_att(ncid, varid, 'add_offset', add_offset)
    if(iret .eq. 0) array = array + add_offset
    !
    iret = nf90_close(ncid)
  end subroutine get_v2d_netcdf_R4


  subroutine get_v2d_netcdf_R8(filename, name, array, Xdim, Ydim)
    use netcdf
    implicit none
    character(len=*), intent(in) :: name, filename
    integer, intent(in) :: Xdim, Ydim
    real(REAL64), dimension(Xdim,Ydim), intent(out) :: array
    integer :: ncid, varid
    real    :: scale_factor, add_offset
    integer :: rc, status, iret

    call check_nc_status (  nf90_open      (trim(fileName), NF90_NOWRITE, ncid), _RC )
    call check_nc_status (  nf90_inq_varid (ncid,  name,  varid), _RC )
    call check_nc_status (  nf90_get_var   (ncid, varid,  array), _RC )

    iret = nf90_get_att(ncid, varid, 'scale_factor', scale_factor)
    if(iret .eq. 0) array = array * scale_factor
    !
    iret = nf90_get_att(ncid, varid, 'add_offset', add_offset)
    if(iret .eq. 0) array = array + add_offset
    !
    iret = nf90_close(ncid)
  end subroutine get_v2d_netcdf_R8


  subroutine get_v1d_netcdf_R8(filename, name, array, Xdim, group_name)
    use netcdf
    implicit none
    character(len=*), intent(in) :: name, filename
    character(len=*), optional, intent(in) :: group_name
    integer, intent(in) :: Xdim
    real(REAL64), dimension(Xdim), intent(out) :: array
    integer :: ncid, varid, ncid2
    integer :: rc, status, iret

    call check_nc_status (  nf90_open      (trim(fileName), NF90_NOWRITE, ncid), _RC )
    if (present(group_name)) then
       ncid2= ncid
       call check_nc_status ( nf90_inq_ncid ( ncid2, group_name, ncid),  _RC )
    end if
    call check_nc_status (  nf90_inq_varid (ncid,  name,  varid), _RC )
    call check_nc_status (  nf90_get_var   (ncid, varid,  array), _RC )
    iret = nf90_close(ncid)
  end subroutine get_v1d_netcdf_R8


  subroutine check_nc_status(status, rc)
    use netcdf
    implicit none
    integer, intent (in) :: status
    integer, intent (out), optional :: rc
    if(status /= nf90_noerr) then
       print *, 'netCDF error: '//trim(nf90_strerror(status))
    endif
    if(present(rc))  rc=status-nf90_noerr
  end subroutine check_nc_status


  subroutine time_nc_int_2_esmf (time, tunit, n, rc)
    use ESMF
    implicit none

    type (ESMF_TIME), intent(out) :: time
    integer, intent(in) :: n
    character(len=*), intent(in) :: tunit
    integer, intent (out), optional :: rc

    type (ESMF_Time) :: time0
    type (ESMF_TimeInterval) :: dt
    integer :: iyy,imm,idd,ih,im,is

    call parse_timeunit (tunit, n, time0, dt, rc)
    time = time0 + dt

    ! check
    ! -----
    call ESMF_timeGet(time, yy=iyy, mm=imm, dd=idd, h=ih, m=im, s=is, rc=rc)
    write(6, *) 'obs_start: iyy,imm,idd,ih,im,is', iyy,imm,idd,ih,im,is

    if(present(rc)) rc=0
  end subroutine time_nc_int_2_esmf


  subroutine time_esmf_2_nc_int (time, tunit, n, rc)
    use ESMF
    implicit none

    type (ESMF_TIME), intent(in) :: time
    integer (ESMF_KIND_I8), intent(out) :: n
    character(len=*), intent(in) :: tunit
    integer, intent (out), optional :: rc

    type (ESMF_Time) :: time0
    type (ESMF_TimeInterval) :: dt

    n=0
    call parse_timeunit (tunit, n, time0, dt, rc)
    dt = time - time0
    ! -- To-be-deleted: this is a bug
    ! assume unit is second
    !
    call ESMF_TimeIntervalGet(dt, s_i8=n)

    ! check
    ! -----
    ! write(6, *) 'dt in unit second  is', n

    if(present(rc)) rc=0
  end subroutine time_esmf_2_nc_int


  subroutine parse_timeunit_i4 (tunit, n, t0, dt, rc)
    use ESMF
    implicit none

    character(len=*), intent(in) :: tunit
    integer, intent(in) :: n
    type (ESMF_Time), intent(out) :: t0
    type (ESMF_TimeInterval), intent(out) :: dt
    integer, intent(out) :: rc

    integer :: i
    character(len=ESMF_MAXSTR) :: s1, s2, s_time, s_unit
    character(len=1) :: c1
    integer :: y,m,d,hour,min,sec
    integer :: isec
    type(ESMF_Calendar) :: gregorianCalendar

    i=index(trim(tunit), 'since')
    s_time=trim(tunit(i+5:))
    s_unit=trim(tunit(1:i-1))
    read(s_time,*) s1, s2
    read(s1, '(i4,a1,i2,a1,i2)') y, c1, m, c1, d
    read(s2, '(i2,a1,i2,a1,i2)') hour, c1, min, c1, sec

!    write(6,*) 's_time, s_unit', trim(s_time), trim(s_unit)
!    write(6,*) 's1, s2 ', trim(s1), trim(s2)
!    write(6,*) 'y, m, d', y, m, d
!    write(6,*) 'hour,min,sec', hour,min,sec

    if (trim(s_unit) == 'seconds') then
       isec=n
    else
       stop "s_unit /= 'seconds' is not handled"
    endif

    gregorianCalendar = ESMF_CalendarCreate(ESMF_CALKIND_GREGORIAN, name='Gregorian_obs', rc=rc)
    call ESMF_timeSet(t0, yy=y,mm=m,dd=m,h=hour,m=min,s=sec,&
         calendar=gregorianCalendar, rc=rc)
    call ESMF_timeintervalSet(dt, d=0, h=0, m=0, s=isec, rc=rc)

    !  call ESMF_CalendarDestroy(gregorianCalendar, rc=rc)
    !  if(present(rc)) rc=0
    rc=0

  end subroutine parse_timeunit_i4


  subroutine parse_timeunit_i8 (tunit, n, t0, dt, rc)
    use ESMF
    implicit none

    character(len=*), intent(in) :: tunit
    integer(ESMF_KIND_I8), intent(in) :: n
    type (ESMF_Time), intent(out) :: t0
    type (ESMF_TimeInterval), intent(out) :: dt
    integer, intent(out) :: rc

    integer :: i
    character(len=ESMF_MAXSTR) :: s1, s2, s_time, s_unit
    character(len=1) :: c1
    integer :: y,m,d,hour,min,sec
    integer(ESMF_KIND_I8) :: isec
    type(ESMF_Calendar) :: gregorianCalendar

    i=index(trim(tunit), 'since')
    s_time=trim(tunit(i+5:))
    s_unit=trim(tunit(1:i-1))
    read(s_time,*) s1, s2
    read(s1, '(i4,a1,i2,a1,i2)') y, c1, m, c1, d
    read(s2, '(i2,a1,i2,a1,i2)') hour, c1, min, c1, sec

!    write(6,*) 's_time, s_unit', trim(s_time), trim(s_unit)
!    write(6,*) 's1, s2 ', trim(s1), trim(s2)
!    write(6,*) 'y, m, d', y, m, d
!    write(6,*) 'hour,min,sec', hour,min,sec

    if (trim(s_unit) == 'seconds') then
       isec=n
    else
       stop "s_unit /= 'seconds' is not handled"
    endif

    gregorianCalendar = ESMF_CalendarCreate(ESMF_CALKIND_GREGORIAN, name='Gregorian_obs', rc=rc)
    call ESMF_timeSet(t0, yy=y,mm=m,dd=m,h=hour,m=min,s=sec,&
         calendar=gregorianCalendar, rc=rc)
    call ESMF_timeintervalSet(dt, d=0, h=0, m=0, s_i8=isec, rc=rc)

    !  call ESMF_CalendarDestroy(gregorianCalendar, rc=rc)
    !  if(present(rc)) rc=0
    rc=0

  end subroutine parse_timeunit_i8

  subroutine ESMF_time_to_two_integer (time, itime, rc)
    type (ESMF_Time), intent(in) ::   time
    integer, intent(out) :: itime(2)
    integer, intent(out), optional :: rc
    integer :: i1, i2
    integer :: yy, mm, dd, h, m, s

    call ESMF_TimeGet(time, yy=yy, mm=mm, dd=dd, h=h, m=m, s=s, rc=rc)

    i2=h*10000 + m*100 + s
    i1=yy*10000 + mm*100 + dd
    !    itime= i1*10**6 + i2
    itime(1)=i1
    itime(2)=i2
  end subroutine ESMF_time_to_two_integer


  subroutine two_integer_to_ESMF_time (time, itime, rc)
    type (ESMF_Time), intent(out) ::   time
    integer, intent(in) :: itime(2)
    integer, intent(out), optional :: rc
    integer :: i1, i2
    integer :: yy, mm, dd, h, m, s

    i1= itime(1)
    yy= i1/10000
    mm= mod(i1, 10000)/100
    dd= mod(i1, 100)

    i2= itime(2)
    h= i2/10000
    m= mod(i2, 10000)/100
    s= mod(i2, 100)

    !    write(6,*) 'yy, mm, dd, h, m, s', yy, mm, dd, h, m, s
    call ESMF_TimeSet(time, yy=yy, mm=mm, dd=dd, h=h, m=m, s=s, rc=rc)

  end subroutine two_integer_to_ESMF_time


  subroutine hms_2_s (hms, sec, rc)
    integer, intent(in) :: hms
    integer, intent(out):: sec
    integer, intent(out), optional :: rc
    integer :: h, m, s

    h = hms/10000
    m = mod(hms, 10000)/100
    s = mod(hms, 100)

    sec= h*3600 + m*60 + s
    if (present(rc)) rc=0

  end subroutine hms_2_s



  subroutine bisect_find_LB_R8_I8 (xa, x, n, n_LB, n_UB, rc)
    implicit none
    real(ESMF_KIND_R8), intent(in) :: xa(:)   ! 1D array
    real(ESMF_KIND_R8), intent(in) :: x       ! pt
    integer(ESMF_KIND_I8), intent(out) :: n   !  out: bisect index
    integer(ESMF_KIND_I8), intent(in), optional :: n_LB  !  opt in : LB
    integer(ESMF_KIND_I8), intent(in), optional :: n_UB  !  opt in : UB
    integer, intent(out), optional :: rc

    integer(ESMF_KIND_I8) :: k, klo, khi, dk, LB, UB
    integer :: i, nmax

    LB=1; UB=size(xa,1)
    if(present(n_LB)) LB=n_LB
    if(present(n_UB)) UB=n_UB
    klo=LB; khi=UB; dk=1

    ! write(6,*) 'init klo, khi', klo, khi
    if ( xa(LB ) > xa(UB) )  then
       klo= UB
       khi= LB
       dk= -1
    endif

    !    ----|---------------------------|--------->
    !  Y:   klo                         khi
    !     x         x                       x
    !
    !        Y(n)  <  x  <=  Y(n+1)

    rc=-1
    if ( x <= xa(klo) ) then
       !write(6,*) 'xa(klo), xa(khi), x', xa(klo), xa(khi), x
       n=klo-1
       !write(6,*) 'warning in bisect_find_LB_R8_I8:  x <  array:LB'
       return
    elseif ( x > xa(khi) ) then
       n=khi
       !write(6,*) 'warning in bisect_find_LB_R8_I8:  x >  array:UB'
       return
    endif

    nmax = log(abs(real(khi-klo))) / log(2.0) + 2  ! LOG2(M)
    do i = 1, nmax
       k=(klo+khi)/2
       if ( x <= xa(k) ) then
          khi = k
       else
          klo = k
       endif
       if( abs(klo-khi) <= 1 ) then
          n=klo
          rc=0
          return
       endif
    enddo

  end subroutine bisect_find_LB_R8_I8


  subroutine convert_twostring_2_esmfinterval (symd, shms, interval, rc)
    character(len=*) :: symd
    character(len=*) :: shms
    type (ESMF_TimeInterval), intent(out) :: interval
    integer, optional, intent(out) :: rc
    character(len=20) :: s1, s2
    integer :: y, m, d, hh, mm, ss


    s1=trim(symd)
    read(s1, '(3i2)') y, m, d
    s2=trim(shms)
    read(s2, '(3i2)') hh, mm, ss

    ! debug
    !write(6,'(3a10)') 's1, s2', s1, s2
    !write(6,*) 'int y,m,d,hh,mm,ss', y,m,d,hh,mm,ss

    call ESMF_TimeIntervalSet(interval, yy=y, mm=m, d=d, h=hh, m=mm, s=ss, rc=rc)

    if (present(rc)) rc=0
  end subroutine convert_twostring_2_esmfinterval

end module Plain_NetCDF_Time
