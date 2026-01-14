"""Dagster pipelines for sovereign-dp lakehouse."""

import os
from dagster import (
    Definitions,
    asset,
    AssetExecutionContext,
    ConfigurableResource,
)
import pandas as pd
from trino.dbapi import connect


class TrinoResource(ConfigurableResource):
    """Resource for connecting to Trino."""

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
        return cursor.fetchall()

    def execute_df(self, query: str) -> pd.DataFrame:
        conn = self.get_connection()
        return pd.read_sql(query, conn)


class RustfsResource(ConfigurableResource):
    """Resource for rustfs S3 access."""

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


@asset(group_name="demo")
def demo_schema(context: AssetExecutionContext, trino: TrinoResource):
    """Create demo schema in Iceberg catalog."""
    context.log.info("Creating demo schema...")
    trino.execute("CREATE SCHEMA IF NOT EXISTS iceberg.demo")
    return "iceberg.demo"


@asset(group_name="demo", deps=[demo_schema])
def sample_sales_table(context: AssetExecutionContext, trino: TrinoResource):
    """Create and populate sample sales table."""
    context.log.info("Creating sample sales table...")

    # Create table
    trino.execute("""
        CREATE TABLE IF NOT EXISTS iceberg.demo.sales (
            id BIGINT,
            product VARCHAR,
            quantity INT,
            price DECIMAL(10,2),
            sale_date DATE
        )
    """)

    # Check if data exists
    result = trino.execute("SELECT COUNT(*) FROM iceberg.demo.sales")
    count = result[0][0]

    if count == 0:
        context.log.info("Inserting sample data...")
        trino.execute("""
            INSERT INTO iceberg.demo.sales VALUES
                (1, 'Laptop', 2, 999.99, DATE '2024-01-15'),
                (2, 'Mouse', 5, 29.99, DATE '2024-01-16'),
                (3, 'Keyboard', 3, 79.99, DATE '2024-01-16'),
                (4, 'Monitor', 1, 299.99, DATE '2024-01-17'),
                (5, 'Laptop', 1, 999.99, DATE '2024-01-18')
        """)
    else:
        context.log.info(f"Table already has {count} rows, skipping insert")

    return "iceberg.demo.sales"


@asset(group_name="demo", deps=[sample_sales_table])
def sales_summary(context: AssetExecutionContext, trino: TrinoResource) -> pd.DataFrame:
    """Generate sales summary by product."""
    context.log.info("Generating sales summary...")

    df = trino.execute_df("""
        SELECT
            product,
            SUM(quantity) as total_quantity,
            SUM(quantity * price) as total_revenue
        FROM iceberg.demo.sales
        GROUP BY product
        ORDER BY total_revenue DESC
    """)

    context.log.info(f"Summary: {len(df)} products")
    return df


# Resource configuration from environment
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
    assets=[demo_schema, sample_sales_table, sales_summary],
    resources={
        "trino": trino_resource,
        "rustfs": rustfs_resource,
    },
)
