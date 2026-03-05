"""Tests for Silver layer validators module."""

import pandas as pd
import pytest
import pandera.pandas as pa

from src.silver_layer.validators import validate_silver_schema


class TestValidateSilverSchema:
    """Tests for validate_silver_schema function."""

    @pytest.fixture
    def valid_dataframe(self):
        """Fixture for valid dataframe."""
        return pd.DataFrame(
            {
                "job_id": ["id1", "id2", "id3"],
                "job_title": ["Data Engineer", "Backend Dev", "Frontend Dev"],
                "company_name": ["Company A", "Company B", "Company C"],
                "location": ["Jakarta", "Bandung", "Surabaya"],
                "job_url": [
                    "http://example.com/1",
                    "http://example.com/2",
                    "http://example.com/3",
                ],
                "platform": ["kalibrr", "glints", "jobstreet"],
            }
        )

    def test_validate_valid_dataframe(self, valid_dataframe):
        """Test validation passes for valid dataframe."""
        result = validate_silver_schema(valid_dataframe)
        assert len(result) == 3
        assert list(result.columns) == [
            "job_id",
            "job_title",
            "company_name",
            "location",
            "job_url",
            "platform",
        ]

    def test_validate_missing_required_column(self):
        """Test validation fails when required column is missing."""
        df = pd.DataFrame(
            {
                "job_id": ["id1"],
                "job_title": ["Engineer"],
                "company_name": ["Company"],
                # Missing 'location', 'job_url', 'platform'
            }
        )
        with pytest.raises(pa.errors.SchemaError):
            validate_silver_schema(df)

    def test_validate_duplicate_job_id(self):
        """Test validation fails when job_id is not unique."""
        df = pd.DataFrame(
            {
                "job_id": ["id1", "id1"],  # Duplicate
                "job_title": ["Engineer", "Developer"],
                "company_name": ["Company A", "Company B"],
                "location": ["Jakarta", "Bandung"],
                "job_url": ["http://example.com/1", "http://example.com/2"],
                "platform": ["kalibrr", "glints"],
            }
        )
        with pytest.raises(pa.errors.SchemaError):
            validate_silver_schema(df)

    def test_validate_invalid_platform(self):
        """Test validation fails when platform is not in allowed list."""
        df = pd.DataFrame(
            {
                "job_id": ["id1"],
                "job_title": ["Engineer"],
                "company_name": ["Company"],
                "location": ["Jakarta"],
                "job_url": ["http://example.com/1"],
                "platform": ["invalid_platform"],  # Not in allowed list
            }
        )
        with pytest.raises(pa.errors.SchemaError):
            validate_silver_schema(df)

    def test_validate_null_values(self):
        """Test validation fails when required column has null values."""
        df = pd.DataFrame(
            {
                "job_id": ["id1", None],  # Null value
                "job_title": ["Engineer", "Developer"],
                "company_name": ["Company A", "Company B"],
                "location": ["Jakarta", "Bandung"],
                "job_url": ["http://example.com/1", "http://example.com/2"],
                "platform": ["kalibrr", "glints"],
            }
        )
        with pytest.raises(pa.errors.SchemaError):
            validate_silver_schema(df)

    def test_validate_returns_same_dataframe(self, valid_dataframe):
        """Test that validation returns the same dataframe when valid."""
        result = validate_silver_schema(valid_dataframe)
        pd.testing.assert_frame_equal(result, valid_dataframe)
