MODULE cut_cell
!
!**********************************************************************************
!*  CUT_CELL                                                                      *
!**********************************************************************************
!* This module reads atomic coordinates from an array P and "cuts" it.            *
!* This is useful if one wants to reduce the number of atoms displayed.           *
!**********************************************************************************
!* (C) March 2010 - Pierre Hirel                                                  *
!*     Unité Matériaux Et Transformations (UMET),                                 *
!*     Université de Lille 1, Bâtiment C6, F-59655 Villeneuve D'Ascq (FRANCE)     *
!*     pierre.hirel@univ-lille1.fr                                                *
!* Last modification: P. Hirel - 19 Feb. 2013                                     *
!**********************************************************************************
!* This program is free software: you can redistribute it and/or modify           *
!* it under the terms of the GNU General Public License as published by           *
!* the Free Software Foundation, either version 3 of the License, or              *
!* (at your option) any later version.                                            *
!*                                                                                *
!* This program is distributed in the hope that it will be useful,                *
!* but WITHOUT ANY WARRANTY; without even the implied warranty of                 *
!* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                  *
!* GNU General Public License for more details.                                   *
!*                                                                                *
!* You should have received a copy of the GNU General Public License              *
!* along with this program.  If not, see <http://www.gnu.org/licenses/>.          *
!**********************************************************************************
!
USE comv
USE constants
USE messages
USE files
USE subroutines
!
!
CONTAINS
!
!
SUBROUTINE CUTCELL(P,S,AUX,cut_dir,cutdistance,cutdir,ORIENT,SELECT)
!
IMPLICIT NONE
CHARACTER(LEN=5),INTENT(IN):: cut_dir   !above or below
CHARACTER(LEN=16),INTENT(IN):: cutdir   !x, y, z, or crystallographic direction
CHARACTER(LEN=128):: msg
LOGICAL,DIMENSION(:),ALLOCATABLE:: SELECT, newSELECT  !mask for atom list
INTEGER:: a1, a2, a3
INTEGER:: i, j, NPcut, NP
REAL(dp),INTENT(IN):: cutdistance
REAL(dp):: tempreal
REAL(dp):: V1, V2, V3  !vector components
REAL(dp),DIMENSION(1,3):: Vplane  !crystallographic vector defining the plane
REAL(dp),DIMENSION(3,3),INTENT(IN):: ORIENT !current crystallographic orientation of the system
REAL(dp),DIMENSION(3,3):: ORIENTN      !normalized ORIENT
REAL(dp),DIMENSION(:,:),ALLOCATABLE,INTENT(INOUT):: P, S  !positions of cores, shells
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: Q, T                !positions of cores, shells (temporary)
REAL(dp),DIMENSION(:,:),ALLOCATABLE,INTENT(INOUT):: AUX   !auxiliary properties of atoms
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: newAUX              !auxiliary properties of atoms (temporary)
!
!
!
!Initialize variables
i = 0
NPcut = 0
IF(ALLOCATED(newSELECT)) DEALLOCATE(newSELECT)
IF(ALLOCATED(newAUX)) DEALLOCATE(newAUX)
IF(ALLOCATED(Q)) DEALLOCATE(Q)
IF(ALLOCATED(T)) DEALLOCATE(T)
!
!
CALL ATOMSK_MSG(2056,(/cut_dir//'           ',cutdir/),(/cutdistance/))
!
!
!
100 CONTINUE
!Allocate Q (and if necessary, T for shells and newAUX for auxiliary properties)
!Note: at this point the temporary arrays are allocated with the same size
!     as the original arrays because we don't know how many atoms will be removed
ALLOCATE( Q( SIZE(P,1),4 ) )
IF(ALLOCATED(SELECT)) ALLOCATE( newSELECT( SIZE(P,1) ) )
IF(ALLOCATED(S)) ALLOCATE( T( SIZE(P,1),4 ) )
IF(ALLOCATED(AUX)) ALLOCATE( newAUX( SIZE(AUX,1), SIZE(AUX,2) ) )
!
NP=0
!
SELECT CASE(cutdir)
CASE("x","X","y","Y","z","Z")
  !cutdir is a cartesian direction
  !Define the axes
  IF(cutdir=='x' .OR. cutdir=='X') THEN
    a1 = 1
  ELSEIF(cutdir=='y' .OR. cutdir=='Y') THEN
    a1 = 2
  ELSEIF(cutdir=='z' .OR. cutdir=='Z') THEN
    a1 = 3
  ENDIF
  WRITE(msg,*) 'a1 = ', a1
  CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
  !
  DO i=1,SIZE(P,1)
    IF(.NOT.ALLOCATED(SELECT) .OR. SELECT(i)) THEN
      IF( cut_dir=='above' .AND. P(i,a1)>cutdistance .OR.        &
        & cut_dir=='below' .AND. P(i,a1)<cutdistance      ) THEN
        !This atom must be removed
        NPcut = NPcut+1
      ELSE
        !This atom does not match criteria for cut => it lives
        NP=NP+1
        Q(NP,:) = P(i,:)
        !Save associated shell if any
        IF(ALLOCATED(S)) THEN
          T(NP,:) = S(i,:)
        ENDIF
        !Save associated auxiliary properties if any
        IF(ALLOCATED(AUX)) THEN
          newAUX(NP,:) = AUX(i,:)
        ENDIF
      ENDIF
    ELSE
      !This atom is not in the selected region => it lives
      NP=NP+1
      Q(NP,:) = P(i,:)
      IF(ALLOCATED(SELECT)) THEN
        !Save selection
        newSELECT(NP) = SELECT(i)
      ENDIF
      !Save associated shell if any
      IF(ALLOCATED(S)) THEN
        T(NP,:) = S(i,:)
      ENDIF
      !Save associated auxiliary properties if any
      IF(ALLOCATED(AUX)) THEN
        newAUX(NP,:) = AUX(i,:)
      ENDIF
    ENDIF
  ENDDO
  !
CASE DEFAULT
  !cutdir should contain a crystallographic direction
  !convert it to a vector and save it in Vplane(1,:)
  CALL INDEX_MILLER(cutdir,Vplane(1,:),j)
  IF(j>0) GOTO 800
  !
  !If the system has a defined crystallographic orientation ORIENT,
  !then Vplane(1,:) is defined in that basis
  !=> rotate Vplane(1,:) to express it in cartesian basis
  IF( ANY( NINT(ORIENT(:,:)).NE.0 ) ) THEN
    DO i=1,3
      ORIENTN(i,:) = ORIENT(i,:) / VECLENGTH(ORIENT(i,:))
    ENDDO
    V1 = Vplane(1,1)
    V2 = Vplane(1,2)
    V3 = Vplane(1,3)
    Vplane(1,1) = ORIENTN(1,1)*V1 + ORIENTN(1,2)*V2 + ORIENTN(1,3)*V3
    Vplane(1,2) = ORIENTN(2,1)*V1 + ORIENTN(2,2)*V2 + ORIENTN(2,3)*V3
    Vplane(1,3) = ORIENTN(3,1)*V1 + ORIENTN(3,2)*V2 + ORIENTN(3,3)*V3
  ENDIF
  !Normalize Vplane
  Vplane(1,:) = Vplane(1,:)/VECLENGTH(Vplane(1,:))
  WRITE(msg,'(a8,3f12.3)') 'Vplane: ', Vplane(1,:)
  CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
  !
  DO i=1,SIZE(P(:,1))
    !determine if atom is above or below the plane
    tempreal = VEC_PLANE( Vplane(1,:) , cutdistance , P(i,1:3) )
    IF(.NOT.ALLOCATED(SELECT) .OR. SELECT(i)) THEN
      IF( cut_dir=='above' .AND. tempreal>0.d0 .OR.        &
        & cut_dir=='below' .AND. tempreal<0.d0       ) THEN
        !This atom must be removed
        NPcut = NPcut+1
      ELSE
        !This atom does not match criteria for cut => it lives
        NP=NP+1
        Q(NP,:) = P(i,:)
        IF( ALLOCATED(SELECT)) THEN
          !Save selection
          newSELECT(NP) = SELECT(i)
        ENDIF
        !Save associated shell if any
        IF(ALLOCATED(S)) THEN
          T(NP,:) = S(i,:)
        ENDIF
        !Save associated auxiliary properties if any
        IF(ALLOCATED(AUX)) THEN
          newAUX(NP,:) = AUX(i,:)
        ENDIF
      ENDIF
    ELSE
      !This atom is not in the selected region => it lives
      NP=NP+1
      Q(NP,:) = P(i,:)
      !Save associated shell if any
      IF(ALLOCATED(S)) THEN
        T(NP,:) = S(i,:)
      ENDIF
      !Save associated auxiliary properties if any
      IF(ALLOCATED(AUX)) THEN
        newAUX(NP,:) = AUX(i,:)
      ENDIF
    ENDIF
  ENDDO
  !
END SELECT
!
WRITE(msg,*) 'NPcut, NP:', NPcut, NP
CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
!
!
!
200 CONTINUE
!Replace old arrays with new ones
DEALLOCATE(P)
ALLOCATE(P(NP,4))
DO i=1,NP
  P(i,:) = Q(i,:)
ENDDO
DEALLOCATE(Q)
!
IF(ALLOCATED(SELECT)) THEN
  !Replace old SELECT with newSELECT
  DEALLOCATE(SELECT)
  ALLOCATE( SELECT(NP) )
  DO i=1,NP
    SELECT(i) = newSELECT(i)
  ENDDO
  DEALLOCATE(newSELECT)
ENDIF
!
IF(ALLOCATED(S)) THEN
  !Replace old S with T
  DEALLOCATE(S)
  ALLOCATE( S( NP,4 ) )
  DO i=1,NP
    S(i,:) = T(i,:)
  ENDDO
  DEALLOCATE(T)
ENDIF
!
IF(ALLOCATED(AUX)) THEN
  !Replace old AUX with new AUX
  DEALLOCATE(AUX)
  ALLOCATE( AUX( NP, SIZE(newAUX,2) ) )
  DO i=1,NP
    AUX(i,:) = newAUX(i,:)
  ENDDO
  DEALLOCATE(newAUX)
ENDIF
!
CALL ATOMSK_MSG(2057,(/''/),(/ DBLE(NPcut), DBLE(NP) /))
!
GOTO 1000
!
!
!
800 CONTINUE
CALL ATOMSK_MSG(802,(/''/),(/DBLE(i)/))
nerr = nerr+1
!
!
!
1000 CONTINUE
!
!
END SUBROUTINE CUTCELL
!
END MODULE cut_cell
