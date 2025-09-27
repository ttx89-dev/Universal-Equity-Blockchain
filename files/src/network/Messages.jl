module Messages

using ..Types
using Dates
using SHA
using Base64

export hash_block, canonical_json

const ISO_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"

"""Convert raw bytes to URL-safe base64 without padding."""
function base64url(bytes::Vector{UInt8})
	str = Base64.base64encode(bytes)
	str = replace(str, "+" => "-", "/" => "_")
	return replace(str, "=" => "")
end

@inline encode_hash(h::Types.Hash) = base64url(h)
@inline encode_sig(sig::Vector{UInt8}) = base64url(sig)

datetime_to_iso(dt::DateTime) = Dates.format(dt, ISO_FORMAT)

"""Represent a `BlockHeader` as a canonical dictionary."""
function header_dict(header::Types.BlockHeader)
	return Dict(
		"account_id" => header.account_id,
		"prev_head" => encode_hash(header.prev_head),
		"height" => Int(header.height),
		"state_root_hint" => encode_hash(header.state_root_hint),
		"nonce" => Int(header.nonce),
		"timestamp" => datetime_to_iso(header.timestamp),
		"payload_hash" => encode_hash(header.payload_hash)
	)
end

function payload_dict(payload::Types.SendPayload)
	return Dict(
		"to_account" => payload.to_account,
		"amount" => string(payload.amount),
		"transfer_id" => encode_hash(payload.transfer_id)
	)
end

function payload_dict(payload::Types.ReceivePayload)
	return Dict(
		"from_account" => payload.from_account,
		"transfer_id" => encode_hash(payload.transfer_id)
	)
end

function block_dict(block::Types.SendBlock)
	return Dict(
		"type" => "block/send",
		"header" => header_dict(block.header),
		"payload" => payload_dict(block.payload),
		"signature" => encode_sig(block.sig)
	)
end

function block_dict(block::Types.ReceiveBlock)
	return Dict(
		"type" => "block/receive",
		"header" => header_dict(block.header),
		"payload" => payload_dict(block.payload),
		"signature" => encode_sig(block.sig)
	)
end

"""JSON-escape a UTF-8 string."""
function escape_json(str::AbstractString)
	buf = IOBuffer()
	for c in str
		if c == '\\'
			print(buf, "\\\\")
		elseif c == '"'
			print(buf, "\\\"")
		elseif c == '\b'
			print(buf, "\\b")
		elseif c == '\f'
			print(buf, "\\f")
		elseif c == '\n'
			print(buf, "\\n")
		elseif c == '\r'
			print(buf, "\\r")
		elseif c == '\t'
			print(buf, "\\t")
		else
			print(buf, c)
		end
	end
	return String(take!(buf))
end

function canonical_json(value)
	if value isa Dict
		keys_sorted = sort!(collect(keys(value)))
		parts = IOBuffer()
		print(parts, '{')
		for (idx, key) in enumerate(keys_sorted)
			if idx > 1
				print(parts, ',')
			end
			print(parts, "\"", escape_json(key), "\":", canonical_json(value[key]))
		end
		print(parts, '}')
		return String(take!(parts))
	elseif value isa Vector
		parts = IOBuffer()
		print(parts, '[')
		for (idx, elem) in enumerate(value)
			if idx > 1
				print(parts, ',')
			end
			print(parts, canonical_json(elem))
		end
		print(parts, ']')
		return String(take!(parts))
	elseif value isa AbstractString
		return "\"" * escape_json(value) * "\""
	elseif value isa Bool
		return value ? "true" : "false"
	elseif value isa Integer
		return string(value)
	elseif value isa AbstractFloat
		return string(value)
	elseif value isa Real
		return string(value)
	elseif value === nothing
		return "null"
	else
		error("Unsupported value in canonical JSON: $(typeof(value))")
	end
end

"""Return canonical JSON string for any block."""
function block_to_canonical_json(block::Types.AbstractBlock)
	return canonical_json(block_dict(block))
end

"""Compute SHA-256 hash over the canonical JSON representation of a block."""
function hash_block(block::Types.AbstractBlock)
	json = block_to_canonical_json(block)
	return SHA.sha256(Vector{UInt8}(codeunits(json)))
end

end # module