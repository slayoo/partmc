! Copyright (C) 2007-2010 Nicole Riemer and Matthew West
! Licensed under the GNU General Public License version 2 or (at your
! option) any later version. See the file COPYING for details.

!> \file
!> The partmc program.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> \mainpage PartMC Code Documentation
!!
!! \subpage input_format - Input file format description.
!!
!! \subpage output_format - Output file format description.
!!
!! \subpage module_diagram - Diagram of modules and dependencies.
!!
!! \subpage coding_style - Description of code conventions and style.
!!
!! \subpage publications - Publications about PartMC.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> \page input_format Input File Format
!!
!! The input file format is plain text. See \ref spec_file_format for
!! a description of the file format.
!!
!! When running PartMC with the command <tt>partmc input.spec</tt> the
!! first line of the <tt>input.spec</tt> file must define the \c
!! run_type with:
!! <pre>
!! run_type &lt;type&gt;
!! </pre>
!! where <tt>&lt;type&gt;</tt> is one of \c particle, \c exact, or \c
!! sectional. This determines the type of run as well as the format of the
!! remainder of the spec file:
!!
!! \subpage input_format_particle "Particle-resolved simulation"
!!
!! \subpage input_format_exact "Exact (analytical) solution"
!!
!! \subpage input_format_sectional "Sectional model simulation"

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> \page module_diagram Module Diagram
!!
!! \dotfile partmc_modules.gv

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> \page coding_style Coding Style
!!
!! The code is mainly Fortran 90, with a few parts still clearly
!! showing their Fortran 77 heritage. A few Fortran 95 and Fortran
!! 2003 features are used (mainly the \c COMMAND_ARGUMENT_COUNT and \c
!! GET_COMMAND_ARGUMENT intrinsics). The code needs to be processed
!! with \c cpp or a compatible pre-processor.
!!
!! \section oo_fortran Object Oriented Fortran
!!
!! Extensive use is made of Fortran 90 derived types and pointers for
!! dynamic memory allocation of arrays inside derived types. Derived
!! types are named \c my_type_t and are generally defined in modules
!! named \c pmc_mod_my_type within files named \c my_type.f90. Each
!! derived type has allocation and deallocation functions \c
!! my_type_allocate() and \c my_type_deallocate(), where
!! appropriate. Almost all subroutines and function in each \c
!! my_type.f90 file have names of the form \c my_type_*() and take an
!! object of type \c my_type as the first argument on which to
!! operate.
!!
!! Module names are always the same as the name of the containing
!! file, but prefixed with \c pmc_. Thus the module \c
!! pmc_condense is contained in the file \c condense.f90.
!!
!! \section mem_manage Memory Management
!!
!! The memory allocation policy is that all functions must be called
!! with an already allocated structure. That is, if a subroutine
!! defines a variable of type \c my_type_t, then it must call \c
!! my_type_allocate() or \c my_type_allocate_size() on it before
!! passing it to any other subroutines or functions. The defining
!! subroutine is also responsible for calling \c my_type_deallocate()
!! on every variable it defines.
!!
!! Similarly, any subroutine that declares a pointer variable must
!! allocate it and any data it points to before passing it to other
!! subroutines or functions. If no specific length is known for an array
!! pointer then it should be allocated to zero size. Any subsequent
!! subroutines are free to deallocate and reallocate if they need to
!! change the size.
!!
!! This means that every subroutine (except for allocate and
!! deallocate routines) should contain matching \c
!! allocate()/deallocate() and
!! <tt>my_type_allocate()/my_type_deallocate()</tt> calls.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> \page publications PartMC Publications
!!
!!   - N.&nbsp;Riemer, M.&nbsp;West, R.&nbsp;A.&nbsp;Zaveri, and
!!     R.&nbsp;C.&nbsp;Easter (2010) Estimating black carbon aging
!!     time-scales with a particle-resolved aerosol model, <i>Journal
!!     of Aerosol Science</i> 41(1), 143-158, DOI: <a
!!     href="http://dx.doi.org/10.1016/j.jaerosci.2009.08.009">10.1016/j.jaerosci.2009.08.009</a>
!!   - N.&nbsp;Riemer, M.&nbsp;West, R.&nbsp;A.&nbsp;Zaveri, and
!!     R.&nbsp;C.&nbsp;Easter (2009) Simulating the evolution of soot
!!     mixing state with a particle-resolved aerosol model, <i>Journal
!!     of Geophysical Research</i> 114(D09202), DOI: <a
!!     href="http://dx.doi.org/10.1029/2008JD011073">10.1029/2008JD011073</a>
!!   - R.&nbsp;McGraw, L.&nbsp;Leng, W.&nbsp;Zhu, N.&nbsp;Riemer, and
!!     M.&nbsp;West (2008) Aerosol dynamics using the quadrature
!!     method of moments: Comparing several quadrature schemes with
!!     particle-resolved simulation, <i>Journal of Physics: Conference
!!     Series</i> 125(012020), DOI: <a
!!     href="http://dx.doi.org/10.1088/1742-6596/125/1/012020">10.1088/1742-6596/125/1/012020</a>

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!> Top level driver.
program partmc

  use pmc_mpi
  use pmc_bin_grid
  use pmc_aero_state
  use pmc_aero_dist
  use pmc_aero_binned
  use pmc_kernel_sedi
  use pmc_kernel_golovin
  use pmc_kernel_constant
  use pmc_kernel_brown
  use pmc_kernel_zero
  use pmc_aero_data
  use pmc_aero_weight
  use pmc_env_data
  use pmc_env_state
  use pmc_run_part
  use pmc_run_exact
  use pmc_run_sect
  use pmc_spec_file
  use pmc_gas_data
  use pmc_gas_state
  use pmc_util
