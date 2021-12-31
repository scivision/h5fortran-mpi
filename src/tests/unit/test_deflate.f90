program test_deflate
!! unit tests and registration tests of HDF5 deflate compression write
use, intrinsic:: iso_fortran_env, only: int32, int64, real32, real64, stderr=>error_unit

use hdf5, only : H5D_CHUNKED_F, H5D_CONTIGUOUS_F, hsize_t
use mpi, only : mpi_init, mpi_comm_rank, mpi_comm_size, MPI_COMM_WORLD

use h5mpi, only: hdf5_file, HSIZE_T

implicit none (type, external)

external :: mpi_finalize

character(*), parameter :: fn1='deflate1.h5', fn2='deflate2.h5', fn3='deflate3.h5', fn4='deflate4.h5'
integer, parameter :: N=1000
integer :: ierr

call mpi_init(ierr)
if (ierr /= 0) error stop "mpi_init"

call test_deflate_props(fn1, [50, 1000])
print *,'OK: HDF5 compression props'

call test_deflate_whole(fn2, N)
print *,'OK: HDF5 compress whole'

call test_deflate_slice(fn3, N)
print *,'OK: HDF5 compress slice'

call test_deflate_chunk_size(fn4)
print *,'OK: HDF5 compress whole with chunk size'

call test_get_deflate(fn1)
print *, 'OK: HDF5 get deflate'

call mpi_finalize(ierr)
if (ierr /= 0) error stop "mpi_finalize"

contains

subroutine test_deflate_props(fn, N)

character(*), intent(in) :: fn
integer, intent(in) :: N(2)

type(hdf5_file) :: h5f
integer(HSIZE_T) :: chunks(3)
integer ::  fsize, layout
integer(int64) :: crat

integer(HSIZE_T) :: i0(2), i1(2), dx2
integer :: Nmpi, mpi_id

real(real32), allocatable :: A(:,:)

!> MPI partition
call mpi_comm_size(MPI_COMM_WORLD, Nmpi, ierr)
if(ierr/=0) error stop "mpi_comm_size"
call mpi_comm_rank(MPI_COMM_WORLD, mpi_id, ierr)
if(ierr/=0) error stop "mpi_comm_rank"

if(mpi_id == 0) then
  if (Nmpi > 1 .and. (modulo(N(2), Nmpi) /= 0 .or. Nmpi > N(2))) then
    write(stderr, '(a,1x,i0,1x,i0)') "test_deflate_props: MPI worker count must be multiple of N", N(2), Nmpi
    error stop fn
  endif
end if

dx2 = N(2) / Nmpi

allocate(A(N(1), dx2))

A = 0  !< simplest data

i0(1) = 1
i0(2) = mpi_id * dx2 + 1
i1(1) = size(A, 1)
i1(2) = i0(2) + dx2 - 1

!> write
if(mpi_id == 0) then
  call h5f%open(fn, action='w', comp_lvl=1, mpi=.false.)
  call h5f%write('/small_contig', A(:4,:4))
  call h5f%close()
endif

print '(a,i0,1x,2i5,2x,2i5)', "#1 partition: mpi_id, i0, i1 ", mpi_id, i0, i1

call h5f%open(fn, action='a', comp_lvl=1, mpi=.true., debug=.true.)
call h5f%write('/A', A, N, istart=i0, iend=i1)
call h5f%close()

!> check
inquire(file=fn, size=fsize)
crat = (N(1) * N(2) * storage_size(A) / 8) / fsize
print '(A,F6.2,A,I6)','filesize (Mbytes): ',fsize/1e6, '   2D compression ratio:',crat
if (h5f%parallel_compression) then
  if(crat < 10) error stop '2D low compression'
else
  print *, "MPI commpression was disabled, so " // fn // " was not compressed."
endif

call h5f%open(fn, action='r', debug=.false.)

