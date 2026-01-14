"""Dagster pipelines for sovereign-dp lakehouse.

This module demonstrates a complete data lakehouse workflow:
1. Raw data ingestion to S3 (rustfs)
2. Schema creation in Iceberg via Nessie catalog
3. Data transformation and loading via Trino
4. Analytics and reporting assets
"""

import os
import io
from datetime import date, timedelta
import random
from dagster import (
    Definitions,
    asset,
    AssetExecutionContext,
    ConfigurableResource,
    MaterializeResult,
    MetadataValue,
    define_asset_job,
    AssetSelection,
)
import pandas as pd
from trino.dbapi import connect


class TrinoResource(ConfigurableResource):
    """Resource for connecting to Trino query engine."""

    host: str = "trino-coordinator.sovereign-dp.svc.cluster.local"
    port: int = 8080
    catalog: str = "iceberg"
    schema: str = "default"

    def get_connection(self):
        return connect(
            host=self.host,
            port=self.port,
            catalog=self.catalog,
            schema=self.schema,
        )

    def execute(self, query: str):
        conn = self.get_connection()
        cursor = conn.cursor()
        cursor.execute(query)
        try:
            return cursor.fetchall()
        except Exception:
            return []

    def execute_df(self, query: str) -> pd.DataFrame:
        conn = self.get_connection()
        return pd.read_sql(query, conn)


class RustfsResource(ConfigurableResource):
    """Resource for rustfs S3-compatible object storage."""

    endpoint_url: str = "http://rustfs.sovereign-dp.svc.cluster.local:9000"
    access_key: str = "rustfsadmin"
    secret_key: str = "rustfsadmin"
    bucket: str = "sovereign-dp"

    def get_client(self):
        import boto3
        return boto3.client(
            "s3",
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
        )

    def upload_dataframe(self, df: pd.DataFrame, key: str, format: str = "parquet"):
        """Upload a DataFrame to S3 as parquet or CSV."""
        client = self.get_client()
        buffer = io.BytesIO()
        if format == "parquet":
            df.to_parquet(buffer, index=False)
        else:
            df.to_csv(buffer, index=False)
        buffer.seek(0)
        client.put_object(Bucket=self.bucket, Key=key, Body=buffer.getvalue())
        return f"s3://{self.bucket}/{key}"

    def list_objects(self, prefix: str = ""):
        """List objects in the bucket with optional prefix."""
        client = self.get_client()
        response = client.list_objects_v2(Bucket=self.bucket, Prefix=prefix)
        return [obj["Key"] for obj in response.get("Contents", [])]


# =============================================================================
# RAW DATA LAYER - Ingest raw data to S3 storage
# =============================================================================

@asset(group_name="raw", description="Generate and upload raw orders data to S3")
def raw_orders(context: AssetExecutionContext, rustfs: RustfsResource) -> MaterializeResult:
    """Generate sample orders and upload to rustfs S3 storage."""
    context.log.info("Generating raw orders data...")

    # Generate sample order data
    products = ["Laptop", "Mouse", "Keyboard", "Monitor", "Webcam", "Headset", "USB Hub"]
    regions = ["North", "South", "East", "West"]

    orders = []
    base_date = date(2024, 1, 1)
    for i in range(1, 101):
        orders.append({
            "order_id": i,
            "product": random.choice(products),
            "quantity": random.randint(1, 10),
            "unit_price": round(random.uniform(20, 1200), 2),
            "region": random.choice(regions),
            "order_date": (base_date + timedelta(days=random.randint(0, 90))).isoformat(),
        })

    df = pd.DataFrame(orders)

    # Upload to S3
    s3_path = rustfs.upload_dataframe(df, "raw/orders/orders.parquet", format="parquet")
    context.log.info(f"Uploaded {len(df)} orders to {s3_path}")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(len(df)),
            "s3_path": MetadataValue.text(s3_path),
            "columns": MetadataValue.json(list(df.columns)),
        }
    )


@asset(group_name="raw", description="Generate and upload raw customers data to S3")
def raw_customers(context: AssetExecutionContext, rustfs: RustfsResource) -> MaterializeResult:
    """Generate sample customers and upload to rustfs S3 storage."""
    context.log.info("Generating raw customers data...")

    customers = []
    regions = ["North", "South", "East", "West"]
    tiers = ["Bronze", "Silver", "Gold", "Platinum"]

    for i in range(1, 51):
        customers.append({
            "customer_id": i,
            "customer_name": f"Customer_{i:03d}",
            "region": random.choice(regions),
            "tier": random.choice(tiers),
            "signup_date": (date(2023, 1, 1) + timedelta(days=random.randint(0, 365))).isoformat(),
        })

    df = pd.DataFrame(customers)

    s3_path = rustfs.upload_dataframe(df, "raw/customers/customers.parquet", format="parquet")
    context.log.info(f"Uploaded {len(df)} customers to {s3_path}")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(len(df)),
            "s3_path": MetadataValue.text(s3_path),
        }
    )


# =============================================================================
# STAGING LAYER - Load raw data into Iceberg tables
# =============================================================================

