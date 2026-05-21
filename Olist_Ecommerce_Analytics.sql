-- ============================================================
-- PROJECT   : Brazilian E-Commerce Performance Analytics
-- AUTHOR    : Supriya
-- TOOL      : Microsoft SQL Server Management Studio (v16)
-- DATASET   : Olist Brazilian E-Commerce Public Dataset
--             Source: Kaggle (olistbr/brazilian-ecommerce)
-- PERIOD    : 2016 – 2018
-- ============================================================
-- OVERVIEW
-- --------
-- Olist is a Brazilian e-commerce technology company that connects small and medium-sized businesses to major online
-- marketplaces. 
-- This dataset contains approximately 100,000 anonymized orders placed between 2016 and 2018, spanning customers, 
-- sellers, products, payments, reviews, and delivery logistics across 27 Brazilian states.
-- This project simulates the ad hoc and business analytics requests a data analyst would receive across multiple
-- departments — Customer Support, Product, Finance, Sales, and Marketing. All analysis is performed in pure SQL using
-- CTEs, window functions, and multi-table joins.
-- ============================================================

USE Olist_ECommerce;
GO

-- ============================================================
-- QUERY : Delivered Order Baseline
-- ============================================================
-- Establishes the total count of successfully delivered orders as a baseline KPI for validating all downstream
-- analyses. Canceled (625) and unavailable (609) orders are excluded from all subsequent queries.

SELECT
    COUNT(DISTINCT order_id) AS total_delivered_orders
FROM olist_orders_dataset
WHERE order_status = 'delivered';

GO

-- ============================================================
-- QUERY 1: Customer Satisfaction Rate (FY2018)
-- Requested by: Customer Support Team
-- ============================================================
-- Tracks monthly 5-star review rates for delivered orders in 2018, including average review score and month-over-
-- month change to identify satisfaction trends and anomalies.

-- Part A: Monthly Breakdown
WITH monthly_satisfaction AS (
    SELECT
        FORMAT(r.review_answer_timestamp, 'yyyy-MM') AS yearmonth,
        SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) AS five_star_reviews,
        COUNT(DISTINCT r.order_id) AS total_reviews,
        AVG(CAST(r.review_score AS FLOAT)) AS avg_score
    FROM olist_order_reviews_dataset AS r
    INNER JOIN olist_orders_dataset AS o
        ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    AND YEAR(r.review_answer_timestamp) = 2018
    GROUP BY FORMAT(r.review_answer_timestamp, 'yyyy-MM')
)

SELECT
    yearmonth,
    five_star_reviews,
    total_reviews,
    ROUND(CAST(five_star_reviews AS FLOAT) / total_reviews * 100, 2) AS five_star_pct,
    ROUND(avg_score, 2) AS avg_review_score,
    ROUND(
        CAST(five_star_reviews AS FLOAT) / total_reviews * 100 -
        LAG(CAST(five_star_reviews AS FLOAT) / total_reviews * 100)
        OVER (ORDER BY yearmonth)
    , 2) AS mom_change
FROM monthly_satisfaction
ORDER BY yearmonth;

GO

