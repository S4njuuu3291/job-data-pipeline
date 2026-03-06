from datetime import datetime
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
    
    query = f"select * from v_jobscraper_clean \
            where ingestion_date = '{ingestion_date}' \
            and discovery_type = 'NEW'"

    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": "jobscraper_db"},
        WorkGroup="jobscraper-slack-alert-workgroup"
    )

    while True:
        query_status = athena.get_query_execution(QueryExecutionId=response["QueryExecutionId"])
        status = query_status["QueryExecution"]["Status"]["State"]

        if status in ["SUCCEEDED", "FAILED", "CANCELLED"]:
            break

        print(f"Query status: {status}. Waiting for completion...")
        time.sleep(2)

    parsed_data = []
    
    if status == "SUCCEEDED":
        results = athena.get_query_results(QueryExecutionId=response["QueryExecutionId"])

        if len(results["ResultSet"]["Rows"]) <= 1:
            print("Query completed but no results found.")
            return []

        columns = [col["VarCharValue"] for col in results["ResultSet"]["Rows"][0]["Data"]]

        for row in results["ResultSet"]["Rows"][1:]:
            row_dict = {}
            for idx, col in enumerate(columns):
                value = row["Data"][idx].get("VarCharValue", "")
                row_dict[col] = value
        
            parsed_data.append(row_dict)
    
        print("✅ Athena query completed successfully!")
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
    """Format job data into compact Slack message with shortened URLs."""
    if not parsed_data:
        return "No new job postings found for today."

    message = f"🆕 *Found {len(parsed_data)} New Jobs*\n\n"
    
    for idx, job in enumerate(parsed_data, 1):
        short_url = shorten_url(job['job_url'])
        url_link = f"<{short_url}|Link>"
        
        message += f"{idx}. {job['job_title']} @ {job['company_name']} ({job['location']}, {job['platform']}) {url_link}\n"
    
    return message

def lambda_handler(event, context):
    ingestion_date = event.get("ingestion_date", datetime.now().strftime('%Y-%m-%d'))
    parsed_data = athena_query(ingestion_date)
    
    # Format message from job data
    job_message = format_job_message(parsed_data)
    
    # Create final Slack message
    message = f"📢 *Job Alert - {datetime.now().strftime('%Y-%m-%d %H:%M')}* 📢\n\n{job_message}"

    # Send to Slack
    send_slack_alert(message, import_url())
    logger.info(f"Alert sent: {len(parsed_data)} jobs")

    return {
        "statusCode": 200,
        "body": "Slack message sent successfully!"
    }

if __name__ == "__main__":

    lambda_handler({"ingestion_date": "2026-03-05"}, {})