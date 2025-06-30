#=
This script provides a framework for performing applied category theory on a
database of scientific literature about consciousness studies.

It does the following:
1. Loads the database from three CSV files (objects, morphisms, evidence).
2. Constructs a formal Category, C_Consciousness, as a Labeled, Attributed C-Set using Catlab.jl.
3. Implements functions to find structural patterns ("lenses") and to query for all connections to and from a specific object.
4. Displays the results, including the papers that provide evidence for each step.

To Run:
1. Make sure you have the required Julia packages installed.
   From the Julia REPL (press `]` to enter Pkg mode):
   pkg> add Catlab, DataFrames, CSV
2. Ensure the CSV files are in a `../data/` directory relative to this script.
3. Execute the script: `julia this_script_name.jl`
=#

using Catlab.CategoricalAlgebra
using Catlab.Presentations
using Catlab.Theories
using Catlab.Graphs
using Catlab.ACSets
using DataFrames
using CSV

# --- 1. Load Data from CSV Files ---

# Define file paths. Assumes a directory structure like:
# ./scripts/this_script.jl
# ./data/c_objects.csv
# ...
const DATA_DIR = joinpath(@__DIR__, "..", "data")
const OBJECTS_PATH = joinpath(DATA_DIR, "c_objects.csv")
const MORPHISMS_PATH = joinpath(DATA_DIR, "c_morphisms.csv")
const EVIDENCE_PATH = joinpath(DATA_DIR, "c_evidence.csv")


function load_database()
    try
        println("Loading database files...")
        objects_df = CSV.read(OBJECTS_PATH, DataFrame)
        morphisms_df = CSV.read(MORPHISMS_PATH, DataFrame)
        evidence_df = CSV.read(EVIDENCE_PATH, DataFrame)
        println("Database files loaded successfully.")
        return objects_df, morphisms_df, evidence_df
    catch e
        if e isa SystemError
            println("ERROR: Could not find database files.")
            println("Please ensure the following files exist:")
            println("  - $OBJECTS_PATH")
            println("  - $MORPHISMS_PATH")
            println("  - $EVIDENCE_PATH")
            return nothing
        else
            println("ERROR: Failed to load database files: $e")
            rethrow(e)
        end
    end
end

# --- 2. Build the Category C_Consciousness ---

@present SchConsciousness(FreeSchema) begin
    V::Ob
    E::Ob
    src::Hom(E, V)
    tgt::Hom(E, V)

    # Attributes for objects (vertices) - using AttrType
    ObjectID::AttrType
    Name::AttrType  
    Type::AttrType

    # Attributes for morphisms (edges) - using AttrType
    MorphismID::AttrType
    CitationKey::AttrType
    Notes::AttrType

    # Attribute mappings
    obj_id::Attr(V, ObjectID)
    obj_name::Attr(V, Name)
    obj_type::Attr(V, Type)
    
    morph_id::Attr(E, MorphismID)
    citation::Attr(E, CitationKey)
    notes::Attr(E, Notes)
end

@acset_type LabeledConsciousnessGraph(SchConsciousness, index=[:src, :tgt])

function build_category(objects_df, evidence_df)
    C_Consciousness = LabeledConsciousnessGraph{String, String, String, String, String, String}()
    object_map = Dict{String, Int}()

    println("Adding objects to category...")
    for row in eachrow(objects_df)
        part_index = add_part!(C_Consciousness, :V;
            obj_id=string(row.ObjectID),
            obj_name=string(row.Name),
            obj_type=string(row.Type)
        )
        object_map[string(row.ObjectID)] = part_index
    end

    println("Adding morphisms to category...")
    for (i, row) in enumerate(eachrow(evidence_df))
        src_id = string(row.SourceID)
        tgt_id = string(row.TargetID)
        
        src_idx = get(object_map, src_id, -1)
        tgt_idx = get(object_map, tgt_id, -1)

        if src_idx != -1 && tgt_idx != -1
            add_part!(C_Consciousness, :E;
                src=src_idx,
                tgt=tgt_idx,
                morph_id=string(row.MorphismID),
                citation=string(row.CitationKey),
                notes=string(ismissing(row.Notes) ? "" : row.Notes)
            )
        else
            println("Warning: Skipping evidence row $i due to missing object: $src_id or $tgt_id")
        end
    end

    return C_Consciousness
end

# --- 3. Query Functions ---

"""
Finds all paths in the category that match a given structural pattern.
A pattern is a sequence of object types, e.g., ["Theory", "Method", "Phenomenon"].
"""
function find_lenses(category, pattern::Vector{String})
    if length(pattern) < 2
        error("Lens pattern must have at least two steps (e.g., A -> B).")
    end

    found_lenses = []
    
    function find_paths(start_node_idx, pattern_idx, current_path)
        if subpart(category, start_node_idx, :obj_type) != pattern[pattern_idx]
            return
        end

        if pattern_idx == length(pattern)
            if !isempty(current_path)
                push!(found_lenses, copy(current_path))
            end
            return
        end

        outgoing_edges = incident(category, start_node_idx, :src)
        for edge_idx in outgoing_edges
            target_node_idx = subpart(category, edge_idx, :tgt)
            if subpart(category, target_node_idx, :obj_type) == pattern[pattern_idx + 1]
                push!(current_path, edge_idx)
                find_paths(target_node_idx, pattern_idx + 1, current_path)
                pop!(current_path)
            end
        end
    end

    for v_idx in 1:nparts(category, :V)
        find_paths(v_idx, 1, [])
    end

    return found_lenses
end

