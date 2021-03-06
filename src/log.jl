# exported logarithmic functions

const FP_ILOGB0   = typemin(Int)
const FP_ILOGBNAN = typemin(Int)
const INT_MAX     = typemax(Int)

"""
    ilogb(x)

Returns the integral part of the logarithm of `abs(x)`, using base 2 for the
logarithm. In other words, this computes the binary exponent of `x` such that

    x = significand × 2^exponent,

where `significand ∈ [1, 2)`.

* Exceptional cases (where `Int` is the machine wordsize)
    * `x = 0`    returns `FP_ILOGB0`
    * `x = ±Inf`  returns `INT_MAX`
    * `x = NaN`  returns `FP_ILOGBNAN`
"""
function ilogb(x::FloatType)
    e = ilogbk(abs(x))
    e = vifelse(x == 0, FP_ILOGB0, e)
    e = vifelse(isnan(x), FP_ILOGBNAN, e)
    e = vifelse(isinf(x), INT_MAX, e)
    return e
end



"""
    log10(x)

Returns the base `10` logarithm of `x`.
"""
function log10(a::V) where {V <: FloatType}
    T = eltype(a)
    x = V(dmul(logk(a), MDLN10E(T)))

    x = vifelse(isinf(a), T(Inf), x)
    x = vifelse((a < 0) | isnan(a), T(NaN), x)
    x = vifelse(a == 0, T(-Inf), x)

    return x
end



"""
    log2(x)

Returns the base `2` logarithm of `x`.
"""
function log2(a::V) where {V <: FloatType}
    T = eltype(a)
    u = V(dmul(logk(a), MDLN2E(T)))

    u = vifelse(isinf(a), T(Inf), u)
    u = vifelse((a < 0) | isnan(a), T(NaN), u)
    u = vifelse(a == 0, T(-Inf), u)

    return u
end



const over_log1p(::Type{Float64}) = 1e307
const over_log1p(::Type{Float32}) = 1f38

"""
    log1p(x)

Accurately compute the natural logarithm of 1+x.
"""
@inline function log1p(a::V) where {V<:FloatType}
    T = eltype(a)
    x = V(logk2(dadd2(a, T(1.0))))

    x = vifelse(a > over_log1p(T), T(Inf), x)
    x = vifelse(a < -1, T(NaN), x)
    x = vifelse(a == -1, T(-Inf), x)
    x = vifelse(isnegzero(a), T(-0.0), x)

    return x
end



@inline function log_kernel(x::FloatType64)
    c7 = 0.1532076988502701353
    c6 = 0.1525629051003428716
    c5 = 0.1818605932937785996
    c4 = 0.2222214519839380009
    c3 = 0.2857142932794299317
    c2 = 0.3999999999635251990
    c1 = 0.6666666666667333541
    # return @horner x c1 c2 c3 c4 c5 c6 c7
    @horner x c1 c2 c3 c4 c5 c6 c7
end

@inline function log_kernel(x::FloatType32)
    c3 = 0.3027294874f0
    c2 = 0.3996108174f0
    c1 = 0.6666694880f0
    # return @horner x c1 c2 c3
    @horner x c1 c2 c3
end

"""
    log(x)

Compute the natural logarithm of `x`. The inverse of the natural logarithm is
the natural expoenential function `exp(x)`
"""
@inline function log(d::V) where {V <: FloatType}
    T = eltype(d)
    I = fpinttype(T)
    o = d < floatmin(T)
    d = vifelse(o, d * T(Int64(1) << 32) * T(Int64(1) << 32), d)

    e = ilogb2k(d * T(1.0/0.75))
    m = ldexp3k(d, -e)
    e = vifelse(o, e - I(64), e)

    x  = ddiv(dadd2(T(-1.0), m), dadd2(T(1.0), m))
    x2 = x.hi*x.hi

    t = log_kernel(x2)

    s = dmul(MDLN2(T), convert(V,e))
    s = dadd(s, scale(x, T(2.0)))
    s = dadd(s, x2*x.hi*t)
    r = V(s)

    # r = vifelse(isinf(d), T(Inf), r)
    r = vifelse((d < 0) | isnan(d), T(NaN), r)
    r = vifelse(d == 0, T(-Inf), r)

    return r
end
function log_noinline(d::V) where {V <: FloatType}
    T = eltype(d)
    I = fpinttype(T)
    o = d < floatmin(T)
    d = vifelse(o, d * T(Int64(1) << 32) * T(Int64(1) << 32), d)

    e = ilogb2k(d * T(1.0/0.75))
    m = ldexp3k(d, -e)
    e = vifelse(o, e - I(64), e)

    x  = ddiv(dadd2(T(-1.0), m), dadd2(T(1.0), m))
    x2 = x.hi*x.hi

    t = log_kernel(x2)

    s = dmul(MDLN2(T), convert(V,e))
    s = dadd(s, scale(x, T(2.0)))
    s = dadd(s, x2*x.hi*t)
    r = V(s)

    # r = vifelse(isinf(d), T(Inf), r)
    # r = vifelse((d < 0) | isnan(d), T(NaN), r)
    # r = vifelse(d == 0, T(-Inf), r)

    return r
