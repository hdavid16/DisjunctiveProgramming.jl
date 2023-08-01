"""

"""
function JuMP._build_indicator_constraint(
    _error::Function,
    lvar::LogicalVariableRef,
    con::JuMP.ScalarConstraint,
    ::Type{_MOI.Indicator{A}},
) where {A}
    return DisjunctConstraint(con.func, con.set, lvar)
end

function JuMP.build_constraint(_error::Function, func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractScalarSet, lvar::LogicalVariableRef)
    return DisjunctConstraint(func, set, lvar)
end
function JuMP.build_constraint(_error::Function, func::JuMP.VariableRef, lb::Number, ub::Number, lvar::LogicalVariableRef)
    #for the case lb <= x <= ub
    return DisjunctConstraint(1*func, _MOI.Interval{Float64}(lb,ub), lvar)
end

function JuMP.build_constraint(_error::Function, func::JuMP.AbstractJuMPScalar, set::_MOI.AbstractScalarSet, tag::Type{DisjunctConstraint})
    return DisjunctConstraint(func, set, nothing)
end
function JuMP.build_constraint(_error::Function, func::JuMP.VariableRef, lb::Number, ub::Number, tag::Type{DisjunctConstraint})
    #for the case lb <= x <= ub
    return DisjunctConstraint(1*func, _MOI.Interval{Float64}(lb,ub), nothing)
end

function JuMP.build_constraint(_error::Function, disjuncts::Vector{<:Disjunct})
    # TODO add error checking
    return Disjunction(disjuncts)
end

# TODO: implement parse_constraint_call for the different logical operators 
_first_order_op = (
    (:Ξ, :exactly),
    (:Λ, :atmost), 
    (:Γ, :atleast)
)
for (ops, set) in zip(_first_order_op, [Exactly, AtMost, AtLeast])
    for op in ops
        function JuMP.parse_constraint_call(_error::Function, ::Bool, ::Val{op}, val, lvec)
            build_code = :(JuMP.build_constraint($(_error), $(esc(lvec)), $set($val)))
            return :(), build_code
        end
    end
end

function JuMP.build_constraint(_error::Function, con::Vector{LogicalVariableRef}, set::S) where {S <: Union{MOIAtLeast, MOIAtMost, MOIExactly}}
    return LogicalConstraint(con, set)
end

function JuMP.build_constraint(_error::Function, con::LogicalExpr, set::MOIIsTrue)
    return LogicalConstraint(con, set)
end

function JuMP.add_constraint(
    model::JuMP.Model,
    c::LogicalConstraint,
    name::String = ""
)
    is_gdp_model(model) || error("Can only add logical constraints to `GDPModel`s.")
    # TODO maybe check the variables in the disjuncts belong to the model
    constr_data = LogicalConstraintData(c, name)
    idx = _MOIUC.add_item(_logical_constraints(model), constr_data)
    return LogicalConstraintRef(model, idx)
end

"""

"""
function JuMP.add_constraint(
    model::JuMP.Model,
    con::DisjunctConstraint,
    name::String = ""
)
    is_gdp_model(model) || error("Can only add disjunct constraints to `GDPModel`s.")
    constr_data = DisjunctConstraintData(con, name)
    idx = _MOIUC.add_item(gdp_data(model).disjunct_constraints, constr_data)
    disj_constr_map = _disjunct_constraint_map(model)
    if !isnothing(con.indicator) #map disjunct constraint index to logical var index assigned
        lidx = JuMP.index(con.indicator)
        disj_constr_map[idx] = lidx
    end
    return DisjunctConstraintRef(model, idx)
end

function JuMP.add_constraint(
    model::JuMP.Model, 
    c::Disjunction, 
    name::String = ""
)
    is_gdp_model(model) || error("Can only add _disjunctions to `GDPModel`s.")
    # TODO maybe check the variables in the disjuncts belong to the model
    constr_data = DisjunctionData(c, name)
    idx = _MOIUC.add_item(_disjunctions(model), constr_data)
    return DisjunctionRef(model, idx)
end

function add_disjunction(
    model::JuMP.Model, 
    disjuncts::Vector{Vector{DisjunctConstraintRef}},
    name::String = ""
)
    is_gdp_model(model) || error("Can only add disjunctions to `GDPModel`s.")
    built_disjuncts = Disjunct[] #initialize vector to store disjuncts
    if isempty(name)
        name = "_"
    end
    disjunct_constraints = _disjunct_constraints(model)
    for (i, disjunct) in enumerate(disjuncts) #create each disjunct
        lvar = JuMP.add_variable(model, 
            JuMP.build_variable(error, _variable_info(), LogicalVariable), 
            "$(name)[$i]"
        )
        disj_cons = Tuple(
            disjunct_constraints[JuMP.index(con)].constraint 
            for con in disjunct
        )
        push!(built_disjuncts,
            Disjunct(disj_cons, lvar) #build disjunct
        )
    end
    disjunction_data = DisjunctionData(Disjunction(built_disjuncts), name)
    idx = _MOIUC.add_item(_disjunctions(model), disjunction_data)
    return DisjunctionRef(model, idx)
end

function add_disjunction(
    model::JuMP.Model, 
    indicators::Vector{LogicalVariableRef},
    name::String = ""
)
    is_gdp_model(model) || error("Can only add disjunctions to `GDPModel`s.")
    built_disjuncts = Disjunct[] #initialize vector to store disjuncts
    if isempty(name)
        name = "_"
    end
    disj_constr_map = _disjunct_constraint_map(model)
    disjunct_constraints = _disjunct_constraints(model)
    for lvar in indicators #create each disjunct
        idx = JuMP.index(lvar)
        con_ids = findall(==(idx), disj_constr_map) #find all constraints associated with this indicator
        disj = Disjunct( #build disjunct
            Tuple(
                disjunct_constraints[con_idx].constraint
                for con_idx in con_ids
            ),
            lvar
        )
        push!(built_disjuncts, disj)
    end
    disjunction_data = DisjunctionData(Disjunction(built_disjuncts), name)
    idx = _MOIUC.add_item(_disjunctions(model), disjunction_data)
    return DisjunctionRef(model, idx)
end

"""

"""
JuMP.owner_model(cref::DisjunctConstraintRef) = cref.model

"""

"""
JuMP.owner_model(cref::DisjunctionRef) = cref.model

"""

"""
JuMP.index(cref::DisjunctConstraintRef) = cref.index

"""

"""
JuMP.index(cref::DisjunctionRef) = cref.index

"""

"""
function JuMP.is_valid(model::JuMP.Model, cref::DisjunctionRef)
    return model === JuMP.owner_model(cref)
end

"""

"""
function JuMP.name(cref::DisjunctionRef)
    constr_data = gdp_data(JuMP.owner_model(cref))
    return constr_data.disjunctions[JuMP.index(cref)].name
end

"""

"""
function JuMP.set_name(cref::DisjunctionRef, name::String)
    constr_data = gdp_data(JuMP.owner_model(cref))
    constr_data.disjunctions[JuMP.index(cref)].name = name
    return
end

"""

"""
function JuMP.delete(model::JuMP.Model, cref::DisjunctionRef)
    @assert JuMP.is_valid(model, cref) "Disjunctive constraint does not belong to model."
    constr_data = gdp_data(JuMP.owner_model(cref))
    dict = constr_data.disjunctions[JuMP.index(cref)]
    # TODO check if used by a disjunction and/or a proposition
    delete!(dict, index(cref))
    return 
end

Base.copy(con::DisjunctConstraintRef) = con