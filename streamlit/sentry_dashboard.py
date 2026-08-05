import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Sentry", layout="wide")

session = get_active_session()

st.title("Sentry")
st.caption("Autonomous ops-anomaly investigation agent, built with Snowflake CoCo CLI")

trace_df = session.sql(
    """
    SELECT trace_id, run_ts, sku, warehouse_id, baseline_return_rate, current_return_rate,
           z_score, hypothesis, evidence_summary, confidence, recommended_action
    FROM SENTRY_DB.OPS.SENTRY_TRACE
    ORDER BY run_ts DESC
    """
).to_pandas()

if trace_df.empty:
    st.info("No anomalies logged yet. Run ANOMALY_SCAN() or wait for the scheduled task to fire.")
else:
    st.subheader(f"Anomaly feed ({len(trace_df)})")

    for _, row in trace_df.iterrows():
        with st.container():
            col1, col2, col3 = st.columns([2, 1, 1])
            with col1:
                st.markdown(f"**{row['SKU']} / {row['WAREHOUSE_ID']}**")
                st.caption(str(row["RUN_TS"]))
            with col2:
                st.metric("Return rate", f"{row['CURRENT_RETURN_RATE']:.1%}",
                           delta=f"{(row['CURRENT_RETURN_RATE'] - row['BASELINE_RETURN_RATE']):.1%} vs baseline")
            with col3:
                st.metric("Z-score", f"{row['Z_SCORE']:.1f}")
                st.metric("Confidence", f"{row['CONFIDENCE']:.0%}" if row["CONFIDENCE"] is not None else "n/a")

            st.markdown(f"**Hypothesis:** {row['HYPOTHESIS']}")
            st.markdown(f"**Evidence:** {row['EVIDENCE_SUMMARY']}")
            st.markdown(f"**Recommended action:** {row['RECOMMENDED_ACTION']}")
            st.divider()

st.divider()
st.caption("Sentry watches ORDERS/RETURNS in Snowflake, catches statistically significant "
           "return-rate spikes via a fleet-wide baseline z-test, and uses Cortex COMPLETE to "
           "produce an explainable root-cause hypothesis and recommended action for each one.")
