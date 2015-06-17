MODULE out_lammps_data
!
!
!**********************************************************************************
!*  OUT_LAMMPS_DATA                                                               *
!**********************************************************************************
!* This module writes a data file for LAMMPS, that can be called                  *
!* with the  'read_data <filename>' in the LAMMPS input file, see:                *
!*     http://lammps.sandia.gov/doc/read_data.html                                *
!* Support for bonds is limited to ionic core-shell model.                        *
!**********************************************************************************
!* (C) June 2010 - Pierre Hirel                                                   *
!*     Unité Matériaux Et Transformations (UMET),                                 *
!*     Université de Lille 1, Bâtiment C6, F-59655 Villeneuve D'Ascq (FRANCE)     *
!*     pierre.hirel@univ-lille1.fr                                                *
!* Last modification: P. Hirel - 26 May 2015                                      *
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

!
USE comv
USE constants
USE functions
USE messages
USE files
USE subroutines
!
IMPLICIT NONE
!
!
CONTAINS
!
SUBROUTINE WRITE_LMP_DATA(H,P,S,comment,AUXNAMES,AUX,outputfile)
!
CHARACTER(LEN=*),INTENT(IN):: outputfile
CHARACTER(LEN=2):: answer, skew
CHARACTER(LEN=4096):: msg, temp
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE,INTENT(IN):: AUXNAMES !names of auxiliary properties
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE,INTENT(IN):: comment
LOGICAL:: charges, shells, velocities !are atom charges, shells, velocities, defined?
INTEGER:: i, iloop, j, Nspecies
INTEGER:: molID      !column for molecule ID in AUX
INTEGER:: moleculeID !actual molecule ID
INTEGER:: NPdigits   !number of digits in the number of particles
INTEGER:: Ntypes     !number of atom types
INTEGER:: Nbondtypes !number of bond types (core-shell springs)
INTEGER:: Nshells    !number of shells (core-shell model)
INTEGER:: vx, vy, vz, q, qs, typecol !index of velocities, charges, shell charges, atom types in AUX
INTEGER,DIMENSION(20):: BOND_TYPES  !types of bonds (assuming max. 20 different atom types)
INTEGER,DIMENSION(:),ALLOCATABLE:: BONDS  !list of bonds
REAL(dp):: alpha, beta, gamma, Kx, Ky, Kz !for conventional notation
REAL(dp):: Qcore, Qshell !electric charge of core, shell
REAL(dp):: tiltbefore
REAL(dp),DIMENSION(3):: tilt  !xy, xz, yz
REAL(dp),DIMENSION(3,3),INTENT(IN):: H   !Base vectors of the supercell
REAL(dp),DIMENSION(3,3):: K   !copy of H
REAL(dp),DIMENSION(:,:),POINTER:: Ppoint  !pointer to P or R
REAL(dp),DIMENSION(:,:),ALLOCATABLE,INTENT(IN),TARGET:: P !atom positions
REAL(dp),DIMENSION(:,:),ALLOCATABLE,TARGET:: R !copy of P (if necessary)
REAL(dp),DIMENSION(:,:),ALLOCATABLE,INTENT(IN):: S !positions of shells
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: atypes
REAL(dp),DIMENSION(:,:),ALLOCATABLE:: aentries !array containing result
REAL(dp),DIMENSION(:,:),ALLOCATABLE,INTENT(IN):: AUX !auxiliary properties
!
!
!Initialize variables
 charges = .FALSE.
shells = .FALSE.
velocities = .FALSE.
i=0
j=0
molID = 0
q = 0
typecol = 0
vx = 0
vy = 0
vz = 0
Nbondtypes = 0
Nshells = 0
Nspecies = 0
tilt(:) = 0.d0
K=H
BOND_TYPES(:) = 0
IF(ALLOCATED(R)) DEALLOCATE(R)
Ppoint=>P
!Find how many different species are in P
CALL FIND_NSP(P(:,4),atypes)
Ntypes = SIZE(atypes(:,1))
!
msg = 'entering WRITE_LMP_DATA'
CALL ATOMSK_MSG(999,(/msg/),(/0.d0/))
!
!Count number of digits composing the number of particles
WRITE(temp,*) SIZE(P,1)
NPdigits = LEN_TRIM(ADJUSTL(temp))
!
IF( ALLOCATED(BONDS) .AND. SIZE(BONDS)>0 ) THEN
  !count how many bonds exist
  !CALL FIND_NSP( DBLE(BONDS(:,3)) , aentries )
  Nbondtypes = SIZE(aentries,1)
