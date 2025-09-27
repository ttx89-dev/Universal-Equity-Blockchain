module CommitteeSelection

using ..Types
using Random, SHA

# Deterministic PRNG-based selection for v0.1 (replace with VRF later)
"""
    select_committee(all_members::Vector{AccountID};
                     committee_size::Int, epoch::UInt64,
                     account::AccountID, seq::UInt64)

Returns a Committee and mapping to bitmap indexes.
"""
function select_committee(all_members::Vector{Types.AccountID};
                          committee_size::Int=32, epoch::UInt64=0,
                          account::Types.AccountID="", seq::UInt64=0)

    seed_bytes = SHA.sha256(string(epoch, "|", account, "|", seq))
    rng = MersenneTwister(reinterpret(UInt32, seed_bytes[1:4])[1])
    pool = copy(all_members)
    shuffle!(rng, pool)
    sel = length(pool) >= committee_size ? pool[1:committee_size] : pool
    cid = bytes2hex(SHA.sha256(string(epoch, account, seq)))
    Committee = Types.Committee(epoch, cid, sel)
    idxmap = Dict{Types.AccountID, Int}()
    for (i, m) in enumerate(sel)
        idxmap[m] = i
    end
    return Committee, idxmap
end

end # module