end



# First we split the argument to its mantissa `m` and integer exponent `e` so
# that `d = m \times 2^e`, where `m \in [0.5, 1)` then we apply the polynomial
# approximant on this reduced argument `m` before putting back the exponent
# in. This first part is done with the help of the private function
# `ilogbk(x)` and we put the exponent back using

#     `\log(m \times 2^e) = \log(m) + \log 2^e =  \log(m) + e\times MLN2

# The polynomial we evaluate is based on coefficients from

#     `log_2(x) = 2\sum_{n=0}^\infty \frac{1}{2n+1} \bigl(\frac{x-1}{x+1}^{2n+1}\bigr)`

# That being said, since this converges faster when the argument is close to
# 1, we multiply  `m` by `2` and subtract 1 for the exponent `e` when `m` is
# less than `sqrt(2)/2`

@inline function log_fast_kernel(x::FloatType64)
    c8 = 0.153487338491425068243146
    c7 = 0.152519917006351951593857
    c6 = 0.181863266251982985677316
    c5 = 0.222221366518767365905163
    c4 = 0.285714294746548025383248
    c3 = 0.399999999950799600689777
    c2 = 0.6666666666667778740063
    c1 = 2.0
    # return @horner x c1 c2 c3 c4 c5 c6 c7 c8
    @horner x c1 c2 c3 c4 c5 c6 c7 c8
end

@inline function log_fast_kernel(x::FloatType32)
    c5 = 0.2392828464508056640625f0
    c4 = 0.28518211841583251953125f0
    c3 = 0.400005877017974853515625f0
    c2 = 0.666666686534881591796875f0
    c1 = 2f0
    # return @horner x c1 c2 c3 c4 c5
    @horner x c1 c2 c3 c4 c5
end

# @inline fm(x::SIMDPirates.AbstractSIMDVector) = SVec(SIMDPirates.extract_data(x))
# @inline fm(x::SIMDPirates.AbstractSIMDVector) = x

"""
    log_fast(x)

Compute the natural logarithm of `x`. The inverse of the natural logarithm is
the natural expoenential function `exp(x)`
"""
@inline function log_fast(d::FloatType)
    T = eltype(d)
    I = fpinttype(T)
    o = d < floatmin(T)
    d = vifelse(o, d * T(Int64(1) << 32) * T(Int64(1) << 32), d)

    e = ilogb2k(d * T(1.0/0.75))
    m = ldexp3k(d, -e)
    e = vifelse(o, e - I(64), e)

    x  = (m - one(I)) / (m + one(I))
    x2 = x * x

    t = log_fast_kernel(x2)

    x = x * t + T(MLN2) * e

    # x = vifelse(isinf(d), T(Inf), x)
    x = vifelse((d < zero(I)) | isnan(d), T(NaN), x)
    x = vifelse(d == zero(I), T(-Inf), x)

    return x
end
function log_fast_noinline(d::FloatType)
    T = eltype(d)
    I = fpinttype(T)
    o = d < floatmin(T)
    d = vifelse(o, d * T(Int64(1) << 32) * T(Int64(1) << 32), d)

    e = ilogb2k(d * T(1.0/0.75))
    m = ldexp3k(d, -e)
    e = vifelse(o, e - I(64), e)

    x  = (m - one(I)) / (m + one(I))
    x2 = x * x

    t = log_fast_kernel(x2)

    x = x * t + T(MLN2) * e

    # x = vifelse(isinf(d), T(Inf), x)
    # x = vifelse((d < zero(I)) | isnan(d), T(NaN), x)
    # x = vifelse(d == zero(I), T(-Inf), x)

    return x
end

# function log_fast_debug(d::SIMDPirates.SVec)
#     d1 = d[1]
#     T = eltype(d)
#     I = fpinttype(T)
#     o = d < floatmin(T)
#     d = vifelse(o, fm(fm(d * T(Int64(1) << 32)) * T(Int64(1) << 32)), d)
#     d1 = vifelse(o[1], d1 * T(Int64(1) << 32) * T(Int64(1) << 32), d1)
#     @show d[1], d1
#     e = ilogb2k(d * T(1.0/0.75))
#     e1 = ilogb2k(d1 * T(1.0/0.75))
#     @show e[1], e1
#     m = ldexp3k(d, -e)
#     e = vifelse(o, e - I(64), e)
#
#     x  = (m - one(I)) / (m + one(I))
#     x2 = fm(x * x)
#
#     t = log_fast_kernel(x2)
#
#     x = fm(x * t) + fm(T(MLN2) * e)
#
#     x = vifelse(isinf(d), T(Inf), x)
#     x = vifelse((d < zero(I)) | isnan(d), T(NaN), x)
#     x = vifelse(d == zero(I), T(-Inf), x)
#
#     return x
# end
