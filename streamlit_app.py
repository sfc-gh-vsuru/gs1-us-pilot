import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="GS1 US Pilot Results", layout="wide")

st.title("GS1 US x Snowflake — Agentic Grounding Pilot")
st.caption("Does standardized product data + semantic models beat traditional RAG for AI shopping agents?")

# --- Load data ---
summary_df = session.sql("SELECT * FROM GS1_US.EVALUATION.PILOT_SUMMARY ORDER BY CONFIG_ID").to_pandas()
scores_df = session.sql("""
    SELECT f.*, q.QUESTION_TYPE, q.DIFFICULTY
    FROM GS1_US.EVALUATION.FINAL_SCORES f
    JOIN GS1_US.EVALUATION.SHOPPING_QUESTIONS q ON f.QUESTION_ID = q.QUESTION_ID
    ORDER BY f.CONFIG_ID, f.QUESTION_ID
""").to_pandas()

# --- KPI Metrics Row ---
st.markdown("### Accuracy by Configuration")
cols = st.columns(4)
config_order = [1, 2, 3, 4]
config_labels = {
    1: "Scraped Web + RAG",
    2: "Retailer + RAG",
    3: "GS1 + RAG",
    4: "GS1 + Analyst",
}
for i, cfg_id in enumerate(config_order):
    row = summary_df[summary_df["CONFIG_ID"] == cfg_id].iloc[0]
    with cols[i]:
        delta = None
        if cfg_id > 1:
            prev = summary_df[summary_df["CONFIG_ID"] == config_order[i - 1]].iloc[0]["ACCURACY_PCT"]
            delta = f"+{row['ACCURACY_PCT'] - prev:.0f}pp"
        st.metric(
            label=config_labels[cfg_id],
            value=f"{row['ACCURACY_PCT']:.0f}%",
            delta=delta,
        )

st.divider()

# --- Bar Chart: Average Score ---
st.markdown("### Average Score by Configuration (0-5 scale)")
chart_data = summary_df[["CONFIG_NAME", "AVG_SCORE"]].copy()
chart_data = chart_data.set_index("CONFIG_NAME")
st.bar_chart(chart_data, y="AVG_SCORE")

st.divider()

# --- Hypothesis Results ---
st.markdown("### Hypothesis Results")
h_col1, h_col2 = st.columns(2)
with h_col1:
    web_acc = summary_df[summary_df["CONFIG_ID"] == 1].iloc[0]["ACCURACY_PCT"]
    gs1_rag_acc = summary_df[summary_df["CONFIG_ID"] == 3].iloc[0]["ACCURACY_PCT"]
    lift = gs1_rag_acc - web_acc
    st.success(f"**H1 — Data Quality Lift:** GS1 standardized data is {gs1_rag_acc/web_acc:.1f}x more accurate than scraped web data (+{lift:.0f} percentage points)")
with h_col2:
    gs1_analyst_acc = summary_df[summary_df["CONFIG_ID"] == 4].iloc[0]["ACCURACY_PCT"]
    lift2 = gs1_analyst_acc - gs1_rag_acc
    st.success(f"**H2 — Semantic Model Lift:** Cortex Analyst is {gs1_analyst_acc/gs1_rag_acc:.1f}x more accurate than RAG on the same GS1 data (+{lift2:.0f} percentage points)")

st.divider()

# --- Breakdown by Question Type ---
st.markdown("### Accuracy by Question Type")
type_tab_names = sorted(scores_df["QUESTION_TYPE"].unique())
tabs = st.tabs(type_tab_names)
for tab, qtype in zip(tabs, type_tab_names):
    with tab:
        subset = scores_df[scores_df["QUESTION_TYPE"] == qtype]
        pivot = subset.groupby("CONFIG_NAME")["SCORE"].mean().reset_index()
        pivot.columns = ["Configuration", "Avg Score"]
        pivot = pivot.set_index("Configuration")
        st.bar_chart(pivot, y="Avg Score")
        st.caption(f"{len(subset)//4} questions in this category")

st.divider()

# --- Detail Explorer ---
st.markdown("### Question Detail Explorer")
selected_q = st.selectbox(
    "Select a question:",
    scores_df["QUESTION_ID"].unique(),
    format_func=lambda qid: f"Q{qid}: {scores_df[scores_df['QUESTION_ID']==qid].iloc[0]['QUESTION_TEXT'][:80]}",
)

q_data = scores_df[scores_df["QUESTION_ID"] == selected_q].sort_values("CONFIG_ID")
expected = q_data.iloc[0]["EXPECTED_ANSWER"]
st.markdown(f"**Expected Answer:** {expected}")

for _, row in q_data.iterrows():
    with st.expander(f"{config_labels[row['CONFIG_ID']]} — Score: {row['SCORE']}/5"):
        st.markdown(f"**Agent Response:** {row['AGENT_RESPONSE']}")
        if row["JUDGE_RAW"]:
            st.markdown(f"**Judge:** {row['JUDGE_RAW']}")
