# Credentials

This directory contains **templates only** for n8n credentials.

> [!CAUTION]
> **DO NOT** commit actual credentials, API keys, or secrets to this repository.

## Setting Up Credentials in n8n

1. Log into your n8n instance
2. Go to **Settings** → **Credentials**
3. Add credentials for:
   - **HTTP Header Auth**: For ACE backend API (`x-api-key`)
   - **OAuth2**: For external APIs (TikTok, YouTube, etc.)
   - **Postgres**: For Supabase (if direct DB access needed)

## Environment Variables

Set these in your n8n instance environment:

| Variable | Description |
|----------|-------------|
| `ACE_BACKEND_URL` | Base URL for the ACE backend API |
| `ACE_API_KEY` | API key for authenticating with ACE backend |
| `TIKTOK_ACCESS_TOKEN` | OAuth token for TikTok API access |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_KEY` | Supabase service role key |

## Reference

See main [README](../README.md) for full setup instructions.
