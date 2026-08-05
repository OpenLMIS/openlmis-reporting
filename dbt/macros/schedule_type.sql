{% macro schedule_type(period_start, period_end) %}
{#- Reporting cadence from period length (max span per bucket: week 7d, month 31d,
    quarter 92d; longer -> BUQ). Shared by all marts so the logic can't drift. -#}
multiIf(
  dateDiff('day', {{ period_start }}, {{ period_end }}) <= 7,  'Weekly',
  dateDiff('day', {{ period_start }}, {{ period_end }}) <= 31, 'Monthly',
  dateDiff('day', {{ period_start }}, {{ period_end }}) <= 92, 'Quarterly',
  'BUQ'
)
{% endmacro %}
