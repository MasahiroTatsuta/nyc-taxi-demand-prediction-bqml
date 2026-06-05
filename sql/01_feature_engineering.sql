-- NYCタクシーの乗車実績と気象データを結合し、ドメイン知識に基づく特徴量を生成する
CREATE OR REPLACE TABLE `your_project.your_dataset.nyc_taxi_features` AS
WITH base_taxi_data AS (
  -- 1. エリア（Pickup Zone）× 1時間ごとの乗車台数（需要）をカウント
  SELECT
    DATETIME_TRUNC(pickup_datetime, HOUR) AS pickup_hour_ts,
    INT64(pickup_location_id) AS pickup_zone,
    COUNT(1) AS actual_demand
  FROM
    `bigquery-public-data.new_york_taxi_trips.tlc_yellow_trips_2022`
  WHERE
    pickup_datetime BETWEEN '2022-01-01' AND '2022-02-28'
  GROUP BY
    1, 2
),
weather_data AS (
  -- 2. セントラルパーク観測所の気象データ（気温・降水量）を取得・加工
  SELECT
    PARSE_DATETIME('%Y%m%d%H', CONCAT(year, mo, da, '00')) AS weather_date, -- 日単位のデータを日時の開始に合わせる
    (temp - 32) * 5 / 9 AS mean_temperature, -- 華氏から摂氏へ変換
    IF(prcp > 0.0, 1, 0) AS is_rainy_day
  FROM
    `bigquery-public-data.noaa_gsod.gsod2022`
  WHERE
    stn = '725053' -- NYC CENTRAL PARK のステーションID
),
enriched_features AS (
  -- 3. 時系列のラグ（過去データ）や需要の加速度、エリア特性のフラグを生成
  SELECT
    t.pickup_hour_ts,
    t.pickup_zone,
    t.actual_demand,
    
    -- カレンダー・時間帯特徴量
    EXTRACT(HOUR FROM t.pickup_hour_ts) AS hour_of_day,
    EXTRACT(DAYOFWEEK FROM t.pickup_hour_ts) AS day_of_week,
    IF(EXTRACT(DAYOFWEEK FROM t.pickup_hour_ts) IN (1, 7), 1, 0) AS is_weekend,
    
    -- 潮目の変化（ラグ特徴量：1時間前、24時間前、1週間前）
    LAG(t.actual_demand, 1) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts) AS lag_1h,
    LAG(t.actual_demand, 24) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts) AS lag_24h,
    LAG(t.actual_demand, 168) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts) AS lag_168h,
    
    -- 需要の勢い（直近3時間の移動平均 ＆ 需要の加速度・トレンド）
    AVG(t.actual_demand) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS moving_avg_3h,
    (
      LAG(t.actual_demand, 1) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts) - 
      LAG(t.actual_demand, 2) OVER(PARTITION BY t.pickup_zone ORDER BY t.pickup_hour_ts)
    ) AS demand_velocity, -- 1時間前と2時間前の差分（需要の加速度）
    
    -- エリア特性フラグ（JFK空港: 132, ラガーディア空港: 138 など主要スポットのドメイン知識）
    IF(t.pickup_zone IN (132, 138, 230, 161, 162, 234), 1, 0) AS is_hotspot,
    IF(t.pickup_zone IN (132, 138), 1, 0) AS is_airport
  FROM
    base_taxi_data t
)
-- 4. 最後に気象データを結合し、ラグ計算でNULLにならない期間に絞り込む
SELECT
  f.*,
  w.mean_temperature,
  w.is_rainy_day
FROM
  enriched_features f
LEFT JOIN
  weather_data w
ON
  DATETIME_TRUNC(f.pickup_hour_ts, DAY) = w.weather_date
WHERE
  f.lag_168h IS NOT NULL; -- 最初の1週間分のラグ欠損を排除