-- Part B: Annual Summary
SELECT
    YEAR(r.review_answer_timestamp) AS year,
    SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) AS five_star_reviews,
    COUNT(DISTINCT r.order_id) AS total_reviews,
    ROUND(
        CAST(SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(DISTINCT r.order_id) * 100
    , 2) AS five_star_pct,
    ROUND(AVG(CAST(r.review_score AS FLOAT)), 2) AS avg_review_score
FROM olist_order_reviews_dataset AS r
INNER JOIN olist_orders_dataset AS o
    ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
AND YEAR(r.review_answer_timestamp) = 2018
GROUP BY YEAR(r.review_answer_timestamp);

GO

/*
FINDINGS:
Overall 5-star satisfaction rate for FY2018 was 59.1% across 55,304 delivered orders.

March 2018 recorded the lowest monthly rate at 50.99% — 8.1 points below the annual average —
indicating a potential service or logistics issue during that period. Root cause analysis of March delivery times
and seller performance is recommended.

Satisfaction recovered consistently from April onward, reaching 70.97% in October 2018, suggesting
operational improvements in the second half of the year.

LAG() was applied to surface month-over-monthdirectional changes, enabling the support team to
identify inflection points without manual comparison.
*/

-- ============================================================
-- QUERY 2: Order Volume Trends (2016–2018)
-- Requested by: Product Team
-- ============================================================
-- Analyzes order volume by year, month, and year-month combination to identify growth patterns and seasonal trends.

-- Part A: Monthly Orders by Year (Pivot View)
SELECT
    Month_no,
    Month_name,
    SUM(CASE WHEN yr = 2016 THEN 1 ELSE 0 END) AS Year_2016,
    SUM(CASE WHEN yr = 2017 THEN 1 ELSE 0 END) AS Year_2017,
    SUM(CASE WHEN yr = 2018 THEN 1 ELSE 0 END) AS Year_2018
FROM (
    SELECT
        order_id,
        customer_id,
        MONTH(order_purchase_timestamp) AS Month_no,
        DATENAME(MONTH, order_purchase_timestamp) AS Month_name,
        YEAR(order_purchase_timestamp) AS yr
    FROM olist_orders_dataset
    WHERE order_status NOT IN ('unavailable', 'canceled')
) AS monthly_data
GROUP BY Month_no, Month_name
ORDER BY Month_no ASC;

GO

-- Part B: Annual Order Summary
SELECT
    YEAR(order_purchase_timestamp) AS year,
    COUNT(DISTINCT customer_id) AS total_customers,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(
        CAST(COUNT(DISTINCT order_id) AS FLOAT) /
        CAST(COUNT(DISTINCT customer_id) AS FLOAT)
    , 2) AS orders_per_customer
FROM olist_orders_dataset
WHERE order_status NOT IN ('unavailable', 'canceled')
GROUP BY YEAR(order_purchase_timestamp)
ORDER BY year;

GO

-- Part C: Year-Month Trend with Month-over-Month Growth
WITH monthly_orders AS (
    SELECT
        FORMAT(order_purchase_timestamp, 'yyyy-MM') AS yearmonth,
        COUNT(DISTINCT customer_id) AS total_customers,
        COUNT(DISTINCT order_id) AS total_orders
    FROM olist_orders_dataset
    WHERE order_status NOT IN ('unavailable', 'canceled')
    GROUP BY FORMAT(order_purchase_timestamp, 'yyyy-MM')
)

SELECT
    yearmonth,
    total_customers,
    total_orders,
    LAG(total_orders) OVER (ORDER BY yearmonth) AS prev_month_orders,
    ROUND(
        CAST(total_orders - LAG(total_orders) OVER (ORDER BY yearmonth) AS FLOAT) /
        NULLIF(LAG(total_orders) OVER (ORDER BY yearmonth), 0) * 100
    , 2) AS mom_growth_pct
FROM monthly_orders
ORDER BY yearmonth;

GO

/*
FINDINGS:
2016 order volume was negligible (296 orders),reflecting early-stage platform operations.
Sustained growth began in 2017 and continuedthrough 2018.

November 2017 recorded a significant volume spike (~7,423 orders) consistent with Brazil's Black
Friday promotional event. More notably, post- November 2017 monthly volumes stabilized at
6,000–7,000 orders — approximately double the pre-November baseline of 3,000–4,000.

This suggests Black Friday 2017 drove lasting customer acquisition rather than a one-time spike.
Whether those acquired customers demonstrated long-term retention is examined in Query 10.
*/

-- ============================================================
-- QUERY 3: Payment Method Analysis
-- Requested by: Finance Team
-- ============================================================
-- Analyzes payment type distribution by transaction volume and revenue contribution. Includes credit card installment
-- breakdown to assess customer affordability patterns.

-- Part A: Payment Method Summary
SELECT
    a.payment_type,
    COUNT(a.payment_type) AS total_transactions,
    ROUND(CAST(COUNT(a.payment_type) AS FLOAT) /
        SUM(COUNT(a.payment_type)) OVER () * 100, 2) AS transaction_pct,
    CAST(SUM(a.payment_value) AS INT) AS total_revenue,
    CAST(SUM(a.payment_value) / 1000 AS INT) AS revenue_K,
    ROUND(AVG(a.payment_value), 2) AS avg_order_value,
    ROUND(CAST(SUM(a.payment_value) AS FLOAT) /
        SUM(SUM(a.payment_value)) OVER () * 100, 2) AS revenue_pct
FROM olist_order_payments_dataset AS a
INNER JOIN olist_orders_dataset AS b
    ON a.order_id = b.order_id
WHERE b.order_status <> 'canceled'
AND b.order_delivered_customer_date IS NOT NULL
GROUP BY a.payment_type
ORDER BY total_transactions DESC;

GO

-- Part B: Credit Card Installment Distribution
SELECT
    a.payment_installments,
    COUNT(*) AS total_orders,
    ROUND(AVG(a.payment_value), 2) AS avg_order_value,
    CAST(SUM(a.payment_value) AS INT) AS total_revenue
FROM olist_order_payments_dataset AS a
INNER JOIN olist_orders_dataset AS b
    ON a.order_id = b.order_id
WHERE b.order_status <> 'canceled'
AND b.order_delivered_customer_date IS NOT NULL
AND a.payment_type = 'credit_card'
GROUP BY a.payment_installments
ORDER BY total_orders DESC;

GO

/*
FINDINGS:
Credit card accounts for 74% of transactions and R$12.1M in revenue. Credit card customers
also show a higher average order value compared to boleto and debit card users, indicating
higher spending capacity in this segment.

Boleto — a Brazilian cash-based payment slip used by unbanked consumers — represents 19%
of transactions, reflecting Brazil's historically low banking penetration (~35% at the time of
this dataset).

Installment analysis shows most credit card orders are settled in 1–3 installments, though
a notable portion extends to 8–10 months, indicating price sensitivity among higher-value
purchasers. This has implications for cash flow forecasting and promotional pricing strategy.
*/

-- ============================================================
-- QUERY 4: Product Category Revenue Performance
-- Requested by: Product Team
-- ============================================================
-- Identifies the top 10 and bottom 10 product categories by total revenue, including revenue share and average
-- order value per category.

-- Part A: Top 10 Categories by Revenue
WITH category_revenue AS (
    SELECT
        t.product_category_name_english AS category,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(p.payment_value), 2) AS total_revenue,
        ROUND(AVG(p.payment_value), 2) AS avg_order_value,
        ROUND(SUM(p.payment_value) /
            SUM(SUM(p.payment_value)) OVER () * 100, 2) AS revenue_pct,
        RANK() OVER (ORDER BY SUM(p.payment_value) DESC) AS revenue_rank
    FROM olist_products_dataset AS pr
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    LEFT JOIN olist_order_items_dataset AS i
        ON pr.product_id = i.product_id
    LEFT JOIN olist_orders_dataset AS o
        ON i.order_id = o.order_id
    LEFT JOIN olist_order_payments_dataset AS p
        ON i.order_id = p.order_id
    WHERE o.order_status <> 'canceled'
    AND o.order_delivered_customer_date IS NOT NULL
    AND t.product_category_name_english IS NOT NULL
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY t.product_category_name_english
)

