# ConCart - mapping out consciousness studies

**Mapping the structure of research with applied category theory.**

---

## The Core Idea

The field of consciousness studies is famously fragmented, with dozens of competing theories, methods, and conceptual frameworks. This project aims not to propose another theory of consciousness, but to help individual researchers manage the *meta-problem* of understanding the field's structure.

The goal is to use the tools of applied category theory to build a computable, queryable map of that can manage your local collection of papers in complementary ways to traditional article databases like Zotero and Mendeley. By representing theories, phenomena, and methods as **objects** and the relationships between them (like "explains," "measures," or "critiques") as **morphisms**, we can create a formal knowledge graph: $C_{\text{Consciousness}}$.

This allows us to:
* Make the structural assumptions of different research programs explicit.
* Formally compare and contrast theories.
* Use "lenses" (categorical functors) to find specific structural patterns in the literature.
* Identify areas where evidence is thin or where theories are structurally incompatible.

## The Framework

Our framework consists of two main components: a database and a query engine.

### 1. The Database

The structure of a field is captured in a relational database stored as a set of CSV files in the `/data` directory.

* **`papers.csv`**: A bibliographic database of relevant scientific papers.
* **`c_objects.csv`**: A master list of every unique object (node) in our category, such as `theory:iit` or `phenomenon:change_blindness`. Each object has a defined `Type`.
* **`c_morphisms.csv`**: The "rulebook" defining the types of relationships (arrows) that can exist, like `rel:posits` or `rel:measures`, and the object types they can connect.
* **`c_evidence.csv`**: The central table that builds the category. Each row is a single arrow, linking a source object to a target object via a specific morphism type, and provides a citation from `papers.csv` as evidence.

### 2. The Code

The `/code` directory contains the tools to interact with the database.
* **`tui.jl`**: The terminal front end
* **`concart.jl`**: The core query engine written in Julia, using the `Catlab.jl` library. It loads the database into a formal categorical structure and provides functions to perform structural queries, such as finding lenses or exploring the local neighborhood of a specific theory.
* **`find_paper_urls.py`**: A Python utility script that uses the Google Gemini API to find direct PDF links for the papers in the database, making it easier to consult the source material.

## Getting Started

### Prerequisites

* **Julia**: Version 1.6 or later.
* **Python**: Version 3.8 or later.
* **A Gemini API Key**: For running the Python script.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/trondarild/ConCart](https://github.com/trondarild/ConCart) 
    cd ConCart
    ```

2.  **Install Julia dependencies:**
    Open the Julia REPL, enter Pkg mode by pressing `]`, and run:
    ```julia
    pkg> add Catlab, DataFrames, CSV
    ```

3.  **Install Python dependencies: (optional)**
    ```bash
    pip install pandas requests tqdm
    ```

4.  **Set up Environment Variable (optional):**
    Set your Gemini API key as an environment variable.
    * On Linux/macOS: `export GEMINI_API_KEY="YOUR_KEY_HERE"`
    * On Windows: `set GEMINI_API_KEY="YOUR_KEY_HERE"`

### Usage

1.  **Populate the Database**: Add and classify papers in the `/data` CSV files.
2.  **Run the Julia Query Engine**:
    ```bash
    cd scripts
    julia tui.jl
    ```
    This will build the category and start the terminal interface. Use `help`to see available commands. 
3.  **(Optional) Find PDFs**:
    ```bash
    cd scripts
    python find_paper_urls.py
    ```

## How to Contribute

This is a living project, and contributions are highly welcome! You can contribute by:
* **Adding Papers**: Expanding the `papers.csv` database with more literature.
* **Classifying Data**: Adding new entries to `c_objects.csv` and, most importantly, `c_evidence.csv` by reading papers and mapping out the relationships they assert.
* **Improving the Code**: Enhancing the query functions, adding visualization capabilities, or improving the database schema.
* **Fixing Errors**: Correcting classifications or identifying bugs.

Please feel free to open an issue or submit a pull request.