@asset(group_name="staging", description="Create lakehouse schema in Iceberg catalog")
def lakehouse_schema(context: AssetExecutionContext, trino: TrinoResource):
    """Create the lakehouse schema via Nessie catalog."""
    context.log.info("Creating lakehouse schema in Iceberg catalog...")
    trino.execute("CREATE SCHEMA IF NOT EXISTS iceberg.lakehouse")
    context.log.info("Schema iceberg.lakehouse created")
    return "iceberg.lakehouse"


@asset(
    group_name="staging",
    deps=[lakehouse_schema, raw_orders],
    description="Load orders from S3 into Iceberg table"
)
def stg_orders(context: AssetExecutionContext, trino: TrinoResource, rustfs: RustfsResource) -> MaterializeResult:
    """Load raw orders from S3 into an Iceberg staging table."""
    context.log.info("Loading orders into Iceberg staging table...")

    # Read from S3
    import pyarrow.parquet as pq
    client = rustfs.get_client()
    response = client.get_object(Bucket=rustfs.bucket, Key="raw/orders/orders.parquet")
    df = pd.read_parquet(io.BytesIO(response["Body"].read()))

    # Drop and recreate table for idempotency
    trino.execute("DROP TABLE IF EXISTS iceberg.lakehouse.stg_orders")
    trino.execute("""
        CREATE TABLE iceberg.lakehouse.stg_orders (
            order_id BIGINT,
            product VARCHAR,
            quantity INT,
            unit_price DECIMAL(10,2),
            region VARCHAR,
            order_date DATE
        )
    """)

    # Insert data in batches
    for _, row in df.iterrows():
        trino.execute(f"""
            INSERT INTO iceberg.lakehouse.stg_orders VALUES (
                {row['order_id']},
                '{row['product']}',
                {row['quantity']},
                {row['unit_price']},
                '{row['region']}',
                DATE '{row['order_date']}'
            )
        """)

    result = trino.execute("SELECT COUNT(*) FROM iceberg.lakehouse.stg_orders")
    count = result[0][0]
    context.log.info(f"Loaded {count} orders into staging table")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(count),
            "table": MetadataValue.text("iceberg.lakehouse.stg_orders"),
        }
    )


@asset(
    group_name="staging",
    deps=[lakehouse_schema, raw_customers],
    description="Load customers from S3 into Iceberg table"
)
def stg_customers(context: AssetExecutionContext, trino: TrinoResource, rustfs: RustfsResource) -> MaterializeResult:
    """Load raw customers from S3 into an Iceberg staging table."""
    context.log.info("Loading customers into Iceberg staging table...")

    # Read from S3
    client = rustfs.get_client()
    response = client.get_object(Bucket=rustfs.bucket, Key="raw/customers/customers.parquet")
    df = pd.read_parquet(io.BytesIO(response["Body"].read()))

    # Drop and recreate table
    trino.execute("DROP TABLE IF EXISTS iceberg.lakehouse.stg_customers")
    trino.execute("""
        CREATE TABLE iceberg.lakehouse.stg_customers (
            customer_id BIGINT,
            customer_name VARCHAR,
            region VARCHAR,
            tier VARCHAR,
            signup_date DATE
        )
    """)

    # Insert data
    for _, row in df.iterrows():
        trino.execute(f"""
            INSERT INTO iceberg.lakehouse.stg_customers VALUES (
                {row['customer_id']},
                '{row['customer_name']}',
                '{row['region']}',
                '{row['tier']}',
                DATE '{row['signup_date']}'
            )
        """)

    result = trino.execute("SELECT COUNT(*) FROM iceberg.lakehouse.stg_customers")
    count = result[0][0]
    context.log.info(f"Loaded {count} customers into staging table")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(count),
            "table": MetadataValue.text("iceberg.lakehouse.stg_customers"),
        }
    )


# =============================================================================
# ANALYTICS LAYER - Aggregated and transformed data
# =============================================================================

@asset(
    group_name="analytics",
    deps=[stg_orders],
    description="Sales aggregated by region and product"
)
def sales_by_region(context: AssetExecutionContext, trino: TrinoResource) -> MaterializeResult:
    """Create regional sales summary in Iceberg."""
    context.log.info("Creating regional sales summary...")

    trino.execute("DROP TABLE IF EXISTS iceberg.lakehouse.sales_by_region")
    trino.execute("""
        CREATE TABLE iceberg.lakehouse.sales_by_region AS
        SELECT
            region,
            product,
            COUNT(*) as order_count,
            SUM(quantity) as total_quantity,
            CAST(SUM(quantity * unit_price) AS DECIMAL(12,2)) as total_revenue,
            CAST(AVG(unit_price) AS DECIMAL(10,2)) as avg_unit_price
        FROM iceberg.lakehouse.stg_orders
        GROUP BY region, product
    """)

    result = trino.execute("SELECT COUNT(*) FROM iceberg.lakehouse.sales_by_region")
    count = result[0][0]

    # Get sample data for metadata
    df = trino.execute_df("SELECT * FROM iceberg.lakehouse.sales_by_region ORDER BY total_revenue DESC LIMIT 5")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(count),
            "table": MetadataValue.text("iceberg.lakehouse.sales_by_region"),
            "preview": MetadataValue.md(df.to_markdown(index=False)),
        }
    )


