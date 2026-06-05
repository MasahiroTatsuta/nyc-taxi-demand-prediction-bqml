-- 1. 機械学習モデル（勾配ブースティングツリー）の構築と学習の実行
CREATE OR REPLACE MODEL `your_project.your_dataset.nyc_taxi_xgboost_model`
OPTIONS(
  MODEL_TYPE='BOOSTED_TREE_REGRESSOR', -- 高精度な勾配ブースティングを採用
  BOOSTER_TYPE='GBTREE',
  INPUT_LABEL_COLS=['actual_demand'], -- 予測したいターゲット（正解ラベル）
  MAX_ITERATIONS=50,                  -- 学習の最大ステップ数
  EARLY_STOP=TRUE,                    -- 過学習防止の自動早期停止
  DATA_SPLIT_METHOD='SEQ',            -- 時系列データのため、ランダムではなく時間順で分割
  DATA_SPLIT_COL='pickup_hour_ts',
  DATA_SPLIT_FRACTION=0.8             -- 80%を学習、20%を評価用に自動分割
) AS
SELECT
  *
FROM
  `your_project.your_dataset.nyc_taxi_features`
WHERE
  pickup_hour_ts < '2022-02-01 00:00:00'; -- 1月中を学習データとして使用


-- 2. 作成されたモデルの評価（検証データに対する精度確認）
SELECT
  *
FROM
  ML.EVALUATE(MODEL `your_project.your_dataset.nyc_taxi_xgboost_model`);
-- ※ ここで出力された MAE: 8.93 や R2: 0.943 をREADMEに実績として記載します


-- 3. 未知の未来（2022年2月1日の24時間）に対する需要予測の実行（Tableau用データ）
SELECT
  pickup_hour_ts,
  pickup_zone,
  actual_demand,
  predicted_actual_demand AS predicted_demand -- AIが予測した需要値
FROM
  ML.PREDICT(
    MODEL `your_project.your_dataset.nyc_taxi_xgboost_model`,
    (
      SELECT * 
      FROM `your_project.your_dataset.nyc_taxi_features` 
      WHERE pickup_hour_ts BETWEEN '2022-02-01 00:00:00' AND '2022-02-01 23:00:00'
    )
  )
ORDER BY
  pickup_hour_ts ASC,
  pickup_zone ASC;