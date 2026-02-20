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
    asyncio.run(run_kalibrr_pipeline(DEFAULT_KEYWORDS))
    return {"statusCode": 200, "body": "Kalibrr scrape sukses"}


# Handler untuk Glints
def glints_handler(event, context):
    import asyncio
    from src.main.main_glints import run_glints_pipeline

    print("Memicu Lambda Glints...")
    asyncio.run(run_glints_pipeline(DEFAULT_KEYWORDS_GLINTS))
    return {"statusCode": 200, "body": "Glints scrape sukses"}


# Handler untuk JobStreet
def jobstreet_handler(event, context):
    import asyncio
    from src.main.main_jobstreet import run_jobstreet_pipeline

    print("Memicu Lambda JobStreet...")
    asyncio.run(run_jobstreet_pipeline(DEFAULT_KEYWORDS))
    return {"statusCode": 200, "body": "JobStreet scrape sukses"}
