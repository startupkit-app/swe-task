"""
Webhook Delivery System — BONUS CHALLENGE

This module provides the scaffold for the optional webhook delivery system.
Candidates who finish the core tasks early can implement this for extra credit.

Requirements (from REQUIREMENTS.md):
- POST /webhooks: Register a webhook URL
- POST /events: Publish an event to all registered webhooks
- Delivery must be idempotent (each event delivered exactly once per webhook)
- Handle downstream failures with exponential backoff (max 3 retries)
- The mock API randomly returns 500 errors — handle this gracefully

Implementation hints:
- Use Redis Streams (XADD/XREADGROUP) for reliable event delivery
- Use consumer groups for worker coordination
- Store idempotency keys to prevent duplicate delivery
- Consider what happens if a worker crashes mid-delivery

This file is NOT imported by app.py. Candidates must integrate it themselves.
"""

# TODO: Implement webhook registration
# TODO: Implement event publishing to Redis Streams
# TODO: Implement consumer worker with idempotency
# TODO: Implement retry logic with exponential backoff