SELECT TOP 10
    revenue_rank, category, total_orders,
    total_revenue, avg_order_value, revenue_pct
FROM category_revenue
ORDER BY revenue_rank ASC;

GO

-- Part B: Bottom 10 Categories by Revenue
WITH category_revenue AS (
    SELECT
        t.product_category_name_english AS category,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(p.payment_value), 2) AS total_revenue,
        ROUND(AVG(p.payment_value), 2) AS avg_order_value,
        RANK() OVER (ORDER BY SUM(p.payment_value) ASC) AS revenue_rank
    FROM olist_products_dataset AS pr
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    LEFT JOIN olist_order_items_dataset AS i
        ON pr.product_id = i.product_id
    LEFT JOIN olist_orders_dataset AS o
        ON i.order_id = o.order_id
    LEFT JOIN olist_order_payments_dataset AS p
        ON i.order_id = p.order_id
    WHERE o.order_status <> 'canceled'
    AND o.order_delivered_customer_date IS NOT NULL
    AND t.product_category_name_english IS NOT NULL
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY t.product_category_name_english
)

SELECT TOP 10
    revenue_rank, category, total_orders,
    total_revenue, avg_order_value
FROM category_revenue
ORDER BY revenue_rank ASC;

GO

/*
FINDINGS:
Top categories are dominated by everyday essential goods — bed/bath/table (R$1.69M), health & beauty
(R$1.62M), and computers & accessories (R$1.55M). These three categories alone account for a
significant share of total platform revenue.

Bottom 10 categories include expected low-volume niches (security services, DVDs) but also everyday
consumables such as diapers and female clothing. The underperformance of high-frequency categories
warrants investigation into inventory depth, search visibility, and pricing competitiveness relative to
other platforms operating in the Brazilian market.
*/

