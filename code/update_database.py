# -*- coding: utf-8 -*-
"""
This script analyzes research paper PDFs using the Gemini API to automatically
populate a relational database that represents the structure of a scientific field.

It reads a list of PDF file paths from standard input, and for each PDF, it:
1.  Performs a full analysis using the Gemini API.
2.  Generates a CitationKey from the returned bibliographic data.
3.  Checks if this CitationKey already exists in the database.
4.  If the paper is new, it appends the new, non-duplicate information to the
    database CSV files. If the paper already exists, it does nothing.

This script is designed to be idempotent. Running it twice with the same
input will not create duplicate entries in the database.

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
    """Creates a unique CitationKey (e.g., 'Author2023')."""
    if not authors or not year:
        return None
    first_author_last_name = authors.split(',')[0].strip().split(' ')[-1]
    first_author_last_name = re.sub(r'\W+', '', first_author_last_name)
    return f"{first_author_last_name}{year}"

def call_gemini_api(payload: Dict[str, Any], api_key: str) -> Optional[Dict[str, Any]]:
    """Generic function to call the Gemini API and handle responses."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=API_TIMEOUT)
        response.raise_for_status()
        
        result_text = response.json()['candidates'][0]['content']['parts'][0]['text']
        cleaned_text = re.sub(r'```json\n?|```', '', result_text).strip()
        
        return json.loads(cleaned_text)
        
    except requests.exceptions.RequestException as e:
        print(f"Error calling Gemini API: {e}", file=sys.stderr)
    except (json.JSONDecodeError, KeyError, IndexError) as e:
        print(f"Error parsing JSON response: {e}", file=sys.stderr)
        print(f"Received text: {result_text}", file=sys.stderr)
    except Exception as e:
        print(f"An unexpected error occurred during API call: {e}", file=sys.stderr)
    
    return None

# --- Core Gemini and Database Logic ---

