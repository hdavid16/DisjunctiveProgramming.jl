################################################################################
#                              INDICATOR REFORMULATION
################################################################################
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.ScalarConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S}
    reform_con = JuMP.build_constraint(error, [1*bvref, con.func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(con.set))
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, reform_con, con_name)
    end
    
    return [reform_con]
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S}
    set = _vec_to_scalar_set(con.set)
    reform_cons = Vector{JuMP.VectorConstraint}()
    for (i, func) in enumerate(con.func)
        reform_con = JuMP.build_constraint(error, [1*bvref, func], _MOI.Indicator{_MOI.ACTIVATE_ON_ONE}(set))
        push!(reform_cons, reform_con)
        if !nested
            con_name = isempty(name) ? name : string(name, "_", bvref, "_$i")
            _add_reformulated_constraint(model, reform_con, con_name)
        end
    end

    return reform_cons
end
function _reformulate_disjunct_constraint(
    model::JuMP.Model,
    con::JuMP.VectorConstraint{T, S},
    bvref::JuMP.VariableRef,
    method::Indicator,
    name::String,
    nested::Bool
) where {T, S <: _MOI.Indicator}
    if !nested
        con_name = isempty(name) ? name : string(name, "_", bvref)
        _add_reformulated_constraint(model, con, con_name)
    end
    
    return [con]
    # # NOTE The following should not be required if the user adds the appropriate cardinality constraints to the nested disjunction indicators
    # #create intermediate binary variable
    # bvar = JuMP.@variable(model, binary = true, base_name = "$(bvref)_∧_$(con.func[1])")
    # push!(_reformulation_variables(model), JuMP.index(bvar))
    # #reformulate nested indicator constraint
    # reform_cons = [
    #     JuMP.build_constraint(error, [1*bvar, con.func[2]], con.set), # replace indicator variable with new bvar
    #     #add logic constraints: bvar <=> bvref ∧ con.func[1]
    #     JuMP.build_constraint(error, # {bvref ∧ con.func[1]} => bvar
    #         JuMP.@expression(model, (1 - bvref) + (1 - con.func[1]) + bvar),
    #         _MOI.GreaterThan(1)
    #     ),
    #     JuMP.build_constraint(error, # bvar => {bvref ∧ con.func[1]}
    #         JuMP.@expression(model, (1 - bvar) + bvref),
    #         _MOI.GreaterThan(1)
    #     ),
    #     JuMP.build_constraint(error, # bvar => {bvref ∧ con.func[1]}
    #         JuMP.@expression(model, (1 - bvar) + con.func[1]),
    #         _MOI.GreaterThan(1)
    #     )
    # ]
    # for (i, reform_con) in enumerate(reform_cons)
    #     if !nested || i >= 2 # always add the logic constraints to the model
    #         con_name = isempty(name) ? name : string(name, "_", bvref)
    #         _add_reformulated_constraint(model, reform_con, con_name)
    #     end
    # end

    # return [reform_cons[1]]
end