@asset(
    group_name="analytics",
    deps=[stg_orders],
    description="Daily sales trend analysis"
)
def daily_sales_trend(context: AssetExecutionContext, trino: TrinoResource) -> MaterializeResult:
    """Create daily sales trend table in Iceberg."""
    context.log.info("Creating daily sales trend...")

    trino.execute("DROP TABLE IF EXISTS iceberg.lakehouse.daily_sales_trend")
    trino.execute("""
        CREATE TABLE iceberg.lakehouse.daily_sales_trend AS
        SELECT
            order_date,
            COUNT(*) as order_count,
            SUM(quantity) as total_units,
            CAST(SUM(quantity * unit_price) AS DECIMAL(12,2)) as daily_revenue
        FROM iceberg.lakehouse.stg_orders
        GROUP BY order_date
        ORDER BY order_date
    """)

    result = trino.execute("SELECT COUNT(*) FROM iceberg.lakehouse.daily_sales_trend")
    count = result[0][0]

    # Get summary stats
    stats = trino.execute_df("""
        SELECT
            MIN(daily_revenue) as min_revenue,
            MAX(daily_revenue) as max_revenue,
            AVG(daily_revenue) as avg_revenue
        FROM iceberg.lakehouse.daily_sales_trend
    """)

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(count),
            "table": MetadataValue.text("iceberg.lakehouse.daily_sales_trend"),
            "stats": MetadataValue.json(stats.to_dict(orient="records")[0] if len(stats) > 0 else {}),
        }
    )


@asset(
    group_name="analytics",
    deps=[stg_customers],
    description="Customer distribution by tier and region"
)
def customer_segments(context: AssetExecutionContext, trino: TrinoResource) -> MaterializeResult:
    """Create customer segmentation analysis in Iceberg."""
    context.log.info("Creating customer segments analysis...")

    trino.execute("DROP TABLE IF EXISTS iceberg.lakehouse.customer_segments")
    trino.execute("""
        CREATE TABLE iceberg.lakehouse.customer_segments AS
        SELECT
            region,
            tier,
            COUNT(*) as customer_count
        FROM iceberg.lakehouse.stg_customers
        GROUP BY region, tier
    """)

    result = trino.execute("SELECT COUNT(*) FROM iceberg.lakehouse.customer_segments")
    count = result[0][0]

    df = trino.execute_df("SELECT * FROM iceberg.lakehouse.customer_segments ORDER BY customer_count DESC")

    return MaterializeResult(
        metadata={
            "row_count": MetadataValue.int(count),
            "table": MetadataValue.text("iceberg.lakehouse.customer_segments"),
            "preview": MetadataValue.md(df.to_markdown(index=False)),
        }
    )


# =============================================================================
# JOBS - Executable pipelines
# =============================================================================

# Full lakehouse pipeline - runs everything from raw to analytics
lakehouse_pipeline_job = define_asset_job(
    name="lakehouse_pipeline",
    selection=AssetSelection.all(),
    description="Run the complete lakehouse pipeline: raw data → staging → analytics",
)

# Raw layer only - generate and upload raw data to S3
raw_ingestion_job = define_asset_job(
    name="raw_ingestion",
    selection=AssetSelection.groups("raw"),
    description="Generate sample data and upload to S3 storage",
)

# Staging layer only - load from S3 into Iceberg tables
staging_load_job = define_asset_job(
    name="staging_load",
    selection=AssetSelection.groups("staging"),
    description="Load raw data from S3 into Iceberg staging tables",
)

# Analytics layer only - create aggregated tables
analytics_job = define_asset_job(
    name="analytics_refresh",
    selection=AssetSelection.groups("analytics"),
    description="Refresh analytics tables with latest data",
)


# =============================================================================
# RESOURCE CONFIGURATION
# =============================================================================

trino_resource = TrinoResource(
    host=os.getenv("TRINO_HOST", "trino-coordinator.sovereign-dp.svc.cluster.local"),
    port=int(os.getenv("TRINO_PORT", "8080")),
)

rustfs_resource = RustfsResource(
    endpoint_url=os.getenv("AWS_ENDPOINT_URL", "http://rustfs.sovereign-dp.svc.cluster.local:9000"),
    access_key=os.getenv("AWS_ACCESS_KEY_ID", "rustfsadmin"),
    secret_key=os.getenv("AWS_SECRET_ACCESS_KEY", "rustfsadmin"),
)

defs = Definitions(
    assets=[
        # Raw layer
        raw_orders,
        raw_customers,
        # Staging layer
        lakehouse_schema,
        stg_orders,
        stg_customers,
        # Analytics layer
        sales_by_region,
        daily_sales_trend,
        customer_segments,
    ],
    jobs=[
        lakehouse_pipeline_job,
        raw_ingestion_job,
        staging_load_job,
        analytics_job,
    ],
    resources={
        "trino": trino_resource,
        "rustfs": rustfs_resource,
    },
)
