using Distributed
addprocs(1)

@everywhere using Oceananigans, JLD2, Printf, OceananigansAnalysis

#include("utils.jl")
include("cfl_util.jl")
include("jld2_writer.jl")

#
# Initial condition, boundary condition, and tracer forcing
#

 N = 128
 L = 64
N² = 1e-6
Fb = 1e-9
Fu = 0.0
 g = 9.81
βT = 2e-4

hour = 3600
day = 24*hour
tfinal = 8*day

const dTdz = N² / (g * βT)
const T₀₀ = 20.0
const c₀₀ = 1

Fθ = Fb / (g*βT)

cbcs = FieldBoundaryConditions(z=ZBoundaryConditions(
    top    = BoundaryCondition(Value, c₀₀),
    bottom = BoundaryCondition(Value, 0.0)
   ))

Tbcs = FieldBoundaryConditions(z=ZBoundaryConditions(
    top    = BoundaryCondition(Flux, Fθ),
    bottom = BoundaryCondition(Gradient, dTdz)
   ))

ubcs = FieldBoundaryConditions(z=ZBoundaryConditions(
    top    = BoundaryCondition(Flux, Fu),
    bottom = DefaultBC()
   ))

@inline smoothstep(z, δ) = (1 - tanh(z/δ)) / 2

#
# Sponges and forcing
#

#=
const μ₀ = 1e-1 * (Fb / model.grid.Lz^2)^(1/3)
const δˢ = model.grid.Lz / 10
const zˢ = -9 * model.grid.Lz / 10

"A step function which is 0 above z=0 and 1 below."
@inline μ(z) = μ₀ * step(z-zˢ, δˢ) # sponge function

@inline Fuˢ(grid, u, v, w, T, S, i, j, k) = 
    @inbounds -μ(grid.zC[k]) * u[i, j, k] 

@inline Fvˢ(grid, u, v, w, T, S, i, j, k) = 
    @inbounds -μ(grid.zC[k]) * v[i, j, k]

@inline Fwˢ(grid, u, v, w, T, S, i, j, k) = 
    @inbounds -μ(grid.zC[k]) * w[i, j, k]

@inline FTˢ(grid, u, v, w, T, S, i, j, k) = 
    @inbounds  μ(grid.zC[k]) * (T₀★(grid.zC[k]) - T[i, j, k])

forcing = Forcing(Fu=Fuˢ, Fv=Fvˢ, Fw=Fwˢ, FT=FTˢ) #, FS=Fc)
=#

# 
# Model setup
# 

arch = CPU()
@hascuda arch = GPU() # use GPU if it's available

model = Model(
     arch = arch,
        N = (N,   N, N),
        L = (2L, 2L, L), 
  closure = AnisotropicMinimumDissipation(),
      eos = LinearEquationOfState(βT=βT, βS=0.),
constants = PlanetaryConstants(f=1e-4, g=g),
      bcs = BoundaryConditions(u=ubcs, T=Tbcs, S=cbcs)
)

filename(model) = @sprintf("free_convection_Fb%.1e_Fu%.1e_Lz%d_Nz%d",
                           Fb, Fu, model.grid.Lz, model.grid.Nz)

# Temperature initial condition

T₀★(z) = T₀₀ + dTdz * z

# Add a bit of surface-concentrated noise to the initial condition
ξ(z) = 1e-6 * rand() * exp(4z/model.grid.Lz) 

T₀(x, y, z) = T₀★(z) + dTdz * model.grid.Lz * (1 + ξ(z))
u₀(x, y, z) = ξ(z)
v₀(x, y, z) = ξ(z)
c₀(x, y, z) = ξ(z)

set_ic!(model, u=u₀, v=v₀, T=T₀, S=c₀)

#
# Output
#

#=
function savebcs(file, model)
    file["bcs/Fb"] = Fb
    file["bcs/Fu"] = Fu
    file["bcs/dTdz"] = dTdz
    file["bcs/c₀₀"] = c₀₀
    return nothing
end

