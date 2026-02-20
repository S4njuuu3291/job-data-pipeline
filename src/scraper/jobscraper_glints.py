# Lazy import untuk cold start cepat
async def jobscraper_glints(url: str, headless: bool = True):
    # Import HANYA saat fungsi dipanggil (lazy loading)
    from playwright.async_api import Browser, BrowserContext, async_playwright
    from datetime import datetime
    from src.utils.scraper_utils import (
        create_browser,
        create_stealth_context,
        fast_human_scroll,
    )
    from src.utils.keywords import ALLOWED, BLOCKED
    from tenacity import (
        retry,
        stop_after_attempt,
        wait_exponential,
    )
    import hashlib
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

            # Resource blocking dinonaktifkan dulu untuk debugging antibot
            print("Resource blocking disabled for anti-bot debugging")

            # Inisialisasi variabel di luar loop/navigasi agar aman dari UnboundLocalError
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"glints_raw_{timestamp}.json"
            results = []

            # Fungsi Navigasi dengan Retry khusus
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

                # Tunggu selector kartu muncul (PENTING agar tidak TargetClosed)
                print("Waiting for job cards...")
                selector = '[data-glints-tracking-element-name="job_card"]'
                await page.wait_for_selector(selector, timeout=20000)

                await fast_human_scroll(page)

                job_cards = await page.locator(selector).all()
                print(f"Found {len(job_cards)} potential cards")

                for card in job_cards:
                    try:
                        # 1. Job Title
                        title_elem = card.locator('h2[class*="JobTitle"] a').first
                        job_title = (await title_elem.text_content()).strip()

                        # --- INTEGRASI FILTER PUSAT ---
                        job_title_lower = job_title.lower()
                        if not any(word in job_title_lower for word in ALLOWED) or any(
                            word in job_title_lower for word in BLOCKED
                        ):
                            continue

                        # 2. URL
                        relative_url = await title_elem.get_attribute("href")
                        full_url = f"https://glints.com{relative_url}"

                        # 3. Company Name
                        company_elem = card.locator(
                            '[data-cy="company_name_job_card"] a'
                        ).first
                        company_name = (await company_elem.text_content()).strip()

                        # 4. Location
                        location_elem = card.locator(
                            'div[class*="LocationWrapper"]'
                        ).first
                        location = (await location_elem.text_content()).strip()

                        # 5. Job ID (Hash dari URL)
                        job_id = hashlib.md5(full_url.encode()).hexdigest()

                        results.append(
                            {
                                "job_id": job_id,
                                "job_title": job_title,
                                "company_name": company_name,
                                "location": location,
                                "job_url": full_url,
                                "platform": "glints",
                                "scraped_at": timestamp,
                            }
                        )
                    except Exception:
                        continue

                # Simpan Hasil
                if results:
                    output_dir = "/tmp/output"
                    if not os.path.exists(output_dir):
                        os.makedirs(output_dir)

                    file_path = os.path.join(output_dir, filename)
                    with open(file_path, "w", encoding="utf-8") as f:
                        json.dump(results, f, ensure_ascii=False, indent=4)
                    print(f"✅ Sukses! {len(results)} data disimpan di: {file_path}")
                else:
                    print("⚠️ Tidak ada data yang lolos filter.")

            except Exception as e:
                print(f"❌ Error during scraping: {type(e).__name__}: {str(e)}")
            finally:
                await context.close()
                await browser.close()

            return results

    return await _scrape()
