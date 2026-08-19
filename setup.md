# GS1 US x Snowflake Pilot — Setup Guide

## Prerequisites

- Snowflake account with `CREATE DATABASE` privileges
- A warehouse (default: `COCOWH`)
- Snowsight worksheet or SnowSQL/CLI access

---

## Repository Structure

```
GS1/
├── setup.sql              # Everything: DB, tables, views, data load, search, semantic view, Streamlit
├── setup.md               # This file
├── plan_context.md        # Pilot plan and methodology
├── streamlit_app.py       # Dashboard app (Streamlit in Snowflake)
└── data/
    ├── gold_catalog.csv
    ├── retailer_internal.csv
    ├── web_scraped.csv
    ├── gs1_search_corpus.csv
    ├── retailer_search_corpus.csv
    ├── web_search_corpus.csv
    ├── shopping_questions.csv
    ├── final_scores.csv
    ├── agent_results.csv
    └── scored_results.csv
```

---

## Step 1: Run setup.sql (sections 1–5)

This creates the database, schemas, tables, and views.

```bash
snow sql -f setup.sql --connection <your_connection>
```

Or paste sections 1–5 into a Snowsight worksheet and run.

---

## Step 2: Upload CSV files to stage

From the project root directory:

```sql
PUT file://data/gold_catalog.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/retailer_internal.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/web_scraped.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/gs1_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/retailer_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/web_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/shopping_questions.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/final_scores.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/agent_results.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://data/scored_results.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
```

---

## Step 3: Load data into tables

Run the COPY INTO statements (section 6 of `setup.sql`):

```sql
COPY INTO GS1_US.PRODUCTS.GOLD_CATALOG FROM @GS1_US.PUBLIC.DATA_STAGE/gold_catalog.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.PRODUCTS.RETAILER_INTERNAL FROM @GS1_US.PUBLIC.DATA_STAGE/retailer_internal.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.PRODUCTS.WEB_SCRAPED FROM @GS1_US.PUBLIC.DATA_STAGE/web_scraped.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.GROUNDING.GS1_SEARCH_CORPUS FROM @GS1_US.PUBLIC.DATA_STAGE/gs1_search_corpus.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.GROUNDING.RETAILER_SEARCH_CORPUS FROM @GS1_US.PUBLIC.DATA_STAGE/retailer_search_corpus.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.GROUNDING.WEB_SEARCH_CORPUS FROM @GS1_US.PUBLIC.DATA_STAGE/web_search_corpus.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.EVALUATION.SHOPPING_QUESTIONS FROM @GS1_US.PUBLIC.DATA_STAGE/shopping_questions.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.EVALUATION.FINAL_SCORES FROM @GS1_US.PUBLIC.DATA_STAGE/final_scores.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.EVALUATION.AGENT_RESULTS FROM @GS1_US.PUBLIC.DATA_STAGE/agent_results.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
COPY INTO GS1_US.EVALUATION.SCORED_RESULTS FROM @GS1_US.PUBLIC.DATA_STAGE/scored_results.csv FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;
```

---

## Step 4: Create Cortex Search Services

Run section 7 of `setup.sql`. Creates three search services (one per data source):

- `GS1_SEARCH` — GS1 standardized data (Config 3)
- `RETAILER_SEARCH` — retailer internal data (Config 2)
- `WEB_SEARCH` — scraped web data (Config 1)

Allow 1–2 minutes for indexing after creation.

---

## Step 5: Create Semantic View

Run section 8 of `setup.sql`. This creates `GS1_US.GROUNDING.GS1_SEMANTIC_VIEW` — the Cortex Analyst model used for Config 4 (text-to-SQL).

---

## Step 6: Deploy Streamlit Dashboard

Upload and create the app (section 9 of `setup.sql`):

```sql
PUT file://streamlit_app.py @GS1_US.EVALUATION.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
```

Then run the `CREATE STREAMLIT` statement from section 9.

Open in Snowsight: **Streamlit → GS1_US.EVALUATION.PILOT_DASHBOARD**

---

## Verify

```sql
SELECT 'GOLD_CATALOG' AS tbl, COUNT(*) AS rows FROM GS1_US.PRODUCTS.GOLD_CATALOG
UNION ALL SELECT 'FINAL_SCORES', COUNT(*) FROM GS1_US.EVALUATION.FINAL_SCORES
UNION ALL SELECT 'SHOPPING_QUESTIONS', COUNT(*) FROM GS1_US.EVALUATION.SHOPPING_QUESTIONS;
-- Expected: 60, 100, 25
```

```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA GS1_US.GROUNDING;  -- 3 services, ACTIVE
SHOW SEMANTIC VIEWS IN SCHEMA GS1_US.GROUNDING;           -- 1 (GS1_SEMANTIC_VIEW)
```

---

## Notes

- Replace `COCOWH` with your warehouse name if different.
- `PILOT_SUMMARY` is a view computed from `FINAL_SCORES` — no separate data load needed.
