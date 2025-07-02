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
The pattern can be a mix of object Types (e.g., "Theory") and specific
object Names (e.g., "Qualia").
"""
function find_lenses(category, pattern::Vector{String})
    if length(pattern) < 2
        error("Lens pattern must have at least two steps (e.g., A -> B).")
    end

    # A predefined set of valid object types for quick lookup
    valid_types = Set(["Theory", "Phenomenon", "Method", "Concept"])
    found_lenses = []

    function find_paths(start_node_idx, pattern_idx, current_path)
        current_pattern_step = pattern[pattern_idx]
        
        # Determine if the pattern step is a Type or a specific Name
        is_type_match = current_pattern_step in valid_types
        
        # Check if the current node matches the pattern step
        if is_type_match
            if subpart(category, start_node_idx, :obj_type) != current_pattern_step
                return # Type mismatch
            end
        else # Assume it's a name
            if subpart(category, start_node_idx, :obj_name) != current_pattern_step
                return # Name mismatch
            end
        end

        # Base case: we have found a full path matching the pattern
        if pattern_idx == length(pattern)
            if !isempty(current_path)
                push!(found_lenses, copy(current_path))
            end
            return
        end

        # Recursive step: find all outgoing edges and continue the search
        next_pattern_step = pattern[pattern_idx + 1]
        is_next_type_match = next_pattern_step in valid_types

        outgoing_edges = incident(category, start_node_idx, :src)
        for edge_idx in outgoing_edges
            target_node_idx = subpart(category, edge_idx, :tgt)
            
            # Check if the target node matches the *next* step in the pattern
            target_matches = if is_next_type_match
                subpart(category, target_node_idx, :obj_type) == next_pattern_step
            else
                subpart(category, target_node_idx, :obj_name) == next_pattern_step
            end

            if target_matches
                push!(current_path, edge_idx)
                find_paths(target_node_idx, pattern_idx + 1, current_path)
                pop!(current_path)
            end
        end
    end

    # Start the search from every object in the category
    for v_idx in 1:nparts(category, :V)
        find_paths(v_idx, 1, [])
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
