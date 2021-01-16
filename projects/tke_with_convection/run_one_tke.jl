using ColumnModelOptimizationProject

include("setup.jl")
include("utils.jl")

LESbrary_path = "/Users/andresouza/Dropbox/greg-andre/BoundaryLayerTurbulenceData"

# Optimization parameters
        casename = "convection, N²: 2e-6"
         samples = 1000
              Δz = 2.0
              Δt = 1minute
relative_weights = [1e+0, 1e-4, 1e-4, 1e-4]
         LEScase = LESbrary[casename]

# Place to store results
results = @sprintf("tke_calibration_%s_dz%d_dt%d.jld2", 
                   replace(replace(casename, ", " => "_"), ": " => ""),
                   Δz, Δt/minute) 

nll, _ = init_tke_calibration(LEScase.filename;
                                              Δz = Δz,
                                              Δt = Δt,
                                    first_target = LEScase.first, 
                                     last_target = LEScase.last,
                                          fields = tke_fields(LEScase),
                                relative_weights = tke_relative_weights(LEScase),
                              eddy_diffusivities = TKEMassFlux.RiDependentDiffusivities(),
                                   mixing_length = TKEMassFlux.SimpleMixingLength(),
                                  tke_wall_model = TKEMassFlux.PrescribedSurfaceTKEFlux(),
                                    tke_equation = TKEMassFlux.TKEParameters(),
                                      parameters = RiDependentTKEParameters,
                              )
#=
initial_parameters = RiDependentTKEParameters(
                                              Cᴷu⁻  = 1.2,
                                              Cᴷu⁺  = 1.2,
                                              Cᴷc⁻  = 5.0,
                                              Cᴷc⁺  = 5.0,
                                              Cᴷe⁻  = 0.7,
                                              Cᴷe⁺  = 0.7,
                                              CᴷRiᶜ = -1.0,
                                              CᴷRiʷ = 0.1,
                                              Cᴰ    = 4.0,
                                              Cᴸʷ   = 1.0,
                                              Cᴸᵇ   = 1.0,
                                              Cʷu★  = 1.0,
                                              CʷwΔ  = 1.9,
                                             )
=#

initial_parameters = TKEFreeConvectionParameters(
                                                 Cᴷc = 1.0,
                                                 Cᴷe = 1.0,
                                                 Cᴰ = 2.0,
                                                 Cᴸʷ = 1.0,
                                                 Cᴸᵇ = 1.0,
                                                 CʷwΔ = 1.0
                                                )

# Run the case
calibration = calibrate(nll, initial_parameters, samples = 100, iterations = 4)

# Save results
@save results calibration

# Do some simple analysis
model = calibration.negative_log_likelihood.model
 data = calibration.negative_log_likelihood.data
 loss = calibration.negative_log_likelihood.loss
chain = calibration.markov_chains[end]
   C★ = optimal(chain).param

close("all")
viz_fig, viz_axs = visualize_realizations(model, data, loss.targets[[1, end]], C★,
                                           fields = (:T, :e), 
                                          figsize = (16, 6)) 

#=
fig, axs = subplots(ncols=2, figsize=(16, 6))

optimums = optimum_series(annealing)
errors = [optimal(chain).error for chain in annealing.markov_chains]

for (i, name) in enumerate(propertynames(optimums))
    series = optimums[i]
    final_value = series[end]
    lbl = parameter_latex_guide[name]

    sca(axs[1])
    plot(series / final_value, linestyle="-", marker="o", markersize=5, linewidth=1, label=lbl)
end

legend()

sca(axs[2])
plot(errors / errors[1], linestyle="-", marker="o", markersize=5, linewidth=1)
=#
