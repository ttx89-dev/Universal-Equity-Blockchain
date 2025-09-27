module PoW

# Nano-style adjustable admission-work placeholder (legacy PoW naming, disabled by default).
# Implementations can plug in a lightweight puzzle when attack pressure is detected.
# This mechanism never yields mining rewards; it exists solely as an anti-spam gate.

export maybe_do_pow!

function maybe_do_pow!(enabled::Bool)::Bool
    return !enabled || quick_dummy_pow()
end

function quick_dummy_pow()::Bool
    # Placeholder for ~50ms busy loop (do not ship in production)
    s = 0
    for i in 1:10_000_000
        s += i & 0xFF
    end
    return s % 2 == 0
end

end # module