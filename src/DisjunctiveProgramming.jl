module DisjunctiveProgramming

# Import dependencies
import JuMP
import LeftChildRightSiblingTrees

# Create aliases
const _MOI = JuMP.MOI
const _MOIUC = JuMP.MOIU.CleverDicts
const _LCRST = LeftChildRightSiblingTrees

# Load in the source files
include("datatypes.jl")
include("copy.jl")
include("model.jl")
include("logic.jl")
include("variables.jl")
include("constraints.jl")
include("reformulate.jl")
include("bigm.jl")
include("hull.jl")
include("macros.jl")
include("optimize.jl")

# export logic operators (NOTE: these don't get exported although defined in logic.jl)
export ∨, ∧, ⇔, <-->, ⇒, -->, ¬

# Define additional stuff that should not be exported
const _EXCLUDE_SYMBOLS = [Symbol(@__MODULE__), :eval, :include]

# Following JuMP, export everything that doesn't start with a _ 
for sym in names(@__MODULE__, all = true)
    sym_string = string(sym)
    if sym in _EXCLUDE_SYMBOLS || startswith(sym_string, "_") || startswith(sym_string, "@_")
        continue
    end
    if !(Base.isidentifier(sym) || (startswith(sym_string, "@") && Base.isidentifier(sym_string[2:end])))
        continue
    end
    @eval export $sym
end

end # end of the module