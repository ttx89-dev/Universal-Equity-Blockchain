module RateLimiter

using ..Types
using Dates

mutable struct TokenBucket
    capacity::Float64
    tokens::Float64
    refill_rate::Float64      # tokens per second
    last_refill::DateTime
end

mutable struct Limiter
    buckets::Dict{Types.AccountID, TokenBucket}
    default_capacity::Float64
    default_rate::Float64
end

function Limiter(capacity::Float64=5.0, rate::Float64=1.0)
    Limiter(Dict{Types.AccountID, TokenBucket}(), capacity, rate)
end

function rate_limit_check!(rl::Limiter, id::Types.AccountID)::Bool
    tb = get!(rl.buckets, id, TokenBucket(rl.default_capacity, rl.default_capacity, rl.default_rate, now()))
    # Refill
    nowt = now()
    dt = (nowt - tb.last_refill).value / 1000.0
    tb.tokens = min(tb.capacity, tb.tokens + dt * tb.refill_rate)
    tb.last_refill = nowt
    if tb.tokens >= 1.0
        tb.tokens -= 1.0
        return true
    else
        return false
    end
end

end # module