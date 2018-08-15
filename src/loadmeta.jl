## Loading data into various data structures ##

struct Require
    versions::VersionSet
    systems::Vector{Symbol}
end

struct Version
    sha1::Union{Nothing, String}
    requires::Dict{String,Require}
end

struct Package
    uuid::UUID
    url::String
    versions::Dict{VersionNumber,Version}
end

Require(versions::VersionSet) = Require(versions, Symbol[])
Require(version::VersionInterval) = Require(VersionSet([version]), Symbol[])
Version(sha1::String) = Version(sha1, Dict{String,Require}())

function load_requires(path::String)
    requires = Dict{String,Require}()
    requires["julia"] = Require(VersionInterval())
    isfile(path) || return requires
    for r in filter!(r->r isa Requirement, Reqs.read(path))
        new = haskey(requires, r.package)
        versions, systems = VersionSet(r.versions.intervals), r.system
        if haskey(requires, r.package)
            versions = versions ∩ requires[r.package].versions
            systems  = systems  ∪ requires[r.package].systems
        end
        requires[r.package] = Require(versions, Symbol.(systems))
    end
    return requires
end

function load_versions(dir::String)
    versions = Dict{VersionNumber,Version}()
    isdir(dir) || return versions
    for ver in readdir(dir)
        path = joinpath(dir, ver)
        sha1 = joinpath(path, "sha1")
        isfile(sha1) || continue
        requires = load_requires(joinpath(path, "requires"))
        versions[VersionNumber(ver)] = Version(readchomp(sha1), requires)
    end
    return versions
end

function load_packages_METADATA(
    dir::AbstractString,
    selected_packages::AbstractVector{<:AbstractString}
)
    pkgs = Dict{String,Package}()
    for pkg in selected_packages
        path = joinpath(dir, pkg)
        url = joinpath(path, "url")
        versions = joinpath(path, "versions")
        isfile(url) || continue
        pkgs[pkg] = Package(
            uuid5(uuid_package, pkg),
            readchomp(url),
            load_versions(versions),
        )
    end
    pkgs
end

@eval julia_versions() = $([VersionNumber(0,m) for m=1:7])
julia_versions(f::Function) = filter(f, julia_versions())
julia_versions(vi::VersionInterval) = julia_versions(v->v in vi)

macro clean(ex) :(x = $(esc(ex)); $(esc(:clean)) &= x; x) end

function check_packages(
    pkgs::AbstractDict{<:AbstractString,Package},
    other_registries::AbstractDict{<:AbstractString, Package}
)
    for (pkg, p) in pkgs, (ver, v) in p.versions
        if ver != thispatch(ver)
            error("$pkg version $ver is illegeal: no prereleases")
        end
        if ver == v"0.0.0"
            error("$pkg version $ver: Version must be greater than 0.0.0")
        end
        for (req, r) in v.requires
            # req == "julia" && continue
            if haskey(other_registries, req)
                req_registry = other_registries
            elseif haskey(pkgs, req)
                req_registry = pkgs
            else
                error("$pkg ver $ver: requirement $req not found")
            end
            if ! any(w->w in r.versions, keys(req_registry[req].versions)) && 
                error("$pkg ver $ver: compat range not satisfied")
            end
        end
    end
    nothing
end
