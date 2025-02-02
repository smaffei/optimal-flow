MODULE OPTIMISATION_BOUND
   USE SUBS

CONTAINS

   SUBROUTINE CALCULATE_OPTIMAL_FLOW(GAUSS, &
                                     SPEC_U_TOR, &
                                     SPEC_U_POL, &
                                     OBS_COLAT, &
                                     OBS_LONG, &
                                     PHI_OBS, &
                                     LMAX_U, &
                                     LMAX_B_OBS, &
                                     FILENAME, &
                                     TARGET_RMS, &
                                     SCALE_FACTOR, &
                                     RESTRICTION, &
                                     ETA, &
                                     MINIM_FLAG)
      IMPLICIT NONE

!-----------------------------------------------------------------------------
! Computes flows that optimises the specified geomagnetic quantity from a
! background magnetic field defined (assumed in nT) by the Gauss coefficients
! found in FILENAME
!
! INPUTS:
!   OBS_COLAT, OBS_LONG:  colatitude and longitude of the observation/optimisation 
!                         location
!   PHI_OBS:              OBS_LONG * Pi / 180.0_8
!   LMAX_U:               max spherical harmonics degree for the optimal flow
!   LMAX_B_OBS:           max spherical harmonics degree for the background
!                         magnetic field. If more degrees are available in FILENAME,
!                         they are disregarded
!   FILENAME:             full path to the file containing the Gauss coefficients
!                         describing the background magnetic field
!                         format: l m g_lm h_lm
!   TARGET_RMS:           rms flow speed (in km/yr)
!   SCALE_FACTOR:         scale factor for arrows, used to prepare a flow file (FLOW.DAT)
!                         readable by GMT
!                         With SCALE_FACTOR = 5e-2: 20km/yr gives 1cm (factor of 1/20 = 5e-2)
!   RESTRICTION:          flow geometry restriction:
!                         0: unrestricted
!                         1: poloidal
!                         2: toroidal
!                         3: columnar (equatorially symmetric)
!   ETA:                  magnetic diffusivity (in m^2/s)
!   MINIM_FLAG:           based on this value, the rate-of-change of specific 
!                         pre-coded quantity is optimised:
!                         0: dipole tilt
!                         1: magnetic field intensity at OBS location
!                         2: magnetic field intensity at the intensity minimum (e.g. SAA)
!                         3: declination at OBS location
!                         4: axial dipole coefficient g_1^0
!                         5: inclination at OBS location
!                         6: g_1^1
!                         7: VGP latitude
!                         
! OUTPUTS:
! (not really used for the instantaneous optimisation but will be used for the code that implements 
!  temporal integration of the background magnetic field)
!   GAUSS:                Gauss coefficient of the background magnetic field
!   SPEC_U_TOR:           spectral coefficients of the optimal toroidal flow component
!   SPEC_U_POL:           spectral coefficients of the optimal poloidal flow component
!   
!
! OUTPUT FILES:
!   D_CS_CENTRED.DAT:     declination at grid locations at the CMB
!   D_DOT_CS_CENTRED.DAT: declination variations (driven by the optimal solution) 
!                         at grid locations at the CMB
!   D_DOT_ES.DAT:         declination variations (driven by the optimal solution) 
!                         at grid locations at the Earth's surface
!   D_DOT_ES_CENTRED.DAT: same as D_DOT_ES.DAT, but the longitude is displayed
!                         from -180 rather than 0
!   D_ES.DAT:             declination at grid locations at the Earth's surface
!   D_ES_CENTRED.DAT:     same as D_ES.DAT, but the longitude is displayed
!                         from -180 rather than 0
!   FLOW.DAT:             optimal flow (in km/yr) in a format that GMT can read. 
!                         format: lon lat flow direction flow intensity
!   FLOW_L_SPEC.DAT:      Kinetic Energy spectrum per spherical harmonic degree l
!                         (in km/yr^2)
!   FLOW_VECTORS_CENTRED.DAT: optimal flow (in km/yr) on a regular grid
!                             format: lon lat u_theta u_phi
!   FLOW_VECTORS_RANDOM.DAT:  optimal flow (in km/yr) on a random grid (better
!                             for plotting with a quiver plot)
!                             format: lon lat u_theta u_phi
!   F_CS_CENTRED.DAT:     magnetic field intensity (in nT) at grid locations at the CMB
!   F_DOT_CS_CENTRED.DAT: magnetic field intensity variation (driven by the 
!                         optimal solution, in nT/yr) at grid locations at the CMB
!   F_DOT_ES.DAT:         magnetic field intensity variation (driven by the 
!                         optimal solution, in nT/yr) at grid locations at the Earth's surface
!   F_DOT_ES_CENTRED.DAT: same as F_DOT_ES.DAT, but the longitude is displayed
!                         from -180 rather than 0
!   F_ES.DAT:             magnetic field intensity (in nT) at grid locations at the
!                         Earth's surface
!   F_ES_CENTRED.DAT:     same as F_ES.DAT, but the longitude is displayed
!                         from -180 rather than 0
!   G_POL.DAT:            elements of the G vector from the poloidal flow components
!   G_TOR.DAT:            elements of the G vector from the toroidal flow components
!   HARMONICS.DAT:        auxilliary file that the code uses to store spherical harmonic indexes
!                         format: l m cos/sin
!   OPTIMAL_FLOW.DAT:     optimal flow coefficients
!                         format: l m POL(COS) POL(SIN) TOR(COS) TOR(SIN)
!   OPTIMISED_QUANTITY_DOT.DAT: optimal rate of change of the quantity selected with MINIM_FLAG
!-----------------------------------------------------------------------------

      REAL(KIND=EXTRA_LONG_REAL), ALLOCATABLE, INTENT(OUT) :: SPEC_U_TOR(:), SPEC_U_POL(:)
      REAL(KIND=EXTRA_LONG_REAL), ALLOCATABLE, DIMENSION(:), INTENT(OUT) :: GAUSS

      REAL(KIND=LONG_REAL), INTENT(INOUT) ::OBS_COLAT, OBS_LONG, PHI_OBS
      REAL(KIND=LONG_REAL) :: VALUE(2)

      INTEGER, INTENT(IN) :: LMAX_B_OBS, LMAX_U, RESTRICTION, MINIM_FLAG
      
      CHARACTER(300), INTENT(IN) :: FILENAME
      
      REAL(KIND=8), INTENT(IN) :: SCALE_FACTOR, TARGET_RMS, ETA

      TYPE(HARMONIC_STRUCTURE), ALLOCATABLE, DIMENSION(:) :: HARMONICS

      
      REAL(KIND=EXTRA_LONG_REAL) :: B_LOCATION(3), THETA, PHI, X, P
      REAL(KIND=EXTRA_LONG_REAL) :: DP_DT, DI_LOC_DT, DD_LOC_DT

      INTEGER :: L, M, SINCOS, POLTOR, IOS, LMAX_FILE, NP, i, HARMONIC, LMAX_SV, NTHETA_GRID, &
                 NPHI_GRID, I_PHI, I_THETA, NUM_LEGENDRE_SV, INDEX_PLM, J, HARMONIC_TYPE, INDEX
      INTEGER :: MIN_LOC(2)

      CHARACTER(300) ::  JUNK
      
      CHARACTER(1) :: STRING_HARM_TYPE2

      REAL(KIND=EXTRA_LONG_REAL), ALLOCATABLE, DIMENSION(:) :: TOR_U, POL_U, POL_B_DOT, LEGENDRE_GAUW, COSTHETA_GRID
      REAL(KIND=EXTRA_LONG_REAL), ALLOCATABLE, DIMENSION(:, :)  ::  TEMP_THETA_TRANSFORM_DALF, TEMP_THETA_TRANSFORM_ALF

      REAL(KIND=EXTRA_LONG_REAL), ALLOCATABLE :: GRAD_H_B_R(:, :, :), B_R(:, :), DIV_H_U_H(:, :), U_H(:, :, :), &
                                                 ALF_LOCATION(:, :), DALF_LOCATION(:, :), ALF(:, :), DALF(:, :), &
                                                 B_R_DOT(:, :), SPEC(:), LEGENDRE_INV(:, :), ONE_DIV_SIN_THETA(:), &
                                                 EVEC_TOR(:), EVEC_POL(:), FLOW_L_SPEC(:), G(:, :), &
                                                 NABLA2_B_R(:, :), GAUSS_HD(:), &
                                                 B_R_SURF(:, :), B_T_SURF(:, :), B_P_SURF(:, :), F_SURF(:, :)

      REAL(KIND=EXTRA_LONG_REAL) :: COSTHETA_LOC, SINTHETA_LOC, PHI_DEP, DERV_PHI_DEP, B_DOT_LOCATION(3), F_LOC, D_LOC, I_LOC
      REAL(KIND=EXTRA_LONG_REAL) :: LOCATIONS(1), NORM_G

      REAL(KIND=LONG_REAL) :: KE, KE_TOR, KE_POL, TOTAL_RMS, OPT_RATE, NORM_FACTOR, TILT
      REAL(KIND=LONG_REAL) :: DIFFUSION, FACTOR, INCLINATION

      ! Read in Gauss coefficients for field.

      OPEN (11, FILE=FILENAME, STATUS='OLD', FORM='FORMATTED', &
            IOSTAT=IOS, ACTION='READ')
      IF (IOS .NE. 0) THEN
         PRINT *, 'ERROR IN OPENING FILE ', FILENAME
         STOP
      END IF

      NP = LMAX_B_OBS*(LMAX_B_OBS + 2)
      IF (ALLOCATED(GAUSS)) DEALLOCATE (GAUSS)
      ALLOCATE (GAUSS(1:NP))
      GAUSS(:) = 0.0_EXTRA_LONG_REAL
      READ (11, *) JUNK
      J = 1
      DO
         READ (11, *, END=1001) L, M, VALUE(1), VALUE(2)
         IF (M .NE. 0) THEN
            GAUSS(J) = VALUE(1)
            GAUSS(J + 1) = VALUE(2)
            J = J + 2
         ELSE
            GAUSS(J) = VALUE(1)
            J = J + 1
         END IF
         IF (J > NP) EXIT
      END DO
