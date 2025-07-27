--Query to select the database to use incase many databases
Use retail_orders;

--Query to create table in retail orders database
create table orders(
	order_id int primary key,
	order_date date,
	ship_mode varchar(20),
	segment varchar(20),
	country varchar(20),
	city varchar(20),
	state varchar(20),
	postal_code varchar(20),
	region varchar(20),
	category varchar(20),
	sub_category varchar(20),
	product_id varchar(50),
	quantity int,
	discount decimal(7, 2),
	sale_price decimal(7, 2),
	profit decimal(7, 2)
)

--Query to view data inserted in the table
select * from orders order by order_date desc;

-------------------------------------------------------------
----------------Data Analysis Queries------------------------
-------------------------------------------------------------

--1. Find top 10 highest revenue generating products
Select Top 10 
	product_id, 
	SUM(sale_price) AS sales
From orders
Group By product_id
Order By sales desc 

--2. Find top 5 highest selling products in each region
SELECT *
FROM (
    SELECT 
        region,
        product_id,
        SUM(sale_price) AS sales,
        ROW_NUMBER() OVER(PARTITION BY region ORDER BY SUM(sale_price) DESC) as rank
    FROM orders
    GROUP BY region, product_id
) as cte
WHERE rank <= 5;

--3. Find month over month growth comparison for 2022 & 2023 sales
with cte as(
select 
YEAR(order_date) as order_year,
MONTH(order_date) as order_month,
SUM(sale_price) as sales
From orders
group by YEAR(order_date), MONTH(order_date)
)
select 
order_month,
SUM(case when order_year=2022 then sales else 0 end) as sales_2022,
SUM(case when order_year=2023 then sales else 0 end) as sales_2023
from cte
group by order_month
order by order_month

--Alternative Query
SELECT 
    MONTH(order_date) as order_month,
    SUM(CASE WHEN YEAR(order_date) = 2022 THEN sale_price ELSE 0 END) as sales_2022,
    SUM(CASE WHEN YEAR(order_date) = 2023 THEN sale_price ELSE 0 END) as sales_2023
FROM orders
WHERE YEAR(order_date) IN (2022, 2023)
GROUP BY MONTH(order_date)
ORDER BY order_month;

--4. For each category which had month had higher sales
with cte as(
select
category,
format(order_date, 'yyyyMM') as order_year_month,
SUM(sale_price) as sales
from orders
group by category, format(order_date, 'yyyyMM')
)
select * from(
select *,
ROW_NUMBER() over(partition by category order by sales desc) as rank
from cte
) a
where rank=1

--Alternative query
WITH cte AS (
  SELECT
    category,
    DATEADD(DAY, 1 - DAY(order_date), order_date) as order_first_day_of_month, -- get the first day of the month
    SUM(sale_price) as sales
  FROM orders
  GROUP BY category, DATEADD(DAY, 1 - DAY(order_date), order_date) -- use the first day of the month for grouping
)
SELECT *
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) AS rank
  FROM cte
) a
WHERE rank = 1

---5. Which subcategory had highest growth by profit in 2023 compare to 2022
with cte as (
select 
sub_category, 
year(order_date) as order_year,
sum(sale_price) as sales
from orders
group by sub_category, year(order_date)
),
cte2 as(
select 
sub_category,
sum(case when order_year=2022 then sales else 0 end) as sales_2022,
sum(case when order_year=2023 then sales else 0 end) as sales_2023
from cte
group by sub_category
)
select *,
(sales_2023 - sales_2022)*100/sales_2022 as percentage_growth
from cte2
order by percentage_growth desc

--Alternative query
with cte as (
    select 
        sub_category, 
        year(order_date) as order_year,
        sum(sale_price) as sales
    from orders
    group by sub_category, year(order_date)
)
select 
    sub_category,
    sum(case when order_year=2022 then sales else 0 end) as sales_2022,
    sum(case when order_year=2023 then sales else 0 end) as sales_2023,
    (sum(case when order_year=2023 then sales else 0 end) - sum(case when order_year=2022 then sales else 0 end)) * 100.0 / sum(case when order_year=2022 then sales else 0 end) as percentage_growth
from cte
group by sub_category
order by percentage_growth desc