{{
  config(
    materialized='table',
    engine='MergeTree()',
    order_by='(program_name, facility_name, status)'
  )
}}

-- Requisition summary: requisitions enriched with facility and program names.
-- Groups by status for reporting dashboards.
-- Rolling 3-year window on the processing period's end_date, so the mart -
-- and the Period filter that reads it - only offer the same three years the
-- charts show.

select
  r.id              as requisition_id,
  r.status          as status,
  r.emergency       as emergency,
  r.created_date    as created_date,
  r.modified_date   as modified_date,
  f.code            as facility_code,
  f.name            as facility_name,
  gz.name           as geographic_zone_name,
  parent_gz.name    as parent_zone_name,
  p.code            as program_code,
  p.name            as program_name,
  pp.name           as period_name,
  pp.end_date       as period_end_date,

  -- reporting cadence (shared macro - single source of truth across marts)
  {{ schedule_type('pp.start_date', 'pp.end_date') }}
                    as schedule_type
from {{ ref('stg_requisitions') }} r
left join {{ ref('stg_facilities') }} f
  on r.facility_id = f.id
left join {{ ref('stg_geographic_zones') }} gz
  on f.geographic_zone_id = gz.id
left join {{ ref('stg_geographic_zones') }} parent_gz
  on gz.parent_id = parent_gz.id
left join {{ ref('stg_programs') }} p
  on r.program_id = p.id
left join {{ ref('stg_processing_periods') }} pp
  on r.processing_period_id = pp.id
where pp.end_date >= now() - interval 3 year
