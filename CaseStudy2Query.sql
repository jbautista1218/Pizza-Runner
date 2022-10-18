USE pizza_runner;

DROP TABLE IF EXISTS customer_orders_clean;
CREATE TEMPORARY TABLE customer_orders_clean AS (
	SELECT order_id, customer_id, pizza_id,
		CASE
			WHEN exclusions = '' THEN NULL
            WHEN exclusions = 'null' THEN NULL
            ELSE exclusions
		END AS exclusions,
		CASE 
			WHEN extras = '' THEN NULL
            WHEN extras = 'null' THEN NULL
            ELSE extras
		END AS extras,
        order_time
	FROM customer_orders
    );
    
DROP TABLE IF EXISTS runner_orders_clean;
CREATE TEMPORARY TABLE runner_orders_clean AS (
	SELECT order_id, runner_id,
		CASE
			WHEN pickup_time = 'null' THEN NULL
            ELSE pickup_time
		END AS pickup_time,
        CASE
			WHEN distance = 'null' THEN NULL 
            WHEN distance LIKE '%km' THEN TRIM('km' FROM distance)
            ELSE distance
		END AS distance,
        CASE
			WHEN duration = 'null' THEN NULL
            WHEN duration LIKE '%mins' THEN TRIM('mins' FROM duration)
			WHEN duration LIKE '%minute' THEN TRIM('minute' FROM duration)
            WHEN duration LIKE '%minutes' THEN TRIM('minutes' FROM duration)
            ELSE duration
		END AS duration,
		CASE
			WHEN cancellation = '' THEN NULL
            WHEN cancellation = 'null' THEN NULL
            ELSE cancellation
		END AS cancellation
	FROM runner_orders
    );

alter table runner_orders_clean
 modify column pickup_time datetime null,
 modify column distance decimal(5,1) null,
 modify column duration int null;

SELECT *
FROM customer_orders_clean;

SELECT *
FROM runner_orders_clean;
	
-- A. Pizza Metrics
-- How many pizzas were ordered?
SELECT COUNT(*) AS pizzas_ordered
FROM customer_orders_clean;

-- How many unique customer orders were made?
SELECT COUNT(DISTINCT(order_id)) AS unique_customer_orders
FROM customer_orders_clean;

-- How many successful orders were delivered by each runner?
SELECT runner_id, COUNT(order_id) AS successful_orders
FROM runner_orders_clean
WHERE cancellation IS NULL
GROUP BY runner_id;

-- How many of each type of pizza was delivered?
SELECT p.pizza_id, p.pizza_name, count(pizza_name) AS delivered_pizza_count
FROM customer_orders_clean c
JOIN pizza_names p ON c.pizza_id = p.pizza_id
JOIN runner_orders_clean r ON r.order_id = c.order_id
WHERE r.cancellation IS NULL
GROUP BY p.pizza_name;

-- How many Vegetarian and Meatlovers were ordered by each customer?
SELECT c.customer_id, p.pizza_id, p.pizza_name, count(pizza_name) AS times_ordered
FROM customer_orders_clean c
JOIN pizza_names p ON c.pizza_id = p.pizza_id
JOIN runner_orders_clean r ON r.order_id = c.order_id
GROUP BY c.customer_id, p.pizza_name;

-- What was the maximum number of pizzas delivered in a single order?
WITH pizza_count AS (
	SELECT c.order_id, COUNT(c.pizza_id) AS pizza_per_order
    FROM customer_orders_clean c
    JOIN runner_orders_clean r ON c.order_id = r.order_id
    WHERE r.cancellation IS NULL
    GROUP BY c.order_id
    )
SELECT MAX(pizza_per_order) AS most_pizzas_delivered
FROM pizza_count;

-- For each customer, how many delivered pizzas had at least 1 change and how many had no changes?
SELECT c.customer_id,
	SUM(CASE
		WHEN c.exclusions IS NULL AND c.extras IS NULL THEN 1
        ELSE 0 
        END) AS no_change,
	SUM(CASE
		WHEN c.exclusions IS NOT NULL OR c.extras IS NOT NULL THEN 1
        ELSE 0
        END) AS atleast_1_change
