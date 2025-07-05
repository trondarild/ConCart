#=
This script provides a Terminal User Interface (TUI) for interacting with the
Consciousness Cartography database.

It uses the `concart.jl` library for its core logic and `Term.jl`
for creating a rich, interactive user experience in the terminal. It now
includes a self-contained command history feature and advanced search
options for pullbacks, pushouts, and synthesis opportunities.

To Run:
1. Ensure `concart.jl` is in the same directory and has been updated with
   the required functions.
2. Ensure the data files are in `../data/`.
3. From the Julia REPL, install dependencies:
   (press `]`) pkg> add Term
4. Run the script: `julia tui.jl`
=#

# Add necessary packages if not already installed
try
    using Term
catch e
    using Pkg
    Pkg.add("Term")
    using Term
end

# Include the core library and other necessary modules
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

function get_edge_info(category, edge_idx::Int, morphisms_df)
    m_id = subpart(category, edge_idx, :morph_id)
    cit = subpart(category, edge_idx, :citation)
    m_rows = filter(row -> row.MorphismID == m_id, morphisms_df)
    m_label = isempty(m_rows) ? "{red}unknown{/red}" : m_rows[1, :Label]
    return "{italic green}$(m_label){/italic green} {dim}({/dim}{underline cyan}cite: $cit{/underline cyan}{dim}){/dim}"
end

