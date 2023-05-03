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
    if is_gdp_model(model) 
        error("Can only add disjunctions to `GDPModel`s.")
    end
    # TODO maybe check the variables in the disjuncts belong to the model
    constr_data = ConstraintData(c, name)
    idx = _MOIUC.add_item(gdp_data(model), constr_data)
    return DisjunctiveConstraintRef(model, idx)
end
