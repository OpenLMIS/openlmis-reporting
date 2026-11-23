{#
  Upgrade path for the *_with_deleted staging tables. Up to 1.0.0 the
  incremental table lived under the model's own name (e.g. stg_requisitions).
  Raw events can expire (RAW_TTL_DAYS), so that old table may be the only copy
  of some rows. On the first (non-incremental) build, while the old table still
  exists, keep its rows whose id has no event left in raw. Once the old name
  is a view, this emits nothing.

  It cannot tell expired events from deleted ones: a row whose delete event
  has expired too, or whose events were truncated from raw, is kept.
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
  ) as id_str
  from {{ raw_table }}
  where id_str is not null
)
    {%- endif -%}
  {%- endif -%}
{% endmacro %}
