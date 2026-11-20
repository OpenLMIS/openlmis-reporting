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

-- Current-state reconstruction for requisition.requisition_line_items.
-- Incremental: only re-ranks ids whose raw events arrived after the
-- materialized watermark. Rows deleted in the source
-- are kept as tombstones (_cdc_op='d'); see stg_requisitions_with_deleted
-- for the full pattern.

with touched_ids as (
  select distinct coalesce(
    nullIf(JSONExtractString(after,  'id'), ''),
    nullIf(JSONExtractString(before, 'id'), '')
  ) as id_str
  from raw.events_openlmis_requisition_requisition_line_items
  where coalesce(
        nullIf(JSONExtractString(after,  'id'), ''),
        nullIf(JSONExtractString(before, 'id'), '')
      ) != ''
  {% if is_incremental() %}
    -- >= so that an event sharing ts_ms with the watermark is not skipped when it lands after the run
    and ts_ms >= (select coalesce(max(_cdc_ts_ms), 0) from {{ this }})
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
      -- an update and a delete of one transaction can share ts_ms; the LSN orders them
      order by e.ts_ms desc, JSONExtractUInt(e.source, 'lsn') desc, e._ingested_at desc
    ) as _rn
  from raw.events_openlmis_requisition_requisition_line_items e
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
  toUUID(JSONExtractString(row_json, 'id'))                            as id,
  toUUIDOrNull(JSONExtractString(row_json, 'requisitionid'))           as requisition_id,
  toUUIDOrNull(JSONExtractString(row_json, 'orderableid'))             as orderable_id,
  JSONExtractInt(row_json, 'orderableversionnumber')                   as orderable_version_number,
  JSONExtractInt(row_json, 'beginningbalance')                         as beginning_balance,
  JSONExtract(row_json, 'totalreceivedquantity', 'Nullable(Int64)')    as total_received_quantity,
  JSONExtract(row_json, 'totalconsumedquantity', 'Nullable(Int64)')    as total_consumed_quantity,
  JSONExtractInt(row_json, 'totallossesandadjustments')                as total_losses_and_adjustments,
  JSONExtract(row_json, 'stockonhand', 'Nullable(Int64)')              as stock_on_hand,
  JSONExtractInt(row_json, 'totalstockoutdays')                        as total_stockout_days,
  JSONExtract(row_json, 'averageconsumption', 'Nullable(Int64)')       as average_consumption,
  JSONExtract(row_json, 'adjustedconsumption', 'Nullable(Int64)')      as adjusted_consumption,
  JSONExtract(row_json, 'maxperiodsofstock', 'Nullable(Float64)')      as max_periods_of_stock,
  JSONExtractInt(row_json, 'calculatedorderquantity')                  as calculated_order_quantity,
  JSONExtractInt(row_json, 'requestedquantity')                        as requested_quantity,
  JSONExtractInt(row_json, 'approvedquantity')                         as approved_quantity,
  JSONExtractInt(row_json, 'packstoship')                              as packs_to_ship,
  JSONExtractFloat(row_json, 'priceperpack')                           as price_per_pack,
  JSONExtract(row_json, 'totalcost', 'Nullable(Float64)')              as total_cost,
  JSONExtractBool(row_json, 'skipped')                                 as skipped,
  JSONExtractBool(row_json, 'nonfullsupply')                           as non_full_supply,

  -- CDC watermark columns
  ts_ms                                                             as _cdc_ts_ms,
  toDateTime64(ts_ms / 1000, 3)                                     as _cdc_ts,
  op                                                                as _cdc_op
from latest
