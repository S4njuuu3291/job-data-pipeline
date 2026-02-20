from typing import TYPE_CHECKING
import boto3
import io
import pandas as pd
from dotenv import load_dotenv
import os
from datetime import datetime

if TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client

load_dotenv()


def upload_to_s3(df: pd.DataFrame, platform: str):
    s3: S3Client = boto3.client("s3")
    bucket_name = os.getenv("AWS_S3_BUCKET_NAME")

    if not bucket_name:
        raise ValueError("AWS_S3_BUCKET_NAME environment variable not set")

    date_str = datetime.now().strftime("%Y-%m-%d")
    timestamp = datetime.now().strftime("%H%M%S")

    file_key = (
        f"platform={platform}/ingestion_date={date_str}/{platform}_{timestamp}.parquet"
    )

    parquet_buffer = io.BytesIO()
    df.to_parquet(parquet_buffer, engine="pyarrow", index=False)

    try:
        s3.put_object(Bucket=bucket_name, Key=file_key, Body=parquet_buffer.getvalue())
        print(f"🚀 Data mendarat di: s3://{bucket_name}/{file_key}")
        return True
    except Exception as e:
        print(f"❌ Gagal upload ke S3: {e}")
        return False
