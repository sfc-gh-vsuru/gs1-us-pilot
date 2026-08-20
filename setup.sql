-- =============================================================================
-- GS1 US x Snowflake Agentic Grounding Pilot — Setup Script
-- =============================================================================
-- This script creates the full environment from scratch.
-- Run after uploading CSV files to the DATA_STAGE.
-- =============================================================================

-- 1. Database & Schemas
CREATE DATABASE IF NOT EXISTS GS1_US;

CREATE SCHEMA IF NOT EXISTS GS1_US.PRODUCTS
    COMMENT = 'Gold product catalog and derived grounding arms (GS1, retailer, scraped)';
CREATE SCHEMA IF NOT EXISTS GS1_US.GROUNDING
    COMMENT = 'Cortex Search services and Semantic Views for agent grounding';
CREATE SCHEMA IF NOT EXISTS GS1_US.EVALUATION
    COMMENT = 'Shopping questions, agent responses, and scoring results';

-- 2. File format & stage for loading CSVs
CREATE FILE FORMAT IF NOT EXISTS GS1_US.PUBLIC.CSV_FORMAT
    TYPE = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', '');

CREATE STAGE IF NOT EXISTS GS1_US.PUBLIC.DATA_STAGE
    FILE_FORMAT = GS1_US.PUBLIC.CSV_FORMAT;

-- =============================================================================
-- 3. PRODUCTS schema tables
-- =============================================================================

CREATE OR REPLACE TABLE GS1_US.PRODUCTS.GOLD_CATALOG (
    GTIN VARCHAR(14) NOT NULL,
    BRAND VARCHAR(100),
    PRODUCT_NAME VARCHAR(255),
    DESCRIPTION_CLEAN VARCHAR(1000),
    CATEGORY_L1 VARCHAR(100),
    CATEGORY_L2 VARCHAR(100),
    CATEGORY_L3 VARCHAR(100),
    NET_CONTENT FLOAT,
    UOM VARCHAR(10),
    PRICE_USD FLOAT,
    AVAILABILITY VARCHAR(20),
    COUNTRY_OF_ORIGIN VARCHAR(50),
    PACKAGING_TYPE VARCHAR(50),
    CONTAINS_GLUTEN BOOLEAN,
    CONTAINS_DAIRY BOOLEAN,
    CONTAINS_NUTS BOOLEAN,
    CONTAINS_SOY BOOLEAN,
    CONTAINS_EGGS BOOLEAN,
    ALLERGEN_STATEMENT VARCHAR(500),
    ENERGY_KCAL_PER100G FLOAT,
    FAT_G_PER100G FLOAT,
    SATURATES_G_PER100G FLOAT,
    CARBS_G_PER100G FLOAT,
    SUGARS_G_PER100G FLOAT,
    FIBRE_G_PER100G FLOAT,
    PROTEIN_G_PER100G FLOAT,
    SALT_G_PER100G FLOAT,
    CONSTRAINT PK_GOLD PRIMARY KEY (GTIN)
) COMMENT = 'Ground truth product catalog — the answer key for all scoring';

CREATE OR REPLACE TABLE GS1_US.PRODUCTS.RETAILER_INTERNAL (
    SKU VARCHAR(16777216),
    VENDOR VARCHAR(300),
    ITEM_NAME VARCHAR(511),
    DEPARTMENT VARCHAR(100),
    PRICE FLOAT,
    SIZE_TEXT VARCHAR(16777216),
    ALLERGEN_NOTES VARCHAR(500),
    IN_STOCK VARCHAR(12),
    UPC_CODE VARCHAR(16777216),
    LAST_UPDATED DATE,
    CALORIES_PER_SERVING VARCHAR(50),
    PROTEIN_G VARCHAR(20),
    FAT_G VARCHAR(20)
);

CREATE OR REPLACE TABLE GS1_US.PRODUCTS.WEB_SCRAPED (
    SCRAPED_ID VARCHAR(16777216),
    PAGE_TITLE VARCHAR(16777216),
    PAGE_URL VARCHAR(16777216),
    BRAND_TEXT VARCHAR(16777216),
    DESCRIPTION_HTML VARCHAR(16777216),
    WEIGHT_TEXT VARCHAR(16777216),
    BREADCRUMB VARCHAR(16777216),
    PRICE_SCRAPED FLOAT,
    ALLERGEN_TEXT VARCHAR(16777216),
    CAL_TEXT FLOAT,
    FAT_TEXT FLOAT,
    PROTEIN_TEXT FLOAT,
    STAR_RATING NUMBER(27,1),
    REVIEW_COUNT NUMBER(20,0),
    AVAILABILITY VARCHAR(9),
    PROMO_BADGE VARCHAR(16777216),
    SCRAPED_AT TIMESTAMP_LTZ(9)
);

