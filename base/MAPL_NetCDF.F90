!wdb todo
!subroutine to convert
!From: integer: array(2) = [ 20010101  010101 (HHMMSS) ] ![ (YYYYMMDD) (HHMMSS) ]
!To: !ESMF_TIME: with gregorian calendar
!And vice versa.
#include "MAPL_Exceptions.h"
#include "MAPL_ErrLog.h"
! Procedures to convert from NetCDF datetime to ESMF_Time and ESMF_TimeInterval
! NetCDF datetime is: {integer, character(len=*)}
! {1800, 'seconds since 2010-01-23 18:30:37'}
! {TIME_SPAN, 'TIME_UNIT since YYYY-MM-DD hh:mm:ss'}
module MAPL_NetCDF

   use MAPL_ExceptionHandling
   use MAPL_KeywordEnforcerMod
   use MAPL_DateTime_Parsing
   use ESMF

   implicit none

   public :: convert_NetCDF_DateTime_to_ESMF
   public :: convert_ESMF_to_NetCDF_DateTime

   private
   public :: make_ESMF_TimeInterval
   public :: make_NetCDF_DateTime_int_time
   public :: make_NetCDF_DateTime_units_string
   public :: convert_ESMF_Time_to_NetCDF_DateTimeString 
   public :: convert_to_integer
   public :: convert_NetCDF_DateTimeString_to_ESMF_Time
   public :: is_time_unit
   public :: is_valid_netcdf_datetime_string
   public :: get_shift_sign
   public :: split
   public :: split_all
   public :: lr_trim

   character, parameter :: PART_DELIM = ' '
   character, parameter :: ISO_DELIM = 'T'
   character, parameter :: DATE_DELIM = '-'
   character, parameter :: TIME_DELIM = ':'
   character(len=*), parameter :: NETCDF_DATE = '0000' // DATE_DELIM // '00' // DATE_DELIM // '00'
   character(len=*), parameter :: NETCDF_TIME = '00' // TIME_DELIM // '00' // TIME_DELIM // '00'
   character(len=*), parameter :: NETCDF_DATETIME_FORMAT = NETCDF_DATE // PART_DELIM // NETCDF_TIME
   integer, parameter :: LEN_DATE = len(NETCDF_DATE)
   integer, parameter :: LEN_TIME = len(NETCDF_TIME)
   integer, parameter :: LEN_NETCDF_DATETIME = len(NETCDF_DATETIME_FORMAT)
   character(len=*), parameter :: TIME_UNITS(7) = &
      [  'years       ', 'months      ', 'days        ', &
         'hours       ', 'minutes     ', 'seconds     ', 'milliseconds'    ]
   character, parameter :: SPACE = ' '
   type(ESMF_CalKind_Flag), parameter :: CALKIND_FLAG = ESMF_CALKIND_GREGORIAN
   integer, parameter :: MAX_WIDTH = 10

