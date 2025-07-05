#=
This script contains unit tests for the ConCart.jl library.
It uses the built-in `Test` module in Julia.

The purpose of this script is to validate the core functionality of the library
in a predictable, self-contained way, without relying on the actual CSV database.
This ensures that modifications to the library do not break existing logic.

To Run:
1. Ensure `concart.jl` is in the same directory.
2. From the terminal, run: `julia concart_unittest.jl`
   A successful run will print "Test Summary: | Pass: ..." and show no errors.
=#

using Test
using DataFrames

# Include the library we want to test
include("concart.jl")
using .ConCart

# Bring Catlab functions into the test script's scope to resolve errors
using Catlab.CategoricalAlgebra
using Catlab.ACSets


# --- Mock Data ---
# We create in-memory versions of our CSVs for predictable testing.

function create_mock_data()
    # Mock papers.csv
    papers_df = DataFrame(
        CitationKey = ["Paper2020", "Paper2021", "Paper2022"],
        Authors = ["Author A", "Author B", "Author C"],
        Year = [2020, 2021, 2022],
        Title = ["Title A", "Title B", "Title C"],
        Publication = ["Journal A", "Journal B", "Journal C"],
        URL = ["url_a", "url_b", "url_c"]
    )

    # Mock c_objects.csv
    objects_df = DataFrame(
        ObjectID = ["theory:a", "method:b", "phenomenon:c", "theory:d", "concept:e", "concept:f", "phenomenon:g"],
        Name = ["Theory A", "Method B", "Phenomenon C", "Theory D", "Concept E", "Concept F", "Phenomenon G"],
        Type = ["Theory", "Method", "Phenomenon", "Theory", "Concept", "Concept", "Phenomenon"],
        Description = ["Desc A", "Desc B", "Desc C", "Desc D", "Desc E", "Desc F", "Desc G"]
    )

    # Mock c_morphisms.csv
    morphisms_df = DataFrame(
        MorphismID = ["rel:uses", "rel:investigates", "rel:critiques", "rel:explains"],
        Label = ["uses", "investigates", "critiques", "explains"],
        SourceType = ["Theory", "Method", "Theory", "Theory"],
        TargetType = ["Method", "Phenomenon", "Theory", "Phenomenon"]
    )

    # Mock c_evidence.csv - Enriched for testing limits.
    evidence_df = DataFrame(
        EvidenceID = [101, 102, 103, 104, 105, 106],
        CitationKey = ["Paper2020", "Paper2020", "Paper2021", "Paper2022", "Paper2022", "Paper2022"],
        SourceID = ["theory:a", "method:b", "theory:a", "theory:d", "method:b", "theory:d"],
        MorphismID = ["rel:uses", "rel:investigates", "rel:critiques", "rel:explains", "rel:investigates", "rel:investigates"],
        TargetID = ["method:b", "phenomenon:c", "theory:d", "phenomenon:g", "concept:e", "phenomenon:c"],
        Notes = ["Note 1", "Note 2", "Note 3", "Note 4", "Note 5", "Note 6"]
    )

    return papers_df, objects_df, morphisms_df, evidence_df
end


# --- Test Suite ---

@testset "ConCart.jl Tests" begin
    
    # Initialize mock data and build the category once for all tests
    papers_df, objects_df, morphisms_df, evidence_df = create_mock_data()
    category = ConCart.build_category(objects_df, evidence_df)

    @testset "Category Building" begin
        @test nparts(category, :V) == 7
        @test nparts(category, :E) == 6
        
        theory_a_idx = findfirst(c -> c == "Theory A", subpart(category, :obj_name))
        @test !isnothing(theory_a_idx)
        @test subpart(category, theory_a_idx, :obj_type) == "Theory"
    end

    @testset "find_lenses" begin
        pattern_success = ["Theory", "Method", "Phenomenon"]
        lenses_success = find_lenses(category, pattern_success, morphisms_df)
        @test length(lenses_success) == 1
        @test length(lenses_success[1]) == 2
    end

    @testset "find_connections_from_object" begin
        err, connections = find_connections_from_object(category, "Theory A")
        @test isnothing(err)
        @test length(connections) == 2
    end

    @testset "find_connections_to_object" begin
        err, connections = find_connections_to_object(category, "Method B")
        @test isnothing(err)
        @test length(connections) == 1
    end

    @testset "find_papers_for_object" begin
        err, citation_keys = find_papers_for_object(category, "Theory A")
        @test isnothing(err)
        @test Set(citation_keys) == Set(["Paper2020", "Paper2021"])
    end

    @testset "Pushout and Synthesis Tests" begin
        # Test find_cospans (for `synthesize` command)
        err_cospan, cospans = find_cospans(category, "Theory A", "Method B", "Theory D")
        @test isnothing(err_cospan)
        @test length(cospans) == 1
        @test subpart(category, cospans[1]["S_idx"], :obj_name) == "Theory A"
        @test subpart(category, cospans[1]["A_idx"], :obj_name) == "Method B"
        @test subpart(category, cospans[1]["B_idx"], :obj_name) == "Theory D"

        # Test find_cospan_continuations for both completed pushouts and synthesis opportunities
        err_pushout, continuations = find_cospan_continuations(category, "Theory A", "Method B", "Theory D")
        @test isnothing(err_pushout)
        
        # Test for completed pushouts
        completed_squares = filter(d -> d["QA_idx"] == d["QB_idx"], continuations)
        @test length(completed_squares) == 1
        @test subpart(category, completed_squares[1]["QA_idx"], :obj_name) == "Phenomenon C"

        # Test for synthesis opportunities (diverging paths)
        diverging_paths = filter(d -> d["QA_idx"] != d["QB_idx"], continuations)
        @test length(diverging_paths) == 3

        # Create a set of the found diverging pairs to make the test robust to ordering
        found_pairs = Set(
            tuple(sort([
                subpart(category, d["QA_idx"], :obj_name),
                subpart(category, d["QB_idx"], :obj_name)
            ])...) for d in diverging_paths
        )

        expected_pairs = Set([
            ("Phenomenon C", "Phenomenon G"),
            ("Concept E", "Phenomenon G"),
            ("Concept E", "Phenomenon C")
        ])
        # Sort the expected pairs to match the format of found_pairs
        expected_pairs_sorted = Set(tuple(sort(collect(p))...) for p in expected_pairs)

        @test found_pairs == expected_pairs_sorted
    end

end

println("\nConCart tests completed successfully!")
