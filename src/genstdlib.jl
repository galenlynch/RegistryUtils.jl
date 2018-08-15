function stdlib_regdata(stdlib_dir)
    # TODO: use Sys.STDLIBDIR instead once implemented
    isdir(stdlib_dir) || error("stdlib directory does not exist: $stdlib_dir")

    stdlib_uuids = Dict{String,String}()
    stdlib_trees = Dict{String,String}()
    stdlib_deps = Dict{String,Vector{String}}()

    for pkg in readdir(stdlib_dir)
        project_file = joinpath(stdlib_dir, pkg, "Project.toml")
        isfile(project_file) || continue
        project = TOML.parsefile(project_file)
        stdlib_uuids[pkg] = project["uuid"]
        try
        stdlib_trees[pkg] = split(
            readchomp(`git -C $stdlib_dir ls-tree HEAD -- $pkg`)
        )[3]
        catch y
            if y isa BoundsError
                @error "Error while processing $pkg"
            end
            rethrow(y)
        end
        stdlib_deps[pkg] = String[]
        haskey(project, "deps") || continue
        append!(stdlib_deps[pkg], sort!(collect(keys(project["deps"]))))
    end
    stdlib_uuids, stdlib_trees, stdlib_deps
end
