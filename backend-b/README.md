# Backend B

Python (Flask) REST API running on Mac 4 (Anuradha), port 3002.
It binds to 0.0.0.0 so other Macs on the LAN can reach it.

## Run

    python -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    python app.py

## Endpoints

| Endpoint | Response |
|---|---|
| GET / | Page confirming Backend B is running |
| GET /api/status | {"backend":"B","status":"ok"} |

Every response includes the header `X-Backend: B`.

## Test

    curl -i http://<BACKEND_B_IP>:3002/api/status
