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
        CitationKey = ["Paper2020", "Paper2021"],
        Authors = ["Author A", "Author B"],
        Year = [2020, 2021],
        Title = ["Title A", "Title B"],
        Publication = ["Journal A", "Journal B"],
        URL = ["url_a", "url_b"]
    )

    # Mock c_objects.csv
    objects_df = DataFrame(
        ObjectID = ["theory:a", "method:b", "phenomenon:c", "theory:d", "concept:e"],
        Name = ["Theory A", "Method B", "Phenomenon C", "Theory D", "Concept E"],
        Type = ["Theory", "Method", "Phenomenon", "Theory", "Concept"],
        Description = ["Desc A", "Desc B", "Desc C", "Desc D", "Desc E"]
    )

    # Mock c_morphisms.csv
    morphisms_df = DataFrame(
        MorphismID = ["rel:uses_method", "rel:investigates", "rel:critiques"],
        Label = ["uses_method", "investigates", "critiques"],
        SourceType = ["Theory", "Method", "Theory"],
        TargetType = ["Method", "Phenomenon", "Theory"]
    )

    # Mock c_evidence.csv
    evidence_df = DataFrame(
        EvidenceID = [101, 102, 103],
        CitationKey = ["Paper2020", "Paper2020", "Paper2021"],
        SourceID = ["theory:a", "method:b", "theory:a"],
        MorphismID = ["rel:uses_method", "rel:investigates", "rel:critiques"],
        TargetID = ["method:b", "phenomenon:c", "theory:d"],
        Notes = ["Note 1", "Note 2", "Note 3"]
    )

    return papers_df, objects_df, morphisms_df, evidence_df
end


# --- Test Suite ---

@testset "ConCart.jl Tests" begin
    
    # Initialize mock data and build the category once for all tests
    papers_df, objects_df, morphisms_df, evidence_df = create_mock_data()
    category = ConCart.build_category(objects_df, evidence_df)

    @testset "Category Building" begin
        @test nparts(category, :V) == 5
        @test nparts(category, :E) == 3
        
        # Check if an object was created correctly
        theory_a_idx = findfirst(c -> c == "Theory A", subpart(category, :obj_name))
        @test !isnothing(theory_a_idx)
        @test subpart(category, theory_a_idx, :obj_type) == "Theory"
    end

    @testset "find_lenses" begin
        # Test a pattern that should exist and have exactly one result
        pattern_success = ["Theory", "Method", "Phenomenon"]
        lenses_success = find_lenses(category, pattern_success)
        @test length(lenses_success) == 1
        # A lens path of length 2 has two edges
        @test length(lenses_success[1]) == 2 

        # Test a pattern that should not exist
        pattern_fail = ["Phenomenon", "Theory"]
        lenses_fail = find_lenses(category, pattern_fail)
        @test isempty(lenses_fail)
    end

    @testset "Mixed Pattern Lenses" begin
        # Test a pattern mixing a specific name and a type
        pattern_mixed_success = ["Theory A", "Method", "Phenomenon"]
        lenses_mixed_success = find_lenses(category, pattern_mixed_success)
        @test length(lenses_mixed_success) == 1
        @test length(lenses_mixed_success[1]) == 2

        # Test a pattern mixing a type and a specific name
        pattern_mixed_success_2 = ["Theory", "Method", "Phenomenon C"]
        lenses_mixed_success_2 = find_lenses(category, pattern_mixed_success_2)
        @test length(lenses_mixed_success_2) == 1

        # Test a mixed pattern that should fail
        pattern_mixed_fail = ["Theory D", "Method"]
        lenses_mixed_fail = find_lenses(category, pattern_mixed_fail)
        @test isempty(lenses_mixed_fail)
    end

    @testset "find_connections_from_object" begin
        # Theory A should have two outgoing connections
        err, connections = find_connections_from_object(category, "Theory A")
        @test isnothing(err)
        @test length(connections) == 2

        # Phenomenon C should have zero outgoing connections
        err, connections = find_connections_from_object(category, "Phenomenon C")
        @test isnothing(err)
        @test isempty(connections)

        # Test for a non-existent object
        err, connections = find_connections_from_object(category, "Non-existent Object")
        @test !isnothing(err)
        @test isnothing(connections)
    end

    @testset "find_connections_to_object" begin
        # Method B should have one incoming connection
        err, connections = find_connections_to_object(category, "Method B")
        @test isnothing(err)
        @test length(connections) == 1

        # Theory A should have zero incoming connections
        err, connections = find_connections_to_object(category, "Theory A")
        @test isnothing(err)
        @test isempty(connections)

        # Test for a non-existent object
        err, connections = find_connections_to_object(category, "Non-existent Object")
        @test !isnothing(err)
        @test isnothing(connections)
    end

    @testset "find_papers_for_object" begin
        # Test an object connected to multiple papers
        err, citation_keys = find_papers_for_object(category, "Theory A")
        @test isnothing(err)
        @test Set(citation_keys) == Set(["Paper2020", "Paper2021"])
        @test length(citation_keys) == 2

        # Test an object connected to one paper
        err, citation_keys = find_papers_for_object(category, "Phenomenon C")
        @test isnothing(err)
        @test citation_keys == ["Paper2020"]

        # Test an object with no connections
        err, citation_keys = find_papers_for_object(category, "Concept E")
        @test !isnothing(err) # Should return an error message
        @test isnothing(citation_keys)

        # Test for a non-existent object
        err, citation_keys = find_papers_for_object(category, "Non-existent Object")
        @test !isnothing(err)
        @test isnothing(citation_keys)
    end

end

println("\nConCart tests completed successfully!")

