module AdvancedHMCOrdinaryDiffEqExt

if isdefined(Base, :get_extension)
    import AdvancedHMC
    import OrdinaryDiffEq
else
    import ..AdvancedHMC
    import ..OrdinaryDiffEq
end

function AdvancedHMC.step(
    integrator::AdvancedHMC.DiffEqIntegrator,
    h::AdvancedHMC.Hamiltonian,
    z::P,
    n_steps::Int = 1;
    fwd::Bool = n_steps > 0,  # simulate hamiltonian backward when n_steps < 0
    res::Union{Vector{P},P} = z,
) where {P<:AdvancedHMC.PhasePoint}

    AdvancedHMC.@unpack θ, r = z
    # For DynamicalODEProblem `u` is `θ` and `v` is `r`
    # f1 is dr/dt RHS function
    # f2 is dθ/dt RHS function
    v0, u0 = r, θ

    f1(v, u, p, t) = -AdvancedHMC.∂H∂θ(h, u).gradient
    f2(v, u, p, t) = AdvancedHMC.∂H∂r(h, v)

    ϵ = fwd ? AdvancedHMC.step_size(integrator) : -AdvancedHMC.step_size(integrator)
    tspan = (0.0, sign(n_steps))
    problem = OrdinaryDiffEq.DynamicalODEProblem(f1, f2, v0, u0, tspan)
    diffeq_integrator = OrdinaryDiffEq.init(
        problem,
        integrator.solver,
        save_everystep = false,
        save_start = false,
        save_end = false,
        dt = ϵ,
    )

    for i = 1:abs(n_steps)
        OrdinaryDiffEq.step!(diffeq_integrator)
        solution = diffeq_integrator.u.x  # (r, θ) at the proposed step
        z = AdvancedHMC.phasepoint(h, solution[2], solution[1])
        !isfinite(z) && break
        if res isa Vector
            res[i] = z
        else
            res = z
        end
    end
    return res
end

end # module
