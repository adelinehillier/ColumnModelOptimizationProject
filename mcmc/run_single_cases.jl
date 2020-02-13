using ColumnModelOptimizationProject

@free_parameters TKEParametersToOptimize Cᴷu Cᴷc Cᴷe Cᴰ Cᴸʷ Cᴸᵇ Cʷu★

include("setup.jl")
include("utils.jl")

         samples = 1000
      iterations = 3
              Δz = 4.0
              Δt = 4minute
relative_weights = [1e+0, 1e-4, 1e-4, 1e-6]

for casename in LESbrary.keys

    println(
            """

            *** Calibrating KPP to $(casename). ***

            """
           )

    LEScase = LESbrary[casename]

    # Place to store results
    kpp_results = @sprintf("kpp_calibration_%s_dz%d_dt%d.jld2", 
                           replace(replace(casename, ", " => "_"), ": " => ""),
                           Δz, Δt/minute) 

    # Run the case
    kpp_annealing = calibrate_kpp(joinpath(LESbrary_path, LEScase.filename), 
                                       samples = samples,
                                    iterations = iterations,
                                            Δz = Δz,
                                            Δt = Δt,
                                  first_target = LEScase.first, 
                                   last_target = LEScase.last,
                                        fields = LEScase.rotating ? (:T, :U, :V) : (:T, :U),
                              relative_weights = LEScase.rotating ? relative_weights[1:3] : relative_weights[[1, 2]],
                              profile_analysis = GradientProfileAnalysis(gradient_weight=0.5, value_weight=0.5))

    # Save results
    @save kpp_results kpp_annealing

    println(
            """

            *** Calibrating TKEMassFlux to $(casename). ***

            """
           )

    # Place to store results
    tke_results = @sprintf("tke_calibration_simple_%s_dz%d_dt%d.jld2",
                           replace(replace(casename, ", " => "_"), ": " => ""),
                           Δz, Δt/minute)

    # Run the case
    tke_annealing = calibrate_tke(joinpath(LESbrary_path, LEScase.filename), 
                                       samples = samples,
                                    iterations = iterations,
                                            Δz = Δz,
                                            Δt = Δt,
                                  first_target = LEScase.first, 
                                   last_target = LEScase.last,
                                        fields = LEScase.rotating ? (:T, :U, :V, :e) : (:T, :U, :e),
                              relative_weights = LEScase.rotating ? relative_weights : relative_weights[[1, 2, 4]],
                                 mixing_length = TKEMassFlux.SimpleMixingLength(), 
                              profile_analysis = GradientProfileAnalysis(gradient_weight=0.5, value_weight=0.5))

    # Save results
    @save tke_results tke_annealing

end