-- ============================================================
-- QUERY 5: Top 10 Sellers by Category
-- Requested by: Sales Team and Product Team
-- ============================================================
-- Extracts the top 10 revenue-generating sellers per product category using RANK() PARTITION BY, eliminating the need
-- for separate queries per category.

WITH seller_revenue AS (
    SELECT
        t.product_category_name_english AS category,
        s.seller_id,
        ROUND(SUM(p.payment_value), 2) AS total_revenue,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(AVG(p.payment_value), 2) AS avg_order_value,
        RANK() OVER (
            PARTITION BY t.product_category_name_english
            ORDER BY SUM(p.payment_value) DESC
        ) AS seller_rank
    FROM olist_sellers_dataset AS s
    LEFT JOIN olist_order_items_dataset AS i
        ON s.seller_id = i.seller_id
    LEFT JOIN olist_products_dataset AS pr
        ON i.product_id = pr.product_id
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    LEFT JOIN olist_order_payments_dataset AS p
        ON i.order_id = p.order_id
    LEFT JOIN olist_orders_dataset AS o
        ON i.order_id = o.order_id
    WHERE o.order_status <> 'canceled'
    AND o.order_delivered_customer_date IS NOT NULL
    AND t.product_category_name_english IS NOT NULL
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY t.product_category_name_english, s.seller_id
)

SELECT
    category, seller_rank, seller_id,
    total_orders, total_revenue, avg_order_value
FROM seller_revenue
WHERE seller_rank <= 10
ORDER BY category, seller_rank;

GO

/*
FINDINGS:
The platform hosts 2,912 active sellers, but revenue concentration is high within categories.
In watches_gifts, the top-ranked seller generates R$76,433 — significantly above the category median.

Revenue disparity between rank 1 and rank 10 varies considerably by category, indicating that some markets
are dominated by a single high-performing seller while others reflect more competitive distribution.

This analysis supports the Sales team in identifying high-value seller relationships to prioritize for
retention, partnership programs, and promotional collaboration.
*/

-- ============================================================
-- QUERY 6: State-Level Performance Analysis
-- Requested by: Marketing Team
-- ============================================================
-- Aggregates revenue, customer count, and seller count by Brazilian state. Also identifies the top 5 product
-- categories per state and the customer-to-seller ratio as a market opportunity indicator.

-- Part A: Revenue by State
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(p.payment_value), 2) AS total_revenue,
    ROUND(AVG(p.payment_value), 2) AS avg_order_value,
    RANK() OVER (ORDER BY SUM(p.payment_value) DESC) AS revenue_rank
FROM olist_customers_dataset AS c
LEFT JOIN olist_orders_dataset AS o
    ON c.customer_id = o.customer_id
LEFT JOIN olist_order_payments_dataset AS p
    ON o.order_id = p.order_id
WHERE o.order_status <> 'canceled'
AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY total_revenue DESC;

GO

