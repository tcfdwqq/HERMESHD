!***** INITIALCON.F90 ********************************************************************
module initialcon

use params
use helpers
use basis_funcs

use boundary_custom
use boundary


real :: rh_fluid  ! set far-field fluid density

contains

    !===========================================================================
    ! set_ic
    !    Select and set the initial conditions
    !------------------------------------------------------------
    subroutine set_ic(Q_r, id)
        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        ! character(*), intent(in) :: name
        integer i,j,k,id

        ! te_fluid = T_floor
        ! rh_fluid = 1.0
        ! coll = rh_fluid*te_fluid/vis
        ! colvis = coll*vis  ! or, dn*te
        if (ivis == 0) then
            coll = 0
            colvis = 0
        end if

        Q_r(:,:,:,:,:)  = 0.0
        Q_r(:,:,:,rh,1) = rh_floor
        Q_r(:,:,:,en,1) = T_floor*rh_floor/aindm1
        ! QMask(:,:,:) = .false.
        ! MMask(:,:,:) = .false.

        select case(id)
            ! case(0)
            !     call mpi_print(iam, 'Setting up 2D hydrodynamic jet (old version)...')
            !     call fill_fluid2(Q_r)
            case(0)
                call mpi_print(iam, 'Setting up 2D hydrodynamic jet...')
                call hydro_jet(Q_r)
            case(1)
                call mpi_print(iam, 'Setting up 2D isentropic vortex v0...')
                call isentropic_vortex(Q_r, 0)
            case(2)
                call mpi_print(iam, 'Setting up 2D isentropic vortex v1...')
                call isentropic_vortex(Q_r, 1)
            case(3)
                call mpi_print(iam, 'Setting up 1D Sod Shock Tube v1...')
                call sod_shock_tube_1d(Q_r, 0)
            case(4)
                call mpi_print(iam, 'Setting up 1D Sod Shock Tube v2...')
                call sod_shock_tube_1d(Q_r, 1)
            case(5)
                call mpi_print(iam, 'Setting up Poiseuille flow problem...')
                call poiseuille_flow(Q_r)
            case(6)
                call mpi_print(iam, 'Setting up 2D cylinder-in-pipe (laminar)...')
                call pipe_cylinder_2d(Q_r, 0)
            case(7)
                call mpi_print(iam, 'Setting up 2D cylinder-in-pipe (periodic)...')
                call pipe_cylinder_2d(Q_r, 1)
        end select

        ! coll = epsi  ! temporary hack: set coll to epsi to get old behavior
    end subroutine set_ic
    !---------------------------------------------------------------------------


    !===========================================================================
    ! 2D unstable hydrodynamic jet
    !------------------------------------------------------------
    subroutine hydro_jet(Q_r)
        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        integer i,j,k
        real te,dn,pr,beta,beta2,smx,smy,smz,rand_num,rnum

        dn = 1.0
        te = T_floor
        pr = te*dn

        coll   = dn*te/vis  ! global
        colvis = coll*vis   ! or, dn*te  (also global)

        beta  = 1.0   ! jet strength
        beta2 = 0.005 ! perturbation strength

        do k = 1,nz
        do j = 1,ny
        do i = 1,nx
            call random_number(rand_num)
            rnum = (rand_num - 0.5)

            smx = beta*dn/cosh(20*yc(j)/lyu)
            smy = beta2*rnum/cosh(20*yc(j)/lyu)**2
            smz = 0

            Q_r(i,j,k,rh,1) = dn
            Q_r(i,j,k,mx,1) = smx
            Q_r(i,j,k,my,1) = smy
            Q_r(i,j,k,mz,1) = smz
            Q_r(i,j,k,en,1) = pr/aindm1 + 0.5*(smx**2 + smy**2 + smz**2)/dn
        end do
        end do
        end do

    end subroutine hydro_jet
    !---------------------------------------------------------------------------


    !===========================================================================
    ! 2D isentropic vortex
    !------------------------------------------------------------
    ! For a survey of 2D isentropic vortex problems:
    !    Spiegel, et al. "A Survey of the Isentropic..." (2015)
    ! Version 0 -- horizontal propagation, see
    !    Hesthaven & Warburton, "Nodal Discontinuous Galerkin..." (2008)
    ! Version 1 -- diagonal propagation, see
    !    Shu, "Essentially Non-oscillatory and... Weighted" (1998)
    !---------------------------------------------------------------------------
    subroutine isentropic_vortex(Q_r, ver)
        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        integer i,j,k, ver
        real rh_amb,vx_amb,vy_amb,vz_amb,pr_amb,te_amb,Rgsqi,beta
        real xctr,yctr,zctr,xp,yp,r2,delta_vx,delta_vy,delta_T
        real dn,vx,vy,vz,te,pr

        beta   = 5.0            ! vortex strength
        rh_amb = 1.0            ! ambient density
        vx_amb = 1.0            ! ambient x-velocity  1.0/aindex**0.5
        select case(ver)
          case(0)
            vy_amb = 0.0        ! ambient y-velocity  1.0/aindex**0.5
            Rgsqi = 1.0         ! inverse grid length scale squared
          case(1)
            vy_amb = 1.0        ! ambient y-velocity  1.0/aindex**0.5
            Rgsqi = 0.5         ! inverse grid length scale squared
        end select
        vz_amb = 0.0            ! ambient z-velocity
        pr_amb = 1.0            ! ambient pressure (atmospheric pressure)
        te_amb = pr_amb/rh_amb  ! ambient temperature

        xctr = 0.0              ! vortex center in x-directionrh_fluid*te/vis
        yctr = 0.0              ! vortex center in y-direction
        zctr = 0.0              ! vortex center in z-direction

        do k = 1,nz
        do j = 1,ny
        do i = 1,nx
            xp = xc(i) - xctr   ! x-value from vortex center
            yp = yc(j) - yctr   ! y-value from vortex center
            r2 = xp**2 + yp**2  ! radial distance from vortex center

            delta_vx = -yp*beta/(2*pi) * exp( Rgsqi*(1 - r2) )
            delta_vy =  xp*beta/(2*pi) * exp( Rgsqi*(1 - r2) )
            delta_T  = -(aindm1*beta**2)/(16*Rgsqi*aindex*pi**2) * exp( 2*Rgsqi*(1 - r2) )

            vx = vx_amb + delta_vx
            vy = vy_amb + delta_vy
            vz = vz_amb
            te = te_amb + delta_T
            dn = te**(1./aindm1)  ! OR (1 - delta_T)**(1/(gamma-1)), rh_amb * te**(1./aindm1)
            pr = dn**aindex  ! use te*dn OR dn**aindex (for ideal gas)

            Q_r(i,j,k,rh,1) = dn
            Q_r(i,j,k,mx,1) = dn*vx
            Q_r(i,j,k,my,1) = dn*vy
            Q_r(i,j,k,mz,1) = dn*vz
            Q_r(i,j,k,en,1) = pr/aindm1 + 0.5*dn*(vx**2 + vy**2 + vz**2)
        end do
        end do
        end do
        ! print *,'iam=',iam,'xl=',xc(1),'xh=',xc(nx),'yl=',yc(1),'yh=',yc(ny)

    end subroutine isentropic_vortex
    !---------------------------------------------------------------------------


    !===========================================================================
    ! SOD Shock Tube
    !------------------------------------------------------------
    subroutine sod_shock_tube_1d(Q_r, ver)
        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        integer i,j,k, ver
        real rh_hi,rh_lo,pr_hi,pr_lo,xctr,yctr,xp,yp,dn,vx,vy,vz,pr

        rh_hi = 1.0 !e-4  ! NOTE: density floor needs to be 5.0e-6 (e-4 for original)
        pr_hi = 1.0*P_base  ! atmospheric pressure
        rh_lo = 0.125 !e-4
        pr_lo = 0.1*P_base
        vx = 0.0
        vy = 0.0
        vz = 0.0

        xctr = 0
        yctr = 0  ! only needed if shock normal not aligned w/ x-direction

        do k = 1,nz
        do j = 1,ny
        do i = 1,nx
            xp = xc(i) - xctr
            if ( ver == 1 ) then
                yp = yc(j) - yctr
            else
                yp = 0
            endif

            if ( xp+yp <= 0 ) then
                dn = rh_hi
                pr = pr_hi
            endif
            if ( xp+yp > 0 ) then
                dn = rh_lo
                pr = pr_lo
            endif

            Q_r(i,j,k,rh,1) = dn
            Q_r(i,j,k,mx,1) = dn*vx
            Q_r(i,j,k,my,1) = dn*vy
            Q_r(i,j,k,mz,1) = dn*vz
            Q_r(i,j,k,en,1) = pr/aindm1 + 0.5*dn*(vx**2 + vy**2 + vz**2)
        end do
        end do
        end do

    end subroutine sod_shock_tube_1d
    !---------------------------------------------------------------------------


    !===========================================================================
    ! 2D pipe (Poiseuille) flow
    !   * Need outflow BCs on right wall: nu d u/d eta - p*eta = 0
    ! NOTE: This subroutine sets BCs for the problem using custom_boundary
    !------------------------------------------------------------
    subroutine poiseuille_flow(Q_r)
        use boundary_custom

        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        integer i,j,k,ieq
        real dn,pr,te,vx,vy,vz,ux_amb,yp,yp0

        !-------------------------------------------------------
        ! Definitions
        dn = 1.0
        te = T_floor
        pr = dn*te  ! 1.0*P_base  ! can be adjusted to get stable results

        coll   = dn*te/vis  ! global (CES' nu = rh_fluid*T_floor)
        colvis = coll*vis   ! or, dn*te  (also global)

        vx = 0.0
        vy = 0.0
        vz = 0.0

        yp0 = lyd  ! set zero-value of y-coordinate to domain bottom
        ux_amb = 3.0e-1

        !-------------------------------------------------------
        ! Set initial conditions
        do k = 1,nz
        do j = 1,ny
        do i = 1,nx
            Q_r(i,j,k,rh,1) = dn
            Q_r(i,j,k,mx,1) = dn*vx
            Q_r(i,j,k,my,1) = dn*vy
            Q_r(i,j,k,mz,1) = dn*vz
            Q_r(i,j,k,en,1) = pr/aindm1 + 0.5*dn*(vx**2 + vy**2 + vz**2)
        end do
        end do
        end do

        Qxlo_ext_def(:,:,:,:) = 0.0
        call set_xlobc_inflow(ux_amb, dn, pr, Qxlo_ext_def)
    end subroutine poiseuille_flow
    !---------------------------------------------------------------------------


    !===========================================================================
    ! 2D pipe flow around a cylinder
    !   * Re ~ 20 for laminar case (ver 0)
    !   * Re ~ 100 for periodic case (version 1)
    !   * Need outflow BCs on right wall: nu d u/d eta - p*eta = 0
    !   * No-slip BCs everywhere else
    ! NOTE: This subroutine sets BCs for the problem using custom_boundary
    !------------------------------------------------------------
    subroutine pipe_cylinder_2d(Q_r, version)
        use boundary_custom

        implicit none
        real, dimension(nx,ny,nz,nQ,nbasis), intent(inout) :: Q_r
        ! logical, dimension(nx,ny,nz) :: Qmask
        integer i,j,k,ieq,version
        real dn,pr,te,vx,vy,vz,ux_amb,xp0,yp0,cyl_x0,cyl_y0,cyl_rad

        !-------------------------------------------------------
        ! Definitions
        dn = 1.0
        te = T_floor
        pr = dn*te  ! 1.0*P_base  ! can be adjusted to get stable results

        coll   = dn*te/vis  ! global
        colvis = coll*vis   ! or, dn*te  (also global)

        vx = 0.0
        vy = 0.0
        vz = 0.0

        xp0 = lxd              ! set zero-value of x-coordinate to left of domain
        yp0 = lyd              ! set zero-value of y-coordinate to bottom of domain
        cyl_x0  = xp0 + ly/2.  ! center of cylinder relative to origin
        cyl_y0  = yp0 + ly/2.
        cyl_rad = ly/8.

        select case(version)
            case(0)
                ux_amb = 0.3
            case(1)
                ux_amb = 1.5
        end select

        !-------------------------------------------------------
        ! Set initial conditions
        do k = 1,nz
        do j = 1,ny
        do i = 1,nx
            Q_r(i,j,k,rh,1) = dn
            Q_r(i,j,k,mx,1) = dn*vx
            Q_r(i,j,k,my,1) = dn*vy
            Q_r(i,j,k,mz,1) = dn*vz
            Q_r(i,j,k,en,1) = pr/aindm1 + 0.5*dn*(vx**2 + vy**2 + vz**2)
        end do
        end do
        end do

        !-------------------------------------------------------
        ! Generate cylinder mask --> zero out grid quantities in mask
        !   NOTE: might be an offset b/c mask is constructed at faces, not cells
        ! Qmask(:,:,:) = cyl_in_2d_pipe_mask(cyl_x0, cyl_y0, cyl_rad)

        ! where (Qmask(:,:,:))
        !     Q_r(:,:,:,rh,1) = 1.25
        !     Q_r(:,:,:,mx,1) = 0.0
        !     Q_r(:,:,:,my,1) = 0.0
        !     Q_r(:,:,:,mz,1) = 0.0
        ! end where

        ! NOTE: Qxlow_ext_custom, Qcyl_ext, and QMask should already be initialized!
        ! call add_custom_boundaries(icname)
        call set_cyl_in_2d_pipe_boundaries(Qmask, ux_amb, dn, pr, Qxlo_ext_def, Qcyl_ext_c)

    end subroutine pipe_cylinder_2d
    !---------------------------------------------------------------------------

end module initialcon
