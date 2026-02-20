# Lazy import untuk cold start cepat
async def jobscraper_jobstreet(url: str, headless: bool = True):
    # Import HANYA saat fungsi dipanggil (lazy loading)
    from playwright.async_api import Browser, BrowserContext, async_playwright
    from datetime import datetime
    from src.utils.scraper_utils import (
        create_browser,
        create_stealth_context,
        fast_human_scroll,
    )
    from src.utils.keywords import ALLOWED, BLOCKED
    from tenacity import retry, stop_after_attempt, wait_exponential
    import hashlib
    import asyncio
    import json
    import os

    async def _scrape():
        async with async_playwright() as p:
            browser: Browser = await create_browser(p, headless=headless)
            print("Berhasil create browser")
            context: BrowserContext = await create_stealth_context(browser)
            print("Berhasil create stealth_context")

            print("Creating new page...")
            page = await context.new_page()
            print("Page created successfully")
            print("Resource blocking disabled for anti-bot debugging")

            @retry(
                stop=stop_after_attempt(3),
                wait=wait_exponential(multiplier=1, min=2, max=10),
                reraise=True,
            )
            async def navigate_with_retry():
                print(f"Navigating to URL: {url}")
                await page.goto(url, wait_until="networkidle", timeout=60000)

            try:
                await navigate_with_retry()
                print("Successfully loaded page")
                print("Waiting 5 seconds for hydration...")
                await page.wait_for_timeout(5000)
            except Exception as e:
                print(f"Error during page.goto: {type(e).__name__}: {str(e)}")
                raise

            # Penanganan modal login yang sering muncul di JobStreet
            await page.keyboard.press("Escape")
            await asyncio.sleep(1)

            # Strategi Scroll: Lakukan scroll perlahan 3 kali saja
            # Ini memicu lazy loading tanpa mencekik RAM 8GB
            for i in range(3):
                await fast_human_scroll(page)
                await asyncio.sleep(1)

            results = []

            # Mengincar atribut data-automation yang sangat stabil di JobStreet
            job_cards = await page.locator('article[data-automation="normalJob"]').all()
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            for card in job_cards:
                try:
                    # 1. Job Title
                    title_elem = card.locator('[data-automation="jobTitle"]').first
                    job_title = (await title_elem.text_content()).strip()

                    # --- INTEGRASI FILTER PUSAT ---
                    job_title_lower = job_title.lower()
                    if not any(word in job_title_lower for word in ALLOWED) or any(
                        word in job_title_lower for word in BLOCKED
                    ):
                        continue

                    # 2. URL (Path relatif, perlu prefix)
                    relative_url = await title_elem.get_attribute("href")
                    full_url = f"https://id.jobstreet.com{relative_url}"

                    # 3. Company Name
                    company_elem = card.locator('[data-automation="jobCompany"]').first
                    company_name = (await company_elem.text_content()).strip()

                    # 4. Location
                    # Mengambil teks lokasi (Jakarta Selatan, dll)
                    location_elem = card.locator(
                        '[data-automation="jobLocation"]'
                    ).first
                    location = (await location_elem.text_content()).strip()

                    # 5. Job ID (Hash dari URL agar konsisten antar platform)
                    job_id = hashlib.md5(full_url.encode()).hexdigest()

                    results.append(
                        {
                            "job_id": job_id,
                            "job_title": job_title,
                            "company_name": company_name,
                            "location": location,
                            "job_url": full_url,
                            "platform": "jobstreet",
                            "scraped_at": timestamp,
                        }
                    )
                except Exception:
                    continue

            await context.close()
            await browser.close()

            return results

    return await _scrape()
