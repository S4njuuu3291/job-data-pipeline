import pytest
import pandera.pandas as pa
from src.utils.data_validator import validate_job_data
from src.utils.data_validator import job_schema
import pandas as pd

# ===============================================================================
#                              DATA VALIDATOR TESTS
# ===============================================================================

class TestDataValidator:
    def test_valid_data(self):
        data = {
            "job_id": ["1", "2"],
            "job_title": ["Software Engineer", "Data Scientist"],
            "company_name": ["Company A", "Company B"],
            "location": ["Jakarta", "Bandung"],
            "job_url": ["http://example.com/job1", "http://example.com/job2"],
            "platform": ["kalibrr", "jobstreet"],
            "scraped_at": ["2024-06-01T12:00:00Z", "2024-06-01T12:05:00Z"]
        }

        df = pd.DataFrame(data)
        validated_df = validate_job_data(df)

        assert validated_df.equals(df)

    def test_invalid_platform(self):
        data = {
            "job_id": ["1"],
            "job_title": ["Software Engineer"],
            "company_name": ["Company A"],
            "location": ["Jakarta"],
            "job_url": ["http://example.com/job1"],
            "platform": ["invalid_platform"],
            "scraped_at": ["2024-06-01T12:00:00Z"]
        }

        df = pd.DataFrame(data)
        with pytest.raises(pa.errors.SchemaError):
            validate_job_data(df)

    def test_missing_column(self):
        data = {
            "job_id": ["1"],
            "job_title": ["Software Engineer"],
            "company_name": ["Company A"],
            "location": ["Jakarta"],
            "job_url": ["http://example.com/job1"],
            # "platform" column is missing
            "scraped_at": ["2024-06-01T12:00:00Z"]
        }

        df = pd.DataFrame(data)
        with pytest.raises(pa.errors.SchemaError):
            validate_job_data(df)
    
    def test_duplicate_job_id(self):
        data = {
            "job_id": ["1", "1"],  # Duplicate job_id
            "job_title": ["Software Engineer", "Data Scientist"],
            "company_name": ["Company A", "Company B"],
            "location": ["Jakarta", "Bandung"],
            "job_url": ["http://example.com/job1", "http://example.com/job2"],
            "platform": ["kalibrr", "jobstreet"],
            "scraped_at": ["2024-06-01T12:00:00Z", "2024-06-01T12:05:00Z"]
        }

        df = pd.DataFrame(data)
        with pytest.raises(pa.errors.SchemaError):
            validate_job_data(df)
    
    def test_empty_dataframe(self):
        df = pd.DataFrame(columns=job_schema.columns)
        validated_df = validate_job_data(df)

        assert len(validated_df) == 0