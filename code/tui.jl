#=
This script provides a Terminal User Interface (TUI) for interacting with the
Consciousness Cartography database.

It uses the `concart.jl` library for its core logic and `Term.jl`
for creating a rich, interactive user experience in the terminal.

To Run:
1. Ensure `concart.jl` is in the same directory.
2. Ensure the data files are in `../data/`.
3. From the Julia REPL, install Term.jl:
   (press `]`) pkg> add Term
4. Run the script: `julia tui.jl`
=#

# Add Term.jl if not already installed
try
    using Term
catch e
    using Pkg
    Pkg.add("Term")
    using Term
end

# Include the core library
include("concart.jl")
using .ConCart

# --- Display Functions (The "View" Layer) ---

function display_lens(category, lens_path::Vector, morphisms_df)
    if isempty(lens_path) return end

    content = ""
    
    first_edge = lens_path[1]
    start_node_idx = subpart(category, first_edge, :src)
    start_node_name = subpart(category, start_node_idx, :obj_name)
    start_node_type = subpart(category, start_node_idx, :obj_type)
    
    content *= "{blue bold}($start_node_type){/blue bold} {bright_white}$start_node_name{/bright_white}"

    for edge_idx in lens_path
        morphism_id = subpart(category, edge_idx, :morph_id)
        citation = subpart(category, edge_idx, :citation)
        
        morphism_rows = morphisms_df[morphisms_df.MorphismID .== morphism_id, :]
        morphism_label = nrow(morphism_rows) > 0 ? morphism_rows[1, :Label] : "Unknown"

        target_node_idx = subpart(category, edge_idx, :tgt)
        target_node_name = subpart(category, target_node_idx, :obj_name)
        target_node_type = subpart(category, target_node_idx, :obj_type)

        content *= "\n{dim}    ↓--({/dim}{italic green}$morphism_label{/italic green} {dim} evidence: $citation){/dim}"
        content *= "\n{blue bold}($target_node_type){/blue bold} {bright_white}$target_node_name{/bright_white}"
    end
    
    println(Panel(
        RenderableText(content),
        title="Found Lens",
        style="cyan",
        width=80
    ))
end

function display_help()
    help_text = """
    {bold}Available Commands:{/bold}

    • {cyan}find_lens {yellow}<Type1> <Type2> ...{/yellow}
      {dim}Finds paths matching a sequence of object types.{/dim}
      {dim}e.g., find_lens Theory Phenomenon{/dim}

    • {cyan}from {yellow}"<Object Name>"{/yellow}
      {dim}Shows all outgoing connections from an object.{/dim}
      {dim}e.g., from "Structuralist Theories of Consciousness"{/dim}

    • {cyan}to {yellow}"<Object Name>"{/yellow}
      {dim}Shows all incoming connections to an object.{/dim}
      {dim}e.g., to "Neural Correlates"{/dim}

    • {cyan}help{/cyan}{dim}   - Shows this help message.{/dim}
    • {cyan}quit{/cyan}{dim}   - Exits the application.{/dim}
    """
    print(Panel(
        RenderableText(help_text),
        title="Help",
        style="green",
        width=80
    ))
end


# --- Main REPL Loop ---

function main_repl_loop(category, morphisms_df)
    print(Panel(
        "{bold green}Welcome to the Consciousness Cartography TUI{/bold green}",
        subtitle="Type 'help' for commands",
        style="bold green",
        width=80
    ))

    while true
        print(RenderableText("\n{bold magenta}cartography> {/bold magenta}"))
        input = readline()

        # Regex to handle quoted strings
        # parts = matchall(r"\"(.*?)\"|(\S+)", input)
        parts = [m.match for m in eachmatch(r"\"(.*?)\"|(\S+)", input)]

        if isempty(parts) continue end

        command = lowercase(parts[1])

        if command == "quit"
            print(RenderableText("{yellow}Exiting. Goodbye!{/yellow}"))
            break
        elseif command == "help"
            display_help()
        elseif command == "find_lens" && length(parts) > 2
            pattern = String.(parts[2:end])
            lenses = find_lenses(category, pattern)
            println("\nFound $(length(lenses)) lenses matching the pattern [$(join(pattern, " -> "))].")
            for lens in lenses
                display_lens(category, lens, morphisms_df)
            end
        elseif command == "from" && length(parts) > 1
            object_name = join(parts[2:end], " ")
            err, connections = find_connections_from_object(category, object_name)
            if !isnothing(err)
                print(Panel(err, style="bold red", title="Error", width=80))
            else
                println("\nFound $(length(connections)) outgoing connections from \"$object_name\":")
                for conn in connections
                    display_lens(category, [conn], morphisms_df)
                end
            end
        elseif command == "to" && length(parts) > 1
            object_name = join(parts[2:end], " ")
            err, connections = find_connections_to_object(category, object_name)
            if !isnothing(err)
                print(Panel(err, style="bold red", title="Error", width=80))
            else
                println("\nFound $(length(connections)) incoming connections to \"$object_name\":")
                for conn in connections
                    # The 'to' connections are single edges, so we display them one by one
                    # We need a dedicated display function for incoming arrows
                    display_incoming_connection(category, conn, morphisms_df)
                end
            end
        else
            print(Panel("Unknown command or incorrect arguments. Type 'help' for options.", style="bold red", title="Error", width=80))
        end
    end
end

# Dedicated display function for incoming connections to format correctly
function display_incoming_connection(category, edge_idx::Int, morphisms_df)
    content = ""
    
    source_node_idx = subpart(category, edge_idx, :src)
    source_node_name = subpart(category, source_node_idx, :obj_name)
    source_node_type = subpart(category, source_node_idx, :obj_type)
    
    morphism_id = subpart(category, edge_idx, :morph_id)
    citation = subpart(category, edge_idx, :citation)
    morphism_rows = morphisms_df[morphisms_df.MorphismID .== morphism_id, :]
    morphism_label = nrow(morphism_rows) > 0 ? morphism_rows[1, :Label] : "Unknown"

    target_node_idx = subpart(category, edge_idx, :tgt)
    target_node_name = subpart(category, target_node_idx, :obj_name)
    target_node_type = subpart(category, target_node_idx, :obj_type)

    content *= "{blue bold}($source_node_type){/blue bold} {bright_white}$source_node_name{/bright_white}"
    content *= "\n{dim}    ↓--({/dim}{italic green}$morphism_label{/italic green} {dim} evidence: $citation){/dim}"
    content *= "\n{blue bold}($target_node_type){/blue bold} {bright_white}$target_node_name{/bright_white}"

    println(Panel(
        RenderableText(content),
        title="Found Incoming Connection",
        style="cyan",
        width=80
    ))
end


# --- Main Execution ---

function main()
    DATA_DIR = joinpath(@__DIR__, "..", "data")
    db_init = initialize_database(DATA_DIR)
    
    if isnothing(db_init)
        print(Panel("Failed to initialize database. Exiting.", style="bold red", title="Fatal Error", width=80))
        return
    end

    category, morphisms_df = db_init
    main_repl_loop(category, morphisms_df)
end

# Run the TUI
main()
