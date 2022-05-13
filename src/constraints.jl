"""

"""
function JuMP.build_constraint(error::Function, disjuncts::Vector{Disjuncts})
    # TODO add error checking
    return DisjunctionConstraint(disjuncts)
end

"""

"""
function JuMP.add_constraint(
    model::JuMP.Model, 
    c::DisjunctionConstraint, 
    name::String = ""
    )
    # TODO maybe check the variables in the disjuncts belong to the model
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(gdp_data(model), constr_data)
    return DisjunctiveConstraintRef(model, idx)
end
