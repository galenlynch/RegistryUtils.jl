function parse_registry(
    registry_dir = joinpath(homedir(), ".julia", "registries", "General")
)
    registry_dict = TOML.parsefile(joinpath(registry_dir, "Registry.toml"))
    pkgs = Dict{String, Package}()
    for (uuid_str, pkg_lookup) in registry_dict["packages"]
        pkg_name = pkg_lookup["name"]::String
        rel_path = pkg_lookup["path"]::String
        abs_path = joinpath(registry_dir, rel_path)
        pkg = parse_registry_package_dir(abs_path)
        pkgs[pkg_name] = pkg
    end
    pkgs
end

function parse_registry_package_dir(path::AbstractString)
    info = TOML.parsefile(joinpath(path, "Package.toml"))
    deps_data = Operations.load_package_data_raw(
        UUID, joinpath(path, "Deps.toml")
    )
    compat_data = Operations.load_package_data_raw(
        VersionSpec, joinpath(path, "Compat.toml")
    )
    toml_versions = Operations.load_versions(path)
    versions = Dict{VersionNumber, Version}()
    for v in keys(toml_versions)
        reqdict = Dict{String, Require}()
        ver = Version(nothing, reqdict)
        for (vr, dd) in compat_data
            if v in vr
                for (reqname, vs) in dd
                    reqdict[reqname] = Require(convert(VersionSet, vs), Symbol[])
                end
            end
        end
        for (vr, dd) in deps_data
            if v in vr
                for (reqname, uuid) in dd
                    if ! haskey(reqdict, reqname)
                        reqdict[reqname] = Require(VersionSet(), Symbol[])
                    end
                end
            end
        end
        versions[v] = ver
    end
    return Package(
        UUID(info["uuid"]),
        info["repo"],
        versions
    )
end

convert(::Type{VersionNumber}, v::VersionBound) = VersionNumber(v.t...)
function convert(::Type{VersionSet}, vs::VersionSpec)
    VersionSet(
        convert(VersionNumber, vs.ranges[1].lower),
        next_semver(convert(VersionNumber, vs.ranges[1].upper))
    )
end

function next_semver(v::VersionNumber)
    if v.major == 0
        return VersionNumber(0, v.minor + 1, 0)
    else
        return VersionNumber(v.major + 1, 0, 0)
    end
end
