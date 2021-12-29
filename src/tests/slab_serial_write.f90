program write_slab_serial
!! no MPI / parallel at all

use, intrinsic :: iso_fortran_env, only : int64, real32, real64, stderr=>error_unit
use h5mpi, only : hdf5_file
use cli, only : get_cli, get_simsize
use perf, only : print_timing
use kernel, only : phantom

implicit none

type(hdf5_file) :: h5

real(real32), allocatable :: S3(:,:,:)
real(real64), allocatable :: D3(:,:,:)
real :: noise, gensig

character(1000) :: argv, outfn

integer :: ierr, lx1, lx2, lx3, i, real_bits, comp_lvl
integer :: Nrun

logical :: debug = .false.

integer(int64) :: tic, toc
integer(int64), allocatable :: t_elapsed(:)

call get_simsize(lx1, lx2, lx3)

print '(a,1x,i0,1x,i0,1x,i0)', 'Serial: lx1, lx2, lx3 =', lx1, lx2, lx3

!> output HDF5 file to write
Nrun = 1
outfn = ""
real_bits = 32
comp_lvl = 0
noise = 0.
gensig = -1.

do i = 1, command_argument_count()
  call get_command_argument(i, argv, status=ierr)
  if(ierr/=0) error stop "unknown argument: " // argv

  select case(argv)
  case("-o")
    call get_cli(i, argv, outfn)
  case("-Nrun")
    call get_cli(i, argv, Nrun)
  case("-realbits")
    call get_cli(i, argv, real_bits)
  case ("-comp")
    call get_cli(i, argv, comp_lvl)
  case ("-noise")
    call get_cli(i, argv, noise)
  case ("-gen")
    call get_cli(i, argv, gensig)
  case("-d", "-debug")
    debug = .true.
  end select
end do

if(len_trim(outfn) == 0) error stop "please specify -o filename to write"

allocate(t_elapsed(Nrun))
if(real_bits == 32) then
  allocate(S3(lx1, lx2, lx3))
  call random_number(S3)
  S3(1:lx1, 1:lx2, 1:lx3) = noise*S3 + spread(phantom(lx1, lx2, gensig), 3, lx3)
elseif(real_bits==64) then
  allocate(D3(lx1, lx2, lx3))
  call random_number(D3)
  D3(1:lx1, 1:lx2, 1:lx3) = noise*D3 + spread(phantom(lx1, lx2, gensig), 3, lx3)
else
  error stop "unknown real_bits: expect 32 or 64"
endif

!! benchmark loop
!! due to filesystem caching, minimum time isn't appropriate
!! better to use mean/median/variance etc.

main : do i = 1, Nrun

  call system_clock(count=tic)

  call h5%open(trim(outfn), action="w", mpi=.false., comp_lvl=comp_lvl, debug=debug)

  if(real_bits == 32) then
    call h5%write("/A3", S3)
  elseif(real_bits == 64) then
    call h5%write("/A3", D3)
  endif

  call h5%close()

  call system_clock(count=toc)
  t_elapsed(i) = toc-tic

end do main

!> RESULTS

call print_timing(1, h5%comp_lvl, real_bits, [lx1, lx2, lx3], t_elapsed, h5%filesize(), debug, &
 trim(outfn) // ".write_stat.h5")

end program
