mutable struct GDPdata
    gdp_variable_refs::Vector
    gdp_variable_names::Vector
    disjunctions::Dict
end

function GDPModel()
    model = Model()
    model.ext[:GDPdata] = GDPdata()
    # model.optimize_hook = 

    return model
end