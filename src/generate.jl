"""
    generate!(
        registry_packages::Vector{String},
        registry_name::String,
        registry_repo::String,
        [registry_description::String = "", writedir::String = pwd()];
        force::bool = true,
        METADATA_path::String = Pkg.Pkg2.dir("METADATA"),
        registry_dirs::Vector{String} = [joinpath(homedir(), ".julia", "registries", "General")],
        stdlib_dir::String = ""
     )

Generate a registry named `registry_name` with repository `registry_repo`
that contains the packages listed in `registry_packages`. These packages must be
valid METADATA packages in the METADATA directory at `METADATA_path`, but do not
need to be in the official Julia METADATA repository.

The packages in the new registry can have dependencies on packages in other
registries. By default the "General" registry is available to resolve dependencies,
any set of registries can be specified by setting `registry_dirs` to contain the
path for each registry.

Dependencies on the standard library can either be resolved by setting `stdlib_dir`
to be the path of the standard libraries in a git repository (i.e. in the julia
repository), or if `stdlib_dir` is empty then a cached set of UUIDs will be used.
"""
function generate! end
function generate!(
    pkgs::AbstractDict{<:AbstractString, Package},
    other_registries::AbstractDict{<:AbstractString, Package},
    args...; kwargs...
)
    check_packages(pkgs, other_registries)
    _generate!(pkgs, other_registries, args...; kwargs...)
end
function generate!(
    pkgs::AbstractDict{<:AbstractString, Package},
    other_registries::AbstractVector{<:AbstractDict{<:AbstractString, Package}},
    args...; kwargs...
)
    generate!(pkgs, merge(other_registries...), args...; kwargs...)
end
function generate!(
    pkgs::AbstractDict{<:AbstractString, Package},
    registry_name::AbstractString,
    args...;
    registry_dirs::AbstractVector{<:AbstractString} = [
        joinpath(homedir(), ".julia", "registries", "General")
    ],
    kwargs...
)
    generate!(
        pkgs, parse_registry.(registry_dirs), registry_name, args...; kwargs...
    )
end
function generate!(
    package_strings::AbstractVector{<:AbstractString},
    args...; 
    METADATA_path::AbstractString = Pkg.Pkg2.dir("METADATA"),
    kwargs...
)
    isempty(package_strings) && throw(ArgumentError("Must specify packages for registry"))
    pkgs = load_packages_METADATA(METADATA_path, package_strings)
    generate!(pkgs, args...; kwargs...)
end

