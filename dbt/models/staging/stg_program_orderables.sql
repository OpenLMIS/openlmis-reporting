{{
  config(
    materialized='view'
  )
}}

-- Current-state reconstruction for referencedata.program_orderables:
-- the catalog assignment of orderables to programs. A product can belong
-- to several programs at once, and active assignment rows exist per
-- orderable VERSION (the source unique index includes
-- orderableversionnumber), so consumers that need one row per
-- (program, product) must aggregate over orderable_version_number.

with ranked as (
  select
    *,
    row_number() over (
      partition by coalesce(
        nullIf(JSONExtractString(after,  'id'), ''),
        nullIf(JSONExtractString(before, 'id'), '')
      )
      order by ts_ms desc, _ingested_at desc
    ) as _rn
  from raw.events_openlmis_referencedata_program_orderables
  where coalesce(
        nullIf(JSONExtractString(after,  'id'), ''),
        nullIf(JSONExtractString(before, 'id'), '')
      ) != ''
)

select
  toUUID(JSONExtractString(after, 'id'))                          as id,
  toUUIDOrNull(JSONExtractString(after, 'programid'))             as program_id,
  toUUIDOrNull(JSONExtractString(after, 'orderableid'))           as orderable_id,
  JSONExtractInt(after, 'orderableversionnumber')                 as orderable_version_number,
  JSONExtractBool(after, 'active')                                as active,
  JSONExtractBool(after, 'fullsupply')                            as full_supply,
  JSONExtractInt(after, 'displayorder')                           as display_order,
  JSONExtract(after, 'dosesperpatient', 'Nullable(Int64)')        as doses_per_patient,
  JSONExtractFloat(after, 'priceperpack')                         as price_per_pack,
  toUUIDOrNull(JSONExtractString(after, 'orderabledisplaycategoryid')) as orderable_display_category_id
from ranked
where _rn = 1
  and op != 'd'
