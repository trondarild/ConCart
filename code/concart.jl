#=
This is the core library for the Consciousness Cartography project.
It encapsulates all the data loading and category-building logic.
This module is intended to be included and used by a frontend, such as a TUI or a web server.
=#
module ConCart

export find_cospans, find_cospan_continuations, find_pushout_opportunities, find_pushout_candidates, find_pullback_candidates, initialize_database, find_lenses, find_connections_from_object, find_connections_to_object, find_papers_for_object, LabeledConsciousnessGraph, nparts, subpart

using Catlab.CategoricalAlgebra
using Catlab.Presentations
using Catlab.Theories
using Catlab.Graphs
using Catlab.ACSets
using DataFrames
using CSV

# --- Define the Category Schema ---

@present SchConsciousness(FreeSchema) begin
    V::Ob
    E::Ob
    src::Hom(E, V)
    tgt::Hom(E, V)

    # Define attribute types
    ObjectID::AttrType
    Name::AttrType  
    Type::AttrType
    MorphismID::AttrType
    CitationKey::AttrType
    Notes::AttrType

    # Assign attributes to objects (vertices)
    obj_id::Attr(V, ObjectID)
    obj_name::Attr(V, Name)
    obj_type::Attr(V, Type)
    
    # Assign attributes to morphisms (edges)
    morph_id::Attr(E, MorphismID)
    citation::Attr(E, CitationKey)
    notes::Attr(E, Notes)
end

# Define the ACSet type based on our schema. We specify that all AttrTypes will be Strings.
@acset_type LabeledConsciousnessGraph(SchConsciousness, index=[:src, :tgt])

# --- Core Functions ---

"""
    initialize_database(data_dir::String)

Loads all CSV files from the specified directory and constructs the main
C_Consciousness category object.

Returns a tuple containing:
- The main category ACSet.
- The papers DataFrame.
- The objects DataFrame.
- The morphisms DataFrame.
"""
function initialize_database(data_dir::String)
    # Load DataFrames
    papers_path = joinpath(data_dir, "papers.csv")
    objects_path = joinpath(data_dir, "c_objects.csv")
    morphisms_path = joinpath(data_dir, "c_morphisms.csv")
    evidence_path = joinpath(data_dir, "c_evidence.csv")

    try
        papers_df = CSV.read(papers_path, DataFrame)
        objects_df = CSV.read(objects_path, DataFrame)
        morphisms_df = CSV.read(morphisms_path, DataFrame)
        evidence_df = CSV.read(evidence_path, DataFrame)

        # Build and return the category
        println("Building C_Consciousness category from database...")
        category = build_category(objects_df, evidence_df)
        println("Category built successfully with $(nparts(category, :V)) objects and $(nparts(category, :E)) morphisms.")
        
        return category, papers_df, objects_df, morphisms_df

    catch e
        if e isa SystemError
            println("ERROR: Could not find database files in '$data_dir'.")
            return nothing
        else
            rethrow(e)
        end
    end
end

"""
    build_category(objects_df, evidence_df)

Internal function to construct the ACSet from DataFrames.
"""
function build_category(objects_df, evidence_df)
    # Instantiate the ACSet, specifying String for all AttrTypes
    C_Consciousness = LabeledConsciousnessGraph{String, String, String, String, String, String}()
    object_map = Dict{String, Int}()

    for row in eachrow(objects_df)
        part_index = add_part!(C_Consciousness, :V;
            obj_id=row.ObjectID,
            obj_name=row.Name,
            obj_type=row.Type
        )
        object_map[row.ObjectID] = part_index
    end

    for row in eachrow(evidence_df)
        src_idx = get(object_map, row.SourceID, -1)
        tgt_idx = get(object_map, row.TargetID, -1)

        if src_idx != -1 && tgt_idx != -1
            add_part!(C_Consciousness, :E;
                src=src_idx,
                tgt=tgt_idx,
                morph_id=row.MorphismID,
                citation=row.CitationKey,
                notes=string(ismissing(row.Notes) ? "" : row.Notes)
            )
        else
            println("Warning: Skipping evidence row $(row.EvidenceID) due to missing object: $(row.SourceID) or $(row.TargetID)")
        end
    end
    return C_Consciousness
end

