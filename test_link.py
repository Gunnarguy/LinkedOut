import asyncio, httpx

async def test():
    urls = ['https://news.ycombinator.com/item?id=39121', 'https://jobs.lever.co/invalid123'\]
    async with httpx.AsyncClient(timeout=3.0) as client:
        for url in urls:
            try:
                r = await client.head(url, follow_redirects=True)
                print(url, r.status_code)
            except Exception as e:
                print(url, e)
asyncio.run(test())
