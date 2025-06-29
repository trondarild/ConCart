# -*- coding: utf-8 -*-
"""
This script analyzes research paper PDFs using the Gemini API to automatically
populate a relational database that represents the structure of a scientific field.

It reads a list of PDF file paths from standard input, and for each PDF, it:
1.  Constructs a detailed prompt for the Gemini API, including the PDF and a
    list of existing concepts (objects) and relationships (morphisms) from the database.
2.  Instructs Gemini to return a structured JSON object containing:
    a. Bibliographic information for the paper.
    b. Any new concepts or theories identified.
    c. A list of evidential links (morphisms) asserted in the paper.
3.  Reads the existing database CSV files into pandas DataFrames.
4.  Appends the new, non-duplicate information to the DataFrames.
5.  Saves the updated DataFrames back to the CSV files.

This script is designed to be resumable and idempotent.

Prerequisites:
- pandas, requests, tqdm
- A GEMINI_API_KEY environment variable.

Usage:
ls path/to/papers/*.pdf | python this_script.py \
    --papers ../data/papers.csv \
    --objects ../data/c_objects.csv \
    --morphisms ../data/c_morphisms.csv \
    --evidence ../data/c_evidence.csv
"""
import os
import sys
import argparse
import base64
import requests
import json
import pandas as pd
import time
import re
from typing import List, Optional, Dict, Any

# --- Configuration ---
API_TIMEOUT = 5 * 60  # 5 minutes

# --- Helper Functions ---

