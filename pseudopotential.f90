! This file is part of BandFTN.
! Copyright (C) 2013-2014 Adam Hirst <adam@aphirst.karoo.co.uk>
!
! BandFTN is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! BandFTN is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with BandFTN. If not, see <http://www.gnu.org/licenses/>.

module Pseudopotential
  use Constants
  use Lattice

  implicit none

  ! container for wavevectors
  type Wavevec
    real :: k(3)
  end type Wavevec

  ! container for pseudopotential matrix
  type Potmat
    type(Latvec), allocatable :: basis(:)
    complex,      allocatable :: M(:,:), diag(:)
    real,         allocatable :: EVs(:)
    ! storing a copy of the lattice constant in here simplifies things somewhat
    real                      :: A
  contains
    procedure :: Create => Create_potmat
    procedure :: Update => Update_potmat
    ! might be easier to then spread into energy-bands now that eigenvalues are inside here
  end type Potmat

  ! we want to be able to add a matrix to a matrix-diagonal
  interface operator (+)
    procedure :: Matrix_diagonal_addition
  end interface operator (+)

  ! explicit interface to the hermitian LAPACK routine, just a bit of good practice
  interface
    pure subroutine CHEEV(JOBZ, UPLO, N, A, LDA, W, WORK, LWORK, RWORK, INFO)
      character(1), intent(in)     :: JOBZ, UPLO
      integer,      intent(in)     :: N, LDA, LWORK
      complex,      intent(in)     :: A(LDA,N)
      complex,      intent(in out) :: WORK(LWORK)
      real,         intent(in out) :: RWORK(3*N - 2)
      real,         intent(out)    :: W(N)
      integer,      intent(out)    :: INFO
    end subroutine CHEEV
  end interface

  private
  public :: Wavevec, Potmat, operator(+)

contains

  pure function Matrix_diagonal_addition(M, diag) result(md_sum)
    ! Adds a matrix-diagonal to an N*N matrix (by replacement of the diagonal).
    ! (overloads the `+` operator)
    complex, intent(in) :: M(:,:), diag(:)
    complex             :: md_sum(size(diag),size(diag))
    integer             :: i, j

    ! first copy over all the non-diagonal elements
    do concurrent ( i = 1:size(diag), j=1:size(diag), j > i )
      md_sum(i,j) = M(i,j)
    end do
    ! then copy over the diagonal elements
    ! for our purposes, the original matrix diagonal is always 0, so we don't need to actually add
    do concurrent ( i = 1:size(diag) )
      md_sum(i,i) = diag(i)
    end do

  end function Matrix_diagonal_addition

  pure subroutine Create_potmat(this, this_material, magnitude)
    ! Initialises the state of type(Potmat) entity, using the properties of `this_material`
    ! and populates its Miller index basis using RLVs of square-magnitude upto 'magnitude'.
    class(Potmat),  intent(in out)              :: this
    type(Material), intent(in)                  :: this_material
    integer,        intent(in)                  :: magnitude
    integer                                     :: i, j
    type(Latvec),                   allocatable :: groups(:), signings(:)

    ! copy in the lattice constant
    this%A = this_material%A
    ! initialise the RLV basis
    groups = [( Get_groups(i), i=0,magnitude )]
    signings = [( Get_signings(groups(i)), i=1,size(groups) )]
    if (allocated(this%basis)) deallocate(this%basis)
    this%basis = [( Get_permutations(signings(i)), i=1,size(signings) )]
    ! populate the non-zero non-diagonal elements of the potential matrix
    ! rows are g', columns are g
    if (allocated(this%M)) deallocate(this%M)
    if (allocated(this%diag)) deallocate(this%diag)
    if (allocated(this%EVs)) deallocate(this%EVs)
    allocate(this%M( size(this%basis), size(this%basis) ))
    allocate(this%diag( size(this%basis) ))
    allocate(this%EVs( size(this%basis) ))
    ! only need to populate the upper diagonal (since the matrix must have real eigenenergies, it must be Hermitian)
    do concurrent ( i = 1:size(this%basis), j = 1:size(this%basis), j > i )
      this%M(i,j) = this_material%Form_factor(this%basis(i) - this%basis(j))
    end do

  end subroutine Create_potmat

  pure subroutine Update_potmat(this, k)
    ! Updates the diagonal (KE) component of a potential matrix using the current value of wavevector, k,
    ! and computes the corresponding eigenenergies.
    class(Potmat), intent(in out) :: this
    type(Wavevec), intent(in)     :: k
    integer                       :: i, INFO, N
    real                          :: RWORK(3*size(this%EVs) - 2)
    complex                       :: WORK(2*size(this%EVs) - 1)

    do concurrent ( i = 1:size(this%diag) )
      this%diag(i) = (hc/this%A)**2 * sum( (k%k + real(this%basis(i)%hkl))**2 ) / (2.0 * E_e)
    end do
    N = size( this%diag )
    ! LAPACK routine for diagonalising complex, hermitian matrixes
    ! 'N' => no eigenvectors
    ! 'U' => use the upper diagonal of the input matrix
    call CHEEV('N', 'U', N, (this%M + this%diag), N, this%EVs, WORK, size(WORK), RWORK, INFO)

  end subroutine Update_potmat

end module Pseudopotential