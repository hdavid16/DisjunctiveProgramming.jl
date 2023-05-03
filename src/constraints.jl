"""

"""
function JuMP.build_constraint(error::Function, disjuncts::Vector{Disjunct})
    # TODO add error checking
    return DisjunctiveConstraint(disjuncts)
end

"""

"""
function JuMP.add_constraint(
    model::JuMP.Model, 
    c::DisjunctiveConstraint, 
    name::String = ""
    )
    is_gdp_model(model) || error("Can only add disjunctions to `GDPModel`s.")
    # TODO maybe check the variables in the disjuncts belong to the model
    constr_data = DisjunctiveConstraintData(c, name)
    idx = _MOIUC.add_item(gdp_data(model).disjunctions, constr_data)
    return DisjunctiveConstraintRef(model, idx)
end