layout = h5f%layout('/A')
if(layout /= H5D_CHUNKED_F) error stop '#1 not chunked layout: ' // fn
if(.not.h5f%is_chunked('/A')) error stop '#1 not chunked layout: ' // fn
call h5f%chunks('/A', chunks(:2))
! if(any(chunks(:2) /= [100, 100])) then
if(any(chunks(:2) /= [63, 63])) then
  write(stderr, '(a,2I5)') "expected chunks: 63, 63 but got chunks ", chunks(:2)
  error stop '#1 get_chunk mismatch'
endif
layout = h5f%layout('/small_contig')
if(layout /= H5D_CONTIGUOUS_F) error stop '#1 not contiguous layout'
if(.not.h5f%is_contig('/small_contig')) error stop '#1 not contig layout'
call h5f%chunks('/small_contig', chunks(:2))
if(any(chunks(:2) /= -1)) error stop '#1 get_chunk mismatch'

call h5f%close()

end subroutine test_deflate_props


subroutine test_deflate_whole(fn, N)

character(*), intent(in) :: fn
integer, intent(in) :: N

type(hdf5_file) :: h5f
real, allocatable :: big3(:,:,:)
integer(hsize_t) :: crat, chunks(3)
integer :: fsize

allocate(big3(N,N,4))

call h5f%open(fn, action='w',comp_lvl=1, debug=.true.)
call h5f%write('/big3', big3) !, chunk_size=[100,100,1])

call h5f%write('/big3_autochunk', big3)
call h5f%chunks('/big3_autochunk', chunks)
if(any(chunks /= [63,125,1])) error stop '#2 auto chunk unexpected chunk size'

call h5f%close()

inquire(file=fn, size=fsize)
crat = (2*N*N*storage_size(big3)/8) / fsize

print '(A,F6.2,A,I6)','#2 filesize (Mbytes): ',fsize/1e6, '   3D compression ratio:',crat

if (h5f%comp_lvl > 0 .and. crat < 10) error stop '#2 3D low compression'
end subroutine test_deflate_whole


subroutine test_deflate_slice(fn, N)

character(*), intent(in) :: fn
integer, intent(in) :: N

type(hdf5_file) :: h5f
integer, allocatable :: ibig3(:,:,:)
integer(hsize_t) :: crat, chunks(3)
integer :: fsize

allocate(ibig3(N,N,4))

ibig3 = 0

call h5f%open(fn, action='w',comp_lvl=1, debug=.true.)

call h5f%write('/ibig3', ibig3(:N-10,:N-20,:))
call h5f%chunks('/ibig3', chunks)
if(any(chunks /= [62,123,1])) error stop '#3 auto chunk unexpected chunk size'

call h5f%close()

inquire(file=fn, size=fsize)
crat = (N*N*storage_size(ibig3)/8) / fsize

print '(A,F6.2,A,I6)','#3 filesize (Mbytes): ',fsize/1e6, '   3D compression ratio:',crat

if (h5f%comp_lvl > 0 .and. crat < 10) error stop '#3 3D low compression'

end subroutine test_deflate_slice


subroutine test_deflate_chunk_size(fn)

character(*), intent(in) :: fn

type(hdf5_file) :: h5f
integer, allocatable :: ibig2(:,:)
integer(hsize_t) :: crat
integer :: fsize

allocate(ibig2(N,N))

ibig2 = 0

call h5f%open(fn, action='w',comp_lvl=1, debug=.true.)
call h5f%write('/ibig2', ibig2) !, chunk_size=[100,100])
call h5f%close()

inquire(file=fn, size=fsize)
crat = (N*N*storage_size(ibig2)/8) / fsize

print '(A,F6.2,A,I6)','#4 filesize (Mbytes): ',fsize/1e6, '   3D compression ratio:',crat

if (h5f%comp_lvl > 0 .and. crat < 10) error stop '#4 3D low compression'

end subroutine test_deflate_chunk_size


subroutine test_get_deflate(fn)

character(*), intent(in) :: fn

type(hdf5_file) :: h5f

call h5f%open(fn, action='r', debug=.true.)

if (.not. h5f%deflate("/A")) error stop "expected deflate"

call h5f%close()

end subroutine test_get_deflate

end program
