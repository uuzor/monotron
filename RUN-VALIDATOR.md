# Running a Canton Validator with Docker

## Quick Answer: Yes!

There are official Docker images available. Here's how to run a validator with command submission enabled.

---

## Option 1: Canton Open Source Docker Image

### Pull the Image
```bash
docker pull digitalasset/canton-open-source:latest
```

Available tags: `2.8.0-rc1`, `2.7.9`, `2.7.8`, etc.

### Run a Simple Validator
```bash
docker run -d \
  --name canton-validator \
  -p 5001:5001 \
  -p 5002:5002 \
  -p 8080:8080 \
  -v $(pwd)/validator-data:/canton/data \
  digitalasset/canton-open-source:latest
```

### Check Status
```bash
docker logs -f canton-validator
```

---

## Option 2: Splice Validator (Recommended for DevNet)

### Official Images on GitHub Container Registry

```bash
# Splice Validator Image
docker pull ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-validator:0.6.11

# Splice Participant Image
docker pull ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-participant:0.6.11
```

### Full Docker Compose Setup

Create `docker-compose.yml`:

```yaml
version: "3.8"
services:
  splice-validator:
    image: ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-validator:0.6.11
    container_name: splice-validator
    environment:
      - VALIDATOR_HOST=${VALIDATOR_HOST}
      - VALIDATOR_PRIVATE_KEY=${VALIDATOR_PRIVATE_KEY}
      - VALIDATOR_PUBLIC_KEY=${VALIDATOR_PUBLIC_KEY}
      - VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS}
      - AUTH_CLIENT_ID=${AUTH_CLIENT_ID}
    ports:
      - "40440:40440"   # protocol
      - "40441:40441"   # API gRPC external
      - "40442:40442"   # API gRPC internal
      - "40443:40443"   # API HTTP (JSON API)
      - "40444:40444"   # discovery
      - "40445:40445"   # API admin HTTP
      - "10013:10013"   # Prometheus metrics
    volumes:
      - ./data:/var/lib/splice/data
      - ./conf:/etc/splice/conf
    restart: unless-stopped
    networks:
      - splice-net
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 40443 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  canton-participant:
    image: ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-participant:0.6.11
    container_name: canton-participant
    environment:
      - PARTICIPANT_ID=${PARTICIPANT_ID}
      - LEDGER_API_HOST=splice-validator
      - LEDGER_API_PORT=5001
    ports:
      - "5001:5001"   # ledger API
      - "5002:5002"   # admin API
    volumes:
      - ./participant-conf:/etc/participant/conf
    networks:
      - splice-net

networks:
  splice-net:
    driver: bridge
```

Create `.env` file:

```bash
# Validator Configuration
VALIDATOR_HOST=your-server-ip
VALIDATOR_PRIVATE_KEY=your-private-key
VALIDATOR_PUBLIC_KEY=your-public-key
VALIDATOR_ADDRESS=your-server-ip:40441

# Optional (for DevNet integration)
AUTH_CLIENT_ID=your-auth-client-id

# Participant ID (will be generated during setup)
PARTICIPANT_ID=your-participant-id
```

### Start the Validator
```bash
docker compose up -d
docker compose logs -f
```

---

## Option 3: DevNet Participant Node

If you just want to **connect as a participant** (not run a full validator):

```yaml
version: "3.8"
services:
  participant:
    image: ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-participant:0.6.11
    container_name: canton-participant
    environment:
      - LEDGER_API_HOST=ledger-api.validator.devnet.sandbox.fivenorth.io
      - LEDGER_API_PORT=443
      - LEDGER_API_USE_TLS=true
    ports:
      - "5001:5001"   # ledger API
      - "5002:5002"   # admin API
    volumes:
      - ./participant-data:/var/lib/participant/data
      - ./console.conf:/etc/canton/console.conf
    restart: unless-stopped
```

---

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 5001 | Ledger API | gRPC - Submit commands, queries |
| 5002 | Admin API | gRPC - Node administration |
| 8080 | Console | HTTP - Canton console |
| 10013 | Metrics | HTTP - Prometheus metrics |

