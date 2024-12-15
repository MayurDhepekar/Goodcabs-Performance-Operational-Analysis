
USE trips_db;
SELECT * FROM fact_trips;

DESCRIBE trips_db.fact_passenger_summary;
DESCRIBE trips_db.fact_trips;


#       Business Request - 1: City-Level Fare and Trip Summary Report 


SELECT 
    c.city_name,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.fare_amount / NULLIF(t.distance_travelled_km, 0)), 2) AS avg_fare_per_km,
    ROUND(AVG(t.fare_amount), 2) AS avg_fare_per_trip,
    CONCAT(ROUND((COUNT(t.trip_id) * 100.0 / (SELECT COUNT(*) FROM trips_db.fact_trips)), 2), '%') AS contribution_pct_total_trips
FROM 
    trips_db.fact_trips t
JOIN 
    trips_db.dim_city c ON t.city_id = c.city_id
GROUP BY 
    c.city_name;


#      Business Request - 2: Monthly City-Level Trips Target Performance Report 

SELECT 
    c.city_name,
    d.month_name,
    COALESCE(FT.actual_trips, 0) AS actual_trips,
    COALESCE(MT.total_target_trips, 0) AS target_trips,
    CASE
        WHEN COALESCE(FT.actual_trips, 0) > COALESCE(MT.total_target_trips, 0) THEN 'Above Target'
        ELSE 'Below Target'
    END AS performance_status,
    CONCAT(ROUND((COALESCE(FT.actual_trips, 0) - COALESCE(MT.total_target_trips, 0)) * 100.0 / 
    NULLIF(COALESCE(MT.total_target_trips, 0), 0), 2), '%') AS pct_difference
FROM 
    trips_db.dim_city c
CROSS JOIN 
    trips_db.dim_date d
LEFT JOIN 
    (SELECT 
         city_id, 
         DATE_FORMAT(date, '%M') AS month_name, -- Extract month name from 'date' in fact_trips table
         COUNT(*) AS actual_trips
     FROM 
         trips_db.fact_trips
     GROUP BY 
         city_id, DATE_FORMAT(date, '%M')) FT
ON 
    c.city_id = FT.city_id AND d.month_name = FT.month_name
LEFT JOIN 
    targets_db.monthly_target_trips MT
ON 
    c.city_id = MT.city_id AND d.month_name = DATE_FORMAT(MT.month, '%M');
    
    
    #     Business Request - 3: City-Level Repeat Passenger Trip Frequency Report 
    
SELECT
    c.city_name,
    -- Calculate the percentage of repeat passengers who took 2, 3, ..., 10 trips
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 2 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `2-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 3 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `3-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 4 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `4-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 5 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `5-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 6 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `6-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 7 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `7-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 8 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `8-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 9 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `9-Trips`,
    ROUND(COALESCE(SUM(CASE WHEN rt.trip_count = 10 THEN rt.repeat_passenger_count ELSE 0 END) * 100.0 / NULLIF(total.total_repeat_passengers, 0), 0), 2) AS `10-Trips`
FROM 
    trips_db.dim_city c
LEFT JOIN 
    trips_db.dim_repeat_trip_distribution rt ON c.city_id = rt.city_id
LEFT JOIN 
    (SELECT city_id, SUM(repeat_passenger_count) AS total_repeat_passengers
     FROM trips_db.dim_repeat_trip_distribution
     GROUP BY city_id) total ON c.city_id = total.city_id
GROUP BY 
    c.city_name, total.total_repeat_passengers;
    
    #     Business Request - 4: Identify Cities with Highest and Lowest Total New Passengers 
    
WITH RankedCities AS (
    SELECT 
        c.city_name,
        SUM(fps.new_passengers) AS total_new_passengers
    FROM 
        trips_db.dim_city c
    LEFT JOIN 
        trips_db.fact_passenger_summary fps 
    ON c.city_id = fps.city_id
    GROUP BY 
        c.city_name
)

-- Get the top 3 cities with the highest new passengers
(SELECT
    city_name,
    total_new_passengers,
    'Top 3' AS city_category
FROM 
    RankedCities
ORDER BY 
    total_new_passengers DESC
LIMIT 3)

UNION ALL

-- Get the bottom 3 cities with the lowest new passengers
(SELECT
    city_name,
    total_new_passengers,
    'Bottom 3' AS city_category
FROM 
    RankedCities
ORDER BY 
    total_new_passengers ASC
LIMIT 3);


#     Business Request - 5: Identify Month with Highest Revenue for Each City 

WITH CityTotalRevenue AS (
    SELECT
        c.city_name,
        DATE_FORMAT(ft.date, '%M') AS month_name,  -- Extract month name
        SUM(ft.fare_amount) AS revenue
    FROM
        trips_db.dim_city c
    LEFT JOIN
        trips_db.fact_trips ft ON c.city_id = ft.city_id
    GROUP BY
        c.city_name, month_name
),
CityRevenueSummary AS (
    SELECT
        city_name,
        month_name,
        revenue,
        ROW_NUMBER() OVER (PARTITION BY city_name ORDER BY revenue DESC) AS revenue_rank  -- Changed alias to revenue_rank
    FROM
        CityTotalRevenue
),
CityTotal AS (
    SELECT
        city_name,
        SUM(revenue) AS total_revenue
    FROM
        CityTotalRevenue
    GROUP BY
        city_name
)
SELECT
    cr.city_name,
    cr.month_name AS highest_revenue_month,
    cr.revenue,
    CONCAT(ROUND((cr.revenue / ct.total_revenue) * 100, 2), '%') AS percentage_contribution
FROM
    CityRevenueSummary cr
JOIN
    CityTotal ct ON cr.city_name = ct.city_name
WHERE
    cr.revenue_rank = 1  -- Filter to get only the month with the highest revenue
ORDER BY
    cr.city_name;


#     Business Request - 6: Repeat Passenger Rate Analysis 

WITH MonthlyRepeatRate AS (
    SELECT
        c.city_name,
        DATE_FORMAT(fps.month, '%M') AS month,  -- Using the 'month' column from fact_passenger_summary (fps)
        SUM(fps.total_passengers) AS total_passengers,
        SUM(fps.repeat_passengers) AS repeat_passengers
    FROM
        trips_db.dim_city c
    LEFT JOIN
        trips_db.fact_passenger_summary fps ON c.city_id = fps.city_id  -- fact_passenger_summary (fps) for passenger data
    GROUP BY
        c.city_name, month
),
CityRepeatRate AS (
    SELECT
        city_name,
        SUM(repeat_passengers) AS total_repeat_passengers,
        SUM(total_passengers) AS total_passengers
    FROM
        MonthlyRepeatRate
    GROUP BY
        city_name
)
SELECT
    m.city_name,
    m.month,
    m.total_passengers,
    m.repeat_passengers,
    CONCAT(ROUND((m.repeat_passengers / m.total_passengers) * 100, 2), '%') AS monthly_repeat_passenger_rate,
    CONCAT(ROUND((c.total_repeat_passengers / c.total_passengers) * 100, 2), '%') AS city_repeat_passenger_rate
FROM
    MonthlyRepeatRate m
JOIN
    CityRepeatRate c ON m.city_name = c.city_name
ORDER BY
    m.city_name, m.month;


