module RegistryUtils

using Base: thispatch, thisminor, nextpatch, nextminor
import Base: convert
import LibGit2
import UUIDs
import LinearAlgebra: checksquare
import Pkg
using Pkg.Operations
using Pkg.Types
using Pkg.Types: uuid_package, uuid_registry, uuid5, VersionSpec, VersionRange, VersionBound
import Pkg: TOML
import Pkg.Pkg2.Reqs: Reqs, Requirement
import Pkg.Pkg2.Pkg2Types: VersionInterval, VersionSet

export
    generate!

include("loadmeta.jl")
include("loadregistry.jl")
include("utils.jl")
include("gitmeta.jl")
include("genstdlib.jl")
include("generate.jl")
include("update.jl")

end # module
