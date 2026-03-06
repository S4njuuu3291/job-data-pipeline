"""Backfill Silver layer from historical Bronze data."""

import io
import logging
import os
import re
from typing import Optional

import pandas as pd
import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger(__name__)

load_dotenv()


def get_bucket_names() -> tuple[str, str]:
    """Get Bronze and Silver bucket names."""
    bronze = os.getenv("AWS_S3_BUCKET_NAME", "jobscraper-bronze-data-8424560")
    silver = os.getenv("AWS_S3_SILVER_BUCKET_NAME", "jobscraper-silver-data-8424560")
    return bronze, silver


def get_glue_config() -> tuple[str, str]:
    """Get Glue database and table names."""
    db = os.getenv("AWS_GLUE_DATABASE_NAME", "jobscraper_db")
    table = os.getenv("AWS_GLUE_SILVER_TABLE_NAME", "jobscraper_silver_table")
    return db, table


def list_ingestion_dates(bronze_bucket: str) -> list[str]:
    """List all unique ingestion_date values in Bronze bucket."""
    s3 = boto3.client("s3")
    dates = set()
    
    try:
        paginator = s3.get_paginator("list_objects_v2")
        pages = paginator.paginate(Bucket=bronze_bucket)
        
        for page in pages:
            if "Contents" not in page:
                continue
            
            for obj in page["Contents"]:
                # Extract ingestion_date from key like: platform=kalibrr/ingestion_date=2026-03-01/...
                match = re.search(r"ingestion_date=(\d{4}-\d{2}-\d{2})", obj["Key"])
                if match:
                    dates.add(match.group(1))
        
        sorted_dates = sorted(list(dates))
        logger.info(f"Found {len(sorted_dates)} unique ingestion dates")
        return sorted_dates
        
    except ClientError as e:
        logger.error(f"Error listing S3 objects: {e}")
        raise


def normalize_location(location: str) -> str:
    """Normalize location names to standardized format."""
    location = location.lower()
    
    if "jakarta selatan" in location or "south jakarta" in location:
        return "Jakarta Selatan"
    elif "jakarta barat" in location or "west jakarta" in location:
        return "Jakarta Barat"
    elif "jakarta pusat" in location or "central jakarta" in location:
        return "Jakarta Pusat"
    elif "jakarta timur" in location or "east jakarta" in location:
        return "Jakarta Timur"
    elif "jakarta utara" in location or "north jakarta" in location:
        return "Jakarta Utara"
    elif "jakarta" in location:
        return "Jakarta"
    elif "yogyakarta" in location or "jogja" in location:
        return "Yogyakarta"
    elif "bandung" in location:
        return "Bandung"
    elif "surabaya" in location:
        return "Surabaya"
    elif "tangerang" in location:
        return "Tangerang"
    elif "bekasi" in location or "cikarang" in location:
        return "Bekasi"
    elif "depok" in location:
        return "Depok"
    elif "bogor" in location or "cileungsi" in location:
        return "Bogor"
    elif "semarang" in location:
        return "Semarang"
    else:
        return location.title()


def read_bronze_data(
    bronze_bucket: str,
    ingestion_date: str,
    platforms: list[str],
) -> pd.DataFrame:
    """Read parquet files from Bronze bucket for given date and platforms."""
    s3 = boto3.client("s3")
    df_combined = pd.DataFrame()
    
    for platform in platforms:
        prefix = f"platform={platform}/ingestion_date={ingestion_date}/"
        
        try:
            response = s3.list_objects_v2(Bucket=bronze_bucket, Prefix=prefix)
            
            if "Contents" not in response:
                logger.warning(f"No data found for {platform} on {ingestion_date}")
                continue
            
            for obj in response["Contents"]:
                if not obj["Key"].endswith(".parquet"):
                    continue
                
                logger.info(f"Reading: s3://{bronze_bucket}/{obj['Key']}")
                
                try:
                    response = s3.get_object(Bucket=bronze_bucket, Key=obj["Key"])
                    df = pd.read_parquet(io.BytesIO(response["Body"].read()))
                    df_combined = pd.concat([df_combined, df], ignore_index=True)
                    logger.info(f"  ✓ Loaded {len(df)} records")
                except Exception as e:
                    logger.error(f"  ✗ Failed to read: {e}")
                    continue
        
        except ClientError as e:
            logger.error(f"Error listing objects for {platform}: {e}")
            continue
    
    logger.info(f"Total records loaded for {ingestion_date}: {len(df_combined)}")
    return df_combined


def transform_data(df: pd.DataFrame) -> pd.DataFrame:
    """Apply Silver layer transformations."""
    if df.empty:
        logger.warning("Empty dataframe, skipping transformation")
        return df
    
    if "location" in df.columns:
        df["location"] = df["location"].map(normalize_location)
        logger.info("✓ Location normalization applied")
    
    original_count = len(df)
    df = df.drop_duplicates()
    logger.info(f"✓ Deduplicated: {original_count} → {len(df)} records")
    
    return df