-- GS1_STANDARD view (adds provenance columns to GOLD_CATALOG)
CREATE OR REPLACE VIEW GS1_US.PRODUCTS.GS1_STANDARD AS
SELECT
    *,
    'GS1 US Verified' AS DATA_PROVENANCE,
    CURRENT_DATE() AS LAST_VERIFIED_DATE
FROM GS1_US.PRODUCTS.GOLD_CATALOG;

-- =============================================================================
-- 4. GROUNDING schema tables
-- =============================================================================

CREATE OR REPLACE TABLE GS1_US.GROUNDING.GS1_SEARCH_CORPUS (
    GTIN VARCHAR(14),
    TITLE VARCHAR(356),
    DESCRIPTION_CLEAN VARCHAR(1000),
    CATEGORY_PATH VARCHAR(306),
    SEARCH_TEXT VARCHAR(16777216)
);

CREATE OR REPLACE TABLE GS1_US.GROUNDING.RETAILER_SEARCH_CORPUS (
    SKU VARCHAR(16777216),
    TITLE VARCHAR(812),
    SEARCH_TEXT VARCHAR(16777216)
);

CREATE OR REPLACE TABLE GS1_US.GROUNDING.WEB_SEARCH_CORPUS (
    SCRAPED_ID VARCHAR(16777216),
    TITLE VARCHAR(16777216),
    SEARCH_TEXT VARCHAR(16777216)
);

-- =============================================================================
-- 5. EVALUATION schema tables
-- =============================================================================

CREATE OR REPLACE TABLE GS1_US.EVALUATION.SHOPPING_QUESTIONS (
    QUESTION_ID NUMBER(38,0) NOT NULL,
    QUESTION_TEXT VARCHAR(500),
    QUESTION_TYPE VARCHAR(50),
    EXPECTED_ANSWER VARCHAR(2000),
    DIFFICULTY VARCHAR(10),
    TESTS_ATTRIBUTE VARCHAR(100),
    PRIMARY KEY (QUESTION_ID)
);