contains

   ! Convert NetCDF_DateTime {int_time, units_string} to
   ! ESMF time variables {interval, time0, time1} and time unit {tunit}
   ! time0 is the start time, and time1 is time0 + interval
   subroutine convert_NetCDF_DateTime_to_ESMF(int_time, units_string, &
         interval, time0, unusable, time1, tunit, rc)
      integer, intent(in) :: int_time
      character(len=*), intent(in) :: units_string
      type(ESMF_TimeInterval), intent(inout) :: interval
      type(ESMF_Time), intent(inout) :: time0
      class (KeywordEnforcer), optional, intent(in) :: unusable
      type(ESMF_Time), optional, intent(inout) :: time1
      character(len=:), allocatable, optional, intent(out) :: tunit
      integer, optional, intent(out) :: rc
      character(len=:), allocatable :: tunit_
      character(len=len_trim(units_string)) :: parts(2)
      character(len=len_trim(units_string)) :: head
      character(len=len_trim(units_string)) :: tail
      
      integer :: span, factor
      integer :: status

      _UNUSED_DUMMY(unusable)

      _ASSERT(int_time >= 0, 'Negative span not supported')
      _ASSERT((len(lr_trim(units_string)) > 0), 'units empty')

      ! get time unit, tunit
      parts = split(lr_trim(units_string), PART_DELIM)
      head = parts(1)
      tail = parts(2)
      tunit_ = lr_trim(head)
      _ASSERT(is_time_unit(tunit_), 'Unrecognized time unit')
      if(present(tunit)) tunit = tunit_

      ! get span
      parts = split(lr_trim(tail), PART_DELIM)
      head = parts(1)
      tail = parts(2)
      
      factor = get_shift_sign(head)
      _ASSERT(factor /= 0, 'Unrecognized preposition')
      span = factor * int_time

      call convert_NetCDF_DateTimeString_to_ESMF_Time(lr_trim(tail), time0, _RC)
      call make_ESMF_TimeInterval(span, tunit_, time0, interval, _RC)

      ! get time1
      if(present(time1)) time1 = time0 + interval

      _RETURN(_SUCCESS)

   end subroutine convert_NetCDF_DateTime_to_ESMF

   ! Convert ESMF time variables to an NetCDF datetime
   subroutine convert_ESMF_to_NetCDF_DateTime(tunit, t0, int_time, units_string, unusable, t1, interval, rc)
      character(len=*), intent(in) :: tunit
      type(ESMF_Time),  intent(inout) :: t0
      integer, intent(out) :: int_time
      character(len=:), allocatable, intent(out) :: units_string
      class (KeywordEnforcer), optional, intent(in) :: unusable
      type(ESMF_Time), optional, intent(inout) :: t1
      type(ESMF_TimeInterval), optional, intent(inout) :: interval
      integer, optional, intent(out) :: rc
      type(ESMF_TimeInterval) :: interval_
      integer :: status

      _UNUSED_DUMMY(unusable)

      if(present(interval)) then
         interval_ = interval
      elseif(present(t1)) then
         interval_ = t1 - t0
      else
         _FAIL( 'Only one input argument present')
      end if

      call make_NetCDF_DateTime_int_time(interval_, t0, tunit, int_time, _RC)
      call make_NetCDF_DateTime_units_string(t0, tunit, units_string, _RC)

      _RETURN(_SUCCESS)
      
   end subroutine convert_ESMF_to_NetCDF_DateTime

   ! Make ESMF_TimeInterval from a span of time, time unit, and start time
   subroutine make_ESMF_TimeInterval(span, tunit, t0, interval, unusable, rc)
      integer, intent(in) :: span
      character(len=*), intent(in) :: tunit
      type(ESMF_Time), intent(inout) :: t0
      type(ESMF_TimeInterval), intent(inout) :: interval
      class (KeywordEnforcer), optional, intent(in) :: unusable
      integer, optional, intent(out) :: rc
      integer :: status
      
      _UNUSED_DUMMY(unusable)

      select case(lr_trim(tunit)) 
         case('years')
            call ESMF_TimeIntervalSet(interval, startTime=t0, yy=span, _RC)
         case('months')
            call ESMF_TimeIntervalSet(interval, startTime=t0, mm=span, _RC)
         case('hours')
            call ESMF_TimeIntervalSet(interval, startTime=t0, h=span, _RC)
         case('minutes')
            call ESMF_TimeIntervalSet(interval, startTime=t0, m=span, _RC)
         case('seconds')
            call ESMF_TimeIntervalSet(interval, startTime=t0, s=span, _RC)
         case default
            _FAIL('Unrecognized unit')
      end select

      _RETURN(_SUCCESS)

   end subroutine make_ESMF_TimeInterval

   ! Get time span from NetCDF datetime
   subroutine make_NetCDF_DateTime_int_time(interval, t0, tunit, int_time, unusable, rc)
      type(ESMF_TimeInterval), intent(inout) :: interval
      type(ESMF_Time), intent(inout) :: t0
      character(len=*), intent(in) :: tunit
      integer, intent(out) :: int_time
      class (KeywordEnforcer), optional, intent(in) :: unusable
      integer, optional, intent(out) :: rc
      integer :: status
      
      _UNUSED_DUMMY(unusable)

      ! get int_time
      select case(lr_trim(tunit)) 
         case('years')
            call ESMF_TimeIntervalGet(interval, t0, yy=int_time, _RC)
         case('months')
            call ESMF_TimeIntervalGet(interval, t0, mm=int_time, _RC)
         case('hours')
            call ESMF_TimeIntervalGet(interval, t0, h=int_time, _RC)
         case('minutes')
            call ESMF_TimeIntervalGet(interval, t0, m=int_time, _RC)
         case('seconds')
            call ESMF_TimeIntervalGet(interval, t0, s=int_time, _RC)
         case default
            _FAIL('Unrecognized unit')
      end select

      _RETURN(_SUCCESS)

   end subroutine make_NetCDF_DateTime_int_time

   ! Make 'units' for NetCDF datetime
   subroutine make_NetCDF_DateTime_units_string(t0, tunit, units_string, unusable, rc)
      type(ESMF_Time), intent(inout) :: t0
      character(len=*), intent(in) :: tunit
      character(len=:), allocatable, intent(out) :: units_string
      class (KeywordEnforcer), optional, intent(in) :: unusable
      integer, optional, intent(out) :: rc
      character(len=*), parameter :: preposition = 'since'
      character(len=:), allocatable :: datetime_string
      integer :: status
      
      _UNUSED_DUMMY(unusable)

      ! make units_string
      call convert_ESMF_Time_to_NetCDF_DateTimeString(t0, datetime_string, _RC)
      units_string = tunit //SPACE// preposition //SPACE// datetime_string

      _RETURN(_SUCCESS)

   end subroutine make_NetCDF_DateTime_units_string

   ! Convert ESMF_Time to a NetCDF datetime string (start datetime)
   subroutine convert_ESMF_Time_to_NetCDF_DateTimeString(esmf_datetime, datetime_string, unusable, rc)
      type(ESMF_Time), intent(inout) :: esmf_datetime
      character(len=:), allocatable, intent(out) :: datetime_string
      class (KeywordEnforcer), optional, intent(in) :: unusable
      integer, optional, intent(out) :: rc
 
      character(len=*), parameter :: ERR_PRE = 'Failed to write string: '
      integer :: yy, mm, dd, h, m, s
      character(len=10) :: FMT
      character(len=4) :: yy_string
      character(len=2) :: mm_string
      character(len=2) :: dd_string
      character(len=2) :: h_string
      character(len=2) :: m_string
      character(len=2) :: s_string
      character(len=LEN_NETCDF_DATETIME) :: tmp_string
      integer :: status, iostatus

      _UNUSED_DUMMY(unusable)

      call ESMF_TimeGet(esmf_datetime, yy=yy, mm=mm, dd=dd, h=h, m=m, s=s, _RC)

      FMT='(BZ, I2.2)'
      write(s_string, fmt=FMT, iostat=iostatus) s
      _ASSERT(iostatus == 0, ERR_PRE // 'second')
      write(m_string, fmt=FMT, iostat=iostatus) m
      _ASSERT(iostatus == 0, ERR_PRE // 'minute')
      write(h_string, fmt=FMT, iostat=iostatus) h
      _ASSERT(iostatus == 0, ERR_PRE // 'hour')
      write(dd_string, fmt=FMT, iostat=iostatus) dd
      _ASSERT(iostatus == 0, ERR_PRE // 'day')
      write(mm_string, fmt=FMT, iostat=iostatus) mm
      _ASSERT(iostatus == 0, ERR_PRE // 'month')
      FMT='(BZ, I4.4)'
      write(yy_string, fmt=FMT, iostat=iostatus) yy
      _ASSERT(iostatus == 0, ERR_PRE // 'year')

      tmp_string = yy_string // DATE_DELIM // mm_string // DATE_DELIM // dd_string // PART_DELIM // &
         h_string // TIME_DELIM // m_string // TIME_DELIM // s_string

      datetime_string = tmp_string
      
      _RETURN(_SUCCESS)

   end subroutine convert_ESMF_Time_to_NetCDF_DateTimeString

   ! Convert string representing an integer to the integer
   subroutine convert_to_integer(string_in, int_out, rc)
      character(len=*), intent(in) :: string_in
      integer, intent(out) :: int_out
      integer, optional, intent(out) :: rc
      integer :: stat

      read(string_in, '(I16)', iostat=stat) int_out

      if(present(rc)) rc = stat

   end subroutine convert_to_integer

   ! Convert NetCDF datetime to ESMF_Time
   subroutine convert_NetCDF_DateTimeString_to_ESMF_Time(datetime_string, datetime, unusable, rc)
      character(len=*), intent(in) :: datetime_string
      type(ESMF_Time), intent(inout) :: datetime
      class (KeywordEnforcer), optional, intent(in) :: unusable
      integer, optional, intent(out) :: rc
      integer :: status 
      integer :: yy, mm, dd, h, m, s, i, j 
      character(len=4) :: part

      _UNUSED_DUMMY(unusable)

      _ASSERT(is_valid_netcdf_datetime_string(datetime_string), 'Invalid datetime string')

      i = 1
      j = i + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, yy, rc = status)
      _ASSERT(status == 0, 'Unable to convert year string')

      i = j + 2
      j = j + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, mm, rc = status)
      _ASSERT(status == 0, 'Unable to convert month string')

      i = j + 2
      j = j + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, dd, rc = status)
      _ASSERT(status == 0, 'Unable to convert day string')

      i = j + 2
      j = j + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, h, rc = status)
      _ASSERT(status == 0, 'Unable to convert hour string')

      i = j + 2
      j = j + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, m, rc = status)
      _ASSERT(status == 0, 'Unable to convert minute string')

      i = j + 2
      j = j + 3
      part = datetime_string(i:j)
      call convert_to_integer(part, s, rc = status)
      _ASSERT(status == 0, 'Unable to convert second string')
      call ESMF_CalendarSetDefault(CALKIND_FLAG, _RC)
      call ESMF_TimeSet(datetime, yy=yy, mm=mm, dd=dd, h=h, m=m, s=s, _RC)

      _RETURN(_SUCCESS)

   end subroutine convert_NetCDF_DateTimeString_to_ESMF_Time

   function is_valid_netcdf_datetime_string(string) result(tval)
      character(len=*), parameter :: DIGITS = '0123456789'
      character(len=*), intent(in) :: string
      logical :: tval
      integer :: i

      tval = .false.
      
      if(len(string) /= len(NETCDF_DATETIME_FORMAT)) return

      do i=1, len(string)
         if(scan(NETCDF_DATETIME_FORMAT(i:i), DIGITS) > 0) then
            if(scan(string(i:i), DIGITS) <= 0) return
         else
            if(string(i:i) /= NETCDF_DATETIME_FORMAT(i:i)) return
         end if
      end do
      
      tval = .true.

   end function is_valid_netcdf_datetime_string

   function is_time_unit(tunit)
      character(len=*), intent(in) :: tunit
      logical :: is_time_unit
      integer :: i

      is_time_unit = .TRUE.
      do i = 1, size(TIME_UNITS)
         if(lr_trim(tunit) == lr_trim(TIME_UNITS(i))) return
      end do
      is_time_unit = .FALSE.

   end function is_time_unit

   function lr_trim(string)
      character(len=*), intent(in) :: string
      character(len=:), allocatable :: lr_trim

      lr_trim = trim(adjustl(string))

   end function lr_trim

   ! Get the sign of integer represening a time span based on preposition
   function get_shift_sign(preposition)
      character(len=*), intent(in) :: preposition
      integer :: get_shift_sign
      integer, parameter :: POSITIVE = 1
      get_shift_sign = 0
      if(lr_trim(preposition) == 'since') get_shift_sign = POSITIVE
   end function get_shift_sign

   ! Split string at delimiter
   function split(string, delimiter)
      character(len=*), intent(in) :: string
      character(len=*), intent(in) :: delimiter
      character(len=len(string)) :: split(2)
      integer start
 
      split = ['', '']
      split(1) = string
      start = index(string, delimiter)
      if(start < 1) return
      split(1) = string(1:(start - 1))
      split(2) = string((start+len(delimiter)):len(string))
   end function split

   ! Split string into all substrings based on delimiter
   recursive function split_all(string, delimiter) result(parts)
      character(len=*), intent(in) :: string
      character(len=*), intent(in) :: delimiter
      character(len=:), allocatable :: parts(:)
      integer :: start

      start = index(string, delimiter)

      if(start == 0) then
         parts = [string]
      else
         parts = [string(1:(start-1)), split_all(string((start+len(delimiter)):len(string)), delimiter)] 
      end if

   end function split_all

end module MAPL_NetCDF