---

## Prerequisites

1. **Docker & Docker Compose**
   ```bash
   docker --version           # Docker 20.10+
   docker compose version     # Docker Compose 2.0+
   ```

2. **Resources**
   - DevNet: 4 CPU, 8 GB RAM, 50 GB storage
   - MainNet: 8+ CPU, 16+ GB RAM, 250+ GB NVMe

3. **Network**
   - Open ports: 5001, 5002, 8080, 10013
   - For DevNet: Fixed egress IP for allowlisting

---

## Enabling Command Submission

Unlike the Devnet public validator (which has commands disabled), running your own validator/participant enables **full command submission**:

1. Register your submission signing keys
2. Allocate parties on your participant
3. Grant `actAs` rights to users
4. Submit commands via `/v2/commands/submit-and-wait`

### Example: Submit Command to Your Validator

```bash
# Get JWT token
TOKEN=$(curl -s -X POST "https://auth.example.com/oauth/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  | jq -r '.access_token')

# Create a contract
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "commandId": "create-001",
    "actAs": ["MyParty"],
    "userId": "my-user",
    "commands": [{
      "CreateCommand": {
        "templateId": "Main:Invoice",
        "createArguments": {
          "seller": "MyParty",
          "buyer": "OtherParty",
          "amount": {"amount": "1000.00", "currency": "USD"},
          "description": "Test Invoice"
        }
      }
    }]
  }' \
  "http://localhost:5001/v2/commands/submit-and-wait"
```

---

## Quick Start Scripts

### Minimal Canton Sandbox (for testing)
```bash
# Pull and run Canton Sandbox
docker run -d \
  --name canton-sandbox \
  -p 5001:5001 \
  -p 5002:5002 \
  digitalasset/canton-open-source:2.8.0-rc1 \
  -c '
    canton.participants.sandbox = {
      storage.type = memory
      admin-api.port = 5002
      ledger-api.port = 5001
    }
  '
```

### DevNet Participant
```bash
# Connect to DevNet as a participant
docker run -d \
  --name canton-devnet-participant \
  -p 5001:5001 \
  -p 5002:5002 \
  -e LEDGER_API_HOST=ledger-api.validator.devnet.sandbox.fivenorth.io \
  -e LEDGER_API_PORT=443 \
  -e LEDGER_API_USE_TLS=true \
  -v $(pwd)/participant-data:/var/lib/participant/data \
  ghcr.io/digital-asset/decentralized-canton-sync/helm/splice-participant:0.6.11
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Port already in use | Change port mapping or stop conflicting service |
| Container not healthy | Check logs: `docker logs <container>` |
| Command submission fails | Verify party has `actAs` rights |
| Auth token invalid | Regenerate JWT with correct claims |
| Can't connect to DevNet | Verify egress IP is allowlisted |

### Check Logs
```bash
docker compose logs -f
docker logs canton-validator -f
```

### Verify APIs
```bash
# Check Ledger API is responding
curl http://localhost:5001/v2/state/ledger-end

# Check Admin API
curl http://localhost:5002/health
```

---

## Resources

- [Canton Open Source on Docker Hub](https://hub.docker.com/r/digitalasset/canton-open-source/tags)
- [Splice Validator GitHub Packages](https://github.com/orgs/digital-asset/packages/container/package/decentralized-canton-sync%2Fhelm%2Fsplice-validator)
- [Posthuman DevNet Guide](https://nodes.posthuman.digital/chains/canton-testnet)
- [Official Docker Docs](https://docs.dev.sync.global/validator_operator/validator_compose.html)

---

## Summary

| Scenario | Docker Command | Command Submission |
|----------|---------------|-------------------|
| Devnet Public Validator | N/A | ❌ Disabled |
| Local Sandbox | `docker run digitalasset/canton-open-source` | ✅ Enabled |
| Your Own Validator | See docker-compose above | ✅ Enabled |
| Devnet Participant | See participant config | ✅ Enabled |
