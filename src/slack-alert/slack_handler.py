from datetime import datetime, timezone, timedelta
import logging
import time
from typing import TYPE_CHECKING
from boto3 import client
import requests
import os

if TYPE_CHECKING:
    from mypy_boto3_athena import AthenaClient

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

def import_url():
    ssm = client("ssm")
    try:
        response = ssm.get_parameter(Name="/jobscraper/slack/webhook_url", WithDecryption=True)
        return response["Parameter"]["Value"]
    except Exception as e:
        logger.error(f"Failed to retrieve Slack webhook URL from SSM: {e}")
        raise

def athena_query(ingestion_date: str = datetime.now().strftime('%Y-%m-%d')) -> list[dict]:
    athena: AthenaClient = client("athena")
    
    # Use v_jobscraper_clean view which has ingestion_date and discovery_type columns
    # Lake Formation permissions now granted for the view
    query = f"""
    SELECT * FROM v_jobscraper_clean
    WHERE ingestion_date = '{ingestion_date}'
    AND discovery_type = 'NEW'
    """

    logger.info(f"Executing Athena query for date: {ingestion_date}")
    logger.info(f"Query: {query}")
    
    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": "jobscraper_db"},
        WorkGroup="jobscraper-slack-alert-workgroup"
    )

    query_id = response["QueryExecutionId"]
    logger.info(f"Query ID: {query_id}")

    while True:
        query_status = athena.get_query_execution(QueryExecutionId=query_id)
        status = query_status["QueryExecution"]["Status"]["State"]

        if status in ["SUCCEEDED", "FAILED", "CANCELLED"]:
            break

        logger.info(f"Query status: {status}. Waiting for completion...")
        time.sleep(2)

    parsed_data = []
    
    if status == "SUCCEEDED":
        results = athena.get_query_results(QueryExecutionId=query_id)
        rows = results["ResultSet"]["Rows"]
        
        logger.info(f"Query returned {len(rows)} rows (including header)")

        if len(rows) <= 1:
            logger.warning("Query completed but no data found.")
            print(f"⚠️ Query completed but no data found. Rows: {len(rows)}")
            return []

        # Parse column names from header
        columns = [col.get("VarCharValue", "") for col in rows[0]["Data"]]
        logger.info(f"Columns: {columns}")
        print(f"📊 Columns: {columns}")

        # Parse data rows
        for row_idx, row in enumerate(rows[1:], 1):
            row_dict = {}
            try:
                for col_idx, col in enumerate(columns):
                    value = row["Data"][col_idx].get("VarCharValue", "")
                    row_dict[col] = value
                parsed_data.append(row_dict)
            except (IndexError, KeyError) as e:
                logger.warning(f"Error parsing row {row_idx}: {e}")
                continue
    
        logger.info(f"✅ Parsed {len(parsed_data)} job records successfully!")
        print(f"✅ Parsed {len(parsed_data)} job records successfully!")
    else:
        logger.error(f"Query failed with status: {status}")
        print(f"❌ Query failed with status: {status}")
        if "StateChangeReason" in query_status["QueryExecution"]["Status"]:
            reason = query_status['QueryExecution']['Status']['StateChangeReason']
            logger.error(f"Reason: {reason}")
            print(f"❌ Reason: {reason}")
    
    return parsed_data

def send_slack_alert(message: str, webhook_url: str):
    """Send alert message to Slack channel via webhook."""

    payload = {"text": message}
    try:
        response = requests.post(webhook_url, json=payload)
        response.raise_for_status()
        print("✅ Alert sent to Slack successfully!")
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to send alert to Slack: {e}")

def shorten_url(url: str) -> str:
    """Shorten URL using TinyURL API."""
    try:
        response = requests.get(f"https://tinyurl.com/api-create.php?url={url}", timeout=5)
        if response.status_code == 200:
            return response.text
    except Exception as e:
        logger.warning(f"Failed to shorten URL: {e}")
    
    return url  # Fallback to original URL


def format_job_message(parsed_data: list[dict]) -> str:
    """Format job data into beautiful Slack message with proper structure."""
    if not parsed_data:
        return "ℹ️ No new job postings found for today."

    # Platform emoji mapping
    platform_emoji = {
        'glints': '🎯',
        'jobstreet': '💼',
        'kalibrr': '⭐'
    }
    
    message = f"\n🆕 *{len(parsed_data)} New Job{'s' if len(parsed_data) > 1 else ''} Found*\n"
    message += "━" * 50 + "\n\n"
    
    for idx, job in enumerate(parsed_data, 1):
        platform = job.get('platform', 'unknown').lower()
        platform_icon = platform_emoji.get(platform, '💼')
        
        short_url = shorten_url(job['job_url'])
        url_link = f"<{short_url}|Lihat Posisi>"
        
        # Format: number + title
        message += f"*{idx}. {job['job_title']}*\n"
        
        # Format: company | location | platform
        message += f"   {platform_icon} {job['company_name']}  •  📍 {job['location']}\n"
        
        # Format: apply link
        message += f"   {url_link}\n\n"
    
    return message

def lambda_handler(event, context):
    ingestion_date = event.get("ingestion_date", datetime.now().strftime('%Y-%m-%d'))
    parsed_data = athena_query(ingestion_date)
    
    # Format message from job data
    job_message = format_job_message(parsed_data)
    
    # Get current time in WIB (UTC+7)
    wib = timezone(timedelta(hours=7))
    now_wib = datetime.now(wib)
    time_str = now_wib.strftime('%d %b, %H:%M WIB')
    
    # Create final Slack message with header and footer
    message = f"*📋 Job Alert - {time_str}*{job_message}"

    # Send to Slack
    send_slack_alert(message, import_url())
    logger.info(f"Alert sent: {len(parsed_data)} jobs")

    return {
        "statusCode": 200,
        "body": "Slack message sent successfully!"
    }

if __name__ == "__main__":

    lambda_handler({"ingestion_date": "2026-03-05"}, {})