"""Pipeline orchestration for Silver layer transformations."""

import logging
import pandas as pd

from .config import get_list_platforms
from .transformations import apply_location_normalization
from .validators import validate_silver_schema
from .storage import get_bronze_object, upload_to_silver

logger = logging.getLogger(__name__)


def transform_silver(df: pd.DataFrame) -> str:
    """Orchestrate Silver layer transformation pipeline.

    Pipeline steps:
    1. Apply location normalization
    2. Validate against Silver schema
    3. Upload to Silver S3 bucket

    Args:
        df: Bronze layer dataframe

    Returns:
        S3 object key of uploaded file
    """
    # Step 1: Apply transformations
    logger.info("Starting location normalization...")
    df = apply_location_normalization(df)
    logger.info("Location normalization completed.")

    # Step 2: Validate schema
    logger.info("Validating data against Silver schema...")
    df_validated = validate_silver_schema(df)

    # Step 3: Upload to Silver layer
    logger.info("Uploading data to Silver layer...")
    object_key = upload_to_silver(df_validated)

    return object_key


def run_pipeline() -> dict:
    """Run complete Silver layer pipeline.

    Returns:
        Pipeline execution result containing object key and status
    """
    try:
        logger.info("Starting Silver layer pipeline...")

        # Get platforms configuration
        list_platforms = get_list_platforms()
        logger.info(f"Processing platforms: {list_platforms}")

        # Read from Bronze
        df_bronze = get_bronze_object(list_platforms)
        logger.info(f"Read {len(df_bronze)} records from Bronze layer")

        # Transform data
        object_key = transform_silver(df_bronze)

        logger.info("✅ Silver layer pipeline completed successfully")
        return {
            "statusCode": 200,
            "message": "Data transformation to Silver successful",
            "object_key": object_key,
        }

    except Exception as e:
        logger.error(f"❌ Pipeline failed: {e}", exc_info=True)
        return {
            "statusCode": 500,
            "message": f"Data transformation to Silver failed: {str(e)}",
            "error": str(e),
        }
