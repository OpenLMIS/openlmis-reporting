{#
  backfill_schedule_type — fill schedule_type on rows written before the column
  existed, without rebuilding the mart.

  Why this rather than --full-refresh: schedule_type was added to an incremental
  model, so ClickHouse created the column and left every existing row at the
  String default. A full refresh would recompute it, but it would also re-apply
  the model's retention window to history that is already materialised, and
  drop whatever now falls outside. Updating in place touches only the column and
  cannot lose a row.

  The value is derived from period_start_date and period_end_date, both already
  present on the mart, using the same schedule_type macro the model uses, so the
  result is identical to what a rebuild would have produced. Nothing is guessed
  and no value is written by hand.

  Idempotent: the WHERE clause matches only unfilled rows, so a second run is a
  no-op. Runs synchronously (mutations_sync = 2) and fails loudly if any row is
  left behind, so an operator can trust the exit code.

  Follow it with a build. The table-materialised marts downstream, including
  mart_logistics_summary, keep their own stale copies of the column until they
  are rebuilt from this one.

  Two caveats for adopters forking this package. The mutation rewrites every
  part it touches, and with mutations_sync = 2 the client waits for all of them,
  so on a very large mart the wait can exceed the adapter's send_receive_timeout
  (300s by default); the server finishes regardless and the operation is safe to
  re-run. And ALTER ... UPDATE does not work against a Distributed table, and
  needs ON CLUSTER against the local table on a Replicated one.

  Usage, via the platform's dbt wrapper:
    bash scripts/dbt/run.sh run-operation backfill_schedule_type
#}

{% macro backfill_schedule_type() %}

  {% if execute %}

    {% set relation = ref('mart_stock_status') %}
    {% set count_sql %}
      select count(*) as n from {{ relation }} where schedule_type = ''
    {% endset %}

    {% set pending = run_query(count_sql).columns[0].values()[0] | int %}

    {% if pending == 0 %}
      {% do log("backfill_schedule_type: nothing to fill in " ~ relation, info=True) %}
    {% else %}
      {% do log("backfill_schedule_type: filling " ~ pending ~ " row(s) in " ~ relation, info=True) %}

      {% set update_sql %}
        alter table {{ relation }}
        update schedule_type = {{ schedule_type('period_start_date', 'period_end_date') }}
        where schedule_type = ''
        settings mutations_sync = 2
      {% endset %}
      {% do run_query(update_sql) %}

      {% set remaining = run_query(count_sql).columns[0].values()[0] | int %}
      {% if remaining > 0 %}
        {% do exceptions.raise_compiler_error(
             "backfill_schedule_type: " ~ remaining ~ " row(s) still unfilled after the mutation. "
             ~ "Check system.mutations for a failed or in-flight mutation, then re-run.") %}
      {% endif %}
      {% do log("backfill_schedule_type: filled " ~ pending ~ " row(s), none left unfilled", info=True) %}
    {% endif %}

    {% do log("backfill_schedule_type: rebuild downstream with `bash scripts/dbt/run.sh build --exclude tag:reconcile`", info=True) %}

  {% endif %}

{% endmacro %}