1001  CONTINUE

      CLOSE (11)

      IF (L .LT. LMAX_B_OBS) THEN
         WRITE (6, '(A)') '********************'
         WRITE (6, '(A)') 'FIELD MODEL FILE CONTAINS TOO FEW COEFFICIENTS.'
         WRITE (6, '(A,I4,A,I4)') 'LMAX REQUIRED: ', LMAX_B_OBS, ' LMAX IN FILE: ', L
         WRITE (6, '(A)') 'FIELD MODEL IS PADDED WITH ZEROS.'
         WRITE (6, '(A)') '********************'
      END IF

      ! Cheching the original input
      ! PRINT *, 'g10, g11, h11 are', GAUSS(1), GAUSS(2), GAUSS(3)
      ! TILT = ACOS(GAUSS(1)/SQRT(GAUSS(1)**2 + GAUSS(2)**2 + GAUSS(3)**2))
      ! WRITE (6, '(A,x,x,F15.6)') 'DIPOLE TILT (in radians)', TILT

      ! only one set of harmonic coefficients are required - the SV coefficients which have the highest truncation. Those for B[obs] and u are simply just the first section of the coefficients.
      LMAX_SV = LMAX_U + LMAX_B_OBS
      ALLOCATE (HARMONICS(1:LMAX_SV*(LMAX_SV + 2)))
      HARMONIC = 1
      DO L = 1, LMAX_SV
      DO M = 0, L
      DO SINCOS = COSINE_HARMONIC, SINE_HARMONIC  !cos is 1, sin is 2.
         IF (M .eq. 0 .AND. SINCOS .eq. 2) CYCLE
         HARMONICS(HARMONIC)%M = M
         HARMONICS(HARMONIC)%SINCOS = SINCOS
         HARMONICS(HARMONIC)%L = L
         HARMONIC = HARMONIC + 1
      END DO
      END DO
      END DO

      OPEN (21, FILE='HARMONICS.DAT', FORM='FORMATTED', STATUS='REPLACE')
      DO I = 1, LMAX_SV*(LMAX_SV + 2)
         IF (HARMONICS(I)%SINCOS .eq. COSINE_HARMONIC) WRITE (STRING_HARM_TYPE2, '(A)') 'C'
         IF (HARMONICS(I)%SINCOS .eq. SINE_HARMONIC) WRITE (STRING_HARM_TYPE2, '(A)') 'S'

         WRITE (21, '(i3,3x, i3, 3x, A1)') &
            HARMONICS(I)%L, HARMONICS(I)%M, STRING_HARM_TYPE2
      END DO
      CLOSE (21)

      NUM_LEGENDRE_SV = (LMAX_SV + 1)*(LMAX_SV + 2)/2
      NTHETA_GRID = LMAX_SV + 1  !The maximum degree of the colatitude-integrand is Lmax_B_OBS + Lmax_u + Lmax_sv = 2 * Lmax_sv. So number of pts is 1/2 ( 2 * Lmax_sv ) + 1.
      NPHI_GRID = 3*LMAX_SV + 1 !(using the usual 3/2 rule).

      IF (ALLOCATED(FFT_TRANSFORM_ARRAY)) DEALLOCATE (FFT_TRANSFORM_ARRAY)
      ALLOCATE (FFT_TRANSFORM_ARRAY(1:NTHETA_GRID, 0:NPHI_GRID - 1))

      ! FFTs in PHI, REAL to Half complex
      CALL DFFTW_PLAN_MANY_R2R(PLAN_FFT_R2HC, &  ! PLAN
                               1, &  ! Rank of transforms
                               NPHI_GRID, &  ! size of each transform
                               NTHETA_GRID, &  ! how many
                               FFT_TRANSFORM_ARRAY, &  ! Input array
                               SIZE(FFT_TRANSFORM_ARRAY), &  ! subset size of transform (whole set)
                               NTHETA_GRID, &  ! Stride for transform
                               1, &  ! Gap between transforms in array
                               FFT_TRANSFORM_ARRAY, &  ! Output array
                               SIZE(FFT_TRANSFORM_ARRAY), &  ! subset size of output array
                               NTHETA_GRID, &  ! output stride
                               1, &  ! Gap between outputs for transforms.
                               FFTW_R2HC, TRANSFORM_OPTIMISATION)                        ! Transform type; flags

      ALLOCATE (COSTHETA_GRID(NTHETA_GRID), &
                LEGENDRE_GAUW(NTHETA_GRID), &
                ALF(NTHETA_GRID, NUM_LEGENDRE_SV), &
                DALF(NTHETA_GRID, NUM_LEGENDRE_SV), &
                TEMP_THETA_TRANSFORM_DALF(NTHETA_GRID, NUM_LEGENDRE_SV), &
                TEMP_THETA_TRANSFORM_ALF(NTHETA_GRID, NUM_LEGENDRE_SV), &
                LEGENDRE_INV(NTHETA_GRID, NUM_LEGENDRE_SV), &
                ONE_DIV_SIN_THETA(1:NTHETA_GRID))

      ! Evaluate B_r and its horizontal derivative on (theta, phi) grid
      CALL GAUWTS(NTHETA_GRID, COSTHETA_GRID, LEGENDRE_GAUW)

      ! Get the Associated Legendre Functions (ALF) at the theta grid points, with their theta derivatives (DALF), of the ALF's up to degree LMAX_PRECOMP
      CALL GET_LEGENDRE_FUNCTIONS(REAL(COSTHETA_GRID, KIND=EXTRA_LONG_REAL), &
                                  LMAX_SV, &
                                  LMAX_SV, &
                                  TEMP_THETA_TRANSFORM_ALF, &
                                  TEMP_THETA_TRANSFORM_DALF)

      ALF = REAL(TEMP_THETA_TRANSFORM_ALF, KIND=8)
      DALF = REAL(TEMP_THETA_TRANSFORM_DALF, KIND=8)
      ONE_DIV_SIN_THETA(:) = 1.0_LONG_REAL/SQRT(1.0_LONG_REAL - COSTHETA_GRID(:)**2)
      DEALLOCATE (TEMP_THETA_TRANSFORM_DALF, TEMP_THETA_TRANSFORM_ALF)

      DO I = 1, NUM_LEGENDRE_SV
         LEGENDRE_INV(1:NTHETA_GRID, I) = ALF(1:NTHETA_GRID, I)*LEGENDRE_GAUW(1:NTHETA_GRID)
      END DO

      ALLOCATE (B_R_DOT(NTHETA_GRID, 0:NPHI_GRID - 1), SPEC(1:LMAX_SV*(LMAX_SV + 2)))
      ALLOCATE (GAUSS_HD(1:LMAX_B_OBS*(LMAX_B_OBS + 2)))

      ALLOCATE (B_R(1:NTHETA_GRID, 0:NPHI_GRID - 1), &
                GRAD_H_B_R(1:NTHETA_GRID, 0:NPHI_GRID - 1, 2), &
                NABLA2_B_R(1:NTHETA_GRID, 0:NPHI_GRID - 1))

      CALL EVALUATE_B_R_GRID(NTHETA_GRID, &
                             NPHI_GRID, &
                             GAUSS, &
                             HARMONICS, &
                             LMAX_B_OBS, &
                             LMAX_SV, &
                             B_R, &
                             GRAD_H_B_R, &
                             ALF, &
                             DALF, &
                             ONE_DIV_SIN_THETA)

      ALLOCATE (U_H(1:NTHETA_GRID, 0:NPHI_GRID - 1, 2), DIV_H_U_H(1:NTHETA_GRID, 0:NPHI_GRID - 1))

      ! IF I WANT TO OPTIMIZE THE INTENSITY OF THE SAA I NEED TO OVERWRITE SOME THINGS
      IF (MINIM_FLAG .EQ. 2) THEN
         ! find intensity minimum location and define it as LOCATION

         ALLOCATE (B_R_SURF(1:NTHETA_GRID, 0:NPHI_GRID - 1), &
                   B_T_SURF(1:NTHETA_GRID, 0:NPHI_GRID - 1), &
                   B_P_SURF(1:NTHETA_GRID, 0:NPHI_GRID - 1), &
                   F_SURF(1:NTHETA_GRID, 0:NPHI_GRID - 1))

         CALL EVALUATE_B_SURF_GRID(NTHETA_GRID, &
                                   NPHI_GRID, &
                                   GAUSS, &
                                   HARMONICS, &
                                   LMAX_B_OBS, &
                                   LMAX_SV, &
                                   B_R_SURF, &
                                   B_T_SURF, &
                                   B_P_SURF, &
                                   ALF, &
                                   DALF, &
                                   ONE_DIV_SIN_THETA)

         F_SURF = SQRT(B_R_SURF**2 + B_T_SURF**2 + B_P_SURF**2)
         MIN_LOC = MINLOC(F_SURF)
         OBS_COLAT = 180.0_LONG_REAL - MIN_LOC(1)*180.0_LONG_REAL/REAL(NTHETA_GRID, KIND=LONG_REAL) ! COLAT = 0 is the North pole
         OBS_LONG = MIN_LOC(2)*360.0_LONG_REAL/REAL(NPHI_GRID, KIND=LONG_REAL)
         PHI_OBS = OBS_LONG*Pi/180.0_8
      END IF

      COSTHETA_LOC = COS(OBS_COLAT*Pi/180.0_8)
      SINTHETA_LOC = SIN(OBS_COLAT*Pi/180.0_8)
      LOCATIONS(1) = REAL(COSTHETA_LOC, KIND=EXTRA_LONG_REAL)

      ALLOCATE (ALF_LOCATION(1, 1:NUM_LEGENDRE_SV), &
                DALF_LOCATION(1, 1:NUM_LEGENDRE_SV), &
                TEMP_THETA_TRANSFORM_DALF(1, 1:NUM_LEGENDRE_SV), &
                TEMP_THETA_TRANSFORM_ALF(1, 1:NUM_LEGENDRE_SV))

      CALL GET_LEGENDRE_FUNCTIONS(LOCATIONS, LMAX_SV, LMAX_SV, TEMP_THETA_TRANSFORM_ALF, TEMP_THETA_TRANSFORM_DALF)

      ALF_LOCATION = REAL(TEMP_THETA_TRANSFORM_ALF, KIND=8)
      DALF_LOCATION = REAL(TEMP_THETA_TRANSFORM_DALF, KIND=8)
      DEALLOCATE (TEMP_THETA_TRANSFORM_DALF, TEMP_THETA_TRANSFORM_ALF)

      ! Loop over each component of u and transform
      ALLOCATE (G(1:LMAX_U*(LMAX_U + 2), 1:2))
      DO HARMONIC_TYPE = 1, 2 ! Looks like it's toroidal first and poloidal afters
      DO HARMONIC = 1, LMAX_U*(LMAX_U + 2)

         ! Evaluate u_h and its horizontal divergence on (theta, phi) grid
         CALL EVALUATE_U_H_SINGLE_HARMONIC(NTHETA_GRID, &
                                           NPHI_GRID, &
                                           HARMONIC, &
                                           HARMONIC_TYPE, &
                                           U_H, &
                                           DIV_H_U_H, &
                                           ALF, &
                                           DALF, &
                                           HARMONICS, &
                                           LMAX_SV, &
                                           ONE_DIV_SIN_THETA, &
                                           COSTHETA_GRID)

         ! Transform to spherical harmonic decomposition
         DO I_THETA = 1, NTHETA_GRID
         DO I_PHI = 0, NPHI_GRID - 1
            B_R_DOT(I_THETA, I_PHI) = -U_H(I_THETA, I_PHI, 1)*GRAD_H_B_R(I_THETA, I_PHI, 1) - &
                                      U_H(I_THETA, I_PHI, 2)*GRAD_H_B_R(I_THETA, I_PHI, 2) - &
                                      B_R(I_THETA, I_PHI)*DIV_H_U_H(I_THETA, I_PHI)
         END DO
         END DO

         CALL REAL_2_SPEC(B_R_DOT, &
                          SPEC, &
                          LMAX_SV, &
                          LMAX_B_OBS + HARMONICS(HARMONIC)%L, &
                          HARMONICS, &
                          NPHI_GRID, &
                          NTHETA_GRID, &
                          LEGENDRE_INV)

         ! Extrapolate to observation point and evaluate the entry of matrix G.

         B_DOT_LOCATION(1:3) = 0.0_EXTRA_LONG_REAL
         B_LOCATION(1:3) = 0.0_EXTRA_LONG_REAL

         DO I = 1, LMAX_SV*(LMAX_SV + 2)
            ! evaluate B_r at Earth surface
            IF (HARMONICS(I)%SINCOS .EQ. SINE_HARMONIC) THEN
               PHI_DEP = SIN(HARMONICS(I)%M*PHI_OBS)
               DERV_PHI_DEP = HARMONICS(I)%M*COS(HARMONICS(I)%M*PHI_OBS)
            ELSE
               PHI_DEP = COS(HARMONICS(I)%M*PHI_OBS)
               DERV_PHI_DEP = -HARMONICS(I)%M*SIN(HARMONICS(I)%M*PHI_OBS)
            END IF

            INDEX_PLM = HARMONICS(I)%M*LMAX_SV + (HARMONICS(I)%M*(3 - HARMONICS(I)%M))/2 + 1 + (HARMONICS(I)%L - HARMONICS(I)%M)
            B_DOT_LOCATION(1) = B_DOT_LOCATION(1) + &
                                SPEC(I)*(CMB_RADIUS/ES_RADIUS)**(HARMONICS(I)%L + 2)*ALF_LOCATION(1, INDEX_PLM)*PHI_DEP    !/ (HARMONICS(I)%L + 1). No extra factors as they cancel out.
            B_DOT_LOCATION(2) = B_DOT_LOCATION(2) - &
                                SPEC(I)*(CMB_RADIUS/ES_RADIUS)**(HARMONICS(I)%L + 2)* &
                                DALF_LOCATION(1, INDEX_PLM)*PHI_DEP/(HARMONICS(I)%L + 1)
            B_DOT_LOCATION(3) = B_DOT_LOCATION(3) - &
                                SPEC(I)*(CMB_RADIUS/ES_RADIUS)**(HARMONICS(I)%L + 2)* &
                                ALF_LOCATION(1, INDEX_PLM)*DERV_PHI_DEP/SINTHETA_LOC/(HARMONICS(I)%L + 1)

            IF (HARMONICS(I)%L .LE. LMAX_B_OBS) THEN !SV goes to higher L than B[obs], so exclude if index goes higher than required.
               B_LOCATION(1) = B_LOCATION(1) + &
                               GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*PHI_DEP*REAL(HARMONICS(I)%L + 1, KIND=LONG_REAL)   ! B_r
               B_LOCATION(2) = B_LOCATION(2) - &
                               GAUSS(I)*DALF_LOCATION(1, INDEX_PLM)*PHI_DEP  ! B_theta
               B_LOCATION(3) = B_LOCATION(3) - &
                               GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*DERV_PHI_DEP/SINTHETA_LOC ! B_phi
            END IF

         END DO

         ! ***********************************************
         ! Change the  definition of G
         ! ***********************************************
         I_LOC = ATAN(-B_LOCATION(1)/SQRT(B_LOCATION(2)**2 + B_LOCATION(3)**2))
         ! if we want to optimize for the rate of change of declination:
         D_LOC = atan2(B_LOCATION(3), -B_LOCATION(2))
         !    G( HARMONIC, HARMONIC_TYPE ) = (B_DOT_LOCATION(2) * B_LOCATION(3) - B_DOT_LOCATION(3) * B_LOCATION(2)) / ((B_LOCATION(2) * B_LOCATION(2)) + (B_LOCATION(3) * B_LOCATION(3)))

         F_LOC = SQRT(SUM(B_LOCATION**2))
         NORM_G = (GAUSS(1)**2 + GAUSS(2)**2 + GAUSS(3)**2)*SQRT(GAUSS(2)**2 + GAUSS(3)**2)

         IF (MINIM_FLAG .EQ. 0) THEN
            ! if we want to optimize for the rate of change of dipole tilt:
            G(HARMONIC, HARMONIC_TYPE) = 0.5*(CMB_RADIUS/ES_RADIUS)**3* &
                                         (SPEC(2)*GAUSS(1)*GAUSS(2) + &
                                          SPEC(3)*GAUSS(1)*GAUSS(3) - &
                                          SPEC(1)*(GAUSS(2)**2 + GAUSS(3)**2))/ &
                                         NORM_G
         ELSE IF ((MINIM_FLAG .EQ. 1) .OR. (MINIM_FLAG .EQ. 2)) THEN
            ! if we want to optimize for the rate of change of intensity:
            G(HARMONIC, HARMONIC_TYPE) = SUM(B_DOT_LOCATION(:)*B_LOCATION(:))/F_LOC
         ELSE IF ((MINIM_FLAG .EQ. 3)) THEN
            ! if we want to optimize for the rate of change of declination at LOCATION:
            G(HARMONIC, HARMONIC_TYPE) = (B_DOT_LOCATION(2)*B_LOCATION(3) - B_DOT_LOCATION(3)*B_LOCATION(2))/ &
                                         ((B_LOCATION(2)*B_LOCATION(2)) + (B_LOCATION(3)*B_LOCATION(3)))
         ELSE IF ((MINIM_FLAG .EQ. 4)) THEN
            ! if we want to optimise the rate of change of g10
            G(HARMONIC, HARMONIC_TYPE) = 0.5*(CMB_RADIUS/ES_RADIUS)**3*SPEC(1) !* (3 / 4.0_LONG_REAL / Pi)
         ELSE IF ((MINIM_FLAG .EQ. 5)) THEN
            ! if we want to optimise the rate of change of inclination at LOCATION
            G(HARMONIC, HARMONIC_TYPE) = (B_DOT_LOCATION(2)*B_LOCATION(2)*B_LOCATION(1) + &
                                          B_DOT_LOCATION(3)*B_LOCATION(3)*B_LOCATION(1) - &
                                          B_DOT_LOCATION(1)*(B_LOCATION(2)**2 + B_LOCATION(3)**2))/ &
                                         (F_LOC**2*SQRT(B_LOCATION(2)**2 + B_LOCATION(3)**2))
         ELSE IF ((MINIM_FLAG .EQ. 6)) THEN
            ! OPTIMIZE G11
            G(HARMONIC, HARMONIC_TYPE) = 0.5*(CMB_RADIUS/ES_RADIUS)**3*SPEC(2) !* (3 / 4.0_LONG_REAL / Pi)
         ELSE IF ((MINIM_FLAG .EQ. 7)) THEN
            ! OPTIMIZE VGP LATITUDE
            ! GREAT CIRLCE DISTANCE TO VGP
            P = ATAN(2/TAN(I_LOC))
            IF (P .LT. 0) THEN
               P = P + Pi
            END IF
            ! RATE OF CHANGE OF INCLINATION
            DI_LOC_DT = (B_DOT_LOCATION(2)*B_LOCATION(2)*B_LOCATION(1) + B_DOT_LOCATION(3)*B_LOCATION(3)*B_LOCATION(1) &
                         - B_DOT_LOCATION(1)*(B_LOCATION(2)**2 + B_LOCATION(3)**2)) &
                        /(F_LOC**2*SQRT(B_LOCATION(2)**2 + B_LOCATION(3)**2))
            ! RATE OF CHANGE OF DECLINATION
            DD_LOC_DT = (B_DOT_LOCATION(2)*B_LOCATION(3) - B_DOT_LOCATION(3)*B_LOCATION(2))/ &
                        ((B_LOCATION(2)*B_LOCATION(2)) + (B_LOCATION(3)*B_LOCATION(3)))
            ! DP/DT
            DP_DT = -2*DI_LOC_DT/(1 + 3*COS(I_LOC)**2)
            ! AUXILLIARY QUANTITY
            X = COSTHETA_LOC*COS(P) + SINTHETA_LOC*SIN(P)*COS(D_LOC)
            ! finally, G
            G(HARMONIC, HARMONIC_TYPE) = (-COSTHETA_LOC*SIN(P)*DP_DT + SINTHETA_LOC*COS(P)*DP_DT*COS(D_LOC) - &
                                          SINTHETA_LOC*SIN(P)*SIN(D_LOC)*DD_LOC_DT)/SQRT(1 - X**2)
         ELSE IF ((MINIM_FLAG .EQ. 8)) THEN
            ! optimise Br
            G(HARMONIC, HARMONIC_TYPE) = B_DOT_LOCATION(1)
         END IF
      END DO !end loop over harmonics
      END DO !and toroidal / poloidal types.
      !TEST

