styles = ("--", ":", "-.", "o-", "^--")
defaultcolors = plt.rcParams["axes.prop_cycle"].by_key()["color"]

"""
    visualize_realizations(data, model, params...)

Visualize the data alongside several realizations of `column_model`
for each set of parameters in `params`.
"""
function visualize_realizations(column_model, column_data, targets, params::FreeParameters...;
                                     figsize = (10, 4),
                                 paramlabels = ["" for p in params], datastyle="-",
                                 modelkwargs = Dict(),
                                  datakwargs = Dict(),
                                legendkwargs = Dict(),
                                      fields = (:U, :V, :T)
                                )

    # Default kwargs for plot routines
    default_modelkwargs = Dict(:linewidth=>2, :alpha=>0.8)
    default_datakwargs = Dict(:linewidth=>3, :alpha=>0.6)
    default_legendkwargs = Dict(:fontsize=>10, :loc=>"best", :frameon=>true, :framealpha=>0.5)

    # Merge defaults with user-specified options
     modelkwargs = merge(default_modelkwargs, modelkwargs)
      datakwargs = merge(default_datakwargs, datakwargs)
    legendkwargs = merge(default_legendkwargs, legendkwargs)

    #
    # Make plot
    #

    fig, axs = subplots(ncols=length(fields), figsize=figsize)

    for (iparam, param) in enumerate(params)
        set!(column_model, param)
        set!(column_model, column_data, targets[1])

        for (iplot, i) in enumerate(targets)
            run_until!(column_model.model, column_model.Δt, column_data.t[i])

            if iplot == 1
                lbl =  @sprintf("%s KPP, \$ t = %0.1f \$ hours",
                                paramlabels[iparam], column_data.t[i]/hour)
            else
                lbl = ""
            end

            for (ipanel, field) in enumerate(fields)
                sca(axs[ipanel])
                mfld = getproperty(column_model.model.solution, field)
                plot(mfld, styles[iparam]; color=defaultcolors[iplot],
                     label=lbl, modelkwargs...)
            end
        end
    end

    for (iplot, i) in enumerate(targets)
        lbl = iplot == 1 ? "LES, " : ""
        lbl *= @sprintf("\$ t = %0.2f \$ hours", column_data.t[i]/hour)

        for (ipanel, field) in enumerate(fields)
            sca(axs[ipanel])
            dfld = getproperty(column_data, field)[i]
            plot(dfld, datastyle; label=lbl, color=defaultcolors[iplot], datakwargs...)
        end
    end

    axs[2].tick_params(left=false, labelleft=false)
    axs[3].tick_params(left=false, labelleft=false, right=true, labelright=true)
    axs[3].yaxis.set_label_position("right")

    sca(axs[1])
    removespines("top", "right")
    legend(; legendkwargs...)

    sca(axs[2])
    removespines("top", "right", "left")

    sca(axs[3])
    removespines("top", "left")

    if fields == (:U, :V, :T)
        sca(axs[1])
        xlabel("\$ U \$ velocity \$ \\mathrm{(m \\, s^{-1})} \$")
        ylabel(L"z \, \mathrm{(meters)}")

        sca(axs[2])
        xlabel("\$ V \$ velocity \$ \\mathrm{(m \\, s^{-1})} \$")

        sca(axs[3])
        xlabel("Temperature (Celsius)")
        ylabel(L"z \, \mathrm{(meters)}")
    end

    return fig, axs
end

"""
    visualize_realizations([params, column_model], column_data)

Visualize the data alongside a realization of `column_model`
for the given `params`. If `column_model` and `params` are not provided,
only the data is visualized.
"""
function visualize_realization(column_model, column_data, targets, param;
                                    figsize = (10, 4),
                                 modelstyle = "--",
                                  datastyle = "-",
                                modelkwargs = Dict(),
                                 datakwargs = Dict(),
                               legendkwargs = Dict(),
                                     fields = (:U, :V, :T),
                                  showerror = false
                                  )

    # Default kwargs for plot routines
    default_modelkwargs = Dict(:linewidth=>2, :alpha=>0.8)
    default_datakwargs = Dict(:linewidth=>3, :alpha=>0.6)
    default_legendkwargs = Dict(:fontsize=>10, :loc=>"best", :frameon=>true, :framealpha=>0.5)

    # Merge defaults with user-specified options
     modelkwargs = merge(default_modelkwargs, modelkwargs)
      datakwargs = merge(default_datakwargs, datakwargs)
    legendkwargs = merge(default_legendkwargs, legendkwargs)

    fig, axs = subplots(ncols=length(fields), figsize=figsize)

    if column_model != nothing # initialize the model
        set!(column_model, params)
        set!(column_model, column_data, targets[1])
    end

    for (iplot, i) in enumerate(targets)
        column_model != nothing && run_until!(column_model.model, column_model.Δt, column_data.t[i])

        for (ipanel, field) in enumerate(fields)
            sca(axs[ipanel])
            dfld = getproperty(column_data, field)[i]

            if iplot == 1
                leslbl = "LES, "
                kpplbl = "KPP, "
                leslbl *= @sprintf("\$ t = %0.2f \$ hours", column_data.t[i]/hour)
                kpplbl *= @sprintf("\$ t = %0.2f \$ hours", column_data.t[i]/hour)
            else
                leslbl = @sprintf("\$ t = %0.2f \$ hours", column_data.t[i]/hour)
                kpplbl = ""
            end

            if column_model != nothing
                mfld = getproperty(column_model.model.solution, field)
                err = absolute_error(mfld, dfld)
                plot(mfld, modelstyle; color=defaultcolors[iplot], label=kpplbl, modelkwargs...)
            end

            plot(dfld, datastyle; color=defaultcolors[iplot], label=leslbl, datakwargs...)
        end
    end

    axs[2].tick_params(left=false, labelleft=false)
    axs[3].tick_params(left=false, labelleft=false, right=true, labelright=true)
    axs[3].yaxis.set_label_position("right")

    sca(axs[1])
    removespines("top", "right")
    legend(; legendkwargs...)

    sca(axs[2])
    removespines("top", "right", "left")

    sca(axs[3])
    removespines("top", "left")

    if fields == (:U, :V, :T)
        sca(axs[1])
        xlabel("\$ U \$ velocity \$ \\mathrm{(m \\, s^{-1})} \$")
        ylabel(L"z \, \mathrm{(meters)}")

        sca(axs[2])
        xlabel("\$ V \$ velocity \$ \\mathrm{(m \\, s^{-1})} \$")

        sca(axs[3])
        xlabel("Temperature (Celsius)")
        ylabel(L"z \, \mathrm{(meters)}")
    end

    return fig, axs
end

visualize_targets(column_data; kwargs...) = visualize_realization(nothing, nothing, column_data; kwargs...)
