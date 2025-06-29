#=
This script provides a framework for performing applied category theory on a
database of scientific literature about consciousness studies.

It does the following:
1. Loads the database from three CSV files (objects, morphisms, evidence).
2. Constructs a formal Category, C_Consciousness, as a Labeled, Attributed C-Set using Catlab.jl.
3. Implements a `find_lenses` function to discover paths in the category that match a given structural pattern (e.g., Theory -> Method -> Phenomenon).
4. Displays the discovered lenses, including the papers that provide evidence for each step.

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
        println("Objects file: $OBJECTS_PATH")
        println("Morphisms file: $MORPHISMS_PATH")
        println("Evidence file: $EVIDENCE_PATH")
        
        objects_df = CSV.read(OBJECTS_PATH, DataFrame)
        morphisms_df = CSV.read(MORPHISMS_PATH, DataFrame)
        evidence_df = CSV.read(EVIDENCE_PATH, DataFrame)
        
        println("Successfully loaded:")
        println("  - Objects: $(nrow(objects_df)) rows")
        println("  - Morphisms: $(nrow(morphisms_df)) rows")
        println("  - Evidence: $(nrow(evidence_df)) rows")
        
        # Check column names
        println("Objects columns: $(names(objects_df))")
        println("Morphisms columns: $(names(morphisms_df))")
        println("Evidence columns: $(names(evidence_df))")
        
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

# Define a schema for our Attributed C-Set (ACSet).
# This is like a database schema but for a category.
# It has Objects (V for vertices) and Morphisms (E for edges).
# Each has associated data attributes (e.g., Name, Type, CitationKey).

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

# Define the ACSet type based on our schema - Updated syntax
# Define the ACSet type based on our schema - use the macro, not a function!
@acset_type LabeledConsciousnessGraph(SchConsciousness, index=[:src, :tgt])

function build_category(objects_df, evidence_df)
    # Create an empty instance of our category structure
    C_Consciousness = LabeledConsciousnessGraph{String, String, String, String, String, String}()

    # Create a mapping from the string ObjectID to the integer part number in the ACSet
    # This is crucial for connecting the edges correctly.
    object_map = Dict{String, Int}()

    # Populate the objects (vertices) of the category
    println("Adding objects to category...")
    for row in eachrow(objects_df)
        try
            part_index = add_part!(C_Consciousness, :V;
                obj_id=string(row.ObjectID),
                obj_name=string(row.Name),
                obj_type=string(row.Type)
            )
            object_map[string(row.ObjectID)] = part_index
        catch e
            println("Error adding object: $e")
            println("Row data: $row")
            rethrow(e)
        end
    end

    # Populate the morphisms (edges) of the category using the evidence
    println("Adding morphisms to category...")
    for (i, row) in enumerate(eachrow(evidence_df))
        try
            # Look up the integer indices for the source and target objects
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
                    notes=string(ismissing(row.Notes) ? "" : row.Notes) # Handle missing notes
                )
            else
                println("Warning: Skipping evidence row $i due to missing object: $src_id or $tgt_id")
            end
        catch e
            println("Error adding morphism at row $i: $e")
            println("Row data: $row")
            rethrow(e)
        end
    end

    return C_Consciousness
end

# --- 3. Find Lenses (Functors as Paths) ---

"""
Finds all paths in the category that match a given structural pattern.
A pattern is a sequence of object types, e.g., ["Theory", "Method", "Phenomenon"].
"""
function find_lenses(category, pattern::Vector{String})
    if length(pattern) < 2
        error("Lens pattern must have at least two steps (e.g., A -> B).")
    end

    found_lenses = []
    
    # This is a recursive helper function to find paths
    function find_paths(start_node_idx, pattern_idx, current_path)
        # Check if the current node's type matches the pattern
        if subpart(category, start_node_idx, :obj_type) != pattern[pattern_idx]
            return
        end

        # Base case: we have found a full path matching the pattern
        if pattern_idx == length(pattern)
            # A valid lens must have at least one edge.
            if !isempty(current_path)
                push!(found_lenses, copy(current_path))
            end
            return
        end

        # Recursive step: find all outgoing edges and continue the search
        outgoing_edges = incident(category, start_node_idx, :src)
        for edge_idx in outgoing_edges
            target_node_idx = subpart(category, edge_idx, :tgt)
            # Check if the target node matches the *next* step in the pattern
            if subpart(category, target_node_idx, :obj_type) == pattern[pattern_idx + 1]
                push!(current_path, edge_idx)
                find_paths(target_node_idx, pattern_idx + 1, current_path)
                pop!(current_path) # Backtrack for other paths
            end
        end
    end

    # Start the search from every object in the category
    for v_idx in 1:nparts(category, :V)
        find_paths(v_idx, 1, [])
    end

    return found_lenses
end

# --- 4. Display Results ---

# function display_lens(category, lens_path::Vector{Int}, morphisms_df)
function display_lens(category, lens_path::Vector, morphisms_df)

    # Add a guard for empty paths to prevent errors.
    if isempty(lens_path)
        return
    end

    println("--------------------------------------------------")
    println("Found Lens:")
    
    # Get the first node
    first_edge = lens_path[1]
    start_node_idx = subpart(category, first_edge, :src)
    start_node_name = subpart(category, start_node_idx, :obj_name)
    start_node_type = subpart(category, start_node_idx, :obj_type)
    print("  ($start_node_type) $start_node_name")

    for edge_idx in lens_path
        # Get morphism details
        morphism_id = subpart(category, edge_idx, :morph_id)
        citation = subpart(category, edge_idx, :citation)
        
        # Get morphism label from the morphisms dataframe with error handling
        morphism_rows = morphisms_df[morphisms_df.MorphismID .== morphism_id, :]
        if nrow(morphism_rows) > 0
            morphism_label = morphism_rows[1, :Label]
        else
            morphism_label = "Unknown"
            println("Warning: No morphism found with ID $morphism_id")
        end

        # Get target node details
        target_node_idx = subpart(category, edge_idx, :tgt)
        target_node_name = subpart(category, target_node_idx, :obj_name)
        target_node_type = subpart(category, target_node_idx, :obj_type)

        print("\n    --[ $morphism_label (evidence: $citation) ]-->")
        print("\n  ($target_node_type) $target_node_name")
    end
    println("\n--------------------------------------------------")
end

# --- 5. Main Execution ---

function main()
    db = load_database()
    if isnothing(db)
        return
    end
    objects_df, morphisms_df, evidence_df = db

    println("Building C_Consciousness category from database...")
    C_Consciousness = build_category(objects_df, evidence_df)
    println("Category built successfully with $(nparts(C_Consciousness, :V)) objects and $(nparts(C_Consciousness, :E)) morphisms.")

    println("==Example 1: Find lenses matching the classic Theory -> Phenomenon pattern==")
    println("\nSearching for lenses with pattern: [Theory -> Phenomenon]...")
    viewpoint1 = ["Theory", "Phenomenon"]
    lenses1 = find_lenses(C_Consciousness, viewpoint1)
    
    println("Found $(length(lenses1)) lenses matching the pattern.")
    for lens in lenses1
        display_lens(C_Consciousness, lens, morphisms_df)
    end

    println("\n==Example 2: Find how theories critique each other==")
    println("\nSearching for lenses with pattern: [Theory -> Theory]...")
    viewpoint2 = ["Theory", "Theory"]
    lenses2 = find_lenses(C_Consciousness, viewpoint2)

    println("Found $(length(lenses2)) lenses matching the pattern.")
    for lens in lenses2
        display_lens(C_Consciousness, lens, morphisms_df)
    end
end

# Run the main function
main()