"""
    find_lenses(category, pattern::Vector{String}, morphisms_df)

Finds all paths in the category that match a given structural pattern.
The pattern can be a mix of object specifiers (Types, Names, "*") and
morphism specifiers (e.g., "<label>", "*").
"""
function find_lenses(category, pattern::Vector{String}, morphisms_df)
    # A pattern is object-only if it contains no morphism specifiers like "<label>"
    is_object_only_pattern = !any(p -> startswith(p, "<"), pattern)

    # If the pattern is object-only, we treat all elements as object specifiers
    # and insert wildcard morphisms between them.
    if is_object_only_pattern
        new_pattern = String[]
        for i in 1:length(pattern)
            push!(new_pattern, pattern[i])
            if i < length(pattern)
                push!(new_pattern, "*") # Insert wildcard morphism
            end
        end
        pattern = new_pattern
    end

    if isodd(length(pattern)) == false
        error("Lens pattern must have an odd number of elements (Object, Morphism, Object, ...). Processed pattern: $(pattern)")
    end

    valid_types = Set(["Theory", "Phenomenon", "Method", "Concept"])
    found_lenses = []

    # Helper function to check if a node matches an object specifier
    function node_matches(node_idx, specifier)
        if specifier == "*" return true end
        is_type = specifier in valid_types
        return if is_type
            subpart(category, node_idx, :obj_type) == specifier
        else
            subpart(category, node_idx, :obj_name) == specifier
        end
    end

    # Recursive helper function to find paths
    function find_paths_recursive(current_node_idx::Int, pattern_slice::Vector{String}, path_so_far::Vector{Int})
        if isempty(pattern_slice)
            if !isempty(path_so_far)
                push!(found_lenses, copy(path_so_far))
            end
            return
        end

        morphism_spec = pattern_slice[1]
        next_obj_spec = pattern_slice[2]
        remaining_pattern = pattern_slice[3:end]

        outgoing_edges = incident(category, current_node_idx, :src)

        for edge_idx in outgoing_edges
            # Filter by morphism
            morphism_id = subpart(category, edge_idx, :morph_id)
            morphism_label_rows = filter(row -> row.MorphismID == morphism_id, morphisms_df)
            if isempty(morphism_label_rows) continue end
            morphism_label = morphism_label_rows[1, :Label]
            
            morphism_matches = (morphism_spec == "*" || morphism_spec == "<$(morphism_label)>")
            if !morphism_matches continue end

            # Filter by target object
            target_node_idx = subpart(category, edge_idx, :tgt)
            if node_matches(target_node_idx, next_obj_spec)
                new_path = vcat(path_so_far, edge_idx)
                find_paths_recursive(target_node_idx, remaining_pattern, new_path)
            end
        end
    end

    start_obj_spec = pattern[1]
    start_nodes = findall(v -> node_matches(v, start_obj_spec), 1:nparts(category, :V))

    for v_idx in start_nodes
        find_paths_recursive(v_idx, pattern[2:end], Int64[])
    end

    return found_lenses
end

"""
    find_connections_from_object(category, object_name::String)

Finds all direct outgoing connections from a specific object, identified by its name.
"""
function find_connections_from_object(category, object_name::String)
    object_indices = findall(c -> c == object_name, subpart(category, :obj_name))
    if isempty(object_indices)
        return "Object with name '$object_name' not found in the category.", nothing
    end
    return nothing, incident(category, object_indices[1], :src)
end

"""
    find_connections_to_object(category, object_name::String)

Finds all direct incoming connections to a specific object, identified by its name.
"""
function find_connections_to_object(category, object_name::String)
    object_indices = findall(c -> c == object_name, subpart(category, :obj_name))
    if isempty(object_indices)
        return "Object with name '$object_name' not found in the category.", nothing
    end
    return nothing, incident(category, object_indices[1], :tgt)
end

"""
    find_papers_for_object(category, object_name::String)

Finds all papers associated with a given object, either as a source or target of a morphism.
"""
function find_papers_for_object(category, object_name::String)
    object_indices = findall(c -> c == object_name, subpart(category, :obj_name))
    if isempty(object_indices)
        return "Object with name '$object_name' not found in the category.", nothing
    end
    object_idx = object_indices[1]

    incoming_edges = incident(category, object_idx, :tgt)
    outgoing_edges = incident(category, object_idx, :src)
    
    all_edges = vcat(incoming_edges, outgoing_edges)
    if isempty(all_edges)
        return "No papers found associated with '$object_name'.", nothing
    end

    # Get unique citation keys from all associated edges
    citation_keys = unique(subpart(category, all_edges, :citation))
    return nothing, citation_keys
