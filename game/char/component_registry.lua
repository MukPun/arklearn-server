local Components = {}
Components._registry = {}

function Components.register(name, factory_func)
    Components._registry[name] = factory_func
end

function Components.get_registry()
    return Components._registry
end

return Components