"""
Finds and displays all direct outgoing connections from a specific object, identified by its name.
"""
function find_connections_from_object(category, object_name::String, morphisms_df)
    # Find the index of the object with the given name
    object_indices = findall(c -> c == object_name, subpart(category, :obj_name))

    if isempty(object_indices)
        println("Object with name '$object_name' not found in the category.")
        return
    end
    object_idx = object_indices[1] # Assume unique names for simplicity

    println("\n==Finding connections FROM: ($object_name)==")

    # Find all outgoing edges (morphisms) from this object
    outgoing_edges = incident(category, object_idx, :src)

    if isempty(outgoing_edges)
        println("No outgoing connections found for this object.")
        return
    end

    println("Found $(length(outgoing_edges)) outgoing connections:")

    for edge_idx in outgoing_edges
        # This is essentially a lens of length 1, so we can reuse the display logic
        display_lens(category, [edge_idx], morphisms_df)
    end
end

"""
Finds and displays all direct incoming connections to a specific object, identified by its name.
"""
function find_connections_to_object(category, object_name::String, morphisms_df)
    # Find the index of the object with the given name
    object_indices = findall(c -> c == object_name, subpart(category, :obj_name))

    if isempty(object_indices)
        println("Object with name '$object_name' not found in the category.")
        return
    end
    object_idx = object_indices[1] # Assume unique names

    println("\n==Finding connections TO: ($object_name)==")

    # Find all incoming edges (morphisms) to this object
    incoming_edges = incident(category, object_idx, :tgt)

    if isempty(incoming_edges)
        println("No incoming connections found for this object.")
        return
    end

    println("Found $(length(incoming_edges)) incoming connections:")

    for edge_idx in incoming_edges
        display_incoming_connection(category, edge_idx, morphisms_df)
    end
end


# --- 4. Display Results ---

function display_lens(category, lens_path::Vector, morphisms_df)
    if isempty(lens_path)
        return
    end

    println("--------------------------------------------------")
    println("Found Lens:")
    
    first_edge = lens_path[1]
    start_node_idx = subpart(category, first_edge, :src)
    start_node_name = subpart(category, start_node_idx, :obj_name)
    start_node_type = subpart(category, start_node_idx, :obj_type)
    print("  ($start_node_type) $start_node_name")

    for edge_idx in lens_path
        morphism_id = subpart(category, edge_idx, :morph_id)
        citation = subpart(category, edge_idx, :citation)
        
        morphism_rows = morphisms_df[morphisms_df.MorphismID .== morphism_id, :]
        morphism_label = nrow(morphism_rows) > 0 ? morphism_rows[1, :Label] : "Unknown"

        target_node_idx = subpart(category, edge_idx, :tgt)
        target_node_name = subpart(category, target_node_idx, :obj_name)
        target_node_type = subpart(category, target_node_idx, :obj_type)

        print("\n    --[ $morphism_label (evidence: $citation) ]-->")
        print("\n  ($target_node_type) $target_node_name")
    end
    println("\n--------------------------------------------------")
end

function display_incoming_connection(category, edge_idx::Int, morphisms_df)
    println("--------------------------------------------------")
    
    # Get source node details
    source_node_idx = subpart(category, edge_idx, :src)
    source_node_name = subpart(category, source_node_idx, :obj_name)
    source_node_type = subpart(category, source_node_idx, :obj_type)

    # Get morphism details
    morphism_id = subpart(category, edge_idx, :morph_id)
    citation = subpart(category, edge_idx, :citation)
    morphism_rows = morphisms_df[morphisms_df.MorphismID .== morphism_id, :]
    morphism_label = nrow(morphism_rows) > 0 ? morphism_rows[1, :Label] : "Unknown"

    # Get target node details
    target_node_idx = subpart(category, edge_idx, :tgt)
    target_node_name = subpart(category, target_node_idx, :obj_name)
    target_node_type = subpart(category, target_node_idx, :obj_type)

    print("  ($source_node_type) $source_node_name")
    print("\n    --[ $morphism_label (evidence: $citation) ]-->")
    print("\n  ($target_node_type) $target_node_name")
    println("\n--------------------------------------------------")
end


# --- 5. Main Execution ---

function main()
    db = load_database()
    if isnothing(db)
        return
    end
    objects_df, morphisms_df, evidence_df = db

    println("\nBuilding C_Consciousness category from database...")
    C_Consciousness = build_category(objects_df, evidence_df)
    println("Category built successfully with $(nparts(C_Consciousness, :V)) objects and $(nparts(C_Consciousness, :E)) morphisms.")

    # println("\n==Example 1: Find lenses matching the classic Theory -> Phenomenon pattern==")
    # viewpoint1 = ["Theory", "Phenomenon"]
    # lenses1 = find_lenses(C_Consciousness, viewpoint1)
    # println("Found $(length(lenses1)) lenses matching the pattern.")
    # for lens in lenses1
    #     display_lens(C_Consciousness, lens, morphisms_df)
    # end
 # 
    # println("\n==Example 2: Find how theories critique each other==")
    # viewpoint2 = ["Theory", "Theory"]
    # lenses2 = find_lenses(C_Consciousness, viewpoint2)
    # println("Found $(length(lenses2)) lenses matching the pattern.")
    # for lens in lenses2
    #     display_lens(C_Consciousness, lens, morphisms_df)
    # end

    # --- Example 3: Find all direct connections FROM a specific object ---
    specific_object_name = "Categorical Framework"
    find_connections_from_object(C_Consciousness, specific_object_name, morphisms_df)

    # --- NEW: Example 4: Find all direct connections TO a specific object ---
    # specific_object_name_to = "Neural Correlates of Consciousness (NCC)"
    # find_connections_to_object(C_Consciousness, specific_object_name_to, morphisms_df)

end

# Run the main function
main()