def get_full_analysis(pdf_base64: str, existing_objects_df: pd.DataFrame, existing_morphisms_df: pd.DataFrame, api_key: str) -> Optional[Dict[str, Any]]:
    """Performs the full, detailed analysis of the PDF."""
    existing_objects_str = "\n".join([f"- {row['ObjectID']}: {row['Name']}" for _, row in existing_objects_df.iterrows()])
    existing_morphisms_str = "\n".join([f"- {row['MorphismID']}: Connects '{row['SourceType']}' to '{row['TargetType']}' (Label: {row['Label']})" for _, row in existing_morphisms_df.iterrows()])
    json_schema = """
    {
      "bibliographic": {"authors": "Full list of authors", "year": 2024, "title": "Full title", "publication": "Journal name"},
      "new_objects": [{"ObjectID": "type:id", "Name": "Object Name", "Type": "Theory|Phenomenon|Method|Concept", "Description": "A sentence."}],
      "new_evidence": [{"SourceID": "ObjectID", "MorphismID": "MorphismID", "TargetID": "ObjectID", "Notes": "Optional context."}]
    }
    """
    prompt = f"""
You are an expert academic research assistant. Your task is to analyze a research paper and extract structured information to populate a categorical database.

**INSTRUCTIONS:**

1.  **Analyze the attached PDF.**
2.  **Extract Bibliographic Data.**
3.  **Identify Key Objects.** Before creating a new object, check if one already exists in the `EXISTING OBJECTS` list. If so, **USE THE EXISTING ObjectID**. Otherwise, create a new one. `Type` must be one of: `Theory`, `Phenomenon`, `Method`, `Concept`.
4.  **Identify Key Evidence (Morphisms).** A claim is a directed arrow: `(Source Object) --[Relationship]--> (Target Object)`. For the `Relationship`, you **MUST** use a predefined `MorphismID` from the `EXISTING MORPHISMS` list.
5.  **Format Output as JSON.** Return **ONLY** a single, valid JSON object that strictly follows the schema provided.

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
    payload = {
        "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "application/pdf", "data": pdf_base64}}]}],
        "generationConfig": { "temperature": 0.2, "maxOutputTokens": 8192 }
    }
    return call_gemini_api(payload, api_key)


def update_database_files(data: Dict[str, Any], paths: Dict[str, str], citation_key: str):
    """Reads, updates, and writes back the database CSV files."""
    try:
        # 1. Update papers.csv
        papers_df = pd.read_csv(paths['papers'])
        bib_info = data.get('bibliographic', {})

        # FIX: Create a dictionary with keys that exactly match the columns
        # in the papers.csv file to prevent concatenation errors.
        new_row_data = {
            'CitationKey': citation_key,
            'Authors': bib_info.get('authors'),
            'Year': bib_info.get('year'),
            'Title': bib_info.get('title'),
            'Publication': bib_info.get('publication'),
            'URL': pd.NA
        }
        
        # Create a new DataFrame from the single row dictionary
        new_paper_df = pd.DataFrame([new_row_data])

        # Concatenate the new row. Pandas will align columns by name
        # and fill missing ones (like TheoryCategory) with NaN automatically.
        papers_df = pd.concat([papers_df, new_paper_df], ignore_index=True)
        
        # Write back to CSV
        papers_df.to_csv(paths['papers'], index=False)
        print(f"  + Added '{citation_key}' to papers.csv")

        # 2. Update c_objects.csv
        objects_df = pd.read_csv(paths['objects'])
        new_objects = data.get('new_objects', [])
        if new_objects:
            new_obj_df = pd.DataFrame(new_objects)
            new_obj_df = new_obj_df[~new_obj_df['ObjectID'].isin(objects_df['ObjectID'])]
            if not new_obj_df.empty:
                objects_df = pd.concat([objects_df, new_obj_df], ignore_index=True)
                objects_df.to_csv(paths['objects'], index=False)
                for obj_id in new_obj_df['ObjectID']: print(f"  + Added '{obj_id}' to c_objects.csv")
        
        # 3. Update c_evidence.csv
        evidence_df = pd.read_csv(paths['evidence'])
        new_evidence = data.get('new_evidence', [])
        if new_evidence:
            for ev in new_evidence: ev['CitationKey'] = citation_key
            new_ev_df = pd.DataFrame(new_evidence)
            
            # Create a unique key to prevent duplicates
            new_ev_df['unique_key'] = new_ev_df['CitationKey'] + new_ev_df['SourceID'] + new_ev_df['MorphismID'] + new_ev_df['TargetID']
            if not evidence_df.empty:
                # Ensure unique_key column exists before trying to access it
                if 'unique_key' not in evidence_df.columns:
                    evidence_df['unique_key'] = evidence_df['CitationKey'] + evidence_df['SourceID'] + evidence_df['MorphismID'] + evidence_df['TargetID']
                new_ev_df = new_ev_df[~new_ev_df['unique_key'].isin(evidence_df['unique_key'])]
            
            if not new_ev_df.empty:
                next_id = (evidence_df['EvidenceID'].max() + 1) if not evidence_df.empty else 1
                new_ev_df['EvidenceID'] = range(next_id, next_id + len(new_ev_df))
                
                final_evidence_df = pd.concat([evidence_df.drop(columns=['unique_key'], errors='ignore'), new_ev_df.drop(columns=['unique_key'])], ignore_index=True)
                final_evidence_df.to_csv(paths['evidence'], index=False)
                print(f"  + Added {len(new_ev_df)} new evidence entries to c_evidence.csv")

    except Exception as e:
        print(f"FATAL: Could not update database files. Error: {e}", file=sys.stderr)

# --- Main Execution ---

def main():
    parser = argparse.ArgumentParser(description='Analyze PDFs with Gemini and update a categorical database.')
    parser.add_argument('--papers', required=True, help='Path to papers.csv')
    parser.add_argument('--objects', required=True, help='Path to c_objects.csv')
    parser.add_argument('--morphisms', required=True, help='Path to c_morphisms.csv')
    parser.add_argument('--evidence', required=True, help='Path to c_evidence.csv')
    args = parser.parse_args()

    paths = {"papers": args.papers, "objects": args.objects, "morphisms": args.morphisms, "evidence": args.evidence}
    api_key = get_gemini_api_key()
    
    pdf_files = [line.strip() for line in sys.stdin if line.strip().lower().endswith('.pdf')]
    if not pdf_files:
        print("Error: No PDF files provided via stdin.", file=sys.stderr)
        sys.exit(1)

    try:
        # Load all databases once at the start
        papers_df = pd.read_csv(paths['papers'])
        objects_df = pd.read_csv(paths['objects'])
        morphisms_df = pd.read_csv(paths['morphisms'])
    except FileNotFoundError as e:
        print(f"Error: Could not find initial database file {e.filename}. Ensure paths are correct.", file=sys.stderr)
        sys.exit(1)
        
    existing_citation_keys = set(papers_df['CitationKey'])

    for pdf_path in pdf_files:
        if not os.path.exists(pdf_path):
            print(f"Warning: Skipping non-existent file '{pdf_path}'", file=sys.stderr)
            continue
        
        print(f"\n--- Processing: {os.path.basename(pdf_path)} ---")
        
        pdf_base64 = pdf_to_base64(pdf_path)
        if not pdf_base64: continue

        # Perform the full analysis for every file. This is the only API call.
        extracted_data = get_full_analysis(pdf_base64, objects_df, morphisms_df, api_key)
        
        if not extracted_data:
            print(f"  - Analysis failed for '{pdf_path}'. Skipping.")
            time.sleep(2) # API buffer
            continue

        # Now, check if the paper already exists based on the analysis results.
        bib_info = extracted_data.get('bibliographic', {})
        citation_key = create_citation_key(bib_info.get('authors'), bib_info.get('year'))

        if not citation_key:
            print(f"  - Could not generate a valid citation key from analysis results. Skipping.")
            continue

        if citation_key in existing_citation_keys:
            print(f"  - Skipping '{citation_key}'. Already exists in database.")
        else:
            # If it's a new paper, update all relevant files.
            print(f"  - New paper detected ('{citation_key}'). Updating database...")
            update_database_files(extracted_data, paths, citation_key)
            # Add the new key to our set to prevent re-processing in this same run
            existing_citation_keys.add(citation_key)
        
        time.sleep(2) # API buffer

if __name__ == "__main__":
    main()