function display_pullback(category, diagram::Dict, morphisms_df)
    p_line = "{blue bold}(" * subpart(category, diagram["P_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["P_idx"], :obj_name) * "{/bright_white}"
    a_line = "{blue bold}(" * subpart(category, diagram["A_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["A_idx"], :obj_name) * "{/bright_white}"
    b_line = "{blue bold}(" * subpart(category, diagram["B_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["B_idx"], :obj_name) * "{/bright_white}"
    c_line = "{blue bold}(" * subpart(category, diagram["C_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["C_idx"], :obj_name) * "{/bright_white}"

    pa_info = get_edge_info(category, diagram["p_to_a_edge"], morphisms_df)
    pb_info = get_edge_info(category, diagram["p_to_b_edge"], morphisms_df)
    ac_info = get_edge_info(category, diagram["a_to_c_edge"], morphisms_df)
    bc_info = get_edge_info(category, diagram["b_to_c_edge"], morphisms_df)

    final_text = """
    Found a pullback square with {yellow}Common Source (P):{/yellow} $p_line

    {dim}Formed by the paths:{/dim}
    {bold}1:{/bold} $p_line → ($pa_info) → $a_line → ($ac_info) → $c_line
    {bold}2:{/bold} $p_line → ($pb_info) → $b_line → ($bc_info) → $c_line
    """

    println(Term.Panel(
        Term.RenderableText(final_text),
        title="Found Pullback Candidate",
        style="cyan",
        width=120
    ))
end

function display_pushout(category, diagram::Dict, morphisms_df)
    s_line = "{blue bold}(" * subpart(category, diagram["S_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["S_idx"], :obj_name) * "{/bright_white}"
    a_line = "{blue bold}(" * subpart(category, diagram["A_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["A_idx"], :obj_name) * "{/bright_white}"
    b_line = "{blue bold}(" * subpart(category, diagram["B_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["B_idx"], :obj_name) * "{/bright_white}"
    q_line = "{blue bold}(" * subpart(category, diagram["QA_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["QA_idx"], :obj_name) * "{/bright_white}"

    sa_info = get_edge_info(category, diagram["s_to_a_edge"], morphisms_df)
    sb_info = get_edge_info(category, diagram["s_to_b_edge"], morphisms_df)
    aq_info = get_edge_info(category, diagram["a_to_qa_edge"], morphisms_df)
    bq_info = get_edge_info(category, diagram["b_to_qb_edge"], morphisms_df)

    final_text = """
    Found a pushout square with {yellow}Common Target (Q):{/yellow} $q_line

    {dim}Formed by the paths:{/dim}
    {bold}1:{/bold} $s_line → ($sa_info) → $a_line → ($aq_info) → $q_line
    {bold}2:{/bold} $s_line → ($sb_info) → $b_line → ($bq_info) → $q_line
    """
    println(Term.Panel(
        Term.RenderableText(final_text),
        title="Found Pushout Candidate",
        style="yellow",
        width=120
    ))
end

function display_synthesis_opportunity(category, diagram::Dict, morphisms_df)
    s_line = "{blue bold}(" * subpart(category, diagram["S_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["S_idx"], :obj_name) * "{/bright_white}"
    a_line = "{blue bold}(" * subpart(category, diagram["A_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["A_idx"], :obj_name) * "{/bright_white}"
    b_line = "{blue bold}(" * subpart(category, diagram["B_idx"], :obj_type) * "){/blue bold} {bright_white}" * subpart(category, diagram["B_idx"], :obj_name) * "{/bright_white}"

    sa_info = get_edge_info(category, diagram["s_to_a_edge"], morphisms_df)
    sb_info = get_edge_info(category, diagram["s_to_b_edge"], morphisms_df)

    final_text = """
    {yellow}Opportunity for Synthesis:{/yellow}
    A common source diverges to two distinct targets. Consider creating a new concept that unifies them.

    {dim}Diverging paths:{/dim}
    {bold}1:{/bold} $s_line → ($sa_info) → [ $a_line ]
    {bold}2:{/bold} $s_line → ($sb_info) → [ $b_line ]
    """
    println(Term.Panel(
        Term.RenderableText(final_text),
        title="Synthesis Opportunity",
        style="magenta",
        width=120
    ))
end


function display_table(df::DataFrame, title::String)
    if isempty(df)
        println(Term.RenderableText("{yellow}No items to display for '$title'.{/yellow}"))
        return
    end

    display_df = copy(df)
    
    for col_name in names(display_df)
        if eltype(display_df[!, col_name]) <: Union{String, Missing}
            display_df[!, col_name] = [
                (s isa String && length(s) > 50) ? first(s, 47) * "..." : s
                for s in display_df[!, col_name]
            ]
        end
    end
    
    println(Term.RenderableText("\n" * title, style="bold cyan"))
    
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

    • {cyan}find_lens {yellow}<Step1> <Step2> ...{/yellow}
      {dim}Finds paths. A step can be an {bold}object{/bold} (Type or "Name") or a{/dim}
      {dim}{bold}morphism{/bold} (e.g., <critiques>). Object-only queries are still supported.{/dim}
      {dim}e.g., find_lens * <critiques> *{/dim}

    • {cyan}pullback {yellow}"<A>" "<B>" "<C>"{/yellow}
      {dim}Finds objects P that link to A and B, where A and B link to C.{/dim}
      {dim}Use '*' as a wildcard for any object. e.g., pullback "IIT" "*" "Theory"{/dim}

    • {cyan}pushout {yellow}"<S>" "<A>" "<B>"{/yellow}
      {dim}Finds objects Q that A and B both link to, from a common source S.{/dim}
      {dim}Use '*' as a wildcard for any object. e.g., pushout "IIT" "*" *{/dim}

    • {cyan}synthesize {yellow}"<S>" "<A>" "<B>"{/yellow}
      {dim}Finds cospans (A <- S -> B) which represent opportunities for synthesis.{/dim}
      {dim}Use '*' as a wildcard for any object.{/dim}

    • {cyan}from {yellow}"<Object Name>"{/yellow}
      {dim}Shows all outgoing connections from an object.{/dim}

    • {cyan}to {yellow}"<Object Name>"{/yellow}
      {dim}Shows all incoming connections to an object.{/dim}

    • {cyan}list {yellow}<type>{/yellow}
      {dim}Lists items. Types: papers, objects, morphisms, theories, phenomena, etc.{/dim}

    • {cyan}info {yellow}<type> "<Name>"{/yellow}
      {dim}Shows details for an item. e.g., info object "IIT", info morphism "critiques"{/dim}

    • {cyan}papers_for {yellow}"<Object Name>"{/yellow}
      {dim}Lists all papers associated with a given object.{/dim}

    • {cyan}history{/cyan}{dim} - Shows command history.{/dim}
    • {cyan}!!{/cyan}{dim}      - Executes the last command.{/dim}
    • {cyan}!n{/cyan}{dim}      - Executes the nth command from history.{/dim}
    • {cyan}help{/cyan}{dim}    - Shows this help message.{/dim}
    • {cyan}quit{/cyan}{dim}    - Exits the application.{/dim}
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
        subtitle="Type 'help' for commands or 'quit' to exit.",
        style="bold green",
        width=80
    ))

    history = String[]

    while true
        print(Term.RenderableText("\n{bold magenta}cartography> {/bold magenta}"))
        input = readline()

        # Handle history execution commands first
        if startswith(input, "!")
            original_input = input
            if input == "!!" && !isempty(history)
                input = last(history)
                println(Term.RenderableText("{dim}Executing: $input{/dim}"))
            elseif length(input) > 1
                try
                    idx = parse(Int, input[2:end])
                    if 1 <= idx <= length(history)
                        input = history[idx]
                        println(Term.RenderableText("{dim}Executing: $input{/dim}"))
                    else
                        print(Term.Panel("Invalid history index: $idx", style="bold red", title="Error"))
                        continue
                    end
                catch
                    print(Term.Panel("Invalid history command: $original_input", style="bold red", title="Error"))
                    continue
                end
            else
                print(Term.Panel("Invalid history command: $original_input", style="bold red", title="Error"))
                continue
            end
        end

        # Add non-empty, non-history commands to history
        if !isempty(input) && !startswith(input, "!")
            push!(history, input)
        end

        parts = [m.match for m in eachmatch(r"<([^>]+)>|\"(.*?)\"|(\S+)", input)]
        parts = [replace(p, "\""=>"") for p in parts]

        if isempty(parts) continue end
        command = lowercase(parts[1])

        type_map = Dict(
            "theories" => "Theory", "phenomena" => "Phenomenon",
            "methods" => "Method", "concepts" => "Concept"
        )

        if command == "quit"
            print(Term.RenderableText("{yellow}Exiting. Goodbye!{/yellow}\n"))
            break
        elseif command == "help"
            display_help()
        elseif command == "history"
            println(Term.RenderableText("\nCommand History", style="bold cyan"))
            for (i, cmd) in enumerate(history)
                println(Term.RenderableText(" {bold white}$i{/bold white}  $cmd"))
            end
        elseif command == "find_lens" && length(parts) > 1
            pattern = String.(parts[2:end])
            lenses = find_lenses(category, pattern, morphisms_df)
            println("\nFound $(length(lenses)) lenses matching the pattern [$(join(pattern, " -> "))].")
            for lens in lenses
                display_lens(category, lens, morphisms_df)
            end
        elseif command == "pullback" && length(parts) == 4
            name_A, name_B, name_C = parts[2], parts[3], parts[4]
            err, results = find_pullback_candidates(category, name_A, name_B, name_C)
            if !isnothing(err)
                print(Term.Panel(err, style="bold red", title="Error"))
            else
                println("\nFound $(length(results)) pullback candidate(s) for the span $name_A -> $name_C <- $name_B:")
                for diagram in results
                    display_pullback(category, diagram, morphisms_df)
                end
            end
        elseif command == "pushout" && length(parts) == 4
            name_S, name_A, name_B = parts[2], parts[3], parts[4]
            err, results = find_cospan_continuations(category, name_S, name_A, name_B)
            if !isnothing(err)
                print(Term.Panel(err, style="bold red", title="Error"))
            else
                pushouts = filter(d -> d["QA_idx"] == d["QB_idx"], results)
                if isempty(pushouts)
                    println("\nNo completed pushout squares found for the cospan $name_A <- $name_S -> $name_B.")
                else
                    println("\nFound $(length(pushouts)) completed pushout square(s) for the cospan $name_A <- $name_S -> $name_B:")
                    for diagram in pushouts
                        display_pushout(category, diagram, morphisms_df)
                    end
                end
            end
        elseif command == "synthesize" && length(parts) == 4
            name_S, name_A, name_B = parts[2], parts[3], parts[4]
            err, results = find_cospans(category, name_S, name_A, name_B)
            if !isnothing(err)
                print(Term.Panel(err, style="bold red", title="Error"))
            else
                println("\nFound $(length(results)) synthesis opportunities for the cospan $name_A <- $name_S -> $name_B:")
                for diagram in results
                    display_synthesis_opportunity(category, diagram, morphisms_df)
                end
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
            elseif haskey(type_map, list_type)
                type_filter = type_map[list_type]
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
            elseif info_type == "morphism"
                record = filter(row -> row.Label == name, morphisms_df)
                if !isempty(record) display_record(first(record), "Morphism Info: $name") else print(Term.Panel("Morphism not found.", style="red")) end
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
            # Avoid showing error for blank input or history commands
            if !isempty(input)
                print(Term.Panel("Unknown command or incorrect arguments. Type 'help' for options.", style="bold red", title="Error"))
            end
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