function _generate!(
    pkgs::AbstractDict{<:AbstractString, Package},
    other_registries::AbstractDict{<:AbstractString, Package},
    registry_name::AbstractString,
    registry_repo::AbstractString,
    registry_description::AbstractString = "",
    writedir::AbstractString = pwd();
    stdlib_dir::AbstractString = "",
    force::Bool = false,
)
    isdir(writedir) || throw(ArgumentError("$writedir does not exist"))
    prefix = joinpath(writedir, registry_name)
    if isdir(prefix)
        if ! isempty(readdir(prefix)) && ! force
            error("$prefix exists and is not empty, use 'force' to overwrite")
        end
    elseif ispath(prefix)
        if force
            mv(prefix, "$prefix.bak")
            mkdir(prefix)
        else
            error("$prefix is a file, use 'force' to overwrite")
        end
    else
        mkdir(prefix)
    end

    write_toml(prefix, "Registry") do io
        uuid = string(uuid5(uuid_registry, registry_repo))
        println(io, "name = ", repr(registry_name))
        println(io, "uuid = ", repr(uuid))
        println(io, "repo = ", repr(registry_repo))
        println(io, "\ndescription = \"\"\"")
        print(io, registry_description)
        println(io, "\"\"\"")
        println(io, "\n[packages]")
        for (pkg, p) in sort!(collect(pkgs), by=(p->p.uuid.value)∘last)
            bucket = string(uppercase(first(pkg)))
            path = joinpath(bucket, pkg)
            println(
                io,
                p.uuid, " = { name = ", repr(pkg), ", path = ", repr(path), " }"
            )
        end
    end
    
    buckets = Dict()
    for (pkg, p) in pkgs
        bucket = string(uppercase(first(pkg)))
        push!(get!(buckets, bucket, []), (pkg, p))
    end

    if isempty(stdlib_dir)
        for pkg in STDLIBS
            other_registries[pkg] = Package(
                UUID(STDLIB_UUID_STRS[pkg]),
                "https://github.com/JuliaLang/julia.git",
                Dict(
                    VersionNumber(0,7,0) => Version(
                        nothing, Dict{String,Require}()
                    )
                )
            )
        end
    else
        stdlib_uuids, stdlib_trees, stdlib_deps = stdlib_regdata(stdlib_dir)

        for pkg in STDLIBS
            tree = stdlib_trees[pkg]
            deps = Dict(
                dep => Require(VersionInterval()) for dep in stdlib_deps[pkg]
            )
            other_registries[pkg] = Package(
                UUID(stdlib_uuids[pkg]),
                "https://github.com/JuliaLang/julia.git",
                Dict(
                    VersionNumber(0,7,0,("DEV",),("r"*tree[1:8],)) =>
                    Version(tree, deps)
                ),
            )
        end
    end

    trees, stdlibs = gitmeta(pkgs)

    for (pkg, p) in pkgs
        uuid = string(p.uuid)
        haskey(stdlibs, uuid) || continue
        for (ver, v) in p.versions
            n = get(stdlibs[uuid], v.sha1, 0)
            n == 0 && continue
            for lib in STDLIBS
                if n & 1 != 0
                    v.requires[lib] = Require(VersionInterval())
                end
                n >>>= 1
            end
        end
    end

    for (bucket, b_pkgs) in buckets, (pkg, p) in b_pkgs
        haskey(stdlibs, pkg) && continue
        url = p.url
        uuid = string(p.uuid)
        startswith(url, "git://github.com") && (url = "https"*url[4:end])

        # Package.toml
        write_toml(prefix, bucket, pkg, "Package") do io
            println(io, "name = ", repr(pkg))
            println(io, "uuid = ", repr(uuid))
            println(io, "repo = ", repr(url))
        end

        # Versions.toml
        write_toml(prefix, bucket, pkg, "Versions") do io
            for (i, (ver, v)) in enumerate(sort!(collect(p.versions), by=first))
                i > 1 && println(io)
                println(io, "[", toml_key(string(ver)), "]")
                println(io, "git-tree-sha1 = ", repr(trees[uuid][v.sha1]))
            end
        end
        versions = sort!(collect(keys(p.versions)))

        function write_versions_data(f::Function, name::String; lt::Function=isless)
            data = Dict{VersionNumber,Dict{String,String}}()
            for (ver, v) in p.versions, (dep, d) in v.requires
                val = f(dep, d)
                val == nothing && continue
                haskey(data, ver) || (data[ver] = Dict{String,String}())
                # BinDeps injects a dependency on Libdl
                if name == "Deps" && dep == "BinDeps"
                    data[ver]["Libdl"] = "\"8f399da3-3557-5675-b5ff-fb832c97cbdb\""
                end
                data[ver][dep] = val
            end
            compressed = compress_versions_data(data, versions)
            !isempty(compressed) && write_toml(prefix, bucket, pkg, name) do io
                vers = unique(getindex.(compressed, 1))
                keys = sort!(unique(getindex.(compressed, 2)), lt=lt)
                what = (vers, keys)
                ord = (1, 2)
                for (i, x) in enumerate(what[ord[1]])
                    i > 1 && println(io)
                    println(io, "[", toml_key(x), "]")
                    for y in what[ord[2]]
                        for t in compressed
                            t[ord[1]] == x && t[ord[2]] == y || continue
                            println(io, toml_key(y), " = ", t[3])
                        end
                    end
                end
            end
        end

        # Deps.toml
        write_versions_data("Deps") do dep, d
            if dep == "julia"
                res = nothing
            else
                registry = haskey(pkgs, dep) ? pkgs : other_registries
                res = repr(string(registry[dep].uuid))
            end
            res
        end

        # Compat.toml
        write_versions_data("Compat", lt=packagelt) do dep, d
            if dep in STDLIBS
                res = nothing
            else
                registry = haskey(pkgs, dep) ? pkgs : other_registries
                res = versions_repr(compress_versions(
                    d.versions, collect(keys(registry[dep].versions))
                ))
            end
            res
        end
    end
end