def upload_to_silver(
    df: pd.DataFrame,
    silver_bucket: str,
    ingestion_date: str,
    db_name: str,
    table_name: str,
) -> str:
    """Upload transformed data to Silver bucket and register partition."""
    s3 = boto3.client("s3")
    glue = boto3.client("glue")
    
    partition_prefix = f"ingestion_date={ingestion_date}/"
    object_key = f"{partition_prefix}job_data_{ingestion_date}.parquet"
    
    # Upload to S3
    try:
        buffer = io.BytesIO()
        df.to_parquet(buffer, index=False, engine="pyarrow")
        buffer.seek(0)
        
        logger.info(f"Uploading to S3: s3://{silver_bucket}/{object_key}")
        s3.put_object(Bucket=silver_bucket, Key=object_key, Body=buffer.getvalue())
        logger.info("✅ File uploaded successfully")
    except ClientError as e:
        logger.error(f"❌ Failed to upload to S3: {e}")
        raise
    
    # Register partition in Glue
    try:
        # Try to delete existing partition first (idempotency)
        try:
            glue.delete_partition(
                DatabaseName=db_name,
                TableName=table_name,
                PartitionValues=[ingestion_date],
            )
            logger.info(f"♻️ Existing partition /{ingestion_date} deleted")
        except ClientError as e:
            if e.response["Error"]["Code"] == "EntityNotFoundException":
                logger.info(f"ℹ️ Partition doesn't exist, creating new one")
            else:
                logger.warning(f"⚠️ Could not delete partition: {e}")
        
        glue.create_partition(
            DatabaseName=db_name,
            TableName=table_name,
            PartitionInput={
                "Values": [ingestion_date],
                "StorageDescriptor": {
                    "Location": f"s3://{silver_bucket}/{partition_prefix}",
                    "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                    "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                    "SerdeInfo": {
                        "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                        "Parameters": {"serialization.format": "1"},
                    },
                },
            },
        )
        logger.info(f"✅ Partition /{ingestion_date} registered")
    except ClientError as e:
        logger.error(f"❌ Failed to register partition: {e}")
        raise
    
    return object_key


def backfill_silver(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    specific_dates: Optional[list[str]] = None,
):
    """Backfill Silver layer from Bronze data.
    
    Args:
        start_date: Start date in YYYY-MM-DD format (inclusive)
        end_date: End date in YYYY-MM-DD format (inclusive)
        specific_dates: List of specific dates to process
    """
    bronze_bucket, silver_bucket = get_bucket_names()
    db_name, table_name = get_glue_config()
    platforms = os.getenv("platform", "kalibrr,glints,jobstreet").split(",")
    
    logger.info("=" * 70)
    logger.info("SILVER LAYER BACKFILL STARTED")
    logger.info("=" * 70)
    logger.info(f"Bronze bucket: {bronze_bucket}")
    logger.info(f"Silver bucket: {silver_bucket}")
    logger.info(f"Platforms: {platforms}")
    logger.info(f"Glue: {db_name}.{table_name}")
    logger.info("=" * 70)
    
    # Get all available dates
    all_dates = list_ingestion_dates(bronze_bucket)
    
    # Filter dates
    if specific_dates:
        dates_to_process = [d for d in all_dates if d in specific_dates]
    elif start_date or end_date:
        dates_to_process = [
            d for d in all_dates
            if (not start_date or d >= start_date) and (not end_date or d <= end_date)
        ]
    else:
        dates_to_process = all_dates
    
    logger.info(f"Processing {len(dates_to_process)} dates")
    logger.info("=" * 70)
    
    # Process each date
    success_count = 0
    failed_dates = []
    
    for idx, ingestion_date in enumerate(dates_to_process, 1):
        try:
            logger.info(f"\n[{idx}/{len(dates_to_process)}] Processing: {ingestion_date}")
            
            # Read from Bronze
            df = read_bronze_data(bronze_bucket, ingestion_date, platforms)
            
            if df.empty:
                logger.warning(f"⚠️  No data found for {ingestion_date}")
                continue
            
            # Transform
            df = transform_data(df)
            
            # Upload to Silver
            upload_to_silver(df, silver_bucket, ingestion_date, db_name, table_name)
            
            success_count += 1
            logger.info(f"✅ Backfilled {ingestion_date}")
            
        except Exception as e:
            logger.error(f"❌ Failed: {ingestion_date} - {e}")
            failed_dates.append(ingestion_date)
    
    # Summary
    logger.info("\n" + "=" * 70)
    logger.info("BACKFILL SUMMARY")
    logger.info("=" * 70)
    logger.info(f"✅ Successful: {success_count}/{len(dates_to_process)}")
    if failed_dates:
        logger.info(f"❌ Failed: {len(failed_dates)}")
    logger.info("=" * 70)


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "--help":
            print("""Backfill Silver layer from Bronze data
            
Usage:
  python scripts/backfill_silver.py                          # All dates
  python scripts/backfill_silver.py --start 2026-02-20      # From date onwards
  python scripts/backfill_silver.py --range 2026-02-20 2026-03-05  # Range
  python scripts/backfill_silver.py --dates 2026-02-20 2026-02-21  # Specific dates
            """)
            sys.exit(0)
        elif sys.argv[1] == "--start" and len(sys.argv) > 2:
            backfill_silver(start_date=sys.argv[2])
        elif sys.argv[1] == "--range" and len(sys.argv) > 3:
            backfill_silver(start_date=sys.argv[2], end_date=sys.argv[3])
        elif sys.argv[1] == "--dates" and len(sys.argv) > 2:
            backfill_silver(specific_dates=sys.argv[2:])
    else:
        backfill_silver()