-- Part B: Top 5 Product Categories per State
WITH state_category AS (
    SELECT
        c.customer_state,
        t.product_category_name_english AS category,
        ROUND(SUM(p.payment_value), 2) AS total_revenue,
        RANK() OVER (
            PARTITION BY c.customer_state
            ORDER BY SUM(p.payment_value) DESC
        ) AS category_rank
    FROM olist_customers_dataset AS c
    LEFT JOIN olist_orders_dataset AS o
        ON c.customer_id = o.customer_id
    LEFT JOIN olist_order_payments_dataset AS p
        ON o.order_id = p.order_id
    LEFT JOIN olist_order_items_dataset AS i
        ON o.order_id = i.order_id
    LEFT JOIN olist_products_dataset AS pr
        ON i.product_id = pr.product_id
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    WHERE o.order_status <> 'canceled'
    AND o.order_delivered_customer_date IS NOT NULL
    AND t.product_category_name_english IS NOT NULL
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY c.customer_state, t.product_category_name_english
)

SELECT
    customer_state, category_rank, category, total_revenue
FROM state_category
WHERE category_rank <= 5
ORDER BY customer_state, category_rank;

GO

-- Part C: Customer-to-Seller Ratio by State
SELECT
    c.state,
    c.num_customers,
    COALESCE(s.num_sellers, 0) AS num_sellers,
    ROUND(
        CAST(c.num_customers AS FLOAT) /
        NULLIF(s.num_sellers, 0)
    , 1) AS customers_per_seller
FROM (
    SELECT
        customer_state AS state,
        COUNT(DISTINCT customer_unique_id) AS num_customers
    FROM olist_customers_dataset
    GROUP BY customer_state
) AS c
LEFT JOIN (
    SELECT
        seller_state AS state,
        COUNT(DISTINCT seller_id) AS num_sellers
    FROM olist_sellers_dataset
    GROUP BY seller_state
) AS s ON c.state = s.state
ORDER BY num_customers DESC;

GO

/*
FINDINGS:
São Paulo (SP) generates R$5.7M in revenue — nearly 3x Rio de Janeiro (RJ) in second place,
reflecting Brazil's highly concentrated economy activity in major metropolitan areas.

The customer-to-seller ratio reveals market imbalance in several states. Bahia (BA) has
3,277 customers but only 19 sellers (~172 customers per seller vs SP's ~22). Similar
imbalances exist in Pernambuco, Ceará, and Pará.

These states represent underserved markets where existing customer demand is not matched by
adequate seller supply — presenting a targeted seller acquisition opportunity for the business
without requiring incremental customer acquisition.
*/

-- ============================================================
-- QUERY 7: Delivery Performance by State
-- Requested by: Customer Support Team
-- ============================================================
-- Measures average estimated and actual delivery times by state, and compares them to identify whether Olist is
-- meeting its stated delivery commitments.

WITH delivery_analysis AS (
    SELECT
        c.customer_state AS state,
        CAST(AVG(DATEDIFF(DAY,
            o.order_approved_at,
            o.order_estimated_delivery_date
        )) AS INT) AS avg_estimated_days,
        CAST(AVG(DATEDIFF(DAY,
            o.order_approved_at,
            o.order_delivered_customer_date
        )) AS INT) AS avg_actual_days,
        CAST(AVG(DATEDIFF(DAY,
            o.order_delivered_customer_date,
            o.order_estimated_delivery_date
        )) AS INT) AS avg_days_early_or_late,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status <> 'canceled'
    AND o.order_approved_at IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state
)

SELECT
    state, total_orders,
    avg_estimated_days, avg_actual_days,
    avg_days_early_or_late,
    CASE
        WHEN avg_days_early_or_late > 0 THEN 'Early'
        WHEN avg_days_early_or_late < 0 THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,
    RANK() OVER (ORDER BY avg_estimated_days ASC) AS delivery_rank
FROM delivery_analysis
ORDER BY avg_estimated_days ASC;

GO

/*
FINDINGS:
São Paulo records the shortest average estimated delivery at 19 days, reflecting strong logistics 
infrastructure and proximity to distribution hubs.
Remote northern states (AM, AP, RR) average 45 days more than double — due to limited carrier coverage
and road infrastructure constraints.

Importantly, actual delivery times are consistently better than estimated across most states, indicating
Olist sets conservative delivery commitments.
This results in positive customer experiences relative to expectations — a factor likely contributing to
the satisfaction recovery observed from April 2018.

States with faster delivery (SP, MG, PR) correlate with higher customer counts, seller density, and
revenue — confirming logistics capability as a structural driver of e-commerce performance.
*/

