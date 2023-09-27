function test_eq_scalar_affine_bigm()
    model = GDPModel()
    @variable(model, x)
    @variable(model, y, LogicalVariable)
    @constraint(model, con, 3*x == 1, DisjunctConstraint(y))
    _reformulate_logical_variables(model)
    
end