u(model)  = Array(data(model.velocities.u))
v(model)  = Array(data(model.velocities.v))
w(model)  = Array(data(model.velocities.w))
θ(model)  = Array(data(model.tracers.T))
c(model)  = Array(data(model.tracers.S))

struct HorizontalAverages{A}
    U :: A
    V :: A
    T :: A
    S :: A
end

function HorizontalAverages(arch::CPU, grid::Grid{FT}) where FT
    U = zeros(FT, 1, 1, grid.Tz)
    V = zeros(FT, 1, 1, grid.Tz)
    T = zeros(FT, 1, 1, grid.Tz)
    S = zeros(FT, 1, 1, grid.Tz)

    HorizontalAverages(U, V, W, T, S)
end

function HorizontalAverages(arch::CPU, grid::Grid{FT}) where FT
    U = CuArray{FT}(undef, 1, 1, grid.Tz)
    V = CuArray{FT}(undef, 1, 1, grid.Tz)
    T = CuArray{FT}(undef, 1, 1, grid.Tz)
    S = CuArray{FT}(undef, 1, 1, grid.Tz)

    HorizontalAverages(U, V, T, S)
end

HorizontalAverages(m::Model{A}) where A = 
    HorizontalAverages(A(), model.grid)

function hmean!(ϕavg, ϕ::Field)
    ϕavg .= mean(ϕ.data, dims=(1, 2))
end

const avgs = HorizontalAverages(model)

function U(model)
    hmean!(avgs.U, model.velocities.u)
    return Array(avgs.U)
end

function V(model)
    hmean!(avgs.V, model.velocities.v)
    return Array(avgs.V)
end

function T(model)
    hmean!(avgs.T, model.tracers.T)
    return Array(avgs.T)
end

function S(model)
    hmean!(avgs.S, model.tracers.S)
    return Array(avgs.S)
end

profiles = Dict(:U=>U, :V=>V, :T=>T, :C=>C)
  fields = Dict(:u=>u, :v=>v, :w=>w, :θ=>θ, :c=>c)

profile_writer = JLD2OutputWriter(model, profiles; dir="data", 
                                  prefix=filename(model)*"_profiles", 
                                  init=savebcs, frequency=100, force=true,
                                  asynchronous=true)
                                  
field_writer = JLD2OutputWriter(model, fields; dir="data", 
                                prefix=filename(model)*"_fields", 
                                init=savebcs, frequency=1000, force=true,
                                asynchronous=true)
=#

#push!(model.output_writers, profile_writer, field_writer)

ρ₀ = 1035.0
cp = 3993.0

@printf(
    """
    Crunching a (viscous) ocean surface boundary layer with
    
            n : %d, %d, %d
           Fb : %.1e
           Fu : %.1e
            Q : %.2e
          |τ| : %.2e
          1/N : %.1f min
           βT : %.2e
    
    Let's spin the gears.
    
    """, model.grid.Nx, model.grid.Ny, model.grid.Nz, Fb, Fu, 
             -ρ₀*cp*Fb/(model.constants.g*model.eos.βT), abs(ρ₀*Fu),
             sqrt(1/N²) / 60, model.eos.βT
)

# Sensible CFL number
wizard = TimeStepWizard(cfl=1e-1, Δt=20.0)

@time time_step!(model, 1, 1e-16) # time first time-step

function messages(model, walltime, Δt) 
    return @sprintf("i: %05d, t: %.4f hours, Δt: %.1f s, wall: %s\n", 
                    model.clock.iteration, model.clock.time/3600, Δt, 
                    prettytime(1e9*walltime))
end

# Spinup
for i = 1:100
    @time update_Δt!(wizard, model)
    walltime = @elapsed time_step!(model, 1, wizard.Δt)
    println(messages(model, walltime, wizard.Δt))
end


@sync begin
    # Main loop
    while model.clock.time < tfinal
        @time update_Δt!(wizard, model)
        walltime = @elapsed time_step!(model, 100, wizard.Δt)
        println(messages(model, walltime, wizard.Δt))
    end
end
