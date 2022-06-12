# Extend addchild to take the root of another graph as input
function _LCRST.addchild(parent::_LCRST.Node{T}, newc::_LCRST.Node{T}) where T
    # copy the new node if it is not a root
    # otherwise, we are just merging 2 graphs together
    if !_LCRST.isroot(newc)
        newc = copy(newc)
    end
    # add it on to the tree
    newc.parent = parent
    prevc = parent.child
    if prevc == parent
        parent.child = newc
    else
        prevc = _LCRST.lastsibling(prevc)
        prevc.sibling = newc
    end
    return newc
end

# Extend addchild with convenient nothing dispatch for empty previous child
function _LCRST.addchild(
    parent::_LCRST.Node{T}, 
    oldc::Nothing, 
    newc::_LCRST.Node{T}
    ) where T
    return _LCRST.addchild(parent, newc)
end

# Extend addchild to efficiently add multiple children if the previous is known
function _LCRST.addchild(
    parent::_LCRST.Node{T}, 
    prevc::_LCRST.Node{T}, 
    data::T
    ) where T
    # add it on to the tree
    newc = _LCRST.Node(data, parent)
    prevc.sibling = newc
    return newc
end

# Extend addchild to efficiently add multiple children if the previous is known
function _LCRST.addchild(
    parent::_LCRST.Node{T}, 
    prevc::_LCRST.Node{T}, 
    newc::_LCRST.Node{T}
    ) where T
    # check if the prev is actually a child of the parent 
    @assert prevc.parent === parent "Previous child doesn't belong to parent."
    # copy the new node if it is not a root
    # otherwise, we are just merging 2 graphs together
    if !_LCRST.isroot(newc)
        newc = copy(newc)
    end
    # add it on to the tree
    newc.parent = parent
    prevc.sibling = newc
    return newc
end

# Map a LCRST tree based by operating each node with a function
function _map_tree(map_func::Function, node::_LCRST.Node)
    new_node = map_func(node)
    prev = nothing
    for child in node
        prev = _LCRST.addchild(new_node, prev, _map_tree(map_func, child))
    end
    return new_node
end

# Extend copying for graph nodes
function Base.copy(node::_LCRST.Node)
    return _map_tree(n -> _LCRST.Node(n.data), node)
end

# Extend basic functions
Base.broadcastable(p::Proposition) = Ref(p)
Base.copy(p::Proposition) = Proposition(copy(p.tree_root))
function Base.isequal(p1::Proposition, p2::Proposition) 
    return isequal(p1.tree_root, p2.tree_root)
end

## Make convenient dispatch methods for raw child input
# Proposition
function _process_child_input(p::Proposition)
    return p.tree_root
end

# Logical variable
function _process_child_input(v::LogicalVariableRef)
    return NodeData(v)
end

# Function symbol
function _process_child_input(f::Symbol)
    return NodeData(f)
end

# Fallback
function _process_child_input(v)
    error("Unrecognized proposition input `$v`.")
end

# Generic graph builder
function _call_graph(func::Symbol, arg1, args...)
    root = _LCRST.Node(NodeData(func))
    prevc = _LCRST.addchild(root, _process_child_input(arg1))
    for a in args 
        prevc = _LCRST.addchild(root, prevc, _process_child_input(a))
    end
    return root
end

# Define all the logic functions/operators that use 2 arguments
for (name, func) in ((:∨, :∨), (:∨, :lor), (:⊻, :⊻), (:⊻, :lxor), 
                     (:∧, :∧), (:∧, :land), (:⟺, :⟺), 
                     (:⟺, :iff), (:⟹, :⟹), (:⟹, :implies))
    # make an expression constructor
    @eval begin 
        function $func(
            v1::Union{LogicalVariableRef, Proposition}, 
            v2::Union{LogicalVariableRef, Proposition}
            )
            return Proposition(_call_graph($(quot(name)), v1, v2))
        end
    end
end

# Define all the logic functions/operators that use 1 argument
for (name, func) in ((:¬, :¬), (:¬, :lneg))
    # make an expression constructor
    @eval begin 
        function $func(v::Union{LogicalVariableRef, Proposition})
            return Proposition(_call_graph($(quot(name)), v))
        end
    end
end

# Recursively build an expression string, starting with a root node
function _expr_string(
    node::_LCRST.Node{NodeData}, 
    str::String = ""
    )
    # prepocess the raw value
    raw_value = node.data.value
    data_str = string(node.data.value)
    # make a string according to the node structure
    if _LCRST.isleaf(node) && raw_value isa LogicalVariableRef
        # we have a leaf that doesn't require parentheses
        return str * data_str
    elseif _LCRST.isleaf(node)
        # we have a leaf that requires parentheses
        return str * string("(", data_str, ")")
    elseif _LCRST.islastsibling(node.child)
        # we have a unary operator
        return string(data_str, _expr_string(node.child, str))
    else
        # we have multi-argument operator
        str *= "("
        op_str = string(" ", data_str, " ")
        for child in node
            str = string(_expr_string(child, str), op_str)
        end
        return str[1:prevind(str, end, length(op_str))] * ")"
    end
end

# Extend JuMP.function_string for nonlinear expressions
function JuMP.function_string(mode, p::Proposition)
    return _expr_string(p.tree_root)
end

"""

"""
function add_proposition(
    model::JuMP.Model, 
    p::Proposition, 
    name::String = ""
    )
    # TODO validate the variables
    data = PropositionData(p, name)
    idx = _MOIUC.add_item(gdp_data(model), data)
    return PropositionRef(model, idx)
end