FROM customer_orders_clean c
JOIN runner_orders_clean r ON c.order_id = r.order_id
WHERE r.cancellation IS NULL
GROUP BY c.customer_id;

-- How many pizzas were delivered that had both exclusions and extras?
SELECT 
	SUM(CASE
		WHEN c.exclusions IS NOT NULL AND c.extras IS NOT NULL THEN 1
        ELSE 0 
        END) AS exclusions_and_extras
FROM customer_orders_clean c
JOIN runner_orders_clean r ON c.order_id = r.order_id
WHERE r.cancellation IS NULL;

-- What was the total volume of pizzas ordered for each hour of the day?
select extract(hour from order_time) as Hourlydata, count(order_id) as TotalPizzaOrdered
from customer_orders_clean
group by Hourlydata
order by Hourlydata;

-- What was the volume of orders for each day of the week?
select dayname(order_time) as DailyData, count(order_id) as TotalPizzaOrdered
from customer_orders_clean
group by DailyData
order by TotalPizzaOrdered desc;

-- B. Runner and Customer Experience 
-- How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)
select week(registration_date) as Registration_Week, count(runner_id) as Runners_Registered 
from runners
group by Registration_Week;

-- What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
select runner_id, round(avg(timestampdiff(minute,order_time, pickup_time)),1) as AvgTime
from runner_orders_clean r
inner join customer_orders_clean c
on c.order_id = r.order_id
where distance != 0
group by runner_id
order by AvgTime;

-- Is there any relationship between the number of pizzas and how long the order takes to prepare?
with cte as(
	select c.order_id, count(c.order_id) as PizzaCount, round((timestampdiff(minute, order_time, pickup_time))) as AvgTime
	from customer_orders_clean as c
	inner join runner_orders_clean as r
	on c.order_id = r.order_id
	where distance != 0 
	group by c.order_id
    )
select PizzaCount, Avgtime
from cte
group by PizzaCount;

-- What was the average distance travelled for each customer?
select customer_id, avg(distance)
from runner_orders_clean r
join customer_orders_clean c on r.order_id = c.order_id
group by customer_id;

-- What was the difference between the longest and shortest delivery times for all orders?
select (max(duration) - min(duration)) as biggest_difference
from runner_orders_clean;

-- What was the average speed for each runner for each delivery and do you notice any trend for these values?
with cte as (
	select runner_id, order_id, round(distance *60/duration,1) as speed_KPH
	from runner_orders_clean
	where distance != 0
	group by runner_id, order_id
    )
select * 
from cte
order by runner_id;

-- What is the successful delivery percentage for each runner?
with cte as(
	select runner_id, 
    sum(case
		when distance != 0 then 1
		else 0
		end) as successful, 
    count(order_id) as TotalOrders
	from runner_orders_clean
	group by runner_id
    )
select runner_id, round((successful/TotalOrders)*100) as SuccessfulPercentage 
from cte
order by runner_id;

-- C. Ingredient Optimisation
-- Normalize Pizza Recipe table
drop table if exists pizza_recipes1;
create table pizza_recipes1 
(pizza_id int, toppings int);
insert into pizza_recipes1
(pizza_id, toppings) 
values
(1,1),
(1,2),
(1,3),
(1,4),
(1,5),
(1,6),
(1,8),
(1,10),
(2,4),
(2,6),
(2,7),
(2,9),
(2,11),
(2,12);

-- What are the standard ingredients for each pizza?
with cte as (
	select pizza_names.pizza_name,pizza_recipes1.pizza_id, pizza_toppings.topping_name
	from pizza_recipes1
	inner join pizza_toppings
	on pizza_recipes1.toppings = pizza_toppings.topping_id
	inner join pizza_names
	on pizza_names.pizza_id = pizza_recipes1.pizza_id
	order by pizza_name, pizza_recipes1.pizza_id
    )
select pizza_name, group_concat(topping_name) as StandardToppings
from cte
group by pizza_name;

-- If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - how much money has Pizza Runner made so far if there are no delivery fees?
select sum(case
	when c.pizza_id = 1 then 12
    else 10
    end) as Total_Cost
from runner_orders_clean r
join customer_orders_clean c on r.order_id = c.order_id
where distance is not null;