!   DO i=1,SIZE(BONDS)
!     IF( NINT(S(i,4))>0 ) THEN
!       Nshells = Nshells+1
!       IF( .NOT.ANY( NINT(S(i,4))==BOND_TYPES(:) ) ) THEN
!         Nbondtypes = Nbondtypes+1
!         BOND_TYPES(Nbondtypes) = NINT(S(i,4))
!       ENDIF
!     ENDIF
!   ENDDO
ENDIF
!
!Check if some auxiliary properties are present
IF( ALLOCATED(AUXNAMES) ) THEN
  DO i=1,SIZE(AUXNAMES)
    IF( TRIM(ADJUSTL(AUXNAMES(i)))=='vx' ) THEN
      vx = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='vy' ) THEN
      vy = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='vz' ) THEN
      vz = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='molID' ) THEN
      molID = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='q' ) THEN
      q = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='qs' ) THEN
      qs = i
    ELSEIF( TRIM(ADJUSTL(AUXNAMES(i)))=='type' ) THEN
      typecol = i
      !Find how many different species are in AUX
      CALL FIND_NSP(AUX(:,typecol),atypes)
      Ntypes = SIZE(atypes(:,1))
    ENDIF
  ENDDO
  !
  IF( vx.NE.0 .AND. vy.NE.0 .AND. vz.NE.0 ) velocities = .TRUE.
  IF( q.NE.0 ) charges = .TRUE.
ENDIF
!
!
!
100 CONTINUE
OPEN(UNIT=40,FILE=outputfile,STATUS='UNKNOWN',ERR=500)
!
!Write header of data file
WRITE(40,*) TRIM(ADJUSTL(comment(1)))
WRITE(40,*) ''
WRITE(40,*) SIZE(P,1)+Nshells, ' atoms'
IF( Nshells>0 ) THEN
  WRITE(40,*) Nshells, ' bonds'
ENDIF
!
!Determine how many different species are present
WRITE(40,*) Ntypes, ' atom types'
WRITE(40,*) ''
IF( Nbondtypes>0 ) THEN
  WRITE(40,*) Nbondtypes, ' bond types'
  WRITE(40,*) ''
ENDIF
!
!
!Check that supercell vectors form a lower rectangular matrix
IF( DABS(H(1,2))>1.d-12 .OR. DABS(H(1,3))>1.d-12 .OR. DABS(H(2,3))>1.d-12 ) THEN
  !Prompt user whether to rotate the system
  nwarn = nwarn+1
  CALL ATOMSK_MSG(3704,(/''/),(/0.d0/))
  READ(*,*) answer
  IF(answer==langyes .OR. answer==langBigYes) THEN
    !The following does the same as option "-alignx"
    !Copy P to R
    ALLOCATE( R( SIZE(P(:,1)), SIZE(P(1,:)) ) )
    R=P
    !
    !Convert to fractional coordinates
    CALL CART2FRAC(R,K)
    !
    !Convert the matrix K into conventional notation
    Kx = VECLENGTH(K(1,:))
    Ky = VECLENGTH(K(2,:))
    Kz = VECLENGTH(K(3,:))
    alpha = ANGVEC(K(2,:),K(3,:))
    beta  = ANGVEC(K(3,:),K(1,:))
    gamma = ANGVEC(K(1,:),K(2,:))
    !
    !Then convert this conventional notation into lower-triangular matrix K
    CALL CONVMAT(Kx,Ky,Kz,alpha,beta,gamma,K)
    !
    !Convert back to cartesian coordinates
    CALL FRAC2CART(R,K)
    !Modify pointer
    Ppoint=>R
    CALL ATOMSK_MSG(2051,(/''/),(/0.d0/))
    !
  ELSE
    !If user does not want to rotate the system,
    !display a final warning just to be sure
    CALL ATOMSK_MSG(3709,(/''/),(/0.d0/))
  ENDIF
ENDIF
!
!
!Write supercell data
IF( VECLENGTH(K(1,:)) > 1.d-12 ) THEN
  WRITE(40,160) zero, K(1,1), '  xlo xhi'
