using InteractiveUtils, Pkg, Revise
versioninfo(); Pkg.status()

import PyPlot; const plt = PyPlot
using Random, LinearAlgebra, Statistics, ReverseDiff, VecTargets, AdvancedHMC

# Fisher information metric
function gen_∂H∂x(func, x; f=identity)
    hess = VecTargets.gen_hess(func, ReverseDiff.track.(x))
    # QUES What's the best output format of this function?
    return x -> ReverseDiff.jacobian(x -> f(hess(x)[3]), x) # default output shape [∂H∂x₁; ∂H∂x₂; ...]
end

function reshape_H(H)
    d = size(H, 2)
    return cat((H[(i-1)*d+1:i*d,:] for i in 1:d)...; dims=3)
end

function sample_target(hps; rng=MersenneTwister(1110))    
    target = hps.target == :gaussian  ? HighDimGaussian(2) :
             hps.target == :banana    ? Banana() :
             hps.target == :funnel    ? Funnel() :
             hps.target == :funnel101 ? Funnel(101) :
             hps.target == :spiral    ? Spiral(8, 0.1) :
             hps.target == :mogs      ? TwoDimGaussianMixtures() :
             @error "Unknown target $(hps.target)"
    D = dim(target)
    initial_θ = rand(rng, D)
    
    ℓπ = x -> logpdf(target, x)
    _∂ℓπ∂θ = gen_logpdf_grad(target, initial_θ)
    ∂ℓπ∂θ = x -> copy.(_∂ℓπ∂θ(x))
    
    neg_ℓπ = x -> -logpdf(target, x)
    _hess_func = VecTargets.gen_hess(neg_ℓπ, initial_θ) # x -> (value, gradient, hessian)
    hess_func = x -> copy.(_hess_func(x))
    
    G = x -> begin
        H = hess_func(x)[3] + hps.λ * I
        any(.!(isfinite.(H))) ? diagm(ones(length(x))) : H
    end
    _∂G∂θ = gen_∂H∂x(neg_ℓπ, initial_θ)
    ∂G∂θ = x -> reshape_H(copy(_∂G∂θ(x)))

    metric = hps.metric == :dense_euclidean          ? DenseEuclideanMetric(D) :
             hps.metric == :dense_riemannian         ? DenseRiemannianMetric((D,), G, ∂G∂θ) :
             hps.metric == :dense_riemannian_softabs ? DenseRiemannianMetric((D,), G, ∂G∂θ, SoftAbsMap(hps.α)) :
             @error "Unknown metric $(hps.metric)"
    kinetic = GaussianKinetic()
    hamiltonian = Hamiltonian(metric, kinetic, ℓπ, ∂ℓπ∂θ)

    TS = EndPointTS
    
    integrator = hps.integrator == :lf  ? Leapfrog(hps.ϵ) :
                 hps.integrator == :glf ? GeneralizedLeapfrog(hps.ϵ, hps.n) :
                 @error "Unknown integrator $(hps.integrator)"

    tc = FixedNSteps(hps.L)
    
    proposal = HMCKernel(Trajectory{TS}(integrator, tc))

    samples, stats = sample(
        rng, hamiltonian, proposal, initial_θ, hps.n_samples; progress=false, verbose=true
    )
    
    return (; target, hamiltonian, samples, stats)
end

hps = (; target=:gaussian, n_samples=2_000, metric=:dense_euclidean, λ=1e-2, α=20.0, integrator=:lf, ϵ=0.1, n=6, L=8)
retval = sample_target((; hps...))

@info "Samples" mean(retval.samples) var(retval.samples)

retval = sample_target((; hps..., integrator=:glf))

@info "Samples" mean(retval.samples) var(retval.samples)

@time retval = sample_target((; hps..., metric=:dense_riemannian, integrator=:glf))

@info "Samples" mean(retval.samples) var(retval.samples)

using Logging: NullLogger, with_logger

@time retval = with_logger(NullLogger()) do 
    sample_target((; hps..., target=:funnel, metric=:dense_riemannian, integrator=:glf))
end

@info "Average acceptance ratio" mean(map(s -> s.is_accept, retval.stats))

let (fig, ax) = plt.subplots()
    plt.close(fig)
    
    ax.scatter(map(s -> s[1], retval.samples), map(s -> s[2], retval.samples))
    
    fig
end

@time retval = sample_target((; hps..., metric=:dense_riemannian_softabs, integrator=:glf))

@info "Samples" mean(retval.samples) var(retval.samples)

@time retval = with_logger(NullLogger()) do 
    sample_target((; hps..., target=:funnel, metric=:dense_riemannian_softabs, integrator=:glf)) # ϵ=0.1
end

@info "Average acceptance ratio" mean(map(s -> s.is_accept, retval.stats))

let (fig, ax) = plt.subplots()
    plt.close(fig)
    
    ax.scatter(map(s -> s[1], retval.samples), map(s -> s[2], retval.samples))
    
    fig
end