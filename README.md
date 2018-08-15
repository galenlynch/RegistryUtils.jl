# RegistryUtils

A simple set of tools to generate custom registries, consisting of packages in
an existing branch of METADATA, which may depend on packages in the "General"
or other registries.

RegistryUtils.jl is mostly just repackaging the registry scripts in [Pkg.jl][Pkg]

Only one function is currently exported: `generate!`, which is described below

## Requirements
Julia 0.7 or higher

## Installation
This package is not registered, so clone it in order to use it

## Usage

```julia
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
```

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

[Pkg]: https://github.com/JuliaLang/Pkg.jl