CREATE OR REPLACE TABLE GS1_US.EVALUATION.AGENT_RESULTS (
    RUN_ID VARCHAR(50),
    CONFIG_ID NUMBER(38,0),
    CONFIG_NAME VARCHAR(50),
    AGENT_NAME VARCHAR(100),
    QUESTION_ID NUMBER(38,0),
    QUESTION_TEXT VARCHAR(500),
    AGENT_RESPONSE VARCHAR(5000),
    EXPECTED_ANSWER VARCHAR(2000),
    RESPONSE_TIME_MS NUMBER(38,0),
    TOKEN_COUNT NUMBER(38,0),
    RUN_TIMESTAMP TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE GS1_US.EVALUATION.SCORED_RESULTS (
    RUN_ID VARCHAR(50),
    CONFIG_ID NUMBER(38,0),
    CONFIG_NAME VARCHAR(50),
    AGENT_NAME VARCHAR(100),
    QUESTION_ID NUMBER(38,0),
    QUESTION_TEXT VARCHAR(500),
    AGENT_RESPONSE VARCHAR(5000),
    EXPECTED_ANSWER VARCHAR(2000),
    RESPONSE_TIME_MS NUMBER(38,0),
    TOKEN_COUNT NUMBER(38,0),
    RUN_TIMESTAMP TIMESTAMP_NTZ(9),
    JUDGE_RAW VARIANT
);

CREATE OR REPLACE TABLE GS1_US.EVALUATION.FINAL_SCORES (
    CONFIG_ID NUMBER(38,0),
    CONFIG_NAME VARCHAR(50),
    QUESTION_ID NUMBER(38,0),
    QUESTION_TEXT VARCHAR(500),
    AGENT_RESPONSE VARCHAR(5000),
    EXPECTED_ANSWER VARCHAR(2000),
    JUDGE_RAW VARIANT,
    SCORE NUMBER(38,0)
);

-- PILOT_SUMMARY view
CREATE OR REPLACE VIEW GS1_US.EVALUATION.PILOT_SUMMARY AS
SELECT
    config_id,
    config_name,
    CASE config_id
        WHEN 1 THEN 'Scraped Web Data'
        WHEN 2 THEN 'Retailer Internal Data'
        WHEN 3 THEN 'GS1 Standardized Data'
        WHEN 4 THEN 'GS1 + Cortex Analyst'
    END AS data_source,
    CASE config_id
        WHEN 1 THEN 'Cortex Search (RAG)'
        WHEN 2 THEN 'Cortex Search (RAG)'
        WHEN 3 THEN 'Cortex Search (RAG)'
        WHEN 4 THEN 'Semantic View (Text-to-SQL)'
    END AS technique,
    COUNT(*) AS total_questions,
    ROUND(AVG(score), 2) AS avg_score,
    ROUND(AVG(score) / 5.0 * 100, 1) AS quality_pct,
    COUNT_IF(score >= 4) AS correct_answers,
    COUNT_IF(score BETWEEN 2 AND 3) AS partial_answers,
    COUNT_IF(score <= 1) AS failed_answers,
    ROUND(COUNT_IF(score >= 4) * 100.0 / COUNT(*), 1) AS accuracy_pct
FROM GS1_US.EVALUATION.FINAL_SCORES
GROUP BY config_id, config_name;

-- =============================================================================
-- 6. Load data from stage
-- =============================================================================

-- Upload CSVs first:
--   PUT file://data/gold_catalog.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/retailer_internal.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/web_scraped.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/gs1_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/retailer_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/web_search_corpus.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/shopping_questions.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/final_scores.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/agent_results.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://data/scored_results.csv @GS1_US.PUBLIC.DATA_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

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

-- =============================================================================
-- 7. Cortex Search Services
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE GS1_US.GROUNDING.GS1_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES TITLE
    WAREHOUSE = COCOWH
    TARGET_LAG = '1 hour'
    COMMENT = 'Search over GS1 standardized product data (Config 3)'
AS (
    SELECT gtin, title, search_text FROM GS1_US.GROUNDING.GS1_SEARCH_CORPUS
);

CREATE OR REPLACE CORTEX SEARCH SERVICE GS1_US.GROUNDING.RETAILER_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES TITLE
    WAREHOUSE = COCOWH
    TARGET_LAG = '1 hour'
    COMMENT = 'Search over retailer internal product data (Config 2)'
AS (
    SELECT sku, title, search_text FROM GS1_US.GROUNDING.RETAILER_SEARCH_CORPUS
);

CREATE OR REPLACE CORTEX SEARCH SERVICE GS1_US.GROUNDING.WEB_SEARCH
    ON SEARCH_TEXT
    ATTRIBUTES TITLE
    WAREHOUSE = COCOWH
    TARGET_LAG = '1 hour'
    COMMENT = 'Search over scraped web product data (Config 1 - baseline)'
AS (
    SELECT scraped_id, title, search_text FROM GS1_US.GROUNDING.WEB_SEARCH_CORPUS
);

-- =============================================================================
-- 8. Semantic View (for Cortex Analyst — Config 4)
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW GS1_US.GROUNDING.GS1_SEMANTIC_VIEW
    TABLES (
        PRODUCTS AS GS1_US.PRODUCTS.GOLD_CATALOG PRIMARY KEY (GTIN)
            WITH SYNONYMS = ('product','item','grocery','SKU')
    )
    FACTS (
        PRODUCTS.ITEM_PRICE AS price_usd WITH SYNONYMS = ('price','cost','how much') COMMENT = 'Price in US dollars',
        PRODUCTS.CALORIES AS energy_kcal_per100g WITH SYNONYMS = ('calories','energy','kcal') COMMENT = 'Energy in kcal per 100g',
        PRODUCTS.FAT AS fat_g_per100g WITH SYNONYMS = ('fat','total fat') COMMENT = 'Fat grams per 100g',
        PRODUCTS.SATURATED_FAT AS saturates_g_per100g WITH SYNONYMS = ('saturated fat') COMMENT = 'Saturated fat per 100g',
        PRODUCTS.CARBOHYDRATES AS carbs_g_per100g WITH SYNONYMS = ('carbs','carbohydrates') COMMENT = 'Carbs per 100g',
        PRODUCTS.SUGAR AS sugars_g_per100g WITH SYNONYMS = ('sugar','sugars') COMMENT = 'Sugar per 100g',
        PRODUCTS.FIBER AS fibre_g_per100g WITH SYNONYMS = ('fiber','fibre','dietary fiber') COMMENT = 'Fibre per 100g',
        PRODUCTS.PROTEIN AS protein_g_per100g WITH SYNONYMS = ('protein') COMMENT = 'Protein per 100g',
        PRODUCTS.SODIUM AS salt_g_per100g WITH SYNONYMS = ('salt','sodium') COMMENT = 'Salt per 100g'
    )
    DIMENSIONS (
        PRODUCTS.GTIN_ID AS gtin WITH SYNONYMS = ('barcode','UPC','product code','identifier'),
        PRODUCTS.BRAND_NAME AS brand WITH SYNONYMS = ('manufacturer','maker'),
        PRODUCTS.NAME AS product_name WITH SYNONYMS = ('item name','product title'),
        PRODUCTS.TOP_CATEGORY AS category_l1 WITH SYNONYMS = ('department'),
        PRODUCTS.CATEGORY AS category_l2 WITH SYNONYMS = ('aisle','section','product category'),
        PRODUCTS.SUBCATEGORY AS category_l3 WITH SYNONYMS = ('product type','sub-category'),
        PRODUCTS.SIZE_AMOUNT AS net_content WITH SYNONYMS = ('weight','volume','size','amount'),
        PRODUCTS.SIZE_UNIT AS uom WITH SYNONYMS = ('unit','measure'),
        PRODUCTS.PACK_TYPE AS packaging_type WITH SYNONYMS = ('packaging','container'),
        PRODUCTS.ORIGIN AS country_of_origin WITH SYNONYMS = ('made in','source country'),
        PRODUCTS.STOCK_STATUS AS availability WITH SYNONYMS = ('in stock','available'),
        PRODUCTS.HAS_GLUTEN AS contains_gluten WITH SYNONYMS = ('gluten','wheat'),
        PRODUCTS.HAS_DAIRY AS contains_dairy WITH SYNONYMS = ('dairy','milk','lactose'),
        PRODUCTS.HAS_NUTS AS contains_nuts WITH SYNONYMS = ('nuts','tree nuts','peanuts'),
        PRODUCTS.HAS_SOY AS contains_soy WITH SYNONYMS = ('soy','soya'),
        PRODUCTS.HAS_EGGS AS contains_eggs WITH SYNONYMS = ('eggs','egg')
    )
    METRICS (
        PRODUCTS.TOTAL_PRODUCTS AS COUNT(products.gtin) WITH SYNONYMS = ('how many products','product count'),
        PRODUCTS.AVG_PRICE AS AVG(products.price_usd) WITH SYNONYMS = ('average price'),
        PRODUCTS.CHEAPEST AS MIN(products.price_usd) WITH SYNONYMS = ('lowest price','cheapest'),
        PRODUCTS.MOST_EXPENSIVE AS MAX(products.price_usd) WITH SYNONYMS = ('highest price','most expensive'),
        PRODUCTS.AVG_PROTEIN AS AVG(products.protein_g_per100g) WITH SYNONYMS = ('average protein'),
        PRODUCTS.MAX_PROTEIN AS MAX(products.protein_g_per100g) WITH SYNONYMS = ('highest protein','most protein'),
        PRODUCTS.AVG_CALORIES AS AVG(products.energy_kcal_per100g) WITH SYNONYMS = ('average calories')
    )
    COMMENT = 'GS1 US standardized product semantic model for Cortex Analyst (Config 4)';

-- =============================================================================
-- 9. Streamlit Dashboard
-- =============================================================================

CREATE STAGE IF NOT EXISTS GS1_US.EVALUATION.STREAMLIT_STAGE;

-- Upload streamlit_app.py:
--   PUT file://streamlit_app.py @GS1_US.EVALUATION.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE STREAMLIT IF NOT EXISTS GS1_US.EVALUATION.PILOT_DASHBOARD
    ROOT_LOCATION = '@GS1_US.EVALUATION.STREAMLIT_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = 'COCOWH'
    TITLE = 'GS1 US Pilot Results';