-- ============================================================
-- QUERY 8: Repurchase Rate Analysis
-- Requested by: Marketing Team
-- ============================================================
-- Builds a customer-level data mart tracking first purchase, most recent purchase, total orders, repurchase flag,
-- purchase interval, and purchase cycle for the top 3 revenue categories.

WITH customer_purchases AS (
    SELECT
        cu.customer_unique_id,
        t.product_category_name_english AS category,
        MIN(o.order_purchase_timestamp) AS first_purchase,
        MAX(o.order_purchase_timestamp) AS recent_purchase,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS cu
        ON o.customer_id = cu.customer_id
    LEFT JOIN olist_order_items_dataset AS i
        ON o.order_id = i.order_id
    LEFT JOIN olist_products_dataset AS pr
        ON i.product_id = pr.product_id
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    WHERE o.order_status <> 'canceled'
    AND t.product_category_name_english IN (
        'bed_bath_table',
        'health_beauty',
        'computers_accessories'
    )
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY cu.customer_unique_id,
             t.product_category_name_english
),

repurchase_mart AS (
    SELECT
        customer_unique_id, category,
        CONVERT(DATE, first_purchase) AS first_purchase,
        CONVERT(DATE, recent_purchase) AS recent_purchase,
        total_orders,
        CASE
            WHEN first_purchase < recent_purchase THEN 'Y'
            ELSE 'N'
        END AS repurchased,
        DATEDIFF(DAY, first_purchase, recent_purchase) AS interval_days,
        CASE
            WHEN total_orders - 1 = 0
            OR DATEDIFF(DAY, first_purchase, recent_purchase) = 0
            THEN 0
            ELSE DATEDIFF(DAY, first_purchase, recent_purchase)
                 / (total_orders - 1)
        END AS purchase_cycle_days
    FROM customer_purchases
)

SELECT
    category,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN repurchased = 'Y' THEN 1 ELSE 0 END) AS repurchase_customers,
    SUM(CASE WHEN repurchased = 'N' THEN 1 ELSE 0 END) AS single_purchase_customers,
    ROUND(
        CAST(SUM(CASE WHEN repurchased = 'Y' THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(*) * 100
    , 2) AS repurchase_rate_pct,
    AVG(CASE WHEN repurchased = 'Y' THEN interval_days END) AS avg_interval_days,
    AVG(CASE WHEN repurchased = 'Y' THEN purchase_cycle_days END) AS avg_cycle_days
FROM repurchase_mart
GROUP BY category
ORDER BY repurchase_rate_pct DESC;

GO

/*
FINDINGS:
Repurchase rates across all three categories are low: bed_bath_table (1.5%), health_beauty (0.99%),
and computers_accessories (~1.0%).

The low rate in health & beauty is particularly notable given that these are typically high-frequency
consumable products. This may indicate that customers locate sellers through Olist and transact with them
directly on subsequent purchases, or migrate to competing platforms with established loyalty programs.

Customers who do repurchase have an average purchase interval of 60–100 days. This window defines the 
optimal re-engagement timing for marketing campaigns targeting lapsed customers before platform switching
becomes likely.
*/

-- ============================================================
-- QUERY 9: Year-over-Year Category Growth Rate
-- Requested by: Product Team
-- ============================================================
-- Calculates revenue growth rates by category across years using LAG() to identify high-growth and declining segments.

WITH category_yearly AS (
    SELECT
        t.product_category_name_english AS category,
        YEAR(o.order_purchase_timestamp) AS yr,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(p.payment_value), 2) AS total_revenue
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    LEFT JOIN olist_order_items_dataset AS i
        ON o.order_id = i.order_id
    LEFT JOIN olist_products_dataset AS pr
        ON i.product_id = pr.product_id
    LEFT JOIN product_category_name_translation AS t
        ON pr.product_category_name = t.product_category_name
    LEFT JOIN olist_order_payments_dataset AS p
        ON o.order_id = p.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    AND t.product_category_name_english IS NOT NULL
    AND t.product_category_name_english <> 'product_category_name_english'
    GROUP BY t.product_category_name_english,
             YEAR(o.order_purchase_timestamp)
),

category_growth AS (
    SELECT
        category, yr, total_orders, total_revenue,
        LAG(total_revenue) OVER (
            PARTITION BY category ORDER BY yr
        ) AS prev_year_revenue,
        ROUND(
            (total_revenue - LAG(total_revenue) OVER (
                PARTITION BY category ORDER BY yr
            )) /
            NULLIF(LAG(total_revenue) OVER (
                PARTITION BY category ORDER BY yr
            ), 0) * 100
        , 2) AS yoy_growth_pct
    FROM category_yearly
)

SELECT
    category, yr, total_orders, total_revenue,
    prev_year_revenue, yoy_growth_pct,
    RANK() OVER (
        PARTITION BY yr
        ORDER BY yoy_growth_pct DESC
    ) AS growth_rank
FROM category_growth
WHERE yoy_growth_pct IS NOT NULL
ORDER BY yr, growth_rank;

GO

/*
FINDINGS:
The majority of categories demonstrated positive YoY growth from 2017 to 2018, consistent with
overall platform scaling and expanding seller supply.

Categories showing negative YoY growth in an otherwise growing market warrant further investigation.
Likely causes include seller attrition, pricing deterioration, or competitive displacement. These
segments should be reviewed for seller retention issues or category-level promotional underinvestment
before additional resources are allocated.
*/

-- ============================================================
-- QUERY 10: Customer Cohort Retention Analysis
-- Requested by: Marketing Team
-- ============================================================
-- Groups customers by their first purchase month and tracks the proportion returning in each subsequent month to
-- measure platform retention performance over time.

WITH first_purchase AS (
    SELECT
        c.customer_unique_id,
        MIN(FORMAT(o.order_purchase_timestamp, 'yyyy-MM')) AS cohort_month
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),

customer_activity AS (
    SELECT
        f.customer_unique_id, f.cohort_month,
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS order_month,
        DATEDIFF(MONTH,
            CAST(f.cohort_month + '-01' AS DATE),
            CAST(FORMAT(o.order_purchase_timestamp, 'yyyy-MM') + '-01' AS DATE)
        ) AS months_since_first
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    INNER JOIN first_purchase AS f
        ON c.customer_unique_id = f.customer_unique_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),

cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
)

