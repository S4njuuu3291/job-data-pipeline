# Lazy import untuk cold start cepat
import asyncio  # Untuk __main__ block saja


async def run_glints_pipeline(keywords: list):
    # Import HANYA saat fungsi dipanggil
    import pandas as pd
    from src.scraper.jobscraper_glints import jobscraper_glints
    from src.utils.data_validator import validate_job_data
    from src.utils.upload_to_s3 import upload_to_s3

    df_glints_full = (
        pd.DataFrame()
    )  # DataFrame kosong untuk menampung semua hasil dari berbagai keyword

    for keyword in keywords:
        print("--- Start Glints Pipeline ---")
        URL = (
            f"https://glints.com/id/opportunities/jobs/explore?"
            f"keyword={keyword}&country=ID&locationName=All+Cities%2FProvinces"
            f"&lowestLocationLevel=1&sortBy=LATEST&jobTypes=INTERNSHIP%2CFULL_TIME"
            f"&yearsOfExperienceRanges=LESS_THAN_A_YEAR%2CFRESH_GRAD%2CNO_EXPERIENCE"
        )
        raw_data = await jobscraper_glints(URL, headless=True)

        if not raw_data:
            print("❌ Gagal: Tidak ada data yang berhasil ditarik.")
            continue

        df_glints = pd.DataFrame(raw_data)
        df_glints["keyword"] = keyword

        df_glints_full = pd.concat(
            [df_glints_full, df_glints], ignore_index=True
        )  # Gabungkan hasil ke DataFrame utama

    try:
        df = pd.DataFrame(df_glints_full)
        df.drop_duplicates(
            subset=["job_id"], inplace=True
        )  # Hapus duplikat berdasarkan job_id

        df_validated = validate_job_data(df)
        print(f"✅ Validasi Sukses: {len(df_validated)} baris siap dikirim.")

        success = upload_to_s3(df_validated, platform="glints")
        if success:
            print("--- 🏆 Pipeline Selesai dengan Sukses ---")
        else:
            print("--- ⚠️ Pipeline Selesai dengan Error di S3 ---")
        return len(df_validated) if success else 0
    except Exception as e:
        print(f"❌ Pipeline Berhenti di tahap Validasi/Upload: {e}")
        raise


if __name__ == "__main__":
    keywords = [
        "data+engineer+intern",
        "etl+developer+intern",
        "big+data+intern",
        "bi+engineer+intern",
    ]
    asyncio.run(run_glints_pipeline(keywords))
