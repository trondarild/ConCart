#=
This is the core library for the Consciousness Cartography project.
It encapsulates all the data loading and category-building logic.
This module is intended to be included and used by a frontend, such as a TUI or a web server.
=#
module ConCart

export initialize_database, find_lenses, find_connections_from_object, find_connections_to_object, find_papers_for_object, LabeledConsciousnessGraph, nparts, subpart

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
    find_lenses(category, pattern::Vector{String})

Finds all paths in the category that match a given structural pattern.
The pattern can be a mix of object Types (e.g., "Theory"), specific
object Names (e.g., "Qualia"), or wildcards ("*").
"""
function find_lenses(category, pattern::Vector{String})
    if length(pattern) < 2
        error("Lens pattern must have at least two steps (e.g., A -> B).")
    end

    valid_types = Set(["Theory", "Phenomenon", "Method", "Concept"])
    found_lenses = []

    # Recursive helper function to find paths
    function find_paths_recursive(current_node_idx::Int, pattern_slice::Vector{String}, path_so_far::Vector{Int})
        # Base case: if the pattern slice is empty, we have successfully completed a path.
        if isempty(pattern_slice)
            if !isempty(path_so_far)
                push!(found_lenses, copy(path_so_far))
            end
            return
        end

        next_step_pattern = pattern_slice[1]
        remaining_pattern = pattern_slice[2:end]

        # Find all outgoing edges from the current node
        outgoing_edges = incident(category, current_node_idx, :src)

        for edge_idx in outgoing_edges
            target_node_idx = subpart(category, edge_idx, :tgt)
            new_path = vcat(path_so_far, edge_idx)

            if next_step_pattern == "*"
                # Wildcard: this step matches any node. Continue search from the target node.
                find_paths_recursive(target_node_idx, remaining_pattern, new_path)
            else
                # Specific match (Type or Name)
                is_type_match = next_step_pattern in valid_types
                target_matches = if is_type_match
                    subpart(category, target_node_idx, :obj_type) == next_step_pattern
                else
                    subpart(category, target_node_idx, :obj_name) == next_step_pattern
                end

                if target_matches
                    find_paths_recursive(target_node_idx, remaining_pattern, new_path)
                end
            end
        end
    end

    # Start the search from all nodes that match the *first* step of the pattern.
    first_step_pattern = pattern[1]
    rest_of_pattern = pattern[2:end]
    
    start_nodes = if first_step_pattern == "*"
        1:nparts(category, :V) # Start from all nodes if the first step is a wildcard
    else
        is_first_step_type = first_step_pattern in valid_types
        findall(v_idx -> if is_first_step_type
                subpart(category, v_idx, :obj_type) == first_step_pattern
            else
                subpart(category, v_idx, :obj_name) == first_step_pattern
            end, 1:nparts(category, :V))
    end

    for v_idx in start_nodes
        # FIX: Initialize the path with a typed empty vector `Int64[]` instead of `[]`.
        find_paths_recursive(v_idx, rest_of_pattern, Int64[])
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

end # module ConCart
