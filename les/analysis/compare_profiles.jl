using JLD2, PyPlot, Dao,
        ColumnModelOptimizationProject, Printf,
        OceanTurb, OffsetArrays, LinearAlgebra

using ColumnModelOptimizationProject.ModularKPPOptimization

@use_pyplot_utils
usecmbright()

datadir = "data"
name = "simple_flux_Fb0e+00_Fu-1e-04_Nsq5e-06_Lz64_Nz128"

filepath = joinpath(@__DIR__, "..", datadir, name * "_profiles.jld2")

iters = iterations(filepath)
data = ColumnData(filepath, reversed=true, initial=5, targets=[9, 25, 121])
model = ModularKPPOptimization.ColumnModel(data, 5minute, Δ=2)
defaultparams = DefaultFreeParameters(model, WindMixingParameters)

fig, axs = visualize_realization(defaultparams, model, data)
gcf()
