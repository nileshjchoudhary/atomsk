PROGRAM atomsk
!
!**********************************************************************************
!*     o---o                                                         O            *
!*    o---o|                      A T O M S K                        |            *
!*    |   |o          Atom/Molecule/Material Software Kit           ,0;-o         *
!*    o---o           ===--=--------=--------=--------=--         o'   'O         *
!**********************************************************************************
!* This program is meant to convert many formats of files containing              *
!* atomic positions, into other formats. It can also perform some simple          *
!* transformations on atomistic systems.                                          *
!* Please read the contents of /doc for a detailed description.                   *
!**********************************************************************************
!* Version of the program: see "comv.f90"                                         *
!* (C) Feb. 2010 - Pierre Hirel                                                   *
!*     Unité Matériaux Et Transformations (UMET),                                 *
!*     Université de Lille 1, Bâtiment C6, F-59655 Villeneuve D'Ascq (FRANCE)     *
!*     pierre.hirel@univ-lille1.fr                                                *
!* Last modification: P. Hirel - 12 June 2014                                     *
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
!Load modules
USE comv        !common variables
USE constants   !math and physics constants
USE functions   !functions used by the program
USE messages
USE subroutines !subroutines for this program
USE readconf    !read the config file (atomsk.conf)
USE read_cla    !read command-line arguments
!
!Modules managing modes
USE modes
USE mode_interactive
!
!
!
!Declare variables
IMPLICIT NONE
CHARACTER(LEN=3):: outfileformat
CHARACTER(LEN=5),DIMENSION(:),ALLOCATABLE:: outfileformats !list of formats to write
CHARACTER(LEN=5):: zone
CHARACTER(LEN=8):: date
CHARACTER(LEN=10):: time
CHARACTER(LEN=12):: mode     !mode in which the program runs
CHARACTER(LEN=16):: helpsection
CHARACTER(LEN=128):: homedir  !home directory and .atomsk file
CHARACTER(LEN=128):: temp
CHARACTER(LEN=4096):: clarg
CHARACTER(LEN=16),DIMENSION(20):: opt_file !options read from a file
CHARACTER(LEN=4096),DIMENSION(5):: pfiles !pfiles(1)=file1
                                          !pfiles(2)=file2
                                          !pfiles(3)=filefirst
                                          !pfiles(4)=filesecond
                                          !pfiles(5)=listfile
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: options_array !options and their parameters
CHARACTER(LEN=4096),DIMENSION(:),ALLOCATABLE:: cla, cla_new  !command-line arguments
CHARACTER(LEN=128),DIMENSION(:),ALLOCATABLE:: mode_param  !parameters for some special modes
LOGICAL:: fileexists, logopened
INTEGER:: i, j, m, n, ioptions
INTEGER:: strlength
INTEGER,DIMENSION(8):: valuesi, valuesf !initial and final time
REAL(dp):: time_total
REAL(dp):: cpu_t1, cpu_t2
CALL CPU_TIME(cpu_t1)
!
!Get the current date and time
CALL DATE_AND_TIME(DATE, TIME, ZONE, VALUESi)
!VALUES(1): 	The year
!VALUES(2): 	The month
!VALUES(3): 	The day of the month
!VALUES(4): 	Time difference with UTC in minutes
!VALUES(5): 	The hour of the day
!VALUES(6): 	The minutes of the hour
!VALUES(7): 	The seconds of the minute
!VALUES(8): 	The milliseconds of the second
!
!
!Initialize variables
IF(ALLOCATED(options_array)) DEALLOCATE(options_array)
fileexists = .FALSE.
 clarg = ''
outfileformat=''
pfiles(:) = ''
strlength=0
nwarn = 0
nerr = 0
!
!Set default parameters of the program
lang = 'en'
langBigYes = "Y"
langyes = "y"
langno = "n"
logfile='atomsk.log'
helpsection = 'general'
i = IARGC()
IF(i==0) THEN
  mode='interactive'
ELSE
  mode='normal'
ENDIF
overw=.FALSE.  !By default, don't overwrite files
ignore=.FALSE. !By default, don't ignore files already converted
!Define the default level of verbosity:
!    0=silent; no message is ever displayed nor written in log file
!    1=all messages are written on the screen only.
!    2=all messages are written in log file only.
!    3=messages are written in log+screen.
!    4=debug, additional messages are written in log file.
!This default value should be set to 4 only for programming/debugging purposes
verbosity = 1
!
!
!Environment will be set at compilation time (use flag -cpp).
!When compiling for Microsoft Windows(R), use the flag -DWINDOWS
!otherwise UNIX/Linux setup will be assumed
#if defined(WINDOWS)
  !COMPILATION FOR MICROSOFT WINDOWS
  !Path separator is backslash
  pathsep = '\'
  !List command is "dir"
  system_ls = 'dir'
  !Set path of personal config file (%HOMEPATH%\atomsk.ini)
  CALL GET_ENVIRONMENT_VARIABLE('HOMEPATH',homedir)
  homedir = TRIM(ADJUSTL(homedir))//'\atomsk.ini'
