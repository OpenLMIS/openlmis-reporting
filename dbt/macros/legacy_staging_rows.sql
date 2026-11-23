{#
  Upgrade path for the *_with_deleted staging tables. Before OLMIS-8460 the
  incremental table lived under the model's own name (e.g. stg_requisitions).
  Raw events can expire (RAW_TTL_DAYS), so that old table may be the only copy
  of some rows. On the first (non-incremental) build, while the old table still
  exists, keep its rows whose id has no event left in raw. Once the old name
  is a view, this emits nothing.
#}
{% macro legacy_staging_rows(legacy_name, raw_table) %}
  {%- if not is_incremental() -%}
    {%- set legacy = adapter.get_relation(database=this.database, schema=this.schema, identifier=legacy_name) -%}
    {%- if legacy is not none and legacy.type == 'table' %}
union all

select *
from {{ legacy }}
where toString(id) not in (
  select coalesce(
    nullIf(JSONExtractString(after,  'id'), ''),
    nullIf(JSONExtractString(before, 'id'), '')
  )
  from {{ raw_table }}
)
    {%- endif -%}
  {%- endif -%}
{% endmacro %}