end


# Helper to get indices for an object specifier (name or wildcard)
function _get_object_indices(category, specifier)
    if specifier == "*"
        return 1:nparts(category, :V)
    else
        idx = findfirst(c -> c == specifier, subpart(category, :obj_name))
        return isnothing(idx) ? Int[] : [idx]
    end
end

"""
    find_pullback_candidates(category, spec_A, spec_B, spec_C)

Finds all objects P that form a cone over the span A -> C <- B.
Object specifiers can be names or a wildcard "*".
Trivial results where P is A or B, or where A and B are the same
(in wildcard searches), are filtered out.
"""
function find_pullback_candidates(category, spec_A::String, spec_B::String, spec_C::String)
    indices_A = _get_object_indices(category, spec_A)
    indices_B = _get_object_indices(category, spec_B)
    indices_C = _get_object_indices(category, spec_C)

    if isempty(indices_A) || isempty(indices_B) || isempty(indices_C)
        return "Could not find one of the specified objects.", nothing
    end

    all_results = []

    # Create a list of (A,B) pairs to check, avoiding duplicates from wildcards
    pairs_to_check = []
    if spec_A != "*" && spec_B != "*"
        # User specified both, even if they are the same.
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B]
    elseif spec_A != "*" # spec_B is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    elseif spec_B != "*" # spec_A is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    else # Both are "*"
        # Avoid duplicates like (A,B) vs (B,A) and self-pullbacks (A,A)
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia < ib]
    end

    for idx_C in indices_C, (idx_A, idx_B) in pairs_to_check
        # Ensure the span A->C and B->C exists for this combination
        a_to_c_edges = findall(e -> subpart(category, e, :src) == idx_A && subpart(category, e, :tgt) == idx_C, 1:nparts(category, :E))
        b_to_c_edges = findall(e -> subpart(category, e, :src) == idx_B && subpart(category, e, :tgt) == idx_C, 1:nparts(category, :E))

        if isempty(a_to_c_edges) || isempty(b_to_c_edges)
            continue
        end

        # Find all predecessors of A and B
        preds_A_edges = incident(category, idx_A, :tgt)
        preds_A_verts = unique(subpart(category, preds_A_edges, :src))

        preds_B_edges = incident(category, idx_B, :tgt)
        preds_B_verts = unique(subpart(category, preds_B_edges, :src))

        # The intersection of these predecessors are our candidate P objects
        pullback_P_verts = intersect(Set(preds_A_verts), Set(preds_B_verts))

        # For each candidate P, construct the full diagram, filtering out trivial cases
        for p_idx in pullback_P_verts
            # FILTER: Exclude cases where P is the same as A or B
            if p_idx == idx_A || p_idx == idx_B
                continue
            end

            p_to_a_edges = filter(e -> subpart(category, e, :src) == p_idx, preds_A_edges)
            p_to_b_edges = filter(e -> subpart(category, e, :src) == p_idx, preds_B_edges)

            for pa_edge in p_to_a_edges, pb_edge in p_to_b_edges, ac_edge in a_to_c_edges, bc_edge in b_to_c_edges
                push!(all_results, Dict(
                    "P_idx" => p_idx, "A_idx" => idx_A, "B_idx" => idx_B, "C_idx" => idx_C,
                    "p_to_a_edge" => pa_edge, "p_to_b_edge" => pb_edge,
                    "a_to_c_edge" => ac_edge, "b_to_c_edge" => bc_edge
                ))
            end
        end
    end

    if isempty(all_results)
        return "No non-trivial pullback candidates found for the given pattern.", nothing
    end

    return nothing, all_results
end

