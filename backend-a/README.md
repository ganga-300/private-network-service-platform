# Backend A

Python (Flask) REST API running on Mac 3 (Pratiti), port 3001.
It binds to 0.0.0.0 so other Macs on the LAN can reach it.

## Run

    python -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    python app.py

## Endpoints

| Endpoint | Response |
|---|---|
| GET / | Page confirming Backend A is running |
| GET /api/status | {"backend":"A","status":"ok"} |

Every response includes the header `X-Backend: A`.

## Test

    curl -i http://10.7.28.81:3001/api/status

## Phase 2 notes

- In Phase 2, port 3001 can be restricted so that only the nginx edge (Mac 2, 10.7.17.248) can connect.
  See [`../firewall/`](../firewall/). While those rules are on, the `curl` above works only from Mac 2.
- To check that the backend is listening: `lsof -nP -iTCP:3001 -sTCP:LISTEN`