! ***********************************************
! RESTRICT FLOWS
! ***********************************************
      IF (RESTRICTION .eq. 1) THEN  !restrict to poloidal only
         G(:, TOROIDAL_FLOW) = 0.0_LONG_REAL
      ELSE IF (RESTRICTION .eq. 2) THEN  !restrict to toroidal only
         G(:, POLOIDAL_FLOW) = 0.0_LONG_REAL
      END IF

      IF (RESTRICTION .eq. 3) THEN  !restrict to COLUMNAR FLOW
         DO HARMONIC_TYPE = 1, 2
         DO HARMONIC = 1, LMAX_U*(LMAX_U + 2)
            IF (HARMONIC_TYPE .eq. TOROIDAL_FLOW) THEN ! coefficients are zero for l-m even
               IF (MOD(HARMONICS(HARMONIC)%L - HARMONICS(HARMONIC)%M, 2) .eq. 0) G(HARMONIC, TOROIDAL_FLOW) = 0.0_LONG_REAL
            ELSE IF (HARMONIC_TYPE .eq. POLOIDAL_FLOW) THEN ! zero for l-m odd
               IF (MOD(HARMONICS(HARMONIC)%L - HARMONICS(HARMONIC)%M, 2) .eq. 1) G(HARMONIC, POLOIDAL_FLOW) = 0.0_LONG_REAL
            END IF
         END DO
         END DO
      END IF

