module PoP

# Proof-of-Personhood interface (stubs for v0.1)
# Implementations can be swapped (e.g., social attestations, external PoP providers, in-person ceremonies).
#
# For development: accept a local registry map {AccountID => bool}.

mutable struct Registry
    valid::Dict{String,Bool}
end

function Registry()
    Registry(Dict{String,Bool}())
end

is_valid(reg::Registry, id::String)::Bool = get(reg.valid, id, false)

end # module