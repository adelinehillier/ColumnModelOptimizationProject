using Statistics, Distributions, PyPlot, OrderedCollections, Optim, JLD2, Printf
using OceanTurb, Dao, ColumnModelOptimizationProject

using ColumnModelOptimizationProject.TKEMassFluxOptimization
using ColumnModelOptimizationProject.TKEMassFluxOptimization: ColumnModel

datadir = "/Users/gregorywagner/Projects/BoundaryLayerTurbulenceSimulations/idealized/data"

LESbrary = OrderedDict(
                   # Non-rotating
                    "kato, N²: 1e-7" => (
                       filename = "kato_phillips_Nsq1.0e-07_Qu1.0e-04_Nx256_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 1e-7, 
                          first = 5, 
                           last = 51),

                    "kato, N²: 2e-7" => (
                       filename = "kato_phillips_Nsq2.0e-07_Qu1.0e-04_Nx512_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 2e-7, 
                          first = 5, 
                           last = nothing),

                    "kato, N²: 5e-7" => (
                       filename = "kato_phillips_Nsq5.0e-07_Qu1.0e-04_Nx512_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 5e-7, 
                          first = 5, 
                           last = nothing),

                   "kato, N²: 1e-6" => (
                       filename = "kato_phillips_Nsq1.0e-06_Qu1.0e-04_Nx512_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 1e-6, 
                          first = 5, 
                           last = 61),

                   "kato, N²: 1e-5" => (
                       filename = "kato_phillips_Nsq1.0e-05_Qu1.0e-04_Nx256_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 1e-5, 
                          first = 21, 
                           last = 121),

                    "kato, N²: 1e-4" => (
                       filename = "kato_phillips_Nsq1.0e-04_Qu1.0e-04_Nx512_Nz256_averages.jld2", 
                       rotating = false, 
                             N² = 1e-4, 
                          first = 21, 
                           last = nothing),

                    # Rotating
                    "ekman, N²: 1e-6" => (
                       filename = "stress_driven_Nsq1.0e-06_f1.0e-04_Qu4.0e-04_Nh256_Nz256_averages.jld2",
                       rotating = true, 
                             N² = 1e-6, 
                          first = 11, 
                           last = 251),

                    "ekman, N²: 1e-5" => (
                       filename = "stress_driven_Nsq1.0e-05_f1.0e-04_Qu4.0e-04_Nh256_Nz256_averages.jld2",
                       rotating = true, 
                             N² = 1e-5, 
                          first = 11, 
                           last = nothing),

                    "ekman, N²: 1e-4" => (
                       filename = "stress_driven_Nsq1.0e-04_f1.0e-04_Qu4.0e-04_Nh128_Nz128_averages.jld2",
                       rotating = true, 
                             N² = 1e-4, 
                          first = 11, 
                           last = nothing),
                   )

function initialize_calibration(dataname; Δ=4, Δt=10second, first_target=5, last_target=nothing, fields=(:T, :U, :e),
                                 mixing_length = TKEMassFlux.SimpleMixingLength(),
                                tke_wall_model = TKEMassFlux.PrescribedSurfaceTKEFlux())

    # Model and data
    datapath = joinpath(datadir, dataname)
    data = ColumnData(datapath)
    model = ColumnModel(data, Δt, Δ=Δ, mixing_length=mixing_length, tke_wall_model=tke_wall_model)

    # Create loss function and negative-log-likelihood object
    last_target = last_target === nothing ? length(data) : last_target
    targets = first_target:last_target

    # Estimate weights based on maximum variance in the data
    max_variances = [max_variance(data, field, targets) for field in fields]
    weights = [1/σ for σ in max_variances]
    weights[1] *= 1e4
    weights[2] *= 1e2

    # Create loss function and NegativeLogLikelihood
    loss = LossFunction(model, data, fields=fields, targets=targets, weights=weights)
    nll = NegativeLogLikelihood(model, data, loss)

    # Initial state for optimization step
    default_parameters = DefaultFreeParameters(model, ParametersToOptimize)

    return nll, default_parameters
end

set_bound!(bounds, name, bound) =
    name ∈ propertynames(bounds) && setproperty!(bounds, name, bound)

function get_bounds_and_variance(default_parameters)
    # Set bounds on free parameters
    bounds = ParametersToOptimize(((0.01, 2.0) for p in default_parameters)...)

    # Some special bounds, in the cases they are included.
    set_bound!(bounds, :Cᴷu,  (0.01, 0.5))
    set_bound!(bounds, :Cᴷe,  (0.01, 1.0))
    set_bound!(bounds, :Cʷu★, (0.5, 6.0))

    variance = ParametersToOptimize((0.1 * bound[2] for bound in bounds)...)
    variance = Array(variance)

    return bounds, variance
end

function calibrate(nll, initial_parameters; samples=100, iterations=10,

                        annealing_schedule = AdaptiveAlgebraicSchedule(   initial_scale = 1e+0,
                                                                            final_scale = 1e-2,
                                                                       convergence_rate = 1.0, 
                                                                        rate_adaptivity = 1.5),

                       covariance_schedule = AdaptiveAlgebraicSchedule(   initial_scale = 1e+0,
                                                                            final_scale = 1e+0,
                                                                       convergence_rate = 1e+0,
                                                                        rate_adaptivity = 1.0), unused_kwargs...)

    bounds, variance = get_bounds_and_variance(initial_parameters)

    # Iterative simulated annealing...
    prob = anneal(nll, initial_parameters, variance, BoundedNormalPerturbation, bounds;
                           iterations = iterations,
                              samples = samples,
                   annealing_schedule = annealing_schedule,
                  covariance_schedule = covariance_schedule
                 )
    
    return prob
end

function calibrate(datapath; initial_parameters=nothing, calibration_and_initialization_kwargs...)

    nll, default_parameters = initialize_calibration(datapath; calibration_and_initialization_kwargs...)

    initial_parameters = initial_parameters === nothing ? default_parameters : initial_parameters

    return calibrate(nll, initial_parameters; calibration_and_initialization_kwargs...)
end

function calibrate_batch(datapaths...; initial_parameters=nothing, calibration_and_initialization_kwargs...)

    nll_list = []
    for datapath in datapaths
        nll, default_parameters = initialize_calibration(datapath; calibration_kwargs...)
        push!(nll_list, nll)
    end

    batched_nll = BatchedNegativeLogLikelihood([nll for nll in nll_list])

    initial_parameters = initial_parameters === nothing ? default_parameters : initial_parameters

    return calibrate(nll, initial_parameters; calibration_and_initialization_kwargs...)
end
  
buoyancy_frequency(data) = data.constants.g * data.constants.α * data.initial_conditions.dTdz 

struct OptimSafeNegativeLogLikelihood{P, N} 
    parameters :: P
    negative_log_likelihood :: N
    function OptimSafeNegativeLogLikelihood(θ, ℒ)
        θ′ = deepcopy(θ)
        return new{typeof(θ′), typeof(ℒ)}(θ′, ℒ)
    end
end

function (nll::OptimSafeNegativeLogLikelihood)(θ) 
    for i in eachindex(nll.parameters)
        @inbounds nll.parameters[i] = θ[i]
    end
    return nll.negative_log_likelihood(nll.parameters)
end

"Use Optim to obtain a guess for optimal parameters."
function optim_optimized_parameters(nll, initial_parameters)
    optim_nll = OptimSafeNegativeLogLikelihood(initial_parameters, nll)
    residual = optimize(optim_nll, Array(initial_parameters))
    return typeof(initial_parameters)(residual.minimizer)
end
