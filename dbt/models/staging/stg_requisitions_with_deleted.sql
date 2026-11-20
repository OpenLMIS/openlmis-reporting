{{
  config(
    materialized='incremental',
    incremental_strategy='delete_insert',
    unique_key='id',
    engine='MergeTree()',
    order_by='id',
    settings={'allow_nullable_key': 1}
  )
}}

-- Current-state reconstruction for requisition.requisitions, with tombstones
-- for rows deleted in the source.
--
-- Incremental: on each run, we identify the set of requisition ids that
-- have at least one CDC event newer than the watermark (max(_cdc_ts_ms)
-- already in this table). For those ids only, we re-rank across the full
-- raw event history and emit the latest state. The delete_insert strategy
-- then replaces existing rows for those ids.
--
-- Source deletes: when the latest CDC event of an id is op='d', the row is
-- kept as a tombstone (_cdc_op='d', id from the `before` image, the other
-- columns empty). Dropping it here would give delete_insert nothing to
-- replace, and the last known state would stay in the table forever.
-- stg_requisitions is the view that leaves the tombstones out.

with touched_ids as (
  select distinct coalesce(
    nullIf(JSONExtractString(after,  'id'), ''),
    nullIf(JSONExtractString(before, 'id'), '')
  ) as id_str
  from raw.events_openlmis_requisition_requisitions
  where coalesce(
        nullIf(JSONExtractString(after,  'id'), ''),
        nullIf(JSONExtractString(before, 'id'), '')
      ) != ''
  {% if is_incremental() %}
    and ts_ms > (select coalesce(max(_cdc_ts_ms), 0) from {{ this }})
  {% endif %}
),

ranked as (
  select
    e.*,
    row_number() over (
      partition by coalesce(
        nullIf(JSONExtractString(e.after,  'id'), ''),
        nullIf(JSONExtractString(e.before, 'id'), '')
      )
      order by e.ts_ms desc, e._ingested_at desc
    ) as _rn
  from raw.events_openlmis_requisition_requisitions e
  inner join touched_ids t
    on coalesce(
         nullIf(JSONExtractString(e.after,  'id'), ''),
         nullIf(JSONExtractString(e.before, 'id'), '')
       ) = t.id_str
),

latest as (
  select
    *,
    if(op = 'd', before, after) as row_json
  from ranked
  where _rn = 1
)

select
  toUUID(JSONExtractString(row_json, 'id'))                  as id,
  JSONExtractString(row_json, 'status')                      as status,
  JSONExtractBool(row_json, 'emergency')                     as emergency,
  toUUIDOrNull(JSONExtractString(row_json, 'facilityid'))    as facility_id,
  toUUIDOrNull(JSONExtractString(row_json, 'programid'))     as program_id,
  toUUIDOrNull(JSONExtractString(row_json, 'processingperiodid'))  as processing_period_id,
  toUUIDOrNull(JSONExtractString(row_json, 'supervisorynodeid'))   as supervisory_node_id,
  JSONExtractInt(row_json, 'numberofmonthsinperiod')         as number_of_months_in_period,
  parseDateTimeBestEffortOrNull(JSONExtractString(row_json, 'createddate'))   as created_date,
  parseDateTimeBestEffortOrNull(JSONExtractString(row_json, 'modifieddate'))  as modified_date,

  -- CDC watermark columns
  ts_ms                                                   as _cdc_ts_ms,
  toDateTime64(ts_ms / 1000, 3)                           as _cdc_ts,
  op                                                      as _cdc_op
from latest
