module ColumnModelOptimizationProject

export
    dictify,
    FreeParameters,

    # file_wrangling.jl
    iterations,
    times,
    getdata,
    getconstant,
    getbc,
    getic,
    getgridparams,
    getdataparams,

    # data_analysis.jl
    removespines,
    summarize_data,

    # column_models.jl
    ColumnData,
    target_times,
    initial_time,
    ColumnModel ,

    # visualization.jl
    visualize_targets,
    visualize_realization,

    # loss_functions.jl
    temperature_loss,
    velocity_loss,
    weighted_fields_loss,

    # models/kpp_optimization.jl
    KPPOptimization

using
    StaticArrays,
    OceanTurb,
    OceanTurb.Plotting,
    JLD2,
    PyCall,
    Printf,
    PyPlot

import OceanTurb: set!, absolute_error

abstract type FreeParameters{N, T} <: FieldVector{N, T} end

dictify(p) = Dict((k, getproperty(p, k)) for k in propertynames(p))

set!(::Nothing, args...) = nothing # placeholder

include("file_wrangling.jl")
include("data_analysis.jl")
include("column_models.jl")
include("loss_functions.jl")
include("visualization.jl")

include("models/kpp_optimization.jl")

end # module