ENDIF
IF( VECLENGTH(K(2,:)) > 1.d-12 ) THEN
  WRITE(40,160) zero, K(2,2), '  ylo yhi'
ENDIF
IF( VECLENGTH(K(3,:)) > 1.d-12 ) THEN
  WRITE(40,160) zero, K(3,3), '  zlo zhi'
ENDIF
!
IF( DABS(K(2,1))>1.d-12 .OR. DABS(K(3,1))>1.d-12 .OR. DABS(K(3,2))>1.d-12 ) THEN
  !LAMMPS requires that skew parameters are less than half the box
  !length in each direction. If it is not the case, warn the user.
  tilt(1) = K(2,1)
  tilt(2) = K(3,1)
  tilt(3) = K(3,2)
  DO i=1,3
    IF(i==1) THEN
      j = 1
      skew = 'xy'
    ELSEIF(i==2) THEN
      j = 1
      skew = 'xz'
    ELSEIF(i==3) THEN
      j = 2
      skew = 'yz'
    ENDIF
    !
    IF( DABS(tilt(i))>0.5d0*K(j,j) ) THEN
      nwarn=nwarn+1
      !Ask if the skew should be reduced
      CALL ATOMSK_MSG(3705,(/skew/),(/0.d0/))
      READ(*,*) answer
      IF(answer==langyes .OR. answer==langBigYes) THEN
        tiltbefore = tilt(i)
        iloop=0
        DO WHILE( tilt(i)>0.5d0*K(j,j) )
          tilt(i) = tilt(i)-K(j,j)
          iloop=iloop+1
          IF(iloop>100) EXIT
        ENDDO
        !
        DO WHILE( tilt(i)<=-0.5d0*K(j,j) )
          tilt(i) = tilt(i)+K(j,j)
          iloop=iloop+1
          IF(iloop>200) EXIT
        ENDDO
        !
        IF(iloop>100) THEN
          nwarn=nwarn+1
          CALL ATOMSK_MSG(3706,(/skew/),(/0.d0/))
          tilt(i) = tiltbefore
        ELSE
          CALL ATOMSK_MSG(3004,(/skew/),(/0.d0/))
        ENDIF
      ELSE
        CALL ATOMSK_MSG(3005,(/skew/),(/0.d0/))
      ENDIF
    ENDIF
  ENDDO
  WRITE(40,161) tilt(1), tilt(2), tilt(3), ' xy xz yz'
ENDIF
WRITE(40,*) ''
160 FORMAT(f16.8,1X,f16.8,a9)
161 FORMAT(3(f16.8,1X),a9)
!
!
!
200 CONTINUE
molID = 0
Nspecies = 0
!Write atom positions
WRITE(40,'(a5)') 'Atoms'
WRITE(40,*) ''
!
IF( ALLOCATED(S) .AND. SIZE(S,1)==SIZE(P,1) ) THEN
  !Ion shells are present (core-shell model)
  !=> the format is described in Section How-to 25
  !   http://lammps.sandia.gov/doc/Section_howto.html#howto_25
  !
  PRINT*, "molID = ", molID
  PRINT*, "typecol = ", typecol
  !(1) Write positions of cores (atoms) and shells
  !    "atom-ID molecule-ID atom-type q x y z"
  j=0
  DO i=1,SIZE(Ppoint,1)
    j=j+1
    IF( molID>0 ) THEN
      moleculeID = NINT(AUX(i,molID))
    ELSE
      moleculeID = moleculeID+1
    ENDIF
    IF( q>0 ) THEN
      Qcore = AUX(i,q)
    ENDIF
    IF( qs>0 ) THEN
      Qshell = AUX(i,qs)
    ENDIF
    IF( typecol.NE.0 ) THEN
      !Atom types are in auxiliary properties, use it
      Nspecies = NINT(AUX(i,typecol))
    ELSE
      !Replace species by atom types in their order of appearance
      DO iloop=1,SIZE(atypes,1)
        IF( atypes(iloop,1)==INT(Ppoint(iloop,4)) ) Nspecies = j
      ENDDO
    ENDIF
    WRITE(40,212) j, moleculeID, Nspecies, Qcore, Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
    IF( NINT(S(i,4)) == NINT(P(i,4)) ) THEN
      j=j+1
      WRITE(40,212) j, moleculeID, Nspecies, Qshell, S(i,1), S(i,2), S(i,3)
    ENDIF
  ENDDO
  !(2) Write bond pairs with format "ID type atom1 atom2"
  WRITE(40,*) ''
  WRITE(40,'(a5)') 'Bonds'
  WRITE(40,*) ''
  !DO i=1,SIZE(BONDS,1)
    !WRITE(40,210) i, BONDS(i,1), BONDS(i,2), BONDS(i,3)
  !ENDDO
  !