def get_gemini_api_key() -> str:
    """Get the Gemini API key from environment variable."""
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        print("Error: GEMINI_API_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)
    return api_key

def pdf_to_base64(pdf_path: str) -> Optional[str]:
    """Convert a PDF file to a base64 encoded string."""
    try:
        with open(pdf_path, 'rb') as pdf_file:
            return base64.b64encode(pdf_file.read()).decode('utf-8')
    except FileNotFoundError:
        print(f"Error: PDF file not found at '{pdf_path}'", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error reading or encoding PDF '{pdf_path}': {e}", file=sys.stderr)
        return None

def create_citation_key(authors: str, year: int) -> str:
    """Creates a unique CitationKey (e.g., 'Author1EtAl2023')."""
    if not authors:
        return f"Unknown{year}"
    first_author = authors.split(',')[0].strip().split(' ')[-1]
    # Remove non-alphanumeric characters
    first_author = re.sub(r'\W+', '', first_author)
    return f"{first_author}{year}"

# --- Core Gemini and Database Logic ---

def build_prompt(existing_objects_df: pd.DataFrame, existing_morphisms_df: pd.DataFrame) -> str:
    """Builds the master prompt for the Gemini API call."""
    
    # Create concise lists of existing objects and morphisms for the prompt context
    existing_objects_str = "\n".join([f"- {row['ObjectID']}: {row['Name']}" for _, row in existing_objects_df.iterrows()])
    existing_morphisms_str = "\n".join([f"- {row['MorphismID']}: Connects '{row['SourceType']}' to '{row['TargetType']}' (Label: {row['Label']})" for _, row in existing_morphisms_df.iterrows()])

    # The JSON schema we want the model to follow
    json_schema = """
    {
      "bibliographic": {
        "authors": "Full list of authors, comma-separated",
        "year": 2024,
        "title": "The full title of the paper",
        "publication": "The journal or conference name"
      },
      "new_objects": [
        {
          "ObjectID": "type:unique_id",
          "Name": "Human-readable name",
          "Type": "Theory|Phenomenon|Method|Concept",
          "Description": "A one-sentence description."
        }
      ],
      "new_evidence": [
        {
          "SourceID": "ObjectID of the source object",
          "MorphismID": "MorphismID of the relationship",
          "TargetID": "ObjectID of the target object",
          "Notes": "Optional brief quote or context from the paper."
        }
      ]
    }
    """

    prompt = f"""
You are an expert academic research assistant specializing in the philosophy of science and formal modeling. Your task is to analyze a research paper and extract structured information to populate a categorical database.

**INSTRUCTIONS:**

1.  **Analyze the attached PDF.** Read the paper to understand its main arguments, methods, and conclusions.

2.  **Extract Bibliographic Data.** Identify the authors, year, title, and publication venue.

3.  **Identify Key Objects.** Identify the core theories, phenomena, methods, and concepts discussed.
    * **IMPORTANT**: Before creating a new object, check if a similar one already exists in the `EXISTING OBJECTS` list below. If it exists, **USE THE EXISTING ObjectID**.
    * If a genuinely new concept is introduced, create a new object for it. The `ObjectID` should follow the format `type:unique_id` (e.g., `theory:quantum_foam_consciousness`). The `Type` must be one of: `Theory`, `Phenomenon`, `Method`, `Concept`.

4.  **Identify Key Evidence (Morphisms).** Identify the main claims of the paper as relationships between objects.
    * A claim is a directed arrow: `(Source Object) --[Relationship]--> (Target Object)`.
    * For the `Relationship`, you **MUST** use one of the predefined `MorphismID`s from the `EXISTING MORPHISMS` list below.
    * For the `Source` and `Target`, use the appropriate `ObjectID`s (either existing or new ones you've defined in this step).

5.  **Format Output as JSON.** Return **ONLY** a single, valid JSON object that strictly follows the schema provided. Do not include any other text or explanations.

---
**EXISTING OBJECTS (Use these IDs where possible):**
{existing_objects_str}
---
**EXISTING MORPHISMS (Use these IDs for relationships):**
{existing_morphisms_str}
---
**JSON OUTPUT SCHEMA (Your response MUST follow this format):**
```json
{json_schema}
```
---

Now, analyze the attached PDF and generate the complete JSON object.
"""
    return prompt

def analyze_pdf_with_gemini(pdf_path: str, prompt: str, api_key: str) -> Optional[Dict[str, Any]]:
    """Analyzes a PDF with Gemini and returns the structured JSON data."""
    print(f"\nAnalyzing '{os.path.basename(pdf_path)}' with Gemini...")
    
    pdf_base64 = pdf_to_base64(pdf_path)
    if not pdf_base64:
        return None

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    
    payload = {
        "contents": [{
            "parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": "application/pdf", "data": pdf_base64}}
            ]
        }],
        "generationConfig": { "temperature": 0.2, "maxOutputTokens": 8192 }
    }
    headers = {"Content-Type": "application/json"}
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=API_TIMEOUT)
        response.raise_for_status()
        
        result_text = response.json()['candidates'][0]['content']['parts'][0]['text']
        # Clean up potential markdown code fences
        cleaned_text = re.sub(r'```json\n?|```', '', result_text).strip()
        
        return json.loads(cleaned_text)
        
    except requests.exceptions.RequestException as e:
        print(f"Error calling Gemini API for '{pdf_path}': {e}", file=sys.stderr)
    except (json.JSONDecodeError, KeyError) as e:
        print(f"Error parsing JSON response for '{pdf_path}': {e}", file=sys.stderr)
        print(f"Received text: {result_text}", file=sys.stderr)
    except Exception as e:
        print(f"An unexpected error occurred for '{pdf_path}': {e}", file=sys.stderr)
    
    return None

