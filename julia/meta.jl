using Base.Meta

function get_names(ex::Expr)
	@assert isexpr(ex, :block)
	return [arg for arg in ex.args if !isa(arg, LineNumberNode)]
end

function code_constants(name::Symbol, ex::Expr, start::Int, exponential::Bool)
	names = get_names(ex)
	values = start .+ (0:length(names)-1)
	if (exponential)
		values = [1 << x for x in values]
	end
	table = collect(zip(names, values))
	defs = [:(const $name = $value) for (name, value) in zip(names, values)]
	return quote
		const $name = $(QuoteNode(table))
		$(defs...)
	end
end

macro constants(name::Symbol, ex::Expr)
	return esc(code_constants(name, ex, 0, false))
end

macro flags(name::Symbol, start::Int, ex::Expr)
	return esc(code_constants(name, ex, start, true))
end