SELECT
    ca.cohort_month, cs.cohort_customers,
    ca.months_since_first,
    COUNT(DISTINCT ca.customer_unique_id) AS active_customers,
    ROUND(
        CAST(COUNT(DISTINCT ca.customer_unique_id) AS FLOAT)
        / cs.cohort_customers * 100
    , 2) AS retention_rate_pct
FROM customer_activity AS ca
LEFT JOIN cohort_size AS cs
    ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_customers, ca.months_since_first
ORDER BY ca.cohort_month, ca.months_since_first;

GO

/*
FINDINGS:
Retention drops sharply after the first purchase month across all cohorts, with most showing near-zero
returning activity by month 2 or 3. This is consistent with the sub-1.5% repurchase rates identified in Query 8.

The November 2017 cohort was the largest in the dataset, driven by Black Friday acquisition. However, this cohort
did not demonstrate meaningfully higher retention than quieter acquisition months — indicating that high-volume
promotional events improve new customer numbers but do not resolve the underlying retention gap.

The primary growth constraint for Olist is not customer acquisition — order volumes are increasing. The constraint
is retention. A structured post-purchase engagement program targeting customers at the 45–60 day mark could
materially improve lifetime value without requiring additional acquisition spend.
*/

-- ============================================================
-- QUERY 11: RFM Customer Segmentation
-- Requested by: Marketing Team
-- ============================================================
-- Scores each customer on Recency, Frequency, and Monetary value. Weighted RFM scores are calculated using the
-- coefficient of variation method (R: 22.2%, F: 37.5%, M: 40.3%) and customers are classified into five tiers:
-- Diamond, Gold, Silver, Bronze, and Churned.

-- Part A: Customer-Level RFM Scores and Tier Classification
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF(DAY,
            MAX(o.order_purchase_timestamp),
            CAST('2018-10-01' AS DATE)
        ) AS recency,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(p.payment_value), 2) AS monetary
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    LEFT JOIN olist_order_payments_dataset AS p
        ON o.order_id = p.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_unique_id
),

