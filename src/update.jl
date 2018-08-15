function update(
    registry_path = joinpath(homedir(), ".julia", "registries"),
    registry_name = "General"
)
    # gen_stdlib()
    generate(joinpath(registry_path, registry_name))
end
