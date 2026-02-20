# Lazy import untuk cold start cepat
import asyncio  # Untuk __main__ block saja


async def run_jobstreet_pipeline(keywords: list):
    # Import HANYA saat fungsi dipanggil
    import pandas as pd
    from src.scraper.jobscraper_jobstreet import jobscraper_jobstreet
    from src.utils.data_validator import validate_job_data
    from src.utils.upload_to_s3 import upload_to_s3

    df_jobstreet_full = (
        pd.DataFrame()
    )  # DataFrame kosong untuk menampung semua hasil dari berbagai keyword

    for keyword in keywords:
        print("--- 🏁 Memulai Pipeline jobstreet ---")
        URL = f"https://id.jobstreet.com/id/{keyword}-jobs?daterange=7"

        raw_data = await jobscraper_jobstreet(URL, headless=True)

        if not raw_data:
            print("❌ Gagal: Tidak ada data yang berhasil ditarik.")
            continue

        df_jobstreet = pd.DataFrame(raw_data)
        df_jobstreet["keyword"] = keyword

        df_jobstreet_full = pd.concat(
            [df_jobstreet_full, df_jobstreet], ignore_index=True
        )  # Gabungkan hasil ke DataFrame utama

    try:
        df = pd.DataFrame(df_jobstreet_full)
        df.drop_duplicates(
            subset=["job_id"], inplace=True
        )  # Hapus duplikat berdasarkan job_id

        df_validated = validate_job_data(df)
        print(f"✅ Validasi Sukses: {len(df_validated)} baris siap dikirim.")

        success = upload_to_s3(df_validated, platform="jobstreet")
        if success:
            print("--- 🏆 Pipeline Selesai dengan Sukses ---")
        else:
            print("--- ⚠️ Pipeline Selesai dengan Error di S3 ---")
    except Exception as e:
        print(f"❌ Pipeline Berhenti di tahap Validasi/Upload: {e}")


if __name__ == "__main__":
    keywords = [
        "data-engineer-intern",
        "etl-developer-intern",
        "big-data-intern",
        "bi-engineer-intern",
    ]
    asyncio.run(run_jobstreet_pipeline(keywords))
