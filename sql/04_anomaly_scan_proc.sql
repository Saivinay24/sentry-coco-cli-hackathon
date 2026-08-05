-- ANOMALY_SCAN: detect return-rate anomalies, gather evidence, call LLM for analysis,
-- and log results to SENTRY_TRACE. Deduplicates within a 1-hour window.
USE DATABASE SENTRY_DB;
USE SCHEMA OPS;

CREATE OR REPLACE PROCEDURE SENTRY_DB.OPS.ANOMALY_SCAN()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    anomaly_count INTEGER DEFAULT 0;
    v_sku STRING;
    v_warehouse_id STRING;
    v_orders_current INTEGER;
    v_returns_current INTEGER;
    v_current_rate FLOAT;
    v_baseline_rate FLOAT;
    v_z_score FLOAT;
    v_reasons STRING;
    v_prompt STRING;
    v_llm_raw STRING;
    v_llm_clean STRING;
    v_hypothesis STRING;
    v_evidence STRING;
    v_confidence FLOAT;
    v_action STRING;
    already_exists INTEGER;
    
    anomaly_cursor CURSOR FOR
        WITH baseline AS (
            SELECT COUNT(DISTINCT r.return_id)::FLOAT / COUNT(DISTINCT o.order_id) AS baseline_rate
            FROM SENTRY_DB.OPS.ORDERS o
            LEFT JOIN SENTRY_DB.OPS.RETURNS r ON r.order_id = o.order_id
            WHERE o.order_date >= DATEADD(day,-35,CURRENT_DATE()) AND o.order_date < DATEADD(day,-7,CURRENT_DATE())
        ),
        current_window AS (
            SELECT o.sku, o.warehouse_id,
                COUNT(DISTINCT o.order_id) AS orders_current,
                COUNT(DISTINCT r.return_id) AS returns_current
            FROM SENTRY_DB.OPS.ORDERS o
            LEFT JOIN SENTRY_DB.OPS.RETURNS r ON r.order_id = o.order_id
            WHERE o.order_date >= DATEADD(day,-7,CURRENT_DATE())
            GROUP BY 1,2
        )
        SELECT c.sku, c.warehouse_id, c.orders_current, c.returns_current,
            c.returns_current::FLOAT / c.orders_current AS current_rate,
            b.baseline_rate,
            (c.returns_current::FLOAT / c.orders_current - b.baseline_rate)
                / SQRT(b.baseline_rate * (1 - b.baseline_rate) / c.orders_current) AS z_score
        FROM current_window c
        CROSS JOIN baseline b
        WHERE c.orders_current >= 15
          AND (c.returns_current::FLOAT / c.orders_current - b.baseline_rate)
                / SQRT(b.baseline_rate * (1 - b.baseline_rate) / c.orders_current) > 3
        ORDER BY z_score DESC;
BEGIN
    OPEN anomaly_cursor;
    
    FOR rec IN anomaly_cursor DO
        v_sku := rec.sku;
        v_warehouse_id := rec.warehouse_id;
        v_orders_current := rec.orders_current;
        v_returns_current := rec.returns_current;
        v_current_rate := rec.current_rate;
        v_baseline_rate := rec.baseline_rate;
        v_z_score := rec.z_score;
        
        -- Skip if already logged in the last hour (dedup for scheduled runs)
        SELECT COUNT(*) INTO :already_exists
        FROM SENTRY_DB.OPS.SENTRY_TRACE
        WHERE sku = :v_sku
          AND warehouse_id = :v_warehouse_id
          AND run_ts >= DATEADD(hour, -1, CURRENT_TIMESTAMP());
        
        IF (already_exists > 0) THEN
            CONTINUE;
        END IF;
        
        -- Gather top 5 return reasons for this SKU/warehouse in last 7 days
        SELECT LISTAGG(reason_line, '; ') INTO :v_reasons
        FROM (
            SELECT reason || ' (' || COUNT(*) || ')' AS reason_line
            FROM SENTRY_DB.OPS.RETURNS
            WHERE sku = :v_sku
              AND warehouse_id = :v_warehouse_id
              AND return_date >= DATEADD(day, -7, CURRENT_DATE())
            GROUP BY reason
            ORDER BY COUNT(*) DESC
            LIMIT 5
        );
        
        -- Build LLM prompt with evidence
        v_prompt := 'You are an operations analyst. Analyze this anomaly and respond ONLY with a JSON object (no markdown fences, no extra text).

SKU: ' || v_sku || '
Warehouse: ' || v_warehouse_id || '
Current 7-day return rate: ' || ROUND(v_current_rate * 100, 1)::STRING || '% (' || v_returns_current::STRING || ' returns / ' || v_orders_current::STRING || ' orders)
Fleet baseline return rate: ' || ROUND(v_baseline_rate * 100, 1)::STRING || '%
Z-score: ' || ROUND(v_z_score, 2)::STRING || '
Top return reasons (last 7 days): ' || v_reasons || '

Respond with exactly this JSON structure:
{"hypothesis": "<one sentence root cause hypothesis>", "evidence_summary": "<one sentence citing the actual numbers>", "confidence": <float 0-1>, "recommended_action": "<one concrete action>"}';
        
        -- Call Cortex LLM
        SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', :v_prompt) INTO :v_llm_raw;
        
        -- Strip markdown fences if LLM wrapped the JSON
        v_llm_clean := TRIM(v_llm_raw);
        IF (v_llm_clean LIKE '```%') THEN
            v_llm_clean := REGEXP_REPLACE(v_llm_clean, '^```[a-z]*\\n?', '');
            v_llm_clean := REGEXP_REPLACE(v_llm_clean, '\\n?```$', '');
            v_llm_clean := TRIM(v_llm_clean);
        END IF;
        
        -- Parse structured fields from LLM JSON response
        v_hypothesis := PARSE_JSON(v_llm_clean):hypothesis::STRING;
        v_evidence := PARSE_JSON(v_llm_clean):evidence_summary::STRING;
        v_confidence := PARSE_JSON(v_llm_clean):confidence::FLOAT;
        v_action := PARSE_JSON(v_llm_clean):recommended_action::STRING;
        
        -- Insert trace row
        INSERT INTO SENTRY_DB.OPS.SENTRY_TRACE (
            sku, warehouse_id, baseline_return_rate, current_return_rate,
            z_score, hypothesis, evidence_summary, confidence,
            recommended_action, raw_llm_output
        )
        SELECT :v_sku, :v_warehouse_id, :v_baseline_rate, :v_current_rate,
               :v_z_score, :v_hypothesis, :v_evidence, :v_confidence,
               :v_action, TRY_PARSE_JSON(:v_llm_raw);
        
        anomaly_count := anomaly_count + 1;
    END FOR;
    
    RETURN 'ANOMALY_SCAN complete: ' || anomaly_count::STRING || ' new anomalies logged.';
END;
$$;
