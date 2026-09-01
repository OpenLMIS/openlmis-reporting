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
-- Rebuilt on every dbt run (one aggregation per family), so the flags track
-- the data as months fill in. Charts consume the flags through the dataset
-- layer; the incremental marts themselves stay untouched.

with monthly as (

  select
    'stock'                              as family,
    toStartOfMonth(period_end_date)      as month,
    uniqExact(facility_id)               as units
  from {{ ref('mart_stock_status') }}
  group by month

  union all

  select
    'reporting'                          as family,
    toStartOfMonth(period_end_date)      as month,
    countIf(reporting_status = 'Reported') as units
  from {{ ref('mart_reporting_status') }}
  group by month

  union all

  select
    'adjustments'                        as family,
    toStartOfMonth(period_end_date)      as month,
    uniqExact(facility_id)               as units
  from {{ ref('mart_adjustments') }}
  group by month

),

with_ratio as (

  select
    family,
    month,
    units,
    units / nullIf(
      max(units) over (
        partition by family
        order by month
        rows between 3 preceding and 1 preceding
      ), 0)                              as coverage_ratio
  from monthly

),

flagged as (

  select
    family,
    month,
    units,
    coverage_ratio,
    if(coverage_ratio is null
       or coverage_ratio >= {{ var('month_completeness_threshold', 0.8) }},
       1, 0)                             as is_complete
  from with_ratio

)

select
  family,
  month,
  units,
  round(coverage_ratio, 3)               as coverage_ratio,
  is_complete,
  if(is_complete = 1
     and month = max(if(is_complete = 1, month, toDate(0)))
                   over (partition by family),
     1, 0)                               as is_latest_complete
from flagged