! ***********************************************
! CALCULATE DIFFUSIVE CONTRIBUTION
! DISCLAIMER: should be correct but needs some double checking
! ***********************************************

! Calculate diffusive contribution. Now B_DOT_LOCATION is the contribution from horizontal diffusion at location
      DIFFUSION = 0.0_8 ! initialise to this anyway

      IF (MINIM_FLAG .EQ. 0) THEN
    !!!!
         ! old stuff, NEED TO CHECK
    !!!!
         ! Diffusive contribution to the rate of change of dipole tilt
         GAUSS_HD(:) = 0.0_LONG_REAL
         ! Calculate horizontal diffusion of B_r at CMB
         ! CALL EVALUATE_NABLA2_B_R_GRID( NTHETA_GRID, NPHI_GRID, GAUSS, HARMONICS, LMAX_B_OBS, LMAX_SV, NABLA2_B_R, ALF )
         ! get SH coefficients (need to re-check this one)
         ! CALL REAL_2_SPEC( NABLA2_B_R, GAUSS_HD, LMAX_B_OBS, LMAX_B_OBS, HARMONICS, NPHI_GRID, NTHETA_GRID , LEGENDRE_INV )

         ! In the simle case of Livermore, 2014
         DO I = 1, LMAX_B_OBS*(LMAX_B_OBS + 2)
            GAUSS_HD(I) = -REAL(HARMONICS(I)%L, KIND=LONG_REAL)*REAL(HARMONICS(I)%L + 1, KIND=LONG_REAL)*GAUSS(I)/(CMB_RADIUS)**2
         END DO

         WRITE (6, '(A,x,x,3F15.6)') &
            'diffusive contributions to g10, g11, h11 are (nT / year)', &
            GAUSS_HD(1)*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL, &
            GAUSS_HD(2)*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL, &
            GAUSS_HD(3)*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL

         ! multiply by seconds in year to get rad/yr
         ! is this correct? for what case?
         DIFFUSION = ETA*(GAUSS_HD(2)*GAUSS(1)*GAUSS(2) + &
                          GAUSS_HD(3)*GAUSS(1)*GAUSS(3) - &
                          GAUSS_HD(1)*(GAUSS(2)**2 + GAUSS(3)**2))* &
                     3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL/NORM_G

      ELSE IF ((MINIM_FLAG .EQ. 1) .OR. (MINIM_FLAG .EQ. 2)) THEN
         ! rate of change of intensity at location
         B_DOT_LOCATION(1:3) = 0.0_8
         B_LOCATION(1:3) = 0.0_8
         DO I = 1, LMAX_B_OBS*(LMAX_B_OBS + 2)
            ! evaluate B_r  and del_H^2 B_r at Earth surface
            IF (HARMONICS(I)%SINCOS .EQ. SINE_HARMONIC) THEN
               PHI_DEP = SIN(HARMONICS(I)%M*PHI_OBS)
               DERV_PHI_DEP = HARMONICS(I)%M*COS(HARMONICS(I)%M*PHI_OBS)
            ELSE
               PHI_DEP = COS(HARMONICS(I)%M*PHI_OBS)
               DERV_PHI_DEP = -HARMONICS(I)%M*SIN(HARMONICS(I)%M*PHI_OBS)
            END IF
            FACTOR = ETA/CMB_RADIUS**2*REAL(-(HARMONICS(I)%L + 1)*HARMONICS(I)%L, KIND=LONG_REAL)

            INDEX_PLM = HARMONICS(I)%M*LMAX_SV + (HARMONICS(I)%M*(3 - HARMONICS(I)%M))/2 + 1 + (HARMONICS(I)%L - HARMONICS(I)%M)
            B_DOT_LOCATION(1) = B_DOT_LOCATION(1) + &
                                GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*PHI_DEP*REAL(HARMONICS(I)%L + 1, KIND=LONG_REAL)*FACTOR
            B_DOT_LOCATION(2) = B_DOT_LOCATION(2) - &
                                GAUSS(I)*DALF_LOCATION(1, INDEX_PLM)*PHI_DEP*FACTOR
            B_DOT_LOCATION(3) = B_DOT_LOCATION(3) - &
                                GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*DERV_PHI_DEP/SINTHETA_LOC*FACTOR

            IF (HARMONICS(I)%L .LE. LMAX_B_OBS) THEN !SV goes to higher L than B[obs], so exclude if index goes higher than required.
               B_LOCATION(1) = B_LOCATION(1) + &
                               GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*PHI_DEP*REAL(HARMONICS(I)%L + 1, KIND=LONG_REAL)
               B_LOCATION(2) = B_LOCATION(2) - &
                               GAUSS(I)*DALF_LOCATION(1, INDEX_PLM)*PHI_DEP
               B_LOCATION(3) = B_LOCATION(3) - &
                               GAUSS(I)*ALF_LOCATION(1, INDEX_PLM)*DERV_PHI_DEP/SINTHETA_LOC
            END IF
         END DO

         F_LOC = SQRT(SUM(B_LOCATION**2))

         DIFFUSION = SUM(B_DOT_LOCATION(:)*B_LOCATION(:))/F_LOC
         !answer in nT * m^2/s / m^2  * nT / nT= (nT)/s
         ! convert to nT/yr:
         DIFFUSION = DIFFUSION*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL

      ELSE IF ((MINIM_FLAG .EQ. 4)) THEN
         ! if we want to optimise the rate of change of g10
         FACTOR = ETA/CMB_RADIUS**2*2.0_LONG_REAL
         DIFFUSION = GAUSS(1)*FACTOR*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL

      END IF ! end if of MINIM_FLAG cases

      !PRINT*, G!  B_LOCATION, F_LOC

