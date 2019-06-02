using Plots, Oceananigans, Statistics, OceananigansAnalysis, JLD2

removespine(side; ax=gca()) = ax.spines[side].set_visible(false)
removespines(sides...; ax=gca()) = [removespine(side, ax=ax) for side in sides]
usecmbright()

match_yaxes!(ax1, ax2) = nothing

function makeplot(axs, model)

    wb = model.velocities.w * model.tracers.T
     e = turbulent_kinetic_energy(model)
     b = fluctuation(model.tracers.T)
     @. b.data *= model.constants.g * model.eos.βT

     wmax = maxabs(model.velocities.w)
     bmax = maxabs(b)

    # Top row
    sca(axs[1, 1])
    cla()
    plot_xzslice(e, cmap="YlGnBu_r")
    title(L"e")

    sca(axs[1, 2])
    cla()
    plot_hmean(e)
    removespines("left", "top")
    axs[1, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    ylim(-model.grid.Lz, 0)
    title(L"\bar{e}")

    match_yaxes!(axs[1, 2], axs[1, 1])

    # Middle row
    sca(axs[2, 1])
    cla()
    plot_xzslice(b, cmap="RdBu_r", vmin=-bmax, vmax=bmax)
    title(L"b")

    sca(axs[2, 2])
    cla()
    plot_hmean(model.velocities.u)
    plot_hmean(model.velocities.v)
    removespines("left", "top")
    axs[2, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    ylim(-model.grid.Lz, 0)

    match_yaxes!(axs[2, 2], axs[2, 1])

    # Bottom row
    sca(axs[3, 1])
    cla()
    plot_xzslice(model.velocities.w, cmap="RdBu_r", vmin=-wmax, vmax=wmax)
    title(L"w")

    sca(axs[3, 2])
    cla()
    plot_hmean(model.tracers.T, normalize=true, label=L"T")
    plot_hmean(wb, normalize=true, label=L"\overline{wb}")
    removespines("left", "top")
    xlim(-1, 1)
    ylim(-model.grid.Lz, 0)
    axs[3, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    legend()

    match_yaxes!(axs[3, 2], axs[3, 1])

    for ax in axs[1:3, 1]
        ax.axis("off")
        ax.set_aspect(1)
        ax.tick_params(left=false, labelleft=false, bottom=false, labelbottom=false)
    end

    return nothing
end

cfl(Δt, model) = Δt * Umax(model) / Δmin(model.grid)

get_ν(c::ConstantSmagorinsky) = c.ν_background
get_ν(c::AnisotropicMinimumDissipation) = c.ν_background
get_ν(c) = c.ν

function safe_Δt(model, αu, αν=0.01)
    τu = Δmin(model.grid) / Umax(model)
    τν = Δmin(model.grid)^2 / get_ν(model.closure)

    return min(αν*τν, αu*τu)
end

mutable struct JLD2OutputWriter{O} <: OutputWriter
            filepath :: String
             outputs :: O
    output_frequency :: Int
end

function savesubstruct!(file, model, name, flds=propertynames(getproperty(model, name)))
    for fld in flds
        file["$name/$fld"] = getproperty(getproperty(model, name), fld)
    end
    return nothing
end

function saveoutputs!(file, model, outputs)
    i = model.clock.iteration
    file["timeseries/t/$i"] = model.clock.time
    for (o, f) in outputs
        file["timeseries/$o/$i"] = f(model)
    end
    return nothing
end

noinit(args...) = nothing

function JLD2OutputWriter(model, outputs; dir=".", prefix="", frequency=1, init=noinit, force=false)
    mkpath(dir)
    filepath = joinpath(dir, prefix*".jld2")
    force && isfile(filepath) && rm(filepath, force=true)
    jldopen(filepath, "a+") do file
        init(file, model)
        savesubstruct!(file, model, :grid)
        savesubstruct!(file, model, :eos)
        savesubstruct!(file, model, :constants)
        savesubstruct!(file, model, :closure)
    end
    return JLD2OutputWriter(filepath, outputs, frequency)
end

function Oceananigans.write_output(model, fw::JLD2OutputWriter)
    jldopen(fw.filepath, "r+") do file
        saveoutputs!(file, model, fw.outputs)
    end
    return nothing
end

"""
    make_vertical_slice_movie(model::Model, nc_writer::NetCDFOutputWriter,
                              var_name, Nt, Δt, var_offset=0, slice_idx=1)

Make a movie of a vertical slice produced by `model` with output being saved by
`nc_writer`. The variable name `var_name` can be either of "u", "v", "w", "T",
or "S". `Nt` is the number of model iterations (or time steps) taken and ``Δt`
is the time step. A plotting offset `var_offset` can be specified to be
subtracted from the data before plotting (useful for plotting e.g. small
temperature perturbations around T₀). A `slice_idx` can be specified to select
the index of the y-slice to be plotted (useful when plotting vertical slices
from a 3D model, it should be set to 1 for 2D xz-slice models).
"""
function make_vertical_slice_movie(model::Model, nc_writer::NetCDFOutputWriter, var_name, Nt, Δt, var_offset=0, slice_idx=1)
    freq = nc_writer.output_frequency
    N_frames = Int(Nt/freq)

    print("Producing movie... ($N_frames frames)\n")
    Plots.gr(dpi=150)

    animation = @animate for n in 0:N_frames
        print("\rframe = $n / $N_frames   ")
        var = read_output(nc_writer, var_name, freq*n)
        Plots.contour(model.grid.xC, reverse(model.grid.zC), rotl90(var[:, slice_idx, :] .- var_offset),
                      fill=true, levels=9, linewidth=0, color=:balance,
                      clims=(-0.011, 0.011), title="t=$(freq*n*Δt) s ($(round(freq*n*Δt/86400; digits=2)) days)")
        # Plots.heatmap(model.grid.xC, model.grid.zC, rotl90(var[:, slice_idx, :]) .- var_offset,
        #               color=:balance, clims=(-0.01, 0.01), title="t=$(freq*n*Δt) s ($(round(freq*n*Δt/86400; digits=2)) days)")
    end

    mp4(animation, nc_writer.filename_prefix * "$(round(Int, time())).mp4", fps=30)
end

"""
    make_horizontal_slice_movie(model::Model, nc_writer::NetCDFOutputWriter,
                                var_name, Nt, Δt, var_offset=0)

Make a movie of a horizontal slice produced by `model` with output being saved by
`nc_writer`. The variable name `var_name` can be either of "u", "v", "w", "T",
or "S". `Nt` is the number of model iterations (or time steps) taken and ``Δt`
is the time step. A plotting offset `var_offset` can be specified to be
subtracted from the data before plotting (useful for plotting e.g. small
temperature perturbations around T₀).
"""
function make_horizontal_slice_movie(model::Model, nc_writer::NetCDFOutputWriter, var_name, Nt, Δt, var_offset=0)
    freq = nc_writer.output_frequency
    N_frames = Int(Nt/freq)

    print("Producing movie... ($N_frames frames)\n")
    Plots.gr(dpi=150)

    animation = @animate for n in 0:N_frames
        print("\rframe = $n / $N_frames   ")
        var = read_output(nc_writer, var_name, freq*n)
        Plots.heatmap(model.grid.xC, model.grid.yC, var[:, :, 1] .- var_offset,
                      color=:balance, clims=(-0.01, 0.01),
                      title="t=$(freq*n*Δt) s ($(round(freq*n*Δt/86400; digits=2)) days)")
    end

    mp4(animation, nc_writer.filename_prefix * "$(round(Int, time())).mp4", fps=30)
end

"""
    make_vertical_profile_movie(model::Model, nc_writer::NetCDFOutputWriter,
                                var_name, Nt, Δt, var_offset=0)

Make a movie of a vertical profile produced by `model` with output being saved by
`nc_writer`. The variable name `var_name` can be either of "u", "v", "w", "T",
or "S". `Nt` is the number of model iterations (or time steps) taken and ``Δt`
is the time step. A plotting offset `var_offset` can be specified to be
subtracted from the data before plotting (useful for plotting e.g. small
temperature perturbations around T₀).
"""
function make_vertical_profile_movie(model::Model, nc_writer::NetCDFOutputWriter, var_name, Nt, Δt, var_offset=0)
    freq = nc_writer.output_frequency
    N_frames = Int(Nt/freq)

    print("Producing movie... ($N_frames frames)\n")
    Plots.gr(dpi=150)

    animation = @animate for n in 0:N_frames
        print("\rframe = $n / $N_frames   ")
        var = read_output(nc_writer, var_name, freq*n)
        Plots.plot(var[1, 1, :] .- var_offset, model.grid.zC,
                   title="t=$(freq*n*Δt) s ($(round(freq*n*Δt/86400; digits=2)) days)")
    end

    mp4(animation, nc_writer.filename_prefix * "$(round(Int, time())).mp4", fps=30)
end

using NetCDF

function make_avg_temperature_profile_movie()
    Nt, dt = 86400, 0.5
    freq = 3600
    N_frames = Int(Nt/freq)
    filename_prefix = "convection"
    var_offset = 273.15

    Nz, Lz = 128, 100
    dz = Lz/Nz
    zC = -dz/2:-dz:-Lz

    print("Producing movie... ($N_frames frames)\n")
    Plots.gr(dpi=150)

    animation = @animate for n in 0:N_frames
        print("\rframe = $n / $N_frames   ")

        filepath = filename_prefix * lpad(freq*n, 9, "0") * ".nc"
        field_data = ncread(filepath, "T")
        ncclose(filepath)

        T_profile = mean(field_data; dims=[1,2])

        Plots.plot(reshape(T_profile, Nz) .- var_offset, zC,
                   title="t=$(freq*n*dt) s ($(round(freq*n*dt/86400; digits=2)) days)")
    end

    mp4(animation, filename_prefix * "$(round(Int, time())).mp4", fps=30)
end

function channelplot(axs, model)

     e = turbulent_kinetic_energy(model)

     umax = maxabs(model.velocities.u)
     wmax = maxabs(model.velocities.w)
     cmax = maxabs(model.tracers.S)

    # Top row
    sca(axs[1, 1])
    cla()
    plot_xzslice(e, cmap="YlGnBu_r")
    title(L"e")

    sca(axs[1, 2])
    cla()
    plot_hmean(model.velocities.v, label=L"\bar v")
    plot_hmean(model.velocities.w, label=L"\bar w")
    #plot_hmean(e, label=L"\bar{e}")
    removespines("left", "top")
    axs[1, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    ylim(-model.grid.Lz, 0)
    legend()

    match_yaxes!(axs[1, 2], axs[1, 1])

    # Middle row
    sca(axs[2, 1])
    cla()
    plot_xzslice(model.velocities.u, cmap="RdBu_r", vmin=-umax, vmax=umax)
    title(L"u")

    sca(axs[2, 2])
    cla()
    plot_hmean(model.velocities.u)
    removespines("left", "top")
    axs[2, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    ylim(-model.grid.Lz, 0)

    match_yaxes!(axs[2, 2], axs[2, 1])

    # Bottom row
    sca(axs[3, 1])
    cla()
    plot_xzslice(model.tracers.S, cmap="RdBu_r", vmin=-cmax, vmax=cmax)
    title(L"c")

    sca(axs[3, 2])
    cla()
    plot_hmean(model.tracers.S, normalize=true, label=L"c")
    removespines("left", "top")
    xlim(-1, 1)
    ylim(-model.grid.Lz, 0)
    axs[3, 2].tick_params(left=false, labelleft=false, right=true, labelright=true)
    legend()

    match_yaxes!(axs[3, 2], axs[3, 1])

    for ax in axs[1:3, 1]
        ax.axis("off")
        ax.set_aspect(1)
        ax.tick_params(left=false, labelleft=false, bottom=false, labelbottom=false)
    end

    return nothing
end