#ifdef PMC_USE_SUNDIALS
  use pmc_condense
#endif

  character(len=300) :: spec_name
  
  call pmc_mpi_init()

  if (pmc_mpi_rank() == 0) then
     ! only the root process accesses the commandline

     if (command_argument_count() /= 1) then
        call print_usage()
        call die_msg(739173192, "invalid commandline arguments")
     end if

     call get_command_argument(1, spec_name)
  end if

  call pmc_mpi_bcast_string(spec_name)
  call partmc_run(spec_name)

  call pmc_mpi_finalize()

contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Print the usage text to stderr.
  subroutine print_usage()

    write(*,*) 'Usage: partmc <spec-file>'

  end subroutine print_usage

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Do a PartMC run.
  subroutine partmc_run(spec_name)
    
    !> Spec filename.
    character(len=*), intent(in) :: spec_name

    type(spec_file_t) :: file
    character(len=100) :: run_type
    integer :: i

    ! check filename (must be "filename.spec")
    i = len_trim(spec_name)
    if (spec_name((i-4):i) /= '.spec') then
       call die_msg(710381938, "input filename must end in .spec")
    end if
    
    if (pmc_mpi_rank() == 0) then
       ! only the root process does I/O
       call spec_file_open(spec_name, file)
       call spec_file_read_string(file, 'run_type', run_type)
    end if
    
    call pmc_mpi_bcast_string(run_type)
    if (trim(run_type) == 'particle') then
       call partmc_part(file)
    elseif (trim(run_type) == 'exact') then
       call partmc_exact(file)
    elseif (trim(run_type) == 'sectional') then
       call partmc_sect(file)
    else
       call die_msg(719261940, "unknown run_type: " // trim(run_type))
    end if

  end subroutine partmc_run

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Run a Monte Carlo simulation.
  subroutine partmc_part(file)

    !> Spec file.
    type(spec_file_t), intent(out) :: file

    character(len=100) :: kernel_name
    type(gas_data_t) :: gas_data
    type(gas_state_t) :: gas_state
    type(gas_state_t) :: gas_state_init
    type(aero_data_t) :: aero_data
    type(aero_weight_t) :: aero_weight
    type(aero_dist_t) :: aero_dist_init
    type(aero_state_t) :: aero_state
    type(aero_state_t) :: aero_state_init
    type(env_data_t) :: env_data
    type(env_state_t) :: env_state
    type(env_state_t) :: env_state_init
    type(bin_grid_t) :: bin_grid
    type(run_part_opt_t) :: part_opt
    integer :: i_loop
    integer :: rand_init
    character, allocatable :: buffer(:)
    integer :: buffer_size
    integer :: position
    logical :: do_restart
    character(len=PMC_MAX_FILENAME_LEN) :: restart_filename
    integer :: dummy_index, dummy_i_loop
    real(kind=dp) :: dummy_time, dummy_del_t
    character(len=PMC_MAX_FILENAME_LEN) :: sub_filename
    type(spec_file_t) :: sub_file

    !> \page input_format_particle Input File Format: Particle-Resolved Simulation
    !!
    !! See \ref spec_file_format for the input file text format.
    !!
    !! A particle-resolved simulation spec file has the parameters:
    !! - \b run_type (string): must be \c particle
    !! - \b output_prefix (string): prefix of the output filenames
    !!   --- see \ref output_format for the full name format
    !! - \b n_loop (integer): number of loops
    !! - \b n_part (integer): number of computational particles to
    !!   simulate (actual number used will vary between <tt>n_part /
    !!   2</tt> and <tt>n_part * 2</tt> if \c allow_doubling and \c
    !!   allow_halving are \c yes)
    !! - \b kernel (string): the type of coagulation kernel --- must
    !!   be one of: \c sedi for the gravitational sedimentation
    !!   kernel; \c golovin for the additive Golovin kernel;
    !!   \c constant for the constant kernel; \c brown for the
    !!   Brownian kernel, or \c zero for no coagulation
    !! - \subpage input_format_nucleate
    !! - \b restart (logical): whether to restart the simulation
    !!   from a saved output data file
    !! - \b restart_file (string): name of file from which to load
    !!   restart data, which must be a PartMC output NetCDF file
    !!   (only provide option if \c restart is \c yes)
    !! - \b t_max (real, unit s): total simulation time
    !! - \b del_t (real, unit s): timestep size
    !! - \b t_output (real, unit s): the interval on which to
    !!   output data to disk (see \ref output_format)
    !! - \b t_progress (real, unit s): the interval on which to
    !!   write summary information to the screen while running
    !! - \subpage input_format_bin_grid --- only used for efficiency
    !!   gains during coagulation
    !! - \subpage input_format_aero_weight
    !! - \b gas_data (string): name of file from which to read the
    !!   gas material data --- the file format should be
    !!   \subpage input_format_gas_data
    !! - \b gas_init (string): name of file from which to read the
    !!   initial gas state at the start of the simulation (only
    !!   provide option if \c restart is \c no) --- the file format
    !!   should be \subpage input_format_gas_state
    !! - \b aero_data (string): name of file from which to read the
    !!   aerosol material data --- the file format should be
    !!   \subpage input_format_aero_data
    !! - \b aerosol_init (string): filename containing the initial
    !!   aerosol state at the start of the simulation (only provide
    !!   option if \c restart is \c no) --- the file format should
    !!   be \subpage input_format_aero_dist
    !! - \subpage input_format_env_data
    !! - \subpage input_format_env_state
    !! - \b rand_init (integer): if greater than zero then use as
    !!   the seed for the random number generator, or if zero then
    !!   generate a random seed for the random number generator ---
    !!   two simulations on the same machine with the same seed
    !!   (greater than 0) will produce identical output
    !! - \b do_coagulation (logical): whether to perform particle
    !!   coagulation
    !! - \b allow_doubling (logical): if \c yes, then whenever the
    !!   number of simulated particles falls below <tt>n_part /
    !!   2</tt>, every particle is duplicated to give better
    !!   statistics
    !! - \b allow_halving (logical): if \c yes, then whenever the
    !!   number of simulated particles rises above <tt>n_part *
    !!   2</tt>, half of the particles are removed (chosen randomly)
    !!   to reduce the computational expense
    !! - \b do_condensation (logical): whether to perform explicit
    !!   water condensation (requires SUNDIALS support to be
    !!   compiled in; cannot be used simultaneously with MOSAIC)
    !! - \b do_mosaic (logical): whether to use the MOSAIC
    !!   chemistry code (requires support to be compiled in; cannot
    !!   be used simultaneously with condensation)
    !! - \b do_optical (logical): whether to compute optical
    !!   properties of the aersol particles for the output files ---
    !!   see output_format_aero_state (only provide option if \c
    !!   do_mosaic is \c yes)
    !! - \b record_removals (logical): whether to record information
    !!   about aerosol particles removed from the simulation --- see
    !!   \ref output_format_aero_removed
    !! - \b do_parallel (logical): whether to run in parallel mode
    !!   (requires MPI support to be compiled in)
    !! - if \c do_parallel is \c yes, then the following parameters
    !!     must also be provided:
    !!   - \b output_type (string): type of parallel disk output ---
    !!     must be one of: \c central to write one file per processor,
    !!     but all written by processor 0; \c dist for every processor
    !!     to write its own state file; or \c single to transfer all
    !!     data to processor 0 and write a single unified output file
    !!   - \b mix_timescale (real, unit s): timescale on which to mix
    !!     simulation state information amongst processors in an
    !!     attempt to keep them consistent (the mixing rate is inverse
    !!     to \c mix_timescale)
    !!   - \b gas_average (logical): whether to average the gas state
    !!     amongst processors each timestep, to ensure uniform gas
    !!     concentrations
    !!   - \b env_average (logical): whether to average the
    !!     environment state amongst processors each timestep, to
    !!     ensure a uniform environment
    !!   - \b coag_method (logical): type of parallel coagulation ---
    !!     must be one of: \c local for only within-processor
    !!     coagulation; \c collect to transfer all particles to
    !!     processor 0 each timestep and coagulate there; \c central to
    !!     have processor 0 do all coagulation by requesting
    !!     individual particles as needed; or \c dist to have all
    !!     processors perform coagulation globally, requesting
    !!     particles from other processors as needed

    call gas_data_allocate(gas_data)
    call gas_state_allocate(gas_state)
    call gas_state_allocate(gas_state_init)
    call aero_data_allocate(aero_data)
    call aero_weight_allocate(aero_weight)
    call aero_dist_allocate(aero_dist_init)
    call aero_state_allocate(aero_state)
    call aero_state_allocate(aero_state_init)
    call env_data_allocate(env_data)
    call env_state_allocate(env_state)
    call env_state_allocate(env_state_init)
    call bin_grid_allocate(bin_grid)
    
    if (pmc_mpi_rank() == 0) then
       ! only the root process does I/O

       call spec_file_read_string(file, 'output_prefix', &
            part_opt%output_prefix)
       call spec_file_read_integer(file, 'n_loop', part_opt%n_loop)
       call spec_file_read_integer(file, 'n_part', part_opt%n_part_max)
       call spec_file_read_string(file, 'kernel', kernel_name)
       call spec_file_read_nucleate(file, part_opt%nucleate_type)
       call spec_file_read_logical(file, 'restart', do_restart)
       if (do_restart) then
          call spec_file_read_string(file, 'restart_file', restart_filename)
       end if
       
       call spec_file_read_real(file, 't_max', part_opt%t_max)
       call spec_file_read_real(file, 'del_t', part_opt%del_t)
       call spec_file_read_real(file, 't_output', part_opt%t_output)
       call spec_file_read_real(file, 't_progress', part_opt%t_progress)

       call spec_file_read_bin_grid(file, bin_grid)
       call spec_file_read_aero_weight(file, aero_weight)

       if (do_restart) then
          call input_state(restart_filename, bin_grid, aero_data, &
               aero_weight, aero_state_init, gas_data, gas_state_init, &
               env_state_init, dummy_index, dummy_time, dummy_del_t, &
               dummy_i_loop)
       end if

       call spec_file_read_string(file, 'gas_data', sub_filename)
       call spec_file_open(sub_filename, sub_file)
       call spec_file_read_gas_data(sub_file, gas_data)
       call spec_file_close(sub_file)

       if (.not. do_restart) then
          call spec_file_read_string(file, 'gas_init', sub_filename)
          call spec_file_open(sub_filename, sub_file)
          call spec_file_read_gas_state(sub_file, gas_data, &
               gas_state_init)
          call spec_file_close(sub_file)
       end if
       
       call spec_file_read_string(file, 'aero_data', sub_filename)
       call spec_file_open(sub_filename, sub_file)
       call spec_file_read_aero_data(sub_file, aero_data)
       call spec_file_close(sub_file)
       
       if (.not. do_restart) then
          call spec_file_read_string(file, 'aerosol_init', sub_filename)
          call spec_file_open(sub_filename, sub_file)
          call spec_file_read_aero_dist(sub_file, aero_data, aero_dist_init)
          call spec_file_close(sub_file)
       end if
       
       call spec_file_read_env_data(file, bin_grid, gas_data, aero_data, &
            env_data)
       call spec_file_read_env_state(file, env_state_init)
       
       call spec_file_read_integer(file, 'rand_init', rand_init)
       call spec_file_read_logical(file, 'do_coagulation', &
            part_opt%do_coagulation)
       call spec_file_read_logical(file, 'allow_doubling', &
            part_opt%allow_doubling)
       call spec_file_read_logical(file, 'allow_halving', &
            part_opt%allow_halving)
       call spec_file_read_logical(file, 'do_condensation', &
            part_opt%do_condensation)
#ifndef PMC_USE_SUNDIALS
       call assert_msg(121370218, part_opt%do_condensation .eqv. .false., &
            "cannot use condensation, SUNDIALS support is not compiled in")
#endif
       call spec_file_read_logical(file, 'do_mosaic', part_opt%do_mosaic)
       if (part_opt%do_mosaic .and. (.not. mosaic_support())) then
          call spec_file_die_msg(230495365, file, &
               'cannot use MOSAIC, support is not compiled in')
       end if
       if (part_opt%do_mosaic) then
          call spec_file_read_logical(file, 'do_optical', part_opt%do_optical)
       else
          part_opt%do_optical = .false.
       end if
       call spec_file_read_logical(file, 'record_removals', &
            part_opt%record_removals)

       call spec_file_read_logical(file, 'do_parallel', part_opt%do_parallel)
       if (part_opt%do_parallel) then
#ifndef PMC_USE_MPI
          call spec_file_die_msg(929006383, file, &
               'cannot use parallel mode, support is not compiled in')
#endif
          call spec_file_read_string(file, 'output_type', part_opt%output_type)
          call spec_file_read_real(file, 'mix_timescale', part_opt%mix_timescale)
          call spec_file_read_logical(file, 'gas_average', part_opt%gas_average)
          call spec_file_read_logical(file, 'env_average', part_opt%env_average)
          call spec_file_read_string(file, 'coag_method', part_opt%coag_method)
       else
          part_opt%output_type = "single"
          part_opt%mix_timescale = 0d0
          part_opt%gas_average = .false.
          part_opt%env_average = .false.
          part_opt%coag_method = "local"
       end if
       
       call spec_file_close(file)
    end if

    ! finished reading .spec data, now broadcast data

#ifdef PMC_USE_MPI
    if (pmc_mpi_rank() == 0) then
       ! root process determines size
       buffer_size = 0
       buffer_size = buffer_size + pmc_mpi_pack_size_part_opt(part_opt)
       buffer_size = buffer_size + pmc_mpi_pack_size_string(kernel_name)
       buffer_size = buffer_size + pmc_mpi_pack_size_bin_grid(bin_grid)
       buffer_size = buffer_size + pmc_mpi_pack_size_gas_data(gas_data)
       buffer_size = buffer_size + pmc_mpi_pack_size_gas_state(gas_state_init)
       buffer_size = buffer_size + pmc_mpi_pack_size_aero_data(aero_data)
       buffer_size = buffer_size + pmc_mpi_pack_size_aero_weight(aero_weight)
       buffer_size = buffer_size &
            + pmc_mpi_pack_size_aero_dist(aero_dist_init)
       buffer_size = buffer_size + pmc_mpi_pack_size_env_data(env_data)
       buffer_size = buffer_size + pmc_mpi_pack_size_env_state(env_state_init)
       buffer_size = buffer_size + pmc_mpi_pack_size_integer(rand_init)
       buffer_size = buffer_size + pmc_mpi_pack_size_logical(do_restart)
       buffer_size = buffer_size + pmc_mpi_pack_size_aero_state(aero_state_init)
    end if

    ! tell everyone the size and allocate buffer space
    call pmc_mpi_bcast_integer(buffer_size)
    allocate(buffer(buffer_size))

    if (pmc_mpi_rank() == 0) then
       ! root process packs data
       position = 0
       call pmc_mpi_pack_part_opt(buffer, position, part_opt)
       call pmc_mpi_pack_string(buffer, position, kernel_name)
       call pmc_mpi_pack_bin_grid(buffer, position, bin_grid)
       call pmc_mpi_pack_gas_data(buffer, position, gas_data)
       call pmc_mpi_pack_gas_state(buffer, position, gas_state_init)
       call pmc_mpi_pack_aero_data(buffer, position, aero_data)
       call pmc_mpi_pack_aero_weight(buffer, position, aero_weight)
       call pmc_mpi_pack_aero_dist(buffer, position, aero_dist_init)
       call pmc_mpi_pack_env_data(buffer, position, env_data)
       call pmc_mpi_pack_env_state(buffer, position, env_state_init)
       call pmc_mpi_pack_integer(buffer, position, rand_init)
       call pmc_mpi_pack_logical(buffer, position, do_restart)
       call pmc_mpi_pack_aero_state(buffer, position, aero_state_init)
       call assert(181905491, position == buffer_size)
    end if

    ! broadcast data to everyone
    call pmc_mpi_bcast_packed(buffer)

    if (pmc_mpi_rank() /= 0) then
       ! non-root processes unpack data
       position = 0
       call pmc_mpi_unpack_part_opt(buffer, position, part_opt)
       call pmc_mpi_unpack_string(buffer, position, kernel_name)
       call pmc_mpi_unpack_bin_grid(buffer, position, bin_grid)
       call pmc_mpi_unpack_gas_data(buffer, position, gas_data)
       call pmc_mpi_unpack_gas_state(buffer, position, gas_state_init)
       call pmc_mpi_unpack_aero_data(buffer, position, aero_data)
       call pmc_mpi_unpack_aero_weight(buffer, position, aero_weight)
       call pmc_mpi_unpack_aero_dist(buffer, position, aero_dist_init)
       call pmc_mpi_unpack_env_data(buffer, position, env_data)
       call pmc_mpi_unpack_env_state(buffer, position, env_state_init)
       call pmc_mpi_unpack_integer(buffer, position, rand_init)
       call pmc_mpi_unpack_logical(buffer, position, do_restart)
       call pmc_mpi_unpack_aero_state(buffer, position, aero_state_init)
       call assert(143770146, position == buffer_size)
    end if

    ! free the buffer
    deallocate(buffer)
#endif

    call pmc_srand(rand_init + pmc_mpi_rank())

    call gas_state_deallocate(gas_state)
    call gas_state_allocate_size(gas_state, gas_data%n_spec)
    call cpu_time(part_opt%t_wall_start)
    
    do i_loop = 1,part_opt%n_loop
       part_opt%i_loop = i_loop
       
       call gas_state_copy(gas_state_init, gas_state)
       if (do_restart) then
          call aero_state_copy(aero_state_init, aero_state)
       else
          call aero_state_deallocate(aero_state)
          call aero_state_allocate_size(aero_state, bin_grid%n_bin, &
               aero_data%n_spec)
          aero_state%comp_vol = real(part_opt%n_part_max, kind=dp) / &
               aero_dist_weighted_num_conc(aero_dist_init, aero_weight)
          call aero_state_add_aero_dist_sample(aero_state, bin_grid, &
               aero_data, aero_weight, aero_dist_init, 1d0, 0d0)
       end if
       call env_state_copy(env_state_init, env_state)
       call env_data_init_state(env_data, env_state, env_state_init%elapsed_time)

#ifdef PMC_USE_SUNDIALS
       if (part_opt%do_condensation) then
          call condense_equilib_particles(bin_grid, env_state, aero_data, &
               aero_weight, aero_state)
       end if
#endif
       
       if (trim(kernel_name) == 'sedi') then
          call run_part(kernel_sedi, kernel_sedi_max, bin_grid, &
               env_data, env_state, aero_data, aero_weight, &
               aero_state, gas_data, gas_state, part_opt)
       elseif (trim(kernel_name) == 'golovin') then
          call run_part(kernel_golovin, kernel_golovin_max, bin_grid, &
               env_data, env_state, aero_data, aero_weight, &
               aero_state, gas_data, gas_state, part_opt)
       elseif (trim(kernel_name) == 'constant') then
          call run_part(kernel_constant, kernel_constant_max, bin_grid, &
               env_data, env_state, aero_data, aero_weight, &
               aero_state, gas_data, gas_state, part_opt)
       elseif (trim(kernel_name) == 'brown') then
          call run_part(kernel_brown, kernel_brown_max, bin_grid, &
               env_data, env_state, aero_data, aero_weight, &
               aero_state, gas_data, gas_state, part_opt)
       elseif (trim(kernel_name) == 'zero') then
          call run_part(kernel_zero, kernel_zero_max, bin_grid, &
               env_data, env_state, aero_data, aero_weight, &
               aero_state, gas_data, gas_state, part_opt)
       else
          if (pmc_mpi_rank() == 0) then
             call die_msg(727498351, 'unknown kernel type: ' &
                  // trim(kernel_name))
          end if
          call pmc_mpi_abort(1)
       end if

    end do

    call gas_data_deallocate(gas_data)
    call gas_state_deallocate(gas_state)
    call gas_state_deallocate(gas_state_init)
    call aero_data_deallocate(aero_data)
    call aero_weight_deallocate(aero_weight)
    call aero_dist_deallocate(aero_dist_init)
    call aero_state_deallocate(aero_state)
    call aero_state_deallocate(aero_state_init)
    call env_data_deallocate(env_data)
    call env_state_deallocate(env_state)
    call env_state_deallocate(env_state_init)
    call bin_grid_deallocate(bin_grid)

  end subroutine partmc_part

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Run an exact solution simulation.
  subroutine partmc_exact(file)

    !> Spec file.
    type(spec_file_t), intent(out) :: file

    character(len=100) :: soln_name
    type(aero_data_t) :: aero_data
    type(env_data_t) :: env_data
    type(env_state_t) :: env_state
    type(run_exact_opt_t) :: exact_opt
    type(bin_grid_t) :: bin_grid
    type(gas_data_t) :: gas_data
    character(len=PMC_MAX_FILENAME_LEN) :: sub_filename
    type(spec_file_t) :: sub_file

    !> \page input_format_exact Exact (Analytical) Solution
    !!
    !! See \ref spec_file_format for the input file text format.
    !!
    !! An exact (analytical) simulation spec file has the parameters:
    !! - \b run_type (string): must be \c exact
    !! - \b output_prefix (string): prefix of the output filenames ---
    !!   the filenames will be of the form \c PREFIX_SSSSSSSS.nc where
    !!   \c SSSSSSSS is is the eight-digit output index (starting at 1
    !!   and incremented each time the state is output)
    !! - \b t_max (real, unit s): total simulation time
    !! - \b t_output (real, unit s): the interval on which to output
    !!   data to disk and to print progress information to the screen
    !! - \subpage input_format_bin_grid
    !! - \b gas_data (string): name of file from which to read the
    !!   gas material data --- the file format should be
    !!   \subpage input_format_gas_data
    !! - \b aero_data (string): name of file from which to read the
    !!   aerosol material data --- the file format should be
    !!   \subpage input_format_aero_data
    !! - \subpage input_format_env_data
    !! - \subpage input_format_env_state
    !! - \b soln (string): the type of exact solution to generate ---
    !!   must be one of \c golovin_exp, \c constant_exp_cond, or \c
    !!   zero.
    !! - If \c soln is \c golovin_exp then the number concentration is
    !!   generated for an exponential initial condition (\c mode_type
    !!   set to \c exp in \ref input_format_aero_mode) with a Golovin
    !!   coagulation kernel (\c kernel set to \c golovin in \ref
    !!   input_format_particle) and no emissions or dilution. See
    !!   soln_golovin_exp() for the solution expression. The
    !!   subsequent parameters are:
    !!   - \b num_conc (real, unit 1/m^3): The total number
    !!     concentration \f$N_0\f$.
    !!   - \b mean_radius (real, unit m): The radius \f$r_\mu\f$ that
    !!     gives the diameter \f$D_\mu = 2 r_\mu\f$ and the mean volume
    !!     \f$v_\mu = \frac{\pi}{6} D_\mu^3\f$.
    !! - If \c soln is \c constant_exp_cond then the exact solution is
    !!   generated for an exponential initial condition (\c mode_type
    !!   set to \c exp in \ref input_format_aero_mode) with a constant
    !!   coagulation kernel (\c kernel set to \c constant in \ref
    !!   input_format_particle) and no emissions or dilution. See
    !!   soln_constant_exp_cond() for the solution expression. The
    !!   subsequent parameters are:
    !!   - \b num_conc (real, unit 1/m^3): The total number
    !!     concentration \f$N_0\f$.
    !!   - \b mean_radius (real, unit m): The radius \f$r_\mu\f$ that
    !!     gives the diameter \f$D_\mu = 2 r_\mu\f$ and the mean volume
    !!     \f$v_\mu = \frac{\pi}{6} D_\mu^3\f$.
    !! - If \c soln is \c zero then the exact solution is given with
    !!   no coagulation (\c kernel set to \c zero in \ref
    !!   input_format_particle), but with constant emissions and background
    !!   dilution. See soln_zero() for the solution expression. The
    !!   subsequent parameters are:
    !!   - \b aerosol_init (string): The name of the file from which
    !!     to read the inital aerosol distribution, in the format \ref
    !!     input_format_aero_dist.

    ! only serial code here
    if (pmc_mpi_rank() /= 0) then
       return
    end if
    
    call bin_grid_allocate(bin_grid)
    call gas_data_allocate(gas_data)
    call aero_data_allocate(aero_data)
    call env_data_allocate(env_data)
    call env_state_allocate(env_state)
    call aero_dist_allocate(exact_opt%aero_dist_init)

    call spec_file_read_string(file, 'output_prefix', exact_opt%prefix)

    call spec_file_read_real(file, 't_max', exact_opt%t_max)
    call spec_file_read_real(file, 't_output', exact_opt%t_output)

    call spec_file_read_bin_grid(file, bin_grid)

    call spec_file_read_string(file, 'gas_data', sub_filename)
    call spec_file_open(sub_filename, sub_file)
    call spec_file_read_gas_data(sub_file, gas_data)
    call spec_file_close(sub_file)

    call spec_file_read_string(file, 'aero_data', sub_filename)
    call spec_file_open(sub_filename, sub_file)
    call spec_file_read_aero_data(sub_file, aero_data)
    call spec_file_close(sub_file)

    call spec_file_read_env_data(file, bin_grid, gas_data, aero_data, &
         env_data)
    call spec_file_read_env_state(file, env_state)

    call spec_file_read_string(file, 'soln', soln_name)

    if (trim(soln_name) == 'golovin_exp') then
       call spec_file_read_real(file, 'num_conc', exact_opt%num_conc)
       call spec_file_read_real(file, 'mean_radius', exact_opt%mean_radius)
    elseif (trim(soln_name) == 'constant_exp_cond') then
       call spec_file_read_real(file, 'num_conc', exact_opt%num_conc)
       call spec_file_read_real(file, 'mean_radius', exact_opt%mean_radius)
    elseif (trim(soln_name) == 'zero') then
       call spec_file_read_string(file, 'aerosol_init', sub_filename)
       call spec_file_open(sub_filename, sub_file)
       call spec_file_read_aero_dist(sub_file, aero_data, &
            exact_opt%aero_dist_init)
       call spec_file_close(sub_file)
    else
       call die_msg(955390033, 'unknown solution type: ' &
            // trim(soln_name))
    end if
    
    call spec_file_close(file)

    ! finished reading .spec data, now do the run

    call env_data_init_state(env_data, env_state, 0d0)

    if (trim(soln_name) == 'golovin_exp') then
       call run_exact(bin_grid, env_data, env_state, aero_data, exact_opt, &
            soln_golovin_exp)
    elseif (trim(soln_name) == 'golovin_exp') then
       call run_exact(bin_grid, env_data, env_state, aero_data, exact_opt, &
            soln_constant_exp_cond)
    elseif (trim(soln_name) == 'zero') then
       call run_exact(bin_grid, env_data, env_state, aero_data, exact_opt, &
            soln_zero)
    else
       call die_msg(859292825, 'unknown solution type: ' &
            // trim(soln_name))
    end if

    call aero_data_deallocate(aero_data)
    call env_data_deallocate(env_data)
    call env_state_deallocate(env_state)
    call bin_grid_deallocate(bin_grid)
    call gas_data_deallocate(gas_data)
    call aero_dist_deallocate(exact_opt%aero_dist_init)
    
  end subroutine partmc_exact

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  !> Run a sectional code simulation.
  subroutine partmc_sect(file)

    !> Spec file.
    type(spec_file_t), intent(out) :: file

    character(len=100) :: kernel_name
    type(run_sect_opt_t) :: sect_opt
    type(aero_data_t) :: aero_data
    type(aero_dist_t) :: aero_dist_init
    type(aero_state_t) :: aero_init
    type(env_data_t) :: env_data
    type(env_state_t) :: env_state
    type(bin_grid_t) :: bin_grid
    type(gas_data_t) :: gas_data
    character(len=PMC_MAX_FILENAME_LEN) :: sub_filename
    type(spec_file_t) :: sub_file

    !> \page input_format_sectional Sectional Model Simulation
    !!
    !! Under construction...

    ! only serial code here
    if (pmc_mpi_rank() /= 0) then
       return
    end if
    
    call aero_data_allocate(aero_data)
    call aero_dist_allocate(aero_dist_init)
    call env_state_allocate(env_state)
    call env_data_allocate(env_data)
    call bin_grid_allocate(bin_grid)
    call gas_data_allocate(gas_data)

    call spec_file_read_string(file, 'output_prefix', sect_opt%prefix)
    call spec_file_read_string(file, 'kernel', kernel_name)

    call spec_file_read_real(file, 't_max', sect_opt%t_max)
    call spec_file_read_real(file, 'del_t', sect_opt%del_t)
    call spec_file_read_real(file, 't_output', sect_opt%t_output)
    call spec_file_read_real(file, 't_progress', sect_opt%t_progress)

    call spec_file_read_bin_grid(file, bin_grid)

    call spec_file_read_string(file, 'gas_data', sub_filename)
    call spec_file_open(sub_filename, sub_file)
    call spec_file_read_gas_data(sub_file, gas_data)
    call spec_file_close(sub_file)
    
    call spec_file_read_string(file, 'aero_data', sub_filename)
    call spec_file_open(sub_filename, sub_file)
    call spec_file_read_aero_data(sub_file, aero_data)
    call spec_file_close(sub_file)

    call spec_file_read_string(file, 'aerosol_init', sub_filename)
    call spec_file_open(sub_filename, sub_file)
    call spec_file_read_aero_dist(sub_file, aero_data, aero_dist_init)
    call spec_file_close(sub_file)

    call spec_file_read_env_data(file, bin_grid, gas_data, aero_data, &
         env_data)
    call spec_file_read_env_state(file, env_state)

    call spec_file_read_logical(file, 'do_coagulation', &
         sect_opt%do_coagulation)
    
    call spec_file_close(file)

    ! finished reading .spec data, now do the run

    call env_data_init_state(env_data, env_state, 0d0)

    if (trim(kernel_name) == 'sedi') then
       call run_sect(bin_grid, gas_data, aero_data, aero_dist_init, &
            env_data, env_state, kernel_sedi, sect_opt)
    elseif (trim(kernel_name) == 'golovin') then
       call run_sect(bin_grid, gas_data, aero_data, aero_dist_init, &
            env_data, env_state, kernel_golovin, sect_opt)
    elseif (trim(kernel_name) == 'constant') then
       call run_sect(bin_grid, gas_data, aero_data, aero_dist_init, &
            env_data, env_state, kernel_constant, sect_opt)
    elseif (trim(kernel_name) == 'brown') then
       call run_sect(bin_grid, gas_data, aero_data, aero_dist_init, &
            env_data, env_state, kernel_brown, sect_opt)
    elseif (trim(kernel_name) == 'zero') then
       call run_sect(bin_grid, gas_data, aero_data, aero_dist_init, &
            env_data, env_state, kernel_zero, sect_opt)
    else
       call die_msg(859292825, 'unknown kernel type: ' &
            // trim(kernel_name))
    end if

    call aero_data_deallocate(aero_data)
    call aero_dist_deallocate(aero_dist_init)
    call env_state_deallocate(env_state)
    call env_data_deallocate(env_data)
    call bin_grid_deallocate(bin_grid)
    call gas_data_deallocate(gas_data)
    
  end subroutine partmc_sect

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

end program partmc
