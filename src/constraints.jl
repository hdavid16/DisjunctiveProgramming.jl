"""

"""
function JuMP.build_constraint(_error::Function, disjuncts::Vector{<:Disjunct})
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

"""

"""
JuMP.owner_model(cref::DisjunctiveConstraintRef) = cref.model

"""

"""
JuMP.index(cref::DisjunctiveConstraintRef) = cref.index

"""

"""
function JuMP.is_valid(model::JuMP.Model, cref::DisjunctiveConstraintRef)
    return model === JuMP.owner_model(cref)
end

"""

"""
function JuMP.name(cref::DisjunctiveConstraintRef)
    constr_data = gdp_data(JuMP.owner_model(cref))
    return constr_data.disjunctions[JuMP.index(cref)].name
end

"""

"""
function JuMP.set_name(cref::DisjunctiveConstraintRef, name::String)
    constr_data = gdp_data(JuMP.owner_model(cref))
    constr_data.disjunctions[JuMP.index(cref)].name = name
    return
end

"""

"""
function JuMP.delete(model::JuMP.Model, cref::DisjunctiveConstraintRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    constr_data = gdp_data(JuMP.owner_model(cref))
    dict = constr_data.disjunctions[JuMP.index(cref)]
    # TODO check if used by a disjunction and/or a proposition
    delete!(dict, index(cref))
    return 
end