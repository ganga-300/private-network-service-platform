#!/bin/bash
# Sends 10 requests through the nginx edge; X-Backend should alternate A and B.
for i in {1..10}; do
  curl --max-time 6 -sI https://app.netforge.test:8443/api/status | grep -i x-backend
done
