# Retail Orders Analysis: Python ETL into SQL Server + SQL Business Analytics

[![Python](https://img.shields.io/badge/ETL-Python%20%2B%20pandas-3776AB?logo=python)](https://pandas.pydata.org/)
[![SQLAlchemy](https://img.shields.io/badge/Load-SQLAlchemy%20%2B%20pyodbc-D71F00)](https://www.sqlalchemy.org/)
[![SQL Server](https://img.shields.io/badge/Warehouse-Microsoft%20SQL%20Server-CC2927?logo=microsoftsqlserver)](https://www.microsoft.com/sql-server)
[![Kaggle](https://img.shields.io/badge/Dataset-Kaggle%20Retail%20Orders-20BEFF?logo=kaggle)](https://www.kaggle.com/datasets/ankitbansal06/retail-orders)

An end-to-end mini data engineering project that takes a raw retail orders CSV from **Kaggle**, cleans and enriches it with **pandas** (null handling, column standardisation, derived discount / sale price / profit), loads it into **Microsoft SQL Server** with **SQLAlchemy + pyodbc**, and answers five business questions in **T-SQL** using **CTEs, window functions and conditional aggregation**: top products, top products per region, 2022 vs 2023 month-over-month sales, best month per category, and the fastest-growing sub-categories.

---

## 1. Pipeline Architecture & End-to-End Data Flow

### End-to-End Execution Flow
$$\text{Kaggle CSV} \xrightarrow{\text{pandas}} \text{Cleaned DataFrame} \xrightarrow{\text{SQLAlchemy to\_sql}} \text{SQL Server: retail\_orders.orders} \xrightarrow{\text{T-SQL}} \text{Business insights}$$

1. **Extract:** `retail-orders.csv` (9,994 orders, 2022–2023) is downloaded from Kaggle and read with pandas.
2. **Clean:** `"Not Available"` and `"unknown"` are read as nulls (e.g. in `Ship Mode`); column names are lower-cased and snake_cased.
3. **Transform:** `discount`, `sale_price` and `profit` are derived from list price, discount % and cost price; `order_date` is cast to datetime; raw price columns are dropped.
4. **Load:** A SQLAlchemy engine connects to SQL Server over ODBC Driver 17 and appends the DataFrame to the pre-created `orders` table.
5. **Analyse:** `retail-orders-analysis-query-file.sql` runs five analytical queries (each with an alternative formulation).

---

## 2. Component Directory

| Component | Technology | Purpose / Function in Solution | Details |
| :--- | :--- | :--- | :--- |
| **`Retail Orders Analysis.ipynb`** | Jupyter + pandas | Extract, clean, transform and load | 8 sequential steps, documented inline |
| **SQLAlchemy engine** | `sqlalchemy` + `pyodbc` | Connection to SQL Server | `mssql://` URL with `ODBC Driver 17 for SQL Server` |
| **`retail_orders` database** | Microsoft SQL Server (Express) | Analytical store | Single `orders` table with typed columns |
| **`retail-orders-analysis-query-file.sql`** | T-SQL | DDL + five analytical queries | CTEs, `ROW_NUMBER()`, `CASE` pivots, `FORMAT`, `DATEADD` |

---

## 3. Engineering Decisions

| Concern | Naive Approach | This Implementation | Justification |
| :--- | :--- | :--- | :--- |
| **Nulls** | Leave placeholder strings | **`na_values=['Not Available', 'unknown']`** at read time | Real nulls from the start; no string matching later |
| **Column names** | Keep `Order Id`, `Ship Mode` | **`lower()` + spaces → `_`** | Matches SQL column names exactly, so `to_sql` maps cleanly |
| **Money columns** | Store list price, cost and discount % | **Derive `discount`, `sale_price`, `profit`; drop the inputs** | The warehouse holds the measures analysts actually use |
| **Table creation** | Let `to_sql` create the table | **Create the table in SQL first, then `if_exists='append'`** | Keeps control of data types (`DECIMAL(7,2)`, `DATE`, `VARCHAR` sizes) and the primary key |
| **Top-N per group** | Correlated subqueries | **`ROW_NUMBER() OVER (PARTITION BY ...)`** | One pass, readable and index-friendly |
| **Year-over-year** | Self-join two years | **Conditional aggregation (`SUM(CASE WHEN year = ...)`)** | Pivots both years side by side in one query |

---

## 4. Phase 1: Extract & Clean (pandas)

```python
df = pd.read_csv(file_path, na_values=['Not Available', 'unknown'])
df.columns = df.columns.str.lower().str.replace(' ', '_')
```

---

## 5. Phase 2: Transform

```python
df['discount']   = df['list_price'] * df['discount_percent'] * .01
df['sale_price'] = df['list_price'] - df['discount']
df['profit']     = df['sale_price'] - df['cost_price']

df['order_date'] = pd.to_datetime(df['order_date'], format="%Y-%m-%d")
df.drop(['cost_price', 'list_price', 'discount_percent'], axis=1, inplace=True)
```

---

## 6. Phase 3: Load into SQL Server

### Target table
```sql
CREATE TABLE orders (
    order_id     INT PRIMARY KEY,
    order_date   DATE,
    ship_mode    VARCHAR(20),
    segment      VARCHAR(20),
    country      VARCHAR(20),
    city         VARCHAR(20),
    state        VARCHAR(20),
    postal_code  VARCHAR(20),
    region       VARCHAR(20),
    category     VARCHAR(20),
    sub_category VARCHAR(20),
    product_id   VARCHAR(50),
    quantity     INT,
    discount     DECIMAL(7,2),
    sale_price   DECIMAL(7,2),
    profit       DECIMAL(7,2)
);
```

### Append from pandas
```python
import sqlalchemy as sa
server, database = r"<SERVER>\SQLEXPRESS", "retail_orders"
driver = "ODBC+DRIVER+17+FOR+SQL+SERVER"
engine = sa.create_engine(f"mssql://{server}/{database}?driver={driver}")
conn = engine.connect()
df.to_sql('orders', con=conn, index=False, if_exists='append')
```

---

## 7. Phase 4: SQL Business Analytics

| # | Business Question | Technique |
| :--- | :--- | :--- |
| 1 | Top 10 revenue-generating products | `TOP 10` + `GROUP BY` |
| 2 | Top 5 selling products in each region | `ROW_NUMBER() OVER (PARTITION BY region ...)` |
| 3 | Month-over-month sales, 2022 vs 2023 | CTE + conditional aggregation |
| 4 | Best sales month for each category | `FORMAT(order_date, 'yyyyMM')` or `DATEADD` month start + `ROW_NUMBER()` |
| 5 | Sub-category with the highest growth, 2023 vs 2022 | Two CTEs + % growth (calculated on sales) |

### Example: top 5 products per region
```sql
SELECT *
FROM (
    SELECT region, product_id, SUM(sale_price) AS sales,
           ROW_NUMBER() OVER (PARTITION BY region ORDER BY SUM(sale_price) DESC) AS rank
    FROM orders
    GROUP BY region, product_id
) AS cte
WHERE rank <= 5;
```

### Example: 2022 vs 2023 by month
```sql
SELECT MONTH(order_date) AS order_month,
       SUM(CASE WHEN YEAR(order_date) = 2022 THEN sale_price ELSE 0 END) AS sales_2022,
       SUM(CASE WHEN YEAR(order_date) = 2023 THEN sale_price ELSE 0 END) AS sales_2023
FROM orders
WHERE YEAR(order_date) IN (2022, 2023)
GROUP BY MONTH(order_date)
ORDER BY order_month;
```

---

## 8. Repository Structure

```text
data-engineering-retail-orders-analysis/
├── README.md
├── LICENSE
├── Retail Orders Analysis.ipynb              <-- Extract, clean, transform, load
└── retail-orders-analysis-query-file.sql     <-- Table DDL + analytical queries
```

The dataset is not stored in the repo; download it from [Kaggle](https://www.kaggle.com/datasets/ankitbansal06/retail-orders).

---

## 9. Complete Step-by-Step Reproduction Guide

### Step 1: Get the Data
Download `retail-orders.csv` from [Kaggle – Retail Orders](https://www.kaggle.com/datasets/ankitbansal06/retail-orders).

### Step 2: Prepare SQL Server
1. Install SQL Server (Express is fine) and **ODBC Driver 17 for SQL Server**.
2. Create the database and table:
   ```sql
   CREATE DATABASE retail_orders;
   GO
   USE retail_orders;
   -- run the CREATE TABLE orders statement from the .sql file
   ```

### Step 3: Install Python Packages
```bash
pip install pandas sqlalchemy pyodbc jupyter
```

### Step 4: Run the Notebook
1. Open `Retail Orders Analysis.ipynb`.
2. Set `file_path` to your CSV location and the server name to your SQL Server instance.
3. Run all cells; the last step appends 9,994 rows to `orders`.

### Step 5: Run the Analysis
Execute the queries in `retail-orders-analysis-query-file.sql` in SSMS or Azure Data Studio.

---

## Future Improvements
* Turn the notebook into a scheduled, parameterised ETL script.
* Add a Power BI or Tableau dashboard on top of the `orders` table.
* Add demand-forecasting models.

---

## Contact
**Alwyn Munatsi** — [LinkedIn](https://www.linkedin.com/in/alwynmunatsi) · munatsialwyn@gmail.com
