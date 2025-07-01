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
using DataFrames
using CSV
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
    
    println(Term.Panel(
        Term.RenderableText(content),
        title="Found Lens",
        style="cyan",
        width=80
    ))
end

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

    println(Term.Panel(
        Term.RenderableText(content),
        title="Found Incoming Connection",
        style="cyan",
        width=80
    ))
end

function display_table(df::DataFrame, title::String)
    if isempty(df)
        println(Term.RenderableText("{yellow}No items to display for '$title'.{/yellow}"))
        return
    end

    # Create a copy to avoid modifying the original DataFrame
    display_df = copy(df)
    
    # Truncate long strings for better display
    for col_name in names(display_df)
        if eltype(display_df[!, col_name]) <: Union{String, Missing}
            display_df[!, col_name] = [
                (s isa String && length(s) > 50) ? s[1:47] * "..." : s 
                for s in display_df[!, col_name]
            ]
        end
    end
    
    # Print the title separately
    println(Term.RenderableText("\n" * title, style="bold cyan"))
    
    # FIX: Manually convert the DataFrame to a Matrix and pass the header separately.
    # This is the most robust way to ensure compatibility with Term.Table.
    header = names(display_df)
    data_matrix = Matrix(display_df)

    println(Term.Table(
        data_matrix;
        header=header,
        box=:ROUNDED,
        style="cyan"
    ))
end

function display_record(record::DataFrameRow, title::String)
    content = ""
    for name in names(record)
        content *= "{bold yellow}$(name):{/bold yellow} $(record[name])\n"
    end
    println(Term.Panel(content, title=title, style="yellow", width=80))
end

function display_help()
    help_text = """
    {bold}Available Commands:{/bold}

    • {cyan}find_lens {yellow}<Type1> <Type2> ...{/yellow}
      {dim}Finds paths matching a sequence of object types.{/dim}

    • {cyan}from {yellow}"<Object Name>"{/yellow}
      {dim}Shows all outgoing connections from an object.{/dim}

    • {cyan}to {yellow}"<Object Name>"{/yellow}
      {dim}Shows all incoming connections to an object.{/dim}

    • {cyan}list {yellow}<type>{/yellow}
      {dim}Lists all items of a given type. Types can be:{/dim}
      {dim}papers, objects, theories, phenomena, methods, concepts, morphisms{/dim}

    • {cyan}info {yellow}<type> "<Name>"{/yellow}
      {dim}Shows details for a specific item.{/dim}
      {dim}e.g., info object "IIT" or info paper "Crick1998"{/dim}

    • {cyan}papers_for {yellow}"<Object Name>"{/yellow}
      {dim}Lists all papers associated with a given object.{/dim}

    • {cyan}help{/cyan}{dim}   - Shows this help message.{/dim}
    • {cyan}quit{/cyan}{dim}   - Exits the application.{/dim}
    """
    print(Term.Panel(
        Term.RenderableText(help_text),
        title="Help",
        style="green",
        width=80
    ))
end


# --- Main REPL Loop ---

function main_repl_loop(category, papers_df, objects_df, morphisms_df)
    print(Term.Panel(
        "{bold green}Welcome to the Consciousness Cartography TUI{/bold green}",
        subtitle="Type 'help' for commands",
        style="bold green",
        width=80
    ))

    while true
        print(Term.RenderableText("\n{bold magenta}cartography> {/bold magenta}"))
        input = readline()

        parts = [m.match for m in eachmatch(r"\"(.*?)\"|(\S+)", input)]
        parts = [replace(p, "\""=>"") for p in parts]

        if isempty(parts) continue end

        command = lowercase(parts[1])

        if command == "quit"
            print(Term.RenderableText("{yellow}Exiting. Goodbye!{/yellow}"))
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
            if !isnothing(err) print(Term.Panel(err, style="bold red", title="Error")) else
                println("\nFound $(length(connections)) outgoing connections from \"$object_name\":")
                for conn in connections
                    display_lens(category, [conn], morphisms_df)
                end
            end
        elseif command == "to" && length(parts) > 1
            object_name = join(parts[2:end], " ")
            err, connections = find_connections_to_object(category, object_name)
            if !isnothing(err) print(Term.Panel(err, style="bold red", title="Error")) else
                println("\nFound $(length(connections)) incoming connections to \"$object_name\":")
                for conn in connections
                    display_incoming_connection(category, conn, morphisms_df)
                end
            end
        elseif command == "list" && length(parts) > 1
            list_type = lowercase(parts[2])
            if list_type == "papers" display_table(papers_df, "All Papers")
            elseif list_type == "objects" display_table(objects_df, "All Objects")
            elseif list_type == "morphisms" display_table(morphisms_df, "All Morphism Types")
            elseif list_type in ["theories", "phenomena", "methods", "concepts"]
                type_filter = titlecase(list_type[1:end-1]) # "theories" -> "Theory"
                filtered_df = filter(row -> row.Type == type_filter, objects_df)
                display_table(filtered_df, "All $(titlecase(list_type))")
            else println(Term.Panel("Unknown list type: $list_type", style="red"))
            end
        elseif command == "info" && length(parts) > 2
            info_type = lowercase(parts[2])
            name = join(parts[3:end], " ")
            if info_type == "object"
                record = filter(row -> row.Name == name, objects_df)
                if !isempty(record) display_record(first(record), "Object Info: $name") else print(Term.Panel("Object not found.", style="red")) end
            elseif info_type == "paper"
                record = filter(row -> row.CitationKey == name, papers_df)
                if !isempty(record) display_record(first(record), "Paper Info: $name") else print(Term.Panel("Paper not found.", style="red")) end
            else println(Term.Panel("Unknown info type: $info_type", style="red"))
            end
        elseif command == "papers_for" && length(parts) > 1
            object_name = join(parts[2:end], " ")
            err, citation_keys = find_papers_for_object(category, object_name)
            if !isnothing(err) print(Term.Panel(err, style="bold red", title="Error")) else
                println("\nFound $(length(citation_keys)) papers associated with \"$object_name\":")
                associated_papers = filter(row -> row.CitationKey in citation_keys, papers_df)
                display_table(associated_papers, "Associated Papers for $object_name")
            end
        else
            print(Term.Panel("Unknown command or incorrect arguments. Type 'help' for options.", style="bold red", title="Error"))
        end
    end
end


# --- Main Execution ---

function main()
    DATA_DIR = joinpath(@__DIR__, "..", "data")
    db_init = initialize_database(DATA_DIR)
    
    if isnothing(db_init)
        print(Term.Panel("Failed to initialize database. Exiting.", style="bold red", title="Fatal Error"))
        return
    end

    category, papers_df, objects_df, morphisms_df = db_init
    main_repl_loop(category, papers_df, objects_df, morphisms_df)
end

# Run the TUI
main()
