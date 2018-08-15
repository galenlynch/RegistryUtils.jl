const STDLIB_UUID_STRS = Dict(
    "Pkg"              => "44cfe95a-1eb2-52ea-b672-e2afdf69b78f",
    "Statistics"       => "10745b16-79ce-11e8-11f9-7d13ad32a3b2",
    "Test"             => "8dfed614-e22c-5e08-85e1-65c5234f0b40",
    "CRC32c"           => "8bf52ea8-c179-5cab-976a-9e18b702a9bc",
    "Random"           => "9a3f8284-a2c9-5f02-9a11-845980a1fd5c",
    "SuiteSparse"      => "4607b0f0-06f3-5cda-b6b1-a6196a1729e9",
    "Libdl"            => "8f399da3-3557-5675-b5ff-fb832c97cbdb",
    "UUIDs"            => "cf7118a7-6976-5b1a-9a39-7adc72f591a4",
    "Distributed"      => "8ba89e20-285c-5b6f-9357-94700520ee1b",
    "Serialization"    => "9e88b42a-f829-5b0c-bbe9-9e923198166b",
    "SHA"              => "ea8e919c-243c-51af-8825-aaa63cd721ce",
    "DelimitedFiles"   => "8bb1440f-4735-579b-a4ab-409b98df4dab",
    "LinearAlgebra"    => "37e2e46d-f89d-539d-b4ee-838fcccc9c8e",
    "REPL"             => "3fa0cd96-eef1-5676-8a61-b3b8758bbffb",
    "FileWatching"     => "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee",
    "SharedArrays"     => "1a1011a3-84de-559e-8e89-a11a2f7dc383",
    "LibGit2"          => "76f85450-5226-5b5a-8eaa-529ad045b433",
    "Base64"           => "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f",
    "SparseArrays"     => "2f01184e-e22b-5df5-ae63-d93ebab69eaf",
    "Mmap"             => "a63ad114-7e13-5084-954f-fe012c677804",
    "Profile"          => "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79",
    "Unicode"          => "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5",
    "Dates"            => "ade2ca70-3891-5945-98fb-dc099432e06a",
    "InteractiveUtils" => "b77e0a4c-d291-57a0-90e8-8db25a27a240",
    "Future"           => "9fa8497b-333b-5362-9e8d-4d0656e87820",
    "Sockets"          => "6462fe0b-24de-5631-8697-dd941f90decc",
    "Logging"          => "56ddb016-857b-54e1-b83d-db4d58db5568",
    "Printf"           => "de0858da-6303-5e67-8744-51eddeeeb8d7",
    "Markdown"         => "d6f4376e-aef5-505a-96c1-9c027394607a"
)

const STDLIBS = collect(keys(STDLIB_UUID_STRS))

function uses(repo::String, tree::String, lib::String)
    pattern = string(raw"\b(import|using)\s+((\w|\.)+\s*,\s*)*", lib, raw"\b")
    success(`git -C $repo grep -Eq $pattern $tree`)
end

function gitmeta(pkgs::Dict{String,Package})
    @assert length(STDLIBS) ≤ 64 # use 64 bits to encode usage
    fd = joinpath(@__DIR__, "sha1map.toml")
    fs = joinpath(@__DIR__, "stdlib.toml")
    d = ispath(fd) ? TOML.parsefile(fd) : Dict()
    s = Dict()
    if ispath(fs)
        s = TOML.parsefile(fs)
        get(s, "STDLIBS", nothing) == STDLIBS || empty!(s)
        mv(fs, "$fs.old", force=true)
    end
    s["STDLIBS"] = STDLIBS
    io = open(fs, "w")
    println(io, "STDLIBS = [")
    for lib in STDLIBS
        println(io, "    ", repr(lib), ",")
    end
    println(io, "]")
    println(io)
    for (pkg, p) in sort!(collect(pkgs), by=first)
        (pkg == "julia" || isempty(p.versions)) && continue
        uuid = string(p.uuid)
        @info "Package [$uuid] $pkg"
        haskey(d, uuid) || (d[uuid] = Dict())
        haskey(s, uuid) || (s[uuid] = Dict())
        updated = false
        repo_path = joinpath(homedir(), ".julia", "clones", uuid)
        repo = nothing
        for (ver, v) in p.versions
            haskey(d[uuid], v.sha1) &&
            if v"0.7" ∉ v.requires["julia"].versions ||
                haskey(s[uuid], v.sha1)
                continue
            end
            if repo == nothing
                repo = ispath(repo_path) ? LibGit2.GitRepo(repo_path) : begin
                    updated = true
                    @info "Cloning [$uuid] $pkg"
                    LibGit2.clone(p.url, repo_path, isbare=true)
                end
            end
            git_commit_hash = LibGit2.GitHash(v.sha1)
            if !updated
                try LibGit2.GitObject(repo, git_commit_hash)
                catch err
                    if !(err isa LibGit2.GitError && err.code == LibGit2.Error.ENOTFOUND)
                        rethrow(err)
                    end
                    @info "Updating $pkg from $(p.url)"
                    LibGit2.fetch(
                        repo,
                        remoteurl=p.url,
                        refspecs=["+refs/*:refs/remotes/cache/*"]
                    )
                end
            end
            failed = false
            git_commit = try LibGit2.GitObject(repo, git_commit_hash)
            catch err
                failed = true
                if !(err isa LibGit2.GitError && err.code == LibGit2.Error.ENOTFOUND)
                    rethrow(err)
                end
                @error("$pkg: git object $(v.sha1) could not be found")
            end
	    failed && continue
            if !(git_commit isa LibGit2.GitCommit || git_commit isa LibGit2.GitTag)
                error("$pkg: git object $(v.sha1) not a commit – $(typeof(git_commit))")
            end
            git_tree = LibGit2.peel(LibGit2.GitTree, git_commit)
            @assert git_tree isa LibGit2.GitTree
            git_tree_hash = string(LibGit2.GitHash(git_tree))
            d[uuid][v.sha1] = git_tree_hash
            # scan for stdlib dependencies
            v"0.7" in v.requires["julia"].versions || continue
            haskey(s[uuid], v.sha1) && continue
            libs = [uses(repo_path, git_tree_hash, lib) for lib in STDLIBS]
            s[uuid][v.sha1] = sum(d*2^(i-1) for (i,d) in enumerate(libs))
        end
        isempty(s[uuid]) && continue
        println(io, "[$uuid]")
        for (sha1, n) in sort!(collect(s[uuid]), by=string∘first)
            println(io, "$sha1 = $n")
        end
        println(io)
        flush(io)
    end
    open(fd, "w") do io
        TOML.print(io, d, sorted=true)
    end
    close(io)
    rm("$fs.old", force=true)
    return d, s
end