! ***********************************************
! CALCULATE OPTIMAL FLOW IN WRITE OUTPUT
! ***********************************************

      ALLOCATE (EVEC_TOR(1:LMAX_U*(LMAX_U + 2)), EVEC_POL(1:LMAX_U*(LMAX_U + 2)))
      IF (ALLOCATED(SPEC_U_TOR)) DEALLOCATE (SPEC_U_TOR)
      IF (ALLOCATED(SPEC_U_POL)) DEALLOCATE (SPEC_U_POL)
      ALLOCATE (SPEC_U_TOR(1:LMAX_U*(LMAX_U + 2)), SPEC_U_POL(1:LMAX_U*(LMAX_U + 2)))

      KE_TOR = 0.0_LONG_REAL
      KE_POL = 0.0_LONG_REAL
      ! EVEC is the q in Phil's 2014 paper, and NORM_FACTOR is the diagonal matrix E element
      DO I = 1, LMAX_U*(LMAX_U + 2)
         NORM_FACTOR = HARMONICS(I)%L*(HARMONICS(I)%L + 1)*4.0_LONG_REAL*Pi/REAL(2*HARMONICS(I)%L + 1, KIND=LONG_REAL)
         EVEC_TOR(I) = G(I, TOROIDAL_FLOW)/NORM_FACTOR
         EVEC_POL(I) = G(I, POLOIDAL_FLOW)/NORM_FACTOR
      END DO

      ! The flow (defined by the coefficients EVEC) is given in SI units of m/s.
      ! normalise: flow coeffs should describe a flow in km/yr
      EVEC_TOR(:) = EVEC_TOR(:)*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL/1000.0_LONG_REAL
      EVEC_POL(:) = EVEC_POL(:)*3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL/1000.0_LONG_REAL

      DO I = 1, LMAX_U*(LMAX_U + 2)
         NORM_FACTOR = HARMONICS(I)%L*(HARMONICS(I)%L + 1)*4.0_LONG_REAL*Pi/REAL(2*HARMONICS(I)%L + 1, KIND=LONG_REAL)
         KE_TOR = KE_TOR + EVEC_TOR(I)**2*NORM_FACTOR
         KE_POL = KE_POL + EVEC_POL(I)**2*NORM_FACTOR
      END DO
      KE = KE_TOR + KE_POL

      ! KE is \int u^2 dS over the surface of a unit sphere. Convert to dimensional rms (in km/yr)
      TOTAL_RMS = SQRT(KE/(4.0_LONG_REAL*Pi))

      ! Scale solution by the target rms value in km/yr

      EVEC_TOR = EVEC_TOR*TARGET_RMS/TOTAL_RMS
      EVEC_POL = EVEC_POL*TARGET_RMS/TOTAL_RMS

      SPEC_U_TOR = EVEC_TOR/(CMB_RADIUS/1000.0_LONG_REAL)
      SPEC_U_POL = EVEC_POL/(CMB_RADIUS/1000.0_LONG_REAL)

      ! Ooptimal rate-of-change at specified location
      OPT_RATE = SUM(G(:, TOROIDAL_FLOW)*EVEC_TOR(:))*1000.0_LONG_REAL + &
                         SUM(G(:, POLOIDAL_FLOW)*EVEC_POL(:))*1000.0_LONG_REAL
      !Fdot is computed with a flow with units of km/yr: multiply by 1000 to bring it into SI units (of m/s).

      PRINT *, ''
      PRINT *, 'OPTIMISED RATE OF CHANGE IS (UNITS/yr) ', OPT_RATE
      PRINT *, 'NOT INCLUDING HORIZONTAL DIFFUSION OF (UNITS/yr)', DIFFUSION
      !PRINT *, 'F AT LOCATION IS (nT) ', F_LOC
      WRITE (6, '(A,F8.2,A,F8.2,A)') 'FLOW IS ', KE_POL/KE*100, ' % POLOIDAL AND ', KE_TOR/KE*100, '% TOROIDAL IN KE'
      ! write to disk, and convert gauss coeffs describing a flow in km/year to one describing a flow in yr^(-1) on the unit sphere.
      OPEN (22, FILE='OPTIMAL_FLOW.DAT', STATUS='REPLACE', FORM='FORMATTED')
      WRITE (22, '(A,ES10.2,A,I3,A,I3)') 'OPTIMAL FLOW WITH TARGET RMS ', TARGET_RMS, '     LMAX_U ', LMAX_U, ' LMAX_B', LMAX_B_OBS
      DO J = 1, LMAX_U*(LMAX_U + 2)
      IF (HARMONICS(J)%M .NE. 0 .AND. HARMONICS(J)%SINCOS .EQ. COSINE_HARMONIC) THEN
         WRITE (22, '(I3,x,I3,4(x,ES15.5,x))') HARMONICS(J)%L, HARMONICS(J)%M, &
            EVEC_POL(J)/(CMB_RADIUS/1000.0_LONG_REAL), EVEC_POL(J + 1)/(CMB_RADIUS/1000.0_LONG_REAL), &
            EVEC_TOR(J)/(CMB_RADIUS/1000.0_LONG_REAL), EVEC_TOR(J + 1)/(CMB_RADIUS/1000.0_LONG_REAL)
      END IF

      IF (HARMONICS(J)%M .EQ. 0 .AND. HARMONICS(J)%SINCOS .EQ. COSINE_HARMONIC) THEN
         WRITE (22, '(I3,x,I3,4(x,ES15.5,x))') &
            HARMONICS(J)%L, HARMONICS(J)%M, &
            EVEC_POL(J)/(CMB_RADIUS/1000.0_LONG_REAL), 0.0, EVEC_TOR(J)/(CMB_RADIUS/1000.0_LONG_REAL), 0.0_LONG_REAL
      END IF
      END DO

      CLOSE (22)
      ! write the dipole tilt rate
      OPEN (24, FILE='OPTIMISED_QUANTITY_DOT.DAT', STATUS='REPLACE', FORM='FORMATTED')
      WRITE (24, '(A,ES10.2,A,I3,A,I3)') &
         'OPTIMISED RATE OF CHANGE (IN UNITS/yr) WITH TARGET RMS ', TARGET_RMS, &
         '     LMAX_U ', LMAX_U, &
         ' LMAX_B', LMAX_B_OBS
      WRITE (24, '(ES20.10,x)') OPT_RATE
      CLOSE (24)

      ! Write the elements of G (green's functions?)
      OPEN (25, FILE='G_TOR.DAT', STATUS='REPLACE', FORM='FORMATTED')
      OPEN (26, FILE='G_POL.DAT', STATUS='REPLACE', FORM='FORMATTED')
      DO HARMONIC = 1, LMAX_U*(LMAX_U + 2)
         WRITE (25, *) G(HARMONIC, 1)
         WRITE (26, *) G(HARMONIC, 2)
      END DO
      CLOSE (25)
      CLOSE (26)
      ! Calculate spectrum of flow
      OPEN (23, FILE='FLOW_L_SPEC.DAT', STATUS='REPLACE', FORM='FORMATTED')
      ALLOCATE (FLOW_L_SPEC(1:LMAX_U))
      FLOW_L_SPEC(:) = 0.0_LONG_REAL
      DO I = 1, LMAX_U*(LMAX_U + 2)
         NORM_FACTOR = HARMONICS(I)%L*(HARMONICS(I)%L + 1)*4.0_LONG_REAL*Pi/REAL(2*HARMONICS(I)%L + 1, KIND=LONG_REAL)
         FLOW_L_SPEC(HARMONICS(I)%L) = FLOW_L_SPEC(HARMONICS(I)%L) + (EVEC_POL(I)**2 + EVEC_TOR(I)**2)*NORM_FACTOR
      END DO

      WRITE (23, *) 'KE SPECTRUM PER DEGREE L IN (KM/YR)^2: \int u^2 dOmega / (4 Pi)'
      DO I = 1, LMAX_U
         WRITE (23, *) I, FLOW_L_SPEC(I)/(4.0_LONG_REAL*Pi)
      END DO
      CLOSE (23)
      WRITE (6, '(A,x,x,F8.3)') 'RMS FLOW IS (KM/YR)', SQRT(SUM(FLOW_L_SPEC)/(4.0_8*Pi))

      ! Write flow in GMT format
      CALL WRITE_U_GMT(GMT_THETA, GMT_PHI, EVEC_TOR, EVEC_POL, HARMONICS, LMAX_SV, SCALE_FACTOR)

      ! Write flow for Python
      CALL WRITE_U_CENTRED(GMT_THETA, GMT_PHI, EVEC_TOR, EVEC_POL, HARMONICS, LMAX_SV)
      CALL WRITE_U_RANDOM(EVEC_TOR, EVEC_POL, HARMONICS, LMAX_SV)

      ! Calculate the intensity change on the Earth's surface and output in a file that GMT can read

      CALL EVALUATE_U_H(NTHETA_GRID, &
                        NPHI_GRID, &
                        EVEC_TOR, &
                        EVEC_POL, &
                        U_H, &
                        DIV_H_U_H, &
                        ALF, &
                        DALF, &
                        HARMONICS, &
                        LMAX_U, &
                        LMAX_SV, &
                        ONE_DIV_SIN_THETA)
      CALL EVALUATE_B_R_GRID(NTHETA_GRID, &
                             NPHI_GRID, &
                             GAUSS, &
                             HARMONICS, &
                             LMAX_B_OBS, &
                             LMAX_SV, &
                             B_R, &
                             GRAD_H_B_R, &
                             ALF, &
                             DALF, &
                             ONE_DIV_SIN_THETA)

      ! Transform
      DO I_THETA = 1, NTHETA_GRID
      DO I_PHI = 0, NPHI_GRID - 1
         B_R_DOT(I_THETA, I_PHI) = -U_H(I_THETA, I_PHI, 1)*GRAD_H_B_R(I_THETA, I_PHI, 1) - &
                                   U_H(I_THETA, I_PHI, 2)*GRAD_H_B_R(I_THETA, I_PHI, 2) - &
                                   B_R(I_THETA, I_PHI)*DIV_H_U_H(I_THETA, I_PHI)
      END DO
      END DO

      ! B_R_DOT is produced from a flow in units of km/yr. Need to multiply by 1000 to get a magnetic field in units of nT/yr.
      B_R_DOT(:, :) = B_R_DOT(:, :)*1000.0_LONG_REAL

      ! Add horizontal diffusion converting to nT/yr
      DO I = 1, LMAX_B_OBS*(LMAX_B_OBS)

         INDEX = HARMONICS(I)%M*LMAX_SV + &
                 (HARMONICS(I)%M*(3 - HARMONICS(I)%M))/2 + &
                 1 + (HARMONICS(I)%L - HARMONICS(I)%M)
         FACTOR = -ETA* &
                  REAL((HARMONICS(I)%L + 1)*HARMONICS(I)%L, KIND=LONG_REAL)/CMB_RADIUS**2* &
                  REAL((HARMONICS(I)%L + 1), KIND=LONG_REAL)* &
                  (ES_RADIUS/CMB_RADIUS)**(HARMONICS(I)%L + 2)* &
                  3600.0_LONG_REAL*24.0_LONG_REAL*365.0_LONG_REAL

         DO I_PHI = 0, NPHI_GRID - 1
            PHI = I_PHI*2.0_LONG_REAL*Pi/REAL(NPHI_GRID, KIND=LONG_REAL)
            IF (HARMONICS(I)%SINCOS .EQ. SINE_HARMONIC) THEN
               PHI_DEP = SIN(HARMONICS(I)%M*PHI)
            ELSE
               PHI_DEP = COS(HARMONICS(I)%M*PHI)
            END IF

            DO I_THETA = 1, NTHETA_GRID

               B_R_DOT(I_THETA, I_PHI) = B_R_DOT(I_THETA, I_PHI) + FACTOR*GAUSS(I)*PHI_DEP*ALF(I_THETA, INDEX)
            END DO
         END DO
      END DO

      CALL REAL_2_SPEC(B_R_DOT, SPEC, LMAX_SV, LMAX_SV, HARMONICS, NPHI_GRID, NTHETA_GRID, LEGENDRE_INV)

      ! Write F and Fdot for output to GMT
      ! Convert SPEC coefficents to a Gauss-coefficient representation.
      DO J = 1, LMAX_SV*(LMAX_SV + 2)
         SPEC(J) = SPEC(J)*(CMB_RADIUS/ES_RADIUS)**(HARMONICS(J)%L + 2)/REAL(HARMONICS(J)%L + 1, KIND=LONG_REAL)
      END DO

      CALL WRITE_F_DOT_GMT(SPEC, GAUSS, LMAX_B_OBS, LMAX_SV, HARMONICS)

! One further check: calculate B_R_DOT from these SPECS
!        B_DOT_LOCATION(1:3) = 0.0_8

!        DO I = 1, LMAX_SV * (LMAX_SV + 2)
      ! evaluate B_r at Earth surface
!        IF( HARMONICS(I)%SINCOS .EQ. SINE_HARMONIC ) THEN
!        PHI_DEP = SIN(  HARMONICS(I)%M * PHI_OBS )
!        DERV_PHI_DEP = HARMONICS(I)%M * COS(  HARMONICS(I)%M * PHI_OBS )
!        ELSE
!        PHI_DEP = COS(  HARMONICS(I)%M * PHI_OBS )
!        DERV_PHI_DEP = -HARMONICS(I)%M * SIN(  HARMONICS(I)%M * PHI_OBS)
!        ENDIF

!        INDEX_PLM = HARMONICS(I)%M * LMAX_SV +  (HARMONICS(I)%M * (3-HARMONICS(I)%M) ) /2 + 1 + (HARMONICS(I)%L - HARMONICS(I)%M)
!        B_DOT_LOCATION(1) = B_DOT_LOCATION(1) + SPEC(I) * ALF_LOCATION(1, INDEX_PLM) * PHI_DEP * REAL(HARMONICS(I)%L + 1, KIND = LONG_REAL)
!        B_DOT_LOCATION(2) = B_DOT_LOCATION(2) - SPEC(I) * DALF_LOCATION(1, INDEX_PLM) * PHI_DEP
!        B_DOT_LOCATION(3) = B_DOT_LOCATION(3) - SPEC(I) * ALF_LOCATION(1, INDEX_PLM) * DERV_PHI_DEP / SINTHETA_LOC

!        ENDDO

! this was probably a test
!        INCLINATION = ( B_DOT_LOCATION(2) * B_LOCATION(2) * B_LOCATION(1) + B_DOT_LOCATION(3) * B_LOCATION(3) * B_LOCATION(1) &
!            - B_DOT_LOCATION(1) * (B_LOCATION(2)**2 + B_LOCATION(3)**2)  ) &
!            / ( F_LOC**2 * SQRT( B_LOCATION(2)**2 + B_LOCATION(3)**2 ) )
!        PRINT*, 'OPTIMISED INCLINATION RATE AT LOCATION ', INCLINATION

      CALL DFFTW_DESTROY_PLAN(PLAN_FFT_R2HC)
      DEALLOCATE (FFT_TRANSFORM_ARRAY)

      RETURN
   END SUBROUTINE CALCULATE_OPTIMAL_FLOW

END MODULE OPTIMISATION_BOUND
