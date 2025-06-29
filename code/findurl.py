# -*- coding: utf-8 -*-
"""
This script enriches a CSV database of academic papers by finding direct PDF URLs for each entry.

It uses direct HTTP requests to the Google Gemini API (gemini-2.0-flash model) to search for
each paper based on its title, authors, and year. It includes a retry mechanism with
exponential backoff to handle API rate limiting (429 errors).

The script is RESUMABLE. If interrupted, it will continue from where it left off when run again.

Instructions:
1. Make sure you have the required libraries installed:
   pip install pandas requests tqdm

2. Set your Gemini API key as an environment variable named 'GEMINI_API_KEY'.
   - On Linux/macOS: export GEMINI_API_KEY="YOUR_KEY_HERE"
   - On Windows: set GEMINI_API_KEY="YOUR_KEY_HERE"

3. Place your input CSV file at '../data/paper_database.csv' relative to this script's location.

4. Run the script. It will process the papers and save progress to 'papers_with_urls.csv'
   after each successful find.
"""
import pandas as pd
import requests
import json
import time
import os
import random
from tqdm import tqdm

# --- Configuration ---
# Get the API key from an environment variable for better security
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

# Input and output file paths
INPUT_FILE_PATH = "../data/paper_database.csv"
OUTPUT_FILE_PATH = "papers_with_urls.csv"

# Gemini API endpoint
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={GEMINI_API_KEY}"


def main():
    """Main function to orchestrate the script's execution."""
    # --- Pre-run Checks ---
    if not GEMINI_API_KEY:
        print("="*50)
        print("!!! ERROR: GEMINI_API_KEY environment variable not set. !!!")
        print("Please set the environment variable and try again.")
        print("="*50)
        return

    # --- Load Data with Resumption Logic ---
    try:
        if os.path.exists(OUTPUT_FILE_PATH):
            print(f"Found existing output file '{OUTPUT_FILE_PATH}'. Resuming process.")
            df = pd.read_csv(OUTPUT_FILE_PATH)
        else:
            print(f"No output file found. Starting a new process from '{INPUT_FILE_PATH}'.")
            df = pd.read_csv(INPUT_FILE_PATH)
            df['URL'] = pd.NA # Add the URL column for the new file
    except FileNotFoundError:
        print("="*50)
        print(f"!!! ERROR: Input file not found at '{INPUT_FILE_PATH}' !!!")
        print("Please ensure the CSV file exists at the correct location relative to the script.")
        print("="*50)
        return
    except Exception as e:
        print(f"An error occurred while reading the CSV file: {e}")
        return

    # --- Process Papers ---
    process_papers(df)
    
    print("\n" + "="*50)
    print(f"Processing complete!")
    print(f"The final, updated database is saved in '{OUTPUT_FILE_PATH}'")
    print("="*50)
    
    # Display the first few rows of the final dataframe
    final_df = pd.read_csv(OUTPUT_FILE_PATH)
    print("\nPreview of the final data:")
    print(final_df.head())


def process_papers(df):
    """
    Iterates through the DataFrame, finds missing PDF URLs, and saves after each addition.
    """
    print("Starting to process papers to find missing PDF URLs...")
    
    # Using tqdm for a nice progress bar
    for index, row in tqdm(df.iterrows(), total=df.shape[0], desc="Finding PDFs"):
        # Check if URL is missing (NaN, None, etc.)
        if pd.isna(row.get('URL')):
            url = get_pdf_url_with_retry(row['Title'], row['Authors'], row['Year'])
            
            # Update the DataFrame and save progress immediately
            if url != "NA":
                df.loc[index, 'URL'] = url
                # Save the entire dataframe after each successful find
                df.to_csv(OUTPUT_FILE_PATH, index=False)
            
            # A small delay to be respectful to the API and avoid rate limiting
            time.sleep(1.5)


def get_pdf_url_with_retry(paper_title, authors, year):
    """
    Queries the Gemini model with a retry mechanism to handle rate limiting.

    Args:
        paper_title (str): The title of the paper.
        authors (str): The authors of the paper.
        year (int): The publication year.

    Returns:
        str: The found URL or 'NA' if not found or an error occurs.
    """
    # Construct a very specific prompt for the model
    prompt = (
        f"Find a direct, publicly accessible PDF URL for the academic paper titled "
        f"'{paper_title}' by {authors} ({year}). "
        f"Prioritize links from university repositories, arXiv, or official publisher sites. "
        f"Respond with only the full URL. If no direct PDF link can be found, respond with exactly 'NA'."
    )
    
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}]
    }
    
    max_retries = 5
    for attempt in range(max_retries):
        try:
            # Make the POST request to the Gemini API
            response = requests.post(API_URL, headers=headers, json=payload, timeout=60)
            
            # Check for rate limit error (429)
            if response.status_code == 429:
                wait_time = (2 ** attempt) + random.uniform(0, 1)
                tqdm.write(f"Rate limit hit for '{paper_title}'. Waiting {wait_time:.2f}s before retry {attempt + 1}/{max_retries}...")
                time.sleep(wait_time)
                continue  # Try the request again

            response.raise_for_status()  # Raise an exception for other bad status codes (4xx or 5xx)
            
            result = response.json()
            
            # Safely extract the text from the response
            if 'candidates' in result and len(result['candidates']) > 0:
                content = result['candidates'][0].get('content', {})
                if 'parts' in content and len(content['parts']) > 0:
                    url = content['parts'][0].get('text', '').strip()
                    # Validate if the response is a plausible URL
                    if url.startswith("http") and url.lower().endswith(".pdf"):
                        return url
            
            # If parsing fails, validation fails, or no content, return NA
            return "NA"
            
        except requests.exceptions.RequestException as e:
            # Handle potential network or HTTP errors
            tqdm.write(f"API request error for '{paper_title}': {e}")
            return "NA" # Exit on non-rate-limit errors
        except Exception as e:
            # Handle other unexpected errors (e.g., JSON parsing)
            tqdm.write(f"Unexpected error for '{paper_title}': {e}")
            return "NA"

    # If all retries fail
    tqdm.write(f"Failed to process '{paper_title}' after {max_retries} attempts due to persistent rate limiting.")
    return "NA"


# --- Execution ---
if __name__ == "__main__":
    main()