def update_database_files(data: Dict[str, Any], paths: Dict[str, str]):
    """Reads, updates, and writes back the database CSV files."""
    try:
        # Load existing data
        papers_df = pd.read_csv(paths['papers'])
        objects_df = pd.read_csv(paths['objects'])
        evidence_df = pd.read_csv(paths['evidence'])

        # 1. Update papers.csv
        bib_info = data.get('bibliographic', {})
        if bib_info.get('title'):
            citation_key = create_citation_key(bib_info.get('authors'), bib_info.get('year'))
            if citation_key not in papers_df['CitationKey'].values:
                new_paper = pd.DataFrame([{
                    'CitationKey': citation_key,
                    'Authors': bib_info.get('authors'),
                    'Year': bib_info.get('year'),
                    'Title': bib_info.get('title'),
                    'Publication': bib_info.get('publication'),
                    'URL': pd.NA # URL can be found later
                }])
                papers_df = pd.concat([papers_df, new_paper], ignore_index=True)
                papers_df.to_csv(paths['papers'], index=False)
                print(f"  + Added '{citation_key}' to papers.csv")
            else:
                print(f"  - Paper '{citation_key}' already exists in papers.csv")

        # 2. Update c_objects.csv
        new_objects = data.get('new_objects', [])
        if new_objects:
            new_obj_df = pd.DataFrame(new_objects)
            # Filter out objects that already exist
            new_obj_df = new_obj_df[~new_obj_df['ObjectID'].isin(objects_df['ObjectID'])]
            if not new_obj_df.empty:
                objects_df = pd.concat([objects_df, new_obj_df], ignore_index=True)
                objects_df.to_csv(paths['objects'], index=False)
                for obj_id in new_obj_df['ObjectID']:
                    print(f"  + Added '{obj_id}' to c_objects.csv")
        
        # 3. Update c_evidence.csv
        new_evidence = data.get('new_evidence', [])
        if new_evidence:
            # Generate the citation key again for linking
            citation_key = create_citation_key(bib_info.get('authors'), bib_info.get('year'))
            
            # Add citation key to each piece of evidence
            for ev in new_evidence:
                ev['CitationKey'] = citation_key

            new_ev_df = pd.DataFrame(new_evidence)
            
            # Check for duplicates based on a combination of fields
            new_ev_df['unique_key'] = new_ev_df['CitationKey'] + new_ev_df['SourceID'] + new_ev_df['MorphismID'] + new_ev_df['TargetID']
            evidence_df['unique_key'] = evidence_df['CitationKey'] + evidence_df['SourceID'] + evidence_df['MorphismID'] + evidence_df['TargetID']
            
            new_ev_df = new_ev_df[~new_ev_df['unique_key'].isin(evidence_df['unique_key'])]
            
            if not new_ev_df.empty:
                # Get the next EvidenceID
                next_id = evidence_df['EvidenceID'].max() + 1
                new_ev_df['EvidenceID'] = range(next_id, next_id + len(new_ev_df))
                new_ev_df = new_ev_df.drop(columns=['unique_key'])
                
                evidence_df = pd.concat([evidence_df.drop(columns=['unique_key']), new_ev_df], ignore_index=True)
                evidence_df.to_csv(paths['evidence'], index=False)
                print(f"  + Added {len(new_ev_df)} new evidence entries to c_evidence.csv")

    except Exception as e:
        print(f"FATAL: Could not update database files. Error: {e}", file=sys.stderr)


# --- Main Execution ---

def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Analyze research paper PDFs with Gemini and update a categorical database.',
        epilog='Example: ls *.pdf | python %(prog)s --papers ../data/papers.csv ...'
    )
    parser.add_argument('--papers', required=True, help='Path to the papers.csv file.')
    parser.add_argument('--objects', required=True, help='Path to the c_objects.csv file.')
    parser.add_argument('--morphisms', required=True, help='Path to the c_morphisms.csv file.')
    parser.add_argument('--evidence', required=True, help='Path to the c_evidence.csv file.')
    args = parser.parse_args()

    paths = {
        "papers": args.papers,
        "objects": args.objects,
        "morphisms": args.morphisms,
        "evidence": args.evidence
    }

    api_key = get_gemini_api_key()
    
    # Read piped PDF file paths
    pdf_files = [line.strip() for line in sys.stdin if line.strip().lower().endswith('.pdf')]
    if not pdf_files:
        print("Error: No PDF files provided via stdin.", file=sys.stderr)
        sys.exit(1)

    # Load existing database once to build the initial prompt
    try:
        objects_df = pd.read_csv(paths['objects'])
        morphisms_df = pd.read_csv(paths['morphisms'])
    except FileNotFoundError:
        print(f"Error: Could not find initial database files. Ensure paths are correct.", file=sys.stderr)
        sys.exit(1)
        
    master_prompt = build_prompt(objects_df, morphisms_df)

    for pdf_path in pdf_files:
        if not os.path.exists(pdf_path):
            print(f"Warning: Skipping non-existent file '{pdf_path}'", file=sys.stderr)
            continue

        extracted_data = analyze_pdf_with_gemini(pdf_path, master_prompt, api_key)
        
        if extracted_data:
            update_database_files(extracted_data, paths)
        
        # Be respectful to the API
        time.sleep(2)

if __name__ == "__main__":
    main()