ELSE
  IF( Ntypes>1 ) THEN
    IF( charges ) THEN
      !Atom charges are defined
      IF( typecol.NE.0 ) THEN
        !Atom types are in auxiliary properties, use it
        DO i=1,SIZE(Ppoint,1)
          WRITE(40,210) i, NINT(AUX(i,typecol)), AUX(i,q), Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
        ENDDO
        !
      ELSE
        !Replace species by atom types in their order of appearance
        DO i=1,SIZE(Ppoint,1)
          DO j=1,SIZE(atypes,1)
            IF( atypes(j,1)==INT(Ppoint(i,4)) ) Nspecies = j
          ENDDO
          WRITE(40,210) i, Nspecies, AUX(i,q), Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
        ENDDO
      ENDIF
      !
    ELSE
      !No atom charge defined
      IF( typecol.NE.0 ) THEN
        !Atom types are in auxiliary properties, use it
        DO i=1,SIZE(Ppoint,1)
          WRITE(40,211) i, NINT(AUX(i,typecol)), Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
        ENDDO
        !
      ELSE
        !Replace species by atom types in their order of appearance
        DO i=1,SIZE(Ppoint,1)
          DO j=1,SIZE(atypes,1)
            IF( atypes(j,1)==INT(Ppoint(i,4)) ) Nspecies = j
          ENDDO
          WRITE(40,211) i, Nspecies, Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
        ENDDO
      ENDIF
    ENDIF
    !
  ELSE
    Nspecies = 1 !only one type of atom
    !
    IF( charges ) THEN
      DO i=1,SIZE(Ppoint,1)
        !Format when atom charges are defined
        WRITE(40,210) i, Nspecies, AUX(i,q), Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
      ENDDO
      !
    ELSE
      DO i=1,SIZE(Ppoint,1)
        !Format when no atom charge is defined
        WRITE(40,211) i, Nspecies, Ppoint(i,1), Ppoint(i,2), Ppoint(i,3)
      ENDDO
    ENDIF
    !
  ENDIF
  !
ENDIF
210 FORMAT(i8,2X,i3,2X,f7.3,2X,3(f16.8,1X))
211 FORMAT(i8,2X,i3,2X,3(f16.8,1X))
212 FORMAT(i8,2X,i3,2X,i3,2X,f7.3,2X,3(f16.8,1X))
!
!Write velocities
IF( velocities ) THEN
  WRITE(40,*) ''
  WRITE(40,'(a10)') 'Velocities'
  WRITE(40,*) ''
  DO i=1,SIZE(Ppoint(:,1))
    WRITE(40,'(i8,2X,3(f16.8,1X))') i, AUX(i,vx), AUX(i,vy), AUX(i,vz)
  ENDDO
ENDIF
!
!Write shell positions (if any)
!IF( ALLOCATED(S) .AND. SIZE(S,1)>0 ) THEN
!  WRITE(40,*) ''
!  WRITE(40,'(a10)') 'Shells'
!  WRITE(40,*) ''
!  DO i=1,SIZE(S,1)
!    WRITE(40,'(i8,2X,3(f16.8,1X))') NINT(S(i,4)), (S(i,j), j=1,3)
!  ENDDO
!ENDIF
!
!
!
500 CONTINUE
CLOSE(40)
msg = "LAMMPS data"
temp = outputfile
CALL ATOMSK_MSG(3002,(/msg,temp/),(/0.d0/))
GOTO 1000
!
!
!
800 CONTINUE
!
!
!
1000 CONTINUE
IF(ALLOCATED(R)) DEALLOCATE(R)
!
END SUBROUTINE WRITE_LMP_DATA
!
END MODULE out_lammps_data