rfm_scores AS (
    SELECT
        customer_unique_id, recency, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(2) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),

rfm_weighted AS (
    SELECT
        customer_unique_id, recency, frequency, monetary,
        r_score, f_score, m_score,
        ROUND(
            (r_score * 0.2222 / 5 * 100) +
            (f_score * 0.3746 / 2 * 100) +
            (m_score * 0.4031 / 5 * 100)
        , 2) AS rfm_score
    FROM rfm_scores
)

SELECT
    customer_unique_id, recency, frequency, monetary,
    r_score, f_score, m_score, rfm_score,
    CASE
        WHEN rfm_score >= 80 THEN 'Diamond'
        WHEN rfm_score >= 65 THEN 'Gold'
        WHEN rfm_score >= 50 THEN 'Silver'
        WHEN rfm_score >= 35 THEN 'Bronze'
        ELSE 'Churned'
    END AS customer_tier
FROM rfm_weighted
ORDER BY rfm_score DESC;

GO

-- Part B: Tier-Level Summary for Marketing Prioritization
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF(DAY,
            MAX(o.order_purchase_timestamp),
            CAST('2018-10-01' AS DATE)
        ) AS recency,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(p.payment_value), 2) AS monetary
    FROM olist_orders_dataset AS o
    LEFT JOIN olist_customers_dataset AS c
        ON o.customer_id = c.customer_id
    LEFT JOIN olist_order_payments_dataset AS p
        ON o.order_id = p.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT
        customer_unique_id, recency, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        NTILE(2) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_weighted AS (
    SELECT
        customer_unique_id, recency, frequency, monetary,
        r_score, f_score, m_score,
        ROUND(
            (r_score * 0.2222 / 5 * 100) +
            (f_score * 0.3746 / 2 * 100) +
            (m_score * 0.4031 / 5 * 100)
        , 2) AS rfm_score
    FROM rfm_scores
),
rfm_tiered AS (
    SELECT *,
        CASE
            WHEN rfm_score >= 80 THEN 'Diamond'
            WHEN rfm_score >= 65 THEN 'Gold'
            WHEN rfm_score >= 50 THEN 'Silver'
            WHEN rfm_score >= 35 THEN 'Bronze'
            ELSE 'Churned'
        END AS customer_tier
    FROM rfm_weighted
)

SELECT
    customer_tier,
    COUNT(*) AS total_customers,
    ROUND(AVG(recency), 0) AS avg_recency_days,
    ROUND(AVG(frequency), 1) AS avg_orders,
    ROUND(AVG(monetary), 2) AS avg_spend,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(CAST(COUNT(*) AS FLOAT) /
        SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_customers,
    ROUND(SUM(monetary) /
        SUM(SUM(monetary)) OVER () * 100, 2) AS pct_of_revenue
FROM rfm_tiered
GROUP BY customer_tier
ORDER BY
    CASE customer_tier
        WHEN 'Diamond' THEN 1
        WHEN 'Gold'    THEN 2
        WHEN 'Silver'  THEN 3
        WHEN 'Bronze'  THEN 4
        ELSE 5
    END;

GO

/*
FINDINGS:
RFM segmentation provides the Marketing team with a data-driven framework for customer prioritization.
Diamond and Gold tier customers represent a small proportion of total customers but are expected to
account for a disproportionate share of revenue, warranting differentiated engagement strategies
such as early access, loyalty benefits, and dedicated account management.

The Churned tier represents customers with prior purchase history who have not returned — a segment 
with lower reacquisition cost than cold prospects.
Targeted win-back campaigns with personalized incentives are recommended for this group.

Weights applied: Recency (22.2%), Frequency (37.5%), Monetary (40.3%), derived using coefficient of
variation across customer clusters. Tier thresholds are based on score distribution quartiles and can
be adjusted based on business priorities.

Extension opportunity: Running RFM segmentation at the category level would enable more granular
targeting — a customer classified as Diamond overall may be inactive in specific categories, which has
implications for cross-sell and upsell strategy.
*/