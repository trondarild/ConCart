# ConCart Project Context

This document provides a high-level overview of the Consciousness Cartography (ConCart) project for the Gemini AI assistant.

## Project Goal

The Consciousness Cartography (ConCart) project aims to map the landscape of scientific research on consciousness. It uses applied category theory, specifically the Catlab.jl library, to represent scientific papers, concepts, theories, and the relationships between them as a formal category. This allows for powerful, structure-based queries and analysis of the research field.

## Key Technologies

*   **Core Logic & Modeling:** Julia, primarily using the `Catlab.jl` library for all categorical algebra and ACSet (Attributed C-Set) creation.
*   **User Interface:** A Terminal User Interface (TUI) built in Julia using `Term.jl`.
*   **Data Extraction & Processing:** Python, using `pandas` for data manipulation and `requests` to interact with the Google Gemini API for analyzing PDFs and enriching the database.
*   **Database:** A simple file-based database consisting of several CSV files stored in the `data/` directory.

## Directory & File Structure

*   `/` (Project Root - `/Users/trond/Documents/ConCart/`)
    *   `code/`: Contains all the primary source code and scripts.
    *   `data/`: Contains the CSV database files (`papers.csv`, `c_objects.csv`, `c_morphisms.csv`, `c_evidence.csv`).

*   `code/`
    *   `concart.jl`: The core Julia library. It handles loading the database from CSVs and building the Catlab `ACSet`.
    *   `tui.jl`: The Julia-based Terminal User Interface for interacting with the database.
    *   `concart_unittest.jl`, `tui_unittests.jl`: Unit tests for the Julia code.
    *   `update_database.py`: A Python script that uses the Gemini API to analyze PDF papers and extract structured data (objects, morphisms, evidence).
    *   `findurl.py`: A utility Python script to find PDF URLs for papers in the database.
    *   `do_update_database.sh`: A shell script for running the `update_database.py` script on a directory of papers.
    *   `GEMINI.md`: A file containing specific, code-level future improvement ideas.
    *   `PROJECT_CONTEXT.md`: This file, containing high-level project context.

## Core Data Workflow

1.  **Data Ingestion:** A user provides a set of PDF research papers.
2.  **AI-Powered Extraction:** The `update_database.py` script is run on these PDFs. It calls the Gemini API to perform analysis, extracting bibliographic info, key objects (theories, methods, etc.), and evidence (the relationships between objects).
3.  **Database Population:** The extracted information is used to populate the set of CSV files in the `data/` directory. This process is idempotent; it avoids creating duplicate entries.
4.  **Categorical Model Loading:** The `concart.jl` library is used by the TUI to read all the CSV files and construct an in-memory `LabeledConsciousnessGraph` ACSet.
5.  **User Interaction:** The `tui.jl` application allows the user to run queries (`find_lens`, `from`, `to`, etc.) against this in-memory categorical model.

## Development Notes

*   The project maintains a clear separation between the core logic (`concart.jl`) and the user interface (`tui.jl`).
*   There is an established pattern of using `_unittest.jl` files for testing. Any new features or bug fixes in the Julia code should be accompanied by corresponding unit tests.
*   The Python scripts are used for the data pipeline, while Julia is used for the analysis and interaction phase.
