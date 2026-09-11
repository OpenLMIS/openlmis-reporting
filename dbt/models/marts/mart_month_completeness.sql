{{
  config(
    materialized='table',
    engine='MergeTree()',
    order_by='(family, month)'
  )
}}

-- Month-completeness flags for the trend and snapshot charts. The newest
-- reporting month is structurally partial (facilities keep submitting for
-- roughly two months), so SUM/AVG trends plunge on their last point and
-- "latest month" snapshots would show a fraction of the network. Measured
-- on real data: the newest month carried 7% of the usual facilities while
-- the month before it carried 96% - a coverage threshold against the
-- preceding months separates the two cleanly.
--
-- One row per (family, month). A month is complete when its activity
-- reaches var('month_completeness_threshold', 0.8) of the best of the
-- three preceding months; the first months of history, with nothing to
-- compare against, count as complete. Families measure the activity that
-- matters to their charts:
--   stock       - distinct facilities with stock lines  (mart_stock_status)
--   reporting   - submitted reports                      (mart_reporting_status;
--                 obligations exist in advance, so they cannot be the yardstick)
--   adjustments - distinct facilities with adjustments   (mart_adjustments)
--
-- A month must also carry a comparable BASE, which is the population the
-- activity is measured against: obligations for reporting, and the activity
-- itself for the other two families, where the two are the same thing. This
-- catches a month whose cohort changed rather than whose data is late, and
-- there is a live example: the weekly reporting schedule stops generating
-- periods in April 2026, so May 2026 carries 6,072 obligations against 9,284
-- the month before. Reported volume held, so the activity signal alone called
-- May complete, and the pooled reporting rate jumped 51.4% to 75.8% on the
-- final point of every trend - a composition change reading as improvement.
--
-- Rebuilt on every dbt run (one aggregation per family), so the flags track
-- the data as months fill in. Charts consume the flags through the dataset
-- layer; the incremental marts themselves stay untouched.

with monthly as (

  select
    'stock'                              as family,
    toStartOfMonth(period_end_date)      as month,
    uniqExact(facility_id)               as units,
    uniqExact(facility_id)               as base
  from {{ ref('mart_stock_status') }}
  group by month

  union all

  select
    'reporting'                          as family,
    toStartOfMonth(period_end_date)      as month,
    -- Actual reports, and deliberately NOT following the skip policy: this measures how
    -- much data arrived in a month, so a skipped period contributes nothing whatever the
    -- reporting rate is later decided to count. Changing this shifts in_complete_month,
    -- which gates the months every reporting chart draws.
    countIf(reporting_status = 'Reported') as units,
    count()                                as base
  from {{ ref('mart_reporting_status') }}
  group by month

  union all

  select
    'adjustments'                        as family,
    toStartOfMonth(period_end_date)      as month,
    uniqExact(facility_id)               as units,
    uniqExact(facility_id)               as base
  from {{ ref('mart_adjustments') }}
  group by month

),

with_ratio as (

  select
    family,
    month,
    units,
    base,
    units / nullIf(
      max(units) over (
        partition by family
        order by month
        rows between 3 preceding and 1 preceding
      ), 0)                              as coverage_ratio,
    base / nullIf(
      max(base) over (
        partition by family
        order by month
        rows between 3 preceding and 1 preceding
      ), 0)                              as base_ratio
  from monthly

),

flagged as (

  select
    family,
    month,
    units,
    base,
    coverage_ratio,
    base_ratio,
    -- both signals must pass: late data fails the first, a changed cohort the
    -- second. For stock and adjustments the two are the same measure, so the
    -- base test is a no-op there by construction.
    if((coverage_ratio is null
        or coverage_ratio >= {{ var('month_completeness_threshold', 0.8) }})
       and (base_ratio is null
        or base_ratio >= {{ var('month_completeness_threshold', 0.8) }}),
       1, 0)                             as is_complete
  from with_ratio

)

select
  family,
  month,
  units,
  base,
  round(coverage_ratio, 3)               as coverage_ratio,
  round(base_ratio, 3)                   as base_ratio,
  is_complete,
  if(is_complete = 1
     and month = max(if(is_complete = 1, month, toDate(0)))
                   over (partition by family),
     1, 0)                               as is_latest_complete
from flagged