#else
  !COMPILATION FOR UNIX OR Linux
  !Path separator is forward slash
  pathsep = '/'
  !List command will be "ls"
  system_ls = 'ls'
  !
  !Look for a system-wide config file (/etc/atomsk.conf)
  homedir = "/etc/atomsk.conf"
  INQUIRE(FILE=homedir,EXIST=fileexists)
  !If file exists, read parameters from it
  IF(fileexists) THEN
    CALL READ_CONF(homedir)
  ENDIF
  !
  !Set path to the user's personal config file
  !First, check if a directory for config files is defined
  CALL GET_ENVIRONMENT_VARIABLE('XDG_CONFIG_HOME',homedir)
  IF( LEN_TRIM(homedir)<=0 ) THEN
    !None is defined => default is ~/.config/
    CALL GET_ENVIRONMENT_VARIABLE('HOME',homedir)
    homedir = TRIM(ADJUSTL(homedir))//"/.config"
  ENDIF
  !Append name of config file (atomsk.conf)
  homedir = TRIM(ADJUSTL(homedir))//'/atomsk.conf'
  !
  !Detect environment language
  CALL GET_ENVIRONMENT_VARIABLE('LANG',clarg)
#endif
!
!At this point, clarg may contain the language environment variable
!Check if it is a recognizable language, otherwise use English
IF( INDEX(clarg,'fr').NE.0 .OR. INDEX(clarg,'FR').NE.0 ) THEN
  lang = 'fr'
ELSE
  lang = 'en'
ENDIF
!
!
!Read the user's config file (if it exists)
INQUIRE(FILE=homedir,EXIST=fileexists)
!If file exists, read parameters from it
IF(fileexists) THEN
  CALL READ_CONF(homedir)
ENDIF
!
!
!
100 CONTINUE
IF(IARGC()==0) THEN
  !If no command-line argument is specified at all then enter interactive mode
  mode = 'interactive'
  !In interactive mode verbosity cannot be 0 or 2
  !If it is the case, reset it to 1
  IF(verbosity==0 .OR. verbosity==2) verbosity=1
  !
  CALL INTERACT()
