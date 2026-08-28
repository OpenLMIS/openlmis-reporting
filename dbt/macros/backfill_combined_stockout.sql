{#
  backfill_combined_stockout — recompute the flag on rows written under the
  old definition, without rebuilding the mart.

  The definition of combined_stockout was tightened to direct stockout
  evidence only (stock_on_hand = 0 or total_stockout_days > 0); the legacy
  proxies beginning_balance = 0 and max_periods_of_stock = 0 no longer
  count. mart_stock_status is incremental, so already-materialised rows
  keep the old flag until they are touched — this operation rewrites them
  in place, mirroring backfill_schedule_type: no retention window is
  re-applied and no row can be lost.

  Idempotent: the WHERE clause matches only rows whose stored flag differs
  from the recomputed value, so a second run is a no-op. Runs synchronously
  (mutations_sync = 2) and fails loudly if any row is left behind.

  Follow it with a build: the table-materialised marts downstream keep
  their own stale copies of the flag until they are rebuilt from this one.

  Usage, via the platform's dbt wrapper:
    bash scripts/dbt/run.sh run-operation backfill_combined_stockout
#}

{% macro backfill_combined_stockout() %}

  {% if execute %}

    {% set relation = ref('mart_stock_status') %}
    {% set expr = "if(stock_on_hand = 0 or total_stockout_days > 0, 1, 0)" %}

    {% set update_sql %}
      alter table {{ relation }}
      update combined_stockout = {{ expr }}
      where combined_stockout != {{ expr }}
      settings mutations_sync = 2
    {% endset %}

    {% do run_query(update_sql) %}

    {% set check = run_query("select count() from " ~ relation ~ " where combined_stockout != " ~ expr) %}
    {% set remaining = check.columns[0].values()[0] %}
    {% if remaining > 0 %}
      {{ exceptions.raise_compiler_error("backfill_combined_stockout left " ~ remaining ~ " rows unfilled") }}
    {% endif %}
    {{ log("backfill_combined_stockout: complete, 0 rows remaining", info=True) }}

  {% endif %}

{% endmacro %}
