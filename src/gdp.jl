abstract type :ModelVariables end

function GDPModel()
    model = Model()
    model.ext[:gdp_variable_refs] = []
    model.ext[:gdp_variable_names] = []

    return model
end