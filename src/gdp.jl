mutable struct Disjunct
    constraints::Vector{AbstractConstraint}
    indicator::VariableRef
end

mutable struct DisjunctionConstraint <: AbstractConstraint
    disjuncts::Vector{Disjunct}
end

mutable struct GDPdata
    gdp_variable_refs::Vector
    gdp_variable_names::Vector
    disjunctions::Dict
end

function GDPModel()
    model = Model()
    model.ext[:GDPdata] = GDPdata()
    # model.optimize_hook = 

    return model
end