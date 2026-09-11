{{
  config(
    materialized='table',
    engine='MergeTree()',
    order_by='(product_code, period_end_date, facility_name)',
    settings={'allow_nullable_key': 1}
  )
}}

-- Logistics summary: rows of mart_stock_status filtered to the top 5
-- products by total consumption in the latest reporting month, PER
-- PROGRAM. The original global top-5 all came from the highest-volume
-- program, so filtering the dashboard to any other program showed an
-- empty report ("Logistics Summary is always blank" in the client
-- review). Replicates the legacy "Logistics Summary Report" chart's
-- subquery filter (Superset blocks subqueries in adhoc_filters, so we
-- materialize the selection as its own mart). Refreshed on every build.

with latest_month as (
  -- Anchor the "current month" on the latest COMPLETE reporting month.
  -- The newest month present in the data is structurally partial (real
  -- data: 7% of facilities vs 96% the month before), so anchoring on
  -- max(period_end_date) would rank products from a sliver of the network.
  select month as month_start
  from {{ ref('mart_month_completeness') }}
  where family = 'stock'
    and is_latest_complete = 1
),

top_products as (
  -- keys aliased so they cannot collide with s.program_name / s.product_name:
  -- with the same name on both sides of the join the ClickHouse analyser emits the
  -- qualified name into the output, and the table ends up carrying a column
  -- literally called "s.product_name"
  select program_name as tp_program_name, product_name as tp_product_name
  from (
    select
      program_name,
      product_name,
      row_number() over (
        partition by program_name
        order by sum(total_consumed_quantity) desc
      ) as consumption_rank
    from {{ ref('mart_stock_status') }}
    cross join latest_month
    -- Bound on both sides: >= alone would let the structurally partial
    -- months AFTER the complete anchor month leak into the ranking.
    where period_end_date >= latest_month.month_start
      and period_end_date < addMonths(latest_month.month_start, 1)
      and total_consumed_quantity is not null
    group by program_name, product_name
  )
  where consumption_rank <= 5
)

select
  s.*,
  -- Month completeness, so the report can hide the structurally partial newest
  -- month the way every other chart on this dashboard already does. A missing
  -- flag row degrades to "complete" (ClickHouse fills a LEFT JOIN miss with the
  -- type default, not NULL), so a stale flags table can never blank the report.
  if(mc.month = toDate(0), 1, mc.is_complete) as in_complete_month
from {{ ref('mart_stock_status') }} s
inner join top_products tp
  on s.program_name = tp.tp_program_name
 and s.product_name = tp.tp_product_name
left join (
  select month, is_complete
  from {{ ref('mart_month_completeness') }}
  where family = 'stock'
) mc
  on mc.month = toStartOfMonth(s.period_end_date)
