module Aggregation

using ..Types

# v0.1: multisig-style aggregation. Later: BLS aggregate signatures.

"""
    aggregate_qc(votes::Vector{PartialVote}, committee::Committee, threshold::Int)

Collect k-of-n votes into a QuorumCert. Assumes deduplication upstream.
"""
function aggregate_qc(votes::Vector{Types.PartialVote},
                      committee::Types.Committee,
                      threshold::Int=22)

    isempty(votes) && return nothing
    bitmap = falses(length(committee.members))
    partials = Vector{UInt8}[]
    block_hash = votes[1].block_hash
    for v in votes
        @assert v.block_hash == block_hash "Votes for different blocks"
        if 1 <= v.bitmap_index <= length(bitmap) && !bitmap[v.bitmap_index]
            bitmap[v.bitmap_index] = true
            push!(partials, v.partial_sig)
        end
    end
    votes_collected = sum(bitmap)
    return votes_collected >= threshold ? Types.QuorumCert(block_hash, committee.epoch, committee.id, bitmap, reduce(vcat, partials; init=UInt8[]), threshold) : nothing
end

end # module