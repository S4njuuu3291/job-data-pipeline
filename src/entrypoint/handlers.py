# Lazy import untuk handler (tanpa import top-level yang berat)

# Daftar keyword yang ingin kamu scrape secara rutin
DEFAULT_KEYWORDS = [
    "data-engineer-intern",
    "etl-developer-intern",
    "big-data-intern",
    "bi-engineer-intern",
]

DEFAULT_KEYWORDS_GLINTS = [
    "data+engineer+intern",
    "etl+developer+intern",
    "big+data+intern",
    "bi+engineer+intern",
]


# Handler untuk Kalibrr
def kalibrr_handler(event, context):
    import asyncio
    from src.main.main_kalibrr import run_kalibrr_pipeline

    print("Memicu Lambda Kalibrr...")
    # asyncio.run digunakan karena Lambda adalah fungsi sinkronous
    # sedangkan scraper kita asinkronous (async/await)
    try:
        result = asyncio.run(run_kalibrr_pipeline(DEFAULT_KEYWORDS))
        if not result:
            raise RuntimeError("Pipeline selesai tapi 0 data berhasil diproses")
        return {
            "statusCode": 200,
            "body": f"Kalibrr scrape sukses, {result} data berhasil diproses",
        }
    except Exception as e:
        print(f"Error di Lambda Kalibrr: {e}")
        raise


# Handler untuk Glints
def glints_handler(event, context):
    import asyncio
    from src.main.main_glints import run_glints_pipeline

    print("Memicu Lambda Glints...")
    try:
        result = asyncio.run(run_glints_pipeline(DEFAULT_KEYWORDS_GLINTS))
        if not result:
            raise RuntimeError("Pipeline selesai tapi 0 data berhasil diproses")
        return {
            "statusCode": 200,
            "body": f"Glints scrape sukses, {result} data berhasil diproses",
        }
    except Exception as e:
        print(f"Error di Lambda Glints: {e}")
        raise


# Handler untuk JobStreet
def jobstreet_handler(event, context):
    import asyncio
    from src.main.main_jobstreet import run_jobstreet_pipeline

    print("Memicu Lambda JobStreet...")
    try:
        result = asyncio.run(run_jobstreet_pipeline(DEFAULT_KEYWORDS))
        if not result:
            raise RuntimeError("Pipeline selesai tapi 0 data berhasil diproses")
        return {
            "statusCode": 200,
            "body": f"JobStreet scrape sukses, {result} data berhasil diproses",
        }
    except Exception as e:
        print(f"Error di Lambda JobStreet: {e}")
        raise
