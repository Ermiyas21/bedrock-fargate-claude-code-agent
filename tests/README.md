# tests/

Unit tests for the Lambda dispatcher handler.

## Run

```bash
pip install -r requirements-dev.txt
pip install -r scripts/dispatcher/requirements.txt
pytest tests/ -v
```

## What's tested

- Request body parsing (JSON string and dict)
- Event filtering (correct state, action, type)
- Ticket field extraction
- Webhook signature validation (HMAC-SHA256)
- Full handler flow (task start, error handling, auth)

## Notes

- Tests mock all AWS calls (no real AWS credentials needed)
- `AWS_DEFAULT_REGION` must be set (the handler creates boto3 clients at import time)
- Uses `monkeypatch` to inject required env vars before module import
