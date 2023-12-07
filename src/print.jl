################################################################################
#                               PRINTING HELPERS
################################################################################
_wrap_in_math_mode(str::String) = "\$\$ $str \$\$"

# Get the appropriate symbols
_dor_symbol(::MIME"text/plain") = Sys.iswindows() ? "or" : "⋁"
_dor_symbol(::MIME"text/latex") = "\\bigvee"
_imply_symbol(::MIME"text/plain") = Sys.iswindows() ? "-->" : "⟹"
_imply_symbol(::MIME"text/latex") = "\\implies"
_left_pareth_symbol(::MIME"text/plain") = "("
_left_pareth_symbol(::MIME"text/latex") = "\\left("
_right_pareth_symbol(::MIME"text/plain") = ")"
_right_pareth_symbol(::MIME"text/latex") = "\\right)"

# Create the proper string for a cardinality function
_card_func_str(::MIME"text/plain", ::_MOIAtLeast) = "atleast"
_card_func_str(::MIME"text/latex", ::_MOIAtLeast) = "\\text{atleast}"
_card_func_str(::MIME"text/plain", ::_MOIAtMost) = "atmost"
_card_func_str(::MIME"text/latex", ::_MOIAtMost) = "\\text{atmost}"
_card_func_str(::MIME"text/plain", ::_MOIExactly) = "exactly"
_card_func_str(::MIME"text/latex", ::_MOIExactly) = "\\text{exactly}"

################################################################################
#                               CONSTRAINT PRINTING
################################################################################
# Return the string of a DisjunctConstraintRef
function JuMP.constraint_string(
    mode::MIME, 
    cref::DisjunctConstraintRef; 
    in_math_mode = false
    )
    constr_str = JuMP.constraint_string(
        mode, 
        JuMP.name(cref), 
        JuMP.constraint_object(cref); 
        in_math_mode = true
        )
    model = JuMP.owner_model(cref)
    lvar = gdp_data(model).constraint_to_indicator[cref]
    lvar_str = JuMP.function_string(mode, lvar)
    if mode == MIME("text/latex")
        constr_str *= ", \\; \\text{if } $(lvar_str) = \\text{True}"
        if in_math_mode
            return constr_str
        else
            return _wrap_in_math_mode(constr_str)
        end
    end
    return constr_str * ", if $(lvar_str) = True"
end

# Give the constraint string for a logical constraint
function JuMP.constraint_string(
    mode::MIME"text/latex", 
    con::JuMP.ScalarConstraint{<:_LogicalExpr, <:MOI.EqualTo}
    )
    return JuMP.function_string(mode, con) * " = \\text{True}"
end
function JuMP.constraint_string(
    mode::MIME"text/plain", 
    con::JuMP.ScalarConstraint{<:_LogicalExpr, <:MOI.EqualTo}
    )
    return JuMP.function_string(mode, con) * " = True"
end
function JuMP.constraint_string(
    mode, con::JuMP.VectorConstraint{F, <:AbstractCardinalitySet}
    ) where {F}
    con_str = string(_card_func_str(mode, JuMP.moi_set(con)), _left_pareth_symbol(mode))
    con_str *= join((JuMP.function_string(mode, ex) for ex in JuMP.jump_function(con)), ", ")
    return con_str * _right_pareth_symbol(mode)
end

# Return the string of a LogicalConstraintRef
function JuMP.constraint_string(
    mode::MIME, 
    cref::LogicalConstraintRef; 
    in_math_mode = false
    )
    constr_str = JuMP.constraint_string(
        mode, 
        JuMP.name(cref), 
        JuMP.constraint_object(cref); 
        in_math_mode = in_math_mode
    )
    # temporary hack until JuMP provides a better solution for operator printing
    # TODO improve the printing of implications (not recognized by JuMP as two-sided operators)
    if mode == MIME("text/latex")
        return replace(
            constr_str, 
            "&&" => "\\wedge", 
            "||" => "\\vee", 
            "\\textsf{!}" => "\\neg", 
            "==" => "\\iff", 
            "\\textsf{=>}" => "\\implies"
            )
    elseif Sys.iswindows()
        return replace(
            constr_str, 
            "&&" => "and", 
            "||" => "or", 
            "!" => "!",
            "==" => "<-->", 
            "=>" => "-->"
            )
    else
        return replace(
            constr_str, 
            "&&" => "∧", 
            "||" => "∨", 
            "!" => "¬",
            "==" => "⟺", 
            "=>" => "⟹"
            )
    end
end

# Return the string of a Disjunction for plain printing
function JuMP.constraint_string(
    mode::MIME"text/plain", 
    d::Disjunction
    )
    model = JuMP.owner_model(first(d.indicators))
    mappings = _indicator_to_constraints(model)
    disjuncts = Vector{String}(undef, length(d.indicators))
    for (i, lvar) in enumerate(d.indicators)
        disjunct = string("[", JuMP.function_string(mode, lvar), " ", _imply_symbol(mode), " {")
        cons = (JuMP.constraint_string(mode, JuMP.constraint_object(cref)) for cref in mappings[lvar])
        disjuncts[i] = string(disjunct, join(cons, "; "), "}]")
    end
    return join(disjuncts, " $(_dor_symbol(mode)) ")
end

# Return the string of a Disjunction for latex printing
function JuMP.constraint_string(
    mode::MIME"text/latex", 
    d::Disjunction
    )
    model = JuMP.owner_model(first(d.indicators))
    mappings = _indicator_to_constraints(model)
    disjuncts = Vector{String}(undef, length(d.indicators))
    for (i, lvar) in enumerate(d.indicators)
        disjunct = string("\\begin{bmatrix}\n ", JuMP.function_string(mode, lvar), "\\\\\n ")
        cons = (JuMP.constraint_string(mode, JuMP.constraint_object(cref)) for cref in mappings[lvar])
        disjuncts[i] = string(disjunct, join(cons, "\\\\\n "), "\\end{bmatrix}")
    end
    return join(disjuncts, " $(_dor_symbol(mode)) ")
end

# Return the string of a DisjunctionRef
function JuMP.constraint_string(
    mode::MIME, 
    dref::DisjunctionRef;
    in_math_mode::Bool = false
    )
    label = JuMP.name(dref)
    n = isempty(label) ? "" : label * " : "
    d = JuMP.constraint_object(dref)
    constr_str = JuMP.constraint_string(mode, d)
    if mode == MIME("text/latex")
        # Do not print names in text/latex mode.
        if in_math_mode
            return constr_str
        else
            return _wrap_in_math_mode(constr_str)
        end
    end
    return n * JuMP.constraint_string(mode, d)
end

# Overload Base.show as needed
for RefType in (:DisjunctionRef, DisjunctConstraintRef, :LogicalConstraintRef)
    @eval begin
        function Base.show(io::IO, cref::$RefType)
            return print(io, JuMP.constraint_string(MIME("text/plain"), cref))
        end

        function Base.show(io::IO, ::MIME"text/latex", cref::$RefType)
            return print(io, JuMP.constraint_string(MIME("text/latex"), cref))
        end
    end
end

################################################################################
#                              SUMMARY PRINTING
################################################################################

# TODO create functions to print and summaries GDPModels (to show GDPData contains)
