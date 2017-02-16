module prepare_step

use parameters
use helpers
use boundary

! write(*,'(A11,I1,A2,2ES9.1,A3,2ES9.1)') 'Qylow_ext (',iam,'):',Qylow_ext(1:2,1,1,pxx),' | ',Qylow_ext(nx-1:nx,1,1,pxx)
! write(*,'(A12,I1,A2,2ES9.1,A3,2ES9.1)') 'Qyhigh_ext (',iam,'):',Qyhigh_ext(1:2,1,1,pxx),' | ',Qyhigh_ext(nx-1:nx,1,1,pxx)
! write(*,'(A11,I1,A2,2ES9.1,A3,2ES9.1)') 'Qylow_int (',iam,'):',Qylow_int(1:2,1,1,pxx),' | ',Qylow_int(nx-1:nx,1,1,pxx)
! write(*,'(A12,I1,A2,2ES9.1,A3,2ES9.1)') 'Qyhigh_int (',iam,'):',Qyhigh_int(1:2,1,1,pxx),' | ',Qyhigh_int(nx-1:nx,1,1,pxx)

contains

    !===========================================================================
    ! exchange_flux : set internal BCs from field variables
    !------------------------------------------------------------
    subroutine exchange_flux(Q_r)
        integer ieq, i, j, k, ipnt
        real, dimension(nx,ny,nz,nQ,nbasis), intent(in) :: Q_r

        !#########################################################
        ! Step 1: Get fluxes at the boundaries of this MPI domain
        !---------------------------------------------------------
        do ieq = 1,nQ
        do k = 1,nz
        do j = 1,ny
            do ipnt=1,nface
                Qxlow_int(j,k,ipnt,ieq) = sum(bfvals_xm(ipnt,1:nbasis)*Q_r(1,j,k,ieq,1:nbasis))
                Qxhigh_int(j,k,ipnt,ieq) = sum(bfvals_xp(ipnt,1:nbasis)*Q_r(nx,j,k,ieq,1:nbasis))
            end do
        end do
        end do
        end do

        do ieq = 1,nQ
        do k = 1,nz
        do i = 1,nx
            do ipnt=1,nface
                Qylow_int(i,k,ipnt,ieq) = sum(bfvals_ym(ipnt,1:nbasis)*Q_r(i,1,k,ieq,1:nbasis))
                Qyhigh_int(i,k,ipnt,ieq) = sum(bfvals_yp(ipnt,1:nbasis)*Q_r(i,ny,k,ieq,1:nbasis))
            end do
        end do
        end do
        end do

        do ieq = 1,nQ
        do j = 1,ny
        do i = 1,nx
            do ipnt=1,nface
                Qzlow_int(i,j,ipnt,ieq) = sum(bfvals_zm(ipnt,1:nbasis)*Q_r(i,j,1,ieq,1:nbasis))
                Qzhigh_int(i,j,ipnt,ieq) = sum(bfvals_zp(ipnt,1:nbasis)*Q_r(i,j,nz,ieq,1:nbasis))
            end do
        end do
        end do
        end do
        !#########################################################


        !#########################################################
        ! Step 2: Exchange fluxes with (neighboring) MPI domains
        !---------------------------------------------------------
        call perform_flux_exchange
        !#########################################################

    end subroutine exchange_flux
    !---------------------------------------------------------------------------


    !===========================================================================
    ! perform_flux_exchange : exchange fluxes between MPI domains
    !------------------------------------------------------------
    subroutine perform_flux_exchange
        integer mpi_size

        call MPI_BARRIER(cartcomm,ierr)

        !---------------------------------------------
         mpi_size = ny*nz*nface*nQ

        if (nbrs(EAST) .ne. MPI_PROC_NULL) then
            call MPI_ISend(Qxhigh_int,mpi_size,MPI_TT,nbrs(EAST),0,cartcomm,reqs(1),ierr)
        endif
        if (nbrs(WEST) .ne. MPI_PROC_NULL) then
            call MPI_IRecv(Qxlow_ext,mpi_size,MPI_TT,nbrs(WEST),0,cartcomm,reqs(2),ierr)
        endif

        if (nbrs(EAST) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(1),stats(:,1),ierr)
            call MPI_IRecv(Qxhigh_ext,mpi_size,MPI_TT,nbrs(EAST),0,cartcomm,reqs(3),ierr)
        endif
        if (nbrs(WEST) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(2),stats(:,2),ierr)
            call MPI_ISend(Qxlow_int,mpi_size,MPI_TT,nbrs(WEST),0,cartcomm,reqs(4),ierr)
        endif

        if (nbrs(EAST) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(3),stats(:,3),ierr)
        endif
        if (nbrs(WEST) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(4),stats(:,4),ierr)
        endif

        !---------------------------------------------
        mpi_size = nface*nx*nz*nQ

        if (nbrs(NORTH) .ne. MPI_PROC_NULL) then
            call MPI_ISend(Qyhigh_int,mpi_size,MPI_TT,nbrs(NORTH),0,cartcomm,reqs(1),ierr)
        endif
        if (nbrs(SOUTH) .ne. MPI_PROC_NULL) then
            call MPI_IRecv(Qylow_ext,mpi_size,MPI_TT,nbrs(SOUTH),0,cartcomm,reqs(2),ierr)
        endif

        if (nbrs(NORTH) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(1),stats(:,1),ierr)
            call MPI_IRecv(Qyhigh_ext,mpi_size,MPI_TT,nbrs(NORTH),0,cartcomm,reqs(3),ierr)
        endif
        if (nbrs(SOUTH) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(2),stats(:,2),ierr)
            call MPI_ISend(Qylow_int,mpi_size,MPI_TT,nbrs(SOUTH),0,cartcomm,reqs(4),ierr)
        endif

        if (nbrs(NORTH) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(3),stats(:,3),ierr)
        endif
        if (nbrs(SOUTH) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(4),stats(:,4),ierr)
        endif

        !---------------------------------------------
        mpi_size = nface*nx*ny*nQ

        if (nbrs(UP) .ne. MPI_PROC_NULL) then
            call MPI_ISend(Qzhigh_int,mpi_size,MPI_TT,nbrs(UP),0,cartcomm,reqs(1),ierr)
        endif
        if (nbrs(DOWN) .ne. MPI_PROC_NULL) then
            call MPI_IRecv(Qzlow_ext,mpi_size,MPI_TT,nbrs(DOWN),0,cartcomm,reqs(2),ierr)
        endif

        if (nbrs(UP) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(1),stats(:,1),ierr)
            call MPI_IRecv(Qzhigh_ext,mpi_size,MPI_TT,nbrs(UP),0,cartcomm,reqs(3),ierr)
        endif
        if (nbrs(DOWN) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(2),stats(:,2),ierr)
            call MPI_ISend(Qzlow_int,mpi_size,MPI_TT,nbrs(DOWN),0,cartcomm,reqs(4),ierr)
        endif

        if (nbrs(UP) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(3),stats(:,3),ierr)
        endif
        if (nbrs(DOWN) .ne. MPI_PROC_NULL) then
            call MPI_Wait(reqs(4),stats(:,4),ierr)
        endif

    end subroutine perform_flux_exchange
    !---------------------------------------------------------------------------

end module prepare_step