"""
    find_cospan_continuations(category, spec_S, spec_A, spec_B)

Given a cospan A <- S -> B, finds all pairs of paths starting from A and B.
This is used to find both completed pushouts and opportunities for synthesis.
"""
function find_cospan_continuations(category, spec_S::String, spec_A::String, spec_B::String)
    indices_S = _get_object_indices(category, spec_S)
    indices_A = _get_object_indices(category, spec_A)
    indices_B = _get_object_indices(category, spec_B)

    if isempty(indices_S) || isempty(indices_A) || isempty(indices_B)
        return "Could not find one of the specified objects.", nothing
    end

    all_results = []

    # Create a list of (A,B) pairs to check, avoiding duplicates from wildcards
    pairs_to_check = []
    if spec_A != "*" && spec_B != "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B]
    elseif spec_A != "*" # spec_B is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    elseif spec_B != "*" # spec_A is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    else # Both are "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia < ib]
    end

    for idx_S in indices_S, (idx_A, idx_B) in pairs_to_check
        s_to_a_edges = findall(e -> subpart(category, e, :src) == idx_S && subpart(category, e, :tgt) == idx_A, 1:nparts(category, :E))
        s_to_b_edges = findall(e -> subpart(category, e, :src) == idx_S && subpart(category, e, :tgt) == idx_B, 1:nparts(category, :E))

        if isempty(s_to_a_edges) || isempty(s_to_b_edges)
            continue
        end

        succs_A_edges = incident(category, idx_A, :src)
        succs_B_edges = incident(category, idx_B, :src)

        # If A or B have no successors, there's nothing to find.
        if isempty(succs_A_edges) || isempty(succs_B_edges)
            continue
        end

        # Find all pairs of successor edges
        for sa_edge in s_to_a_edges, sb_edge in s_to_b_edges, a_succ_edge in succs_A_edges, b_succ_edge in succs_B_edges
            qa_idx = subpart(category, a_succ_edge, :tgt)
            qb_idx = subpart(category, b_succ_edge, :tgt)
            
            push!(all_results, Dict(
                "S_idx" => idx_S, "A_idx" => idx_A, "B_idx" => idx_B,
                "QA_idx" => qa_idx, "QB_idx" => qb_idx,
                "s_to_a_edge" => sa_edge, "s_to_b_edge" => sb_edge,
                "a_to_qa_edge" => a_succ_edge, "b_to_qb_edge" => b_succ_edge
            ))
        end
    end

    if isempty(all_results)
        return "No continuations found for the given cospan pattern.", nothing
    end

    return nothing, all_results
end

"""
    find_cospans(category, spec_S, spec_A, spec_B)

Finds all cospans A <- S -> B matching the given specifiers. This is used
to identify potential synthesis opportunities.
"""
function find_cospans(category, spec_S::String, spec_A::String, spec_B::String)
    indices_S = _get_object_indices(category, spec_S)
    indices_A = _get_object_indices(category, spec_A)
    indices_B = _get_object_indices(category, spec_B)

    if isempty(indices_S) || isempty(indices_A) || isempty(indices_B)
        return "Could not find one of the specified objects.", nothing
    end

    all_results = []

    # Create a list of (A,B) pairs to check, avoiding duplicates from wildcards
    pairs_to_check = []
    if spec_A != "*" && spec_B != "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B]
    elseif spec_A != "*" # spec_B is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    elseif spec_B != "*" # spec_A is "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia != ib]
    else # Both are "*"
        pairs_to_check = [(ia, ib) for ia in indices_A for ib in indices_B if ia < ib]
    end

    for idx_S in indices_S, (idx_A, idx_B) in pairs_to_check
        s_to_a_edges = findall(e -> subpart(category, e, :src) == idx_S && subpart(category, e, :tgt) == idx_A, 1:nparts(category, :E))
        s_to_b_edges = findall(e -> subpart(category, e, :src) == idx_S && subpart(category, e, :tgt) == idx_B, 1:nparts(category, :E))

        if !isempty(s_to_a_edges) && !isempty(s_to_b_edges)
            # Found a cospan. Return every combination of edges.
            for sa_edge in s_to_a_edges, sb_edge in s_to_b_edges
                 push!(all_results, Dict(
                    "S_idx" => idx_S, "A_idx" => idx_A, "B_idx" => idx_B,
                    "s_to_a_edge" => sa_edge, "s_to_b_edge" => sb_edge
                ))
            end
        end
    end
    
    if isempty(all_results)
        return "No cospans found for the given pattern.", nothing
    end

    return nothing, all_results
end

end # module ConCart