!
!
ELSE
  !Otherwise read command-line arguments
  !Array cla(:) will contain all command-line arguments
  ALLOCATE( cla(IARGC()) )
  cla(:) = ''
  !Copy command-line arguments to the array cla(:) and
  !find the size of the options_array(:) from the command-line options
  ioptions=0
  i=0
  j=0
  DO WHILE ( i<IARGC() )
    i=i+1 !index of actual command-line argument
    j=j+1 !index in cla(:)
    CALL GETARG(i,clarg)
    cla(j) = clarg
    !
    ! 'version', 'help', 'license' are special:
    !they print something and then exit the program
    IF(clarg=='--version' .OR. clarg=='-V') THEN
      CALL DISPLAY_COPYRIGHT()
      GOTO 1100
    ELSEIF(clarg=='--help' .OR. clarg=='help') THEN
      m=i+1
      CALL GETARG(m,clarg)
      READ(clarg,*,END=110,ERR=110) helpsection
      IF( helpsection.NE.'general' .AND. helpsection.NE.'modes' .AND.   &
        & helpsection.NE.'options' .AND. helpsection.NE.'formats'     ) &
        & helpsection='general'
      110 CONTINUE
      CALL DISPLAY_HELP(helpsection)
      GOTO 1100
    ELSEIF(clarg=='--license' .OR. clarg=='--licence') THEN
      CALL DISPLAY_LICENSE()
      GOTO 1100
    !
    !Deal with the behavior of the program
    ELSEIF(clarg=='-ignore' .OR. clarg=='-ig') THEN
      ignore = .TRUE.
    ELSEIF(clarg=='-overwrite' .OR. clarg=='-ow') THEN
      overw = .TRUE.
    ELSEIF(clarg=='-verbosity' .OR. clarg=='-v') THEN
      m=i+1
      CALL GETARG(m,clarg)
      READ(clarg,*,END=120,ERR=120) verbosity
    ELSEIF(clarg=='-log') THEN
      m=i+1
      CALL GETARG(m,clarg)
      logfile = TRIM(ADJUSTL(clarg))
      IF(logfile=='') logfile='atomsk.log'
    ELSEIF(clarg=='-lang' .OR. clarg=='-language') THEN
      m=i+1
      CALL GETARG(m,clarg)
      READ(clarg,*,END=120,ERR=120) lang
    !
    ELSEIF(clarg=="-options" .OR. clarg=="-option" .OR. clarg=="-opt") THEN
      !Read options from a file
      i=i+1
      CALL GETARG(i,clarg)
      CALL CHECKFILE( clarg, "read" )
      j=j-1  !the command-line argument "-options <file>" will be replaced by options/arguments read from the file
      OPEN(UNIT=31,FILE=clarg,FORM="FORMATTED",STATUS="OLD")
      DO
        opt_file(:) = ''
        READ(31,'(a128)',ERR=115,END=115) temp
        temp = ADJUSTL(temp)
        !Ignore empty lines and lines starting with dash sign
        !Also ignore lines that use the keyword "options" (no redundancy here)
        IF( LEN_TRIM(temp)>0 .AND. temp(1:1).NE."#" .AND. temp(1:7).NE."options" .AND. temp(1:7).NE."-options" ) THEN
          n=0
          !Read option name and parameters
          DO WHILE (LEN_TRIM(temp).NE.0)
            n=n+1
            strlength = SCAN( temp , " " )
            opt_file(n) = temp(1:strlength)
            temp = ADJUSTL( temp(LEN_TRIM(opt_file(n))+1:) )
          ENDDO
          !
          !The option and its arguments are now in opt_file(:)
          !=> store them in cla(:)
          IF(ALLOCATED(cla_new)) DEALLOCATE(cla_new)
          IF( j+2==i ) THEN
            !Current option is the first one read from file
            !=> the two arguments "-option <file>" must be removed from cla(:)
            ALLOCATE(cla_new(SIZE(cla)+n-2))
          ELSE
            !Current option is not the first one => it comes after previous option
            ALLOCATE(cla_new(SIZE(cla)+n))
          ENDIF
          cla_new(:) = ""
          !Store command-line arguments preceeding "-options" at the beginning of cla_new(:)
          DO m=1,j
            cla_new(m) = cla(m)
          ENDDO
          !Store option read from the file in cla_new(:)
          ioptions=ioptions+1
          n=1
          DO WHILE (LEN_TRIM(opt_file(n)).NE.0)
            j=j+1
            cla_new(j) = opt_file(n)
            n=n+1
          ENDDO
          DEALLOCATE(cla)
          ALLOCATE(cla(SIZE(cla_new)))
          cla(:) = cla_new(:)
          DEALLOCATE(cla_new)
        ENDIF
      ENDDO
      115 CONTINUE
      CLOSE(31)
    !
    !If it was none of the above but starts with a (-)
    !then it is most probably an option
    ELSEIF(clarg(1:1)=='-' .AND. clarg(1:2).NE.'--') THEN
      ioptions=ioptions+1
    !
    ENDIF
    120 CONTINUE
  ENDDO
  !
  !If the user specified an alternate logfile, change the level of verbosity to 3
  IF( logfile.NE.'atomsk.log' .AND. (verbosity==0 .OR. verbosity==1) ) THEN
    verbosity = 3
  ENDIF
  !
  IF(verbosity<2) THEN
    !Low verbosity: no logfile is written, unit 20 is used as a virtual logfile
    OPEN(UNIT=20,STATUS='SCRATCH',FORM='FORMATTED')
  ELSE
    !High verbosity: logfile is written (and replaced if one already exists)
    OPEN(UNIT=20,FILE=logfile,STATUS='REPLACE',FORM='FORMATTED')
  ENDIF
  !
  !Allocate array for the options; this array will be
  !filled by the routine "GET_CLA" below
  ALLOCATE(options_array(ioptions))
  options_array(:) = ''
  !
  !
  !Print a nice message
  CALL DISPLAY_HEADER()
  CALL DATE_MSG()
  !
  !
  !!Read command-line options and try to understand them
  CALL GET_CLA(cla,mode,options_array,outfileformats,pfiles,mode_param)
  IF(ALLOCATED(cla)) DEALLOCATE(cla)
  IF(nerr>0) GOTO 500
  !
  !
  !
  200 CONTINUE
  !Deal with options that are not compatible
  !Cannot both ignore and overwrite existing files: set overwrite to false
  IF(overw.AND.ignore) overw=.FALSE.
  !
  !Then deal with the different modes
  CALL RUN_MODE(mode,options_array,outfileformats,pfiles,mode_param)
  !
ENDIF  !endif IARGC()==0
!
!
!
500 CONTINUE
!Terminating program
CALL ATOMSK_MSG(1,(/''/),(/0.d0/))
!
!
!
1000 CONTINUE
!Get the current date and time
CALL DATE_AND_TIME(DATE, TIME, ZONE, VALUESf)
!Compute the difference with previous time
VALUESf(:) = VALUESf(:) - VALUESi(:)
!Total time may not be correct when passing midnight and changing month,
!but what are the odds anyway? Give me a break.
time_total = 86400.d0*DBLE(VALUESf(3)) + &
           & 3600.d0*DBLE(VALUESf(5)) + 60.d0*DBLE(VALUESf(6)) + &
           & DBLE(VALUESf(7)) + 1.d-3*DBLE(VALUESf(8))
CALL CPU_TIME(cpu_t2)
 cpu_t2 = cpu_t2 - cpu_t1
CALL ATOMSK_MSG(2,(/''/),(/time_total, cpu_t2/))
!
!
1100 CONTINUE
!Free memory
IF(ALLOCATED(options_array)) DEALLOCATE(options_array)
!Close logfile (if opened)
INQUIRE(UNIT=20,OPENED=logopened)
IF(logopened) CLOSE(20)
!
!
!
END PROGRAM atomsk
