import asyncio
from backend.notion_sync import NotionClient
from backend.job_store import get_job_store

async def debug_push():
    client = NotionClient()
    setup = await client.discover_schema()
    print("Has DB and Token:", setup)
    if not setup: return
    
    # get ardent job
    store = get_job_store()
    jobs = store.get_jobs("saved")
    job = next((j for j in jobs if j.id == "test-ardent-ai-123"), None)
    if not job:
        print("Job not found!")
        return

    # Map props
    props = client._build_properties(job)
    print("Payload properties:")
    import json
    print(json.dumps(props, indent=2))
    
    # Try push
    try:
        await client._create_page(props)
        print("Success! Created page!")
    except Exception as e:
        print("FAILED!")
        print(e)
        if hasattr(e, "response"):
            print("RESPONSE BODY:")
            print(e.response.text)

asyncio.run